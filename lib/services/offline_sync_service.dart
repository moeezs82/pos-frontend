import 'dart:math';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/utils/network_failure.dart';

/// Result of trying to sync one queued sale.
/// - synced        the server has it (fresh create or idempotent replay).
/// - stillOffline  the backend is unreachable; item stays pending.
/// - retrying      a transient server error; item stays pending with backoff.
/// - authRequired  the token was rejected (401/419); sync paused for re-auth.
/// - failed        a terminal/business error; item is dead-lettered.
enum SyncOutcome { synced, stillOffline, retrying, authRequired, failed }

class SyncResult {
  final String clientRef;
  final SyncOutcome outcome;
  final String? invoiceNo;
  final String? error;

  SyncResult({
    required this.clientRef,
    required this.outcome,
    this.invoiceNo,
    this.error,
  });
}

/// Pushes queued offline sales through the exact same `POST /sales`
/// endpoint/code path a normal online sale uses (handover doc §2.4, §3).
/// Handles verify-batch reconciliation for ambiguous (timed-out) attempts,
/// and — post-hardening (handover doc G3/G4/G6) — a real error taxonomy:
/// transient failures back off and retry, auth failures pause for re-login,
/// and only genuinely un-processable sales are dead-lettered for a human.
class OfflineSyncService {
  final String token;
  final _queue = OfflineSalesQueueService.instance;
  late final ApiClient _client = ApiClient(token: token);

  /// Invoked once when a sync attempt is rejected for auth (401/419) so the
  /// app can prompt re-login. The queued sales are left pending and resume
  /// after a successful sign-in — they are never lost to an expired token.
  final void Function()? onAuthRequired;

  OfflineSyncService({required this.token, this.onAuthRequired});

  /// After this many *server-returned* retryable failures a sale is
  /// dead-lettered so it can't loop forever (handover doc G6). Note that a
  /// device simply being offline (network unreachable) does NOT count toward
  /// this cap — that's normal and may last days.
  static const int maxAttempts = 6;

  /// Backoff schedule for retryable server errors: 30s, 1m, 2m, … capped at
  /// 30m, with jitter so a fleet reconnecting together doesn't thundering-herd.
  static Duration _backoffFor(int attempts) {
    const base = 30; // seconds
    const capSeconds = 30 * 60;
    final expSeconds = base * pow(2, (attempts - 1).clamp(0, 10));
    final seconds = expSeconds.clamp(base, capSeconds).toInt();
    final jitter = Random().nextInt((seconds * 0.2).ceil().clamp(1, 60));
    return Duration(seconds: seconds + jitter);
  }

  /// Syncs everything currently pending/failed, oldest occurred_at first.
  ///
  /// [respectBackoff] — when true (automatic triggers) items still inside
  /// their backoff window are skipped; the manual "Sync Now" button passes
  /// false to force a full flush regardless of backoff.
  ///
  /// Stops early if the backend looks unreachable (no point hammering a
  /// down server) or if auth is required (nothing will succeed until the
  /// user signs in again), but keeps going past a single item's transient or
  /// terminal failure so one bad row doesn't block the rest of the batch.
  Future<List<SyncResult>> syncAll({
    void Function(SyncResult result)? onEach,
    bool respectBackoff = true,
  }) async {
    final items = await _queue.pendingOrFailed();
    final results = <SyncResult>[];
    if (items.isEmpty) return results;

    // Cheap first pass: ask the server in ONE call which of these it already
    // has (handover doc §1.4, batched per G8). Anything already saved — e.g.
    // a prior POST whose ack was lost — is marked synced now, so we never
    // re-POST it.
    final reconciled = await _reconcileBatch(items);

    for (final item in items) {
      if (reconciled.contains(item.clientRef)) continue;
      if (respectBackoff && !item.isDueForAutoRetry) continue;

      final result = await syncOne(item, reconcileFirst: false);
      results.add(result);
      onEach?.call(result);

      if (result.outcome == SyncOutcome.stillOffline ||
          result.outcome == SyncOutcome.authRequired) {
        break;
      }
    }
    return results;
  }

  /// Syncs a single queued sale — used by the batch loop and by the sync
  /// screen's per-row "Retry" action (which always tries immediately).
  Future<SyncResult> syncOne(
    OfflineSaleQueueItem item, {
    bool reconcileFirst = true,
  }) async {
    await _queue.markSyncing(item.clientRef);

    try {
      final res = await _client.post('/sales', body: item.payload).timeout(const Duration(seconds: 20));
      // Covers both a fresh create AND the idempotent-replay response
      // (already_existed: true) — either way the sale is confirmed synced.
      final sale = res['data']?['sale'] as Map?;
      final invoiceNo = (sale?['invoice_no'] ?? '').toString();
      await _queue.markSynced(item.clientRef, serverInvoiceNo: invoiceNo);
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.synced, invoiceNo: invoiceNo);
    } catch (e) {
      return _classifyFailure(item, e, reconcileFirst: reconcileFirst);
    }
  }

  Future<SyncResult> _classifyFailure(
    OfflineSaleQueueItem item,
    Object e, {
    required bool reconcileFirst,
  }) async {
    // 1) The server answered, just not with 2xx — status tells us what to do.
    if (e is ApiException) {
      if (e.isAuthFailure) {
        // Token expired/rejected (handover doc G4). Keep the sale pending —
        // it is NOT broken — and signal for re-auth. It resumes after login.
        await _queue.markPending(item.clientRef,
            lastError: 'Session expired — please sign in again to sync.');
        onAuthRequired?.call();
        return SyncResult(
            clientRef: item.clientRef, outcome: SyncOutcome.authRequired, error: e.message);
      }

      if (e.isRetryable) {
        // Transient server/infra error (5xx/429). Back off and retry, up to
        // the cap, then dead-letter so it can't loop forever (handover doc G6).
        return _scheduleOrGiveUp(item, 'Server busy (${e.statusCode}) — will retry: ${e.message}');
      }

      // Terminal business/validation error (422 deleted product, 409 rule,
      // 404, 403). A human must decide — dead-letter it (handover doc G3).
      await _queue.bumpAttempts(item.clientRef, item.attempts + 1);
      await _queue.markFailed(item.clientRef, lastError: _humanize(e));
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.failed, error: e.message);
    }

    // 2) No HTTP response at all — the backend was unreachable.
    if (isNetworkFailure(e)) {
      // Ambiguous: the request may have been saved and only the response
      // lost. Reconcile via verify-batch before deciding (§1.4). Skipped when
      // the batch pass in syncAll already reconciled.
      if (reconcileFirst) {
        final recon = await _tryReconcile(item);
        if (recon != null) return recon;
      }
      // Genuinely offline. Stay pending WITHOUT counting toward the give-up
      // cap — being offline for a while is normal, not a broken sale.
      await _queue.markPending(item.clientRef, lastError: 'Still offline: $e');
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.stillOffline, error: e.toString());
    }

    // 3) Something unexpected (e.g. a malformed response). Treat as retryable
    // rather than instantly terminal, so a transient client-side glitch gets
    // another chance but still can't loop forever.
    return _scheduleOrGiveUp(item, 'Unexpected sync error — will retry: $e');
  }

  /// Applies backoff for a retryable failure, or dead-letters once the cap is
  /// hit (handover doc G6).
  Future<SyncResult> _scheduleOrGiveUp(OfflineSaleQueueItem item, String reason) async {
    final attempts = item.attempts + 1;
    if (attempts >= maxAttempts) {
      await _queue.bumpAttempts(item.clientRef, attempts);
      await _queue.markFailed(item.clientRef,
          lastError: 'Gave up after $attempts attempts. Last error: $reason');
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.failed, error: reason);
    }
    final nextRetryAt = DateTime.now().add(_backoffFor(attempts));
    await _queue.scheduleRetry(item.clientRef,
        attempts: attempts, nextRetryAt: nextRetryAt, lastError: reason);
    return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.retrying, error: reason);
  }

  /// Turns a terminal ApiException into cashier-readable text for the
  /// dead-letter row (handover doc §C).
  String _humanize(ApiException e) {
    switch (e.statusCode) {
      case 404:
        return 'A product or record in this sale no longer exists on the server.';
      case 409:
        return 'This sale conflicts with a business rule on the server: ${e.message}';
      case 422:
        return 'The server rejected this sale: ${e.message}';
      case 403:
        return 'Not allowed to sync this sale (permission): ${e.message}';
      default:
        return 'Server rejected this sale (${e.statusCode}): ${e.message}';
    }
  }

  /// One verify-batch call for every uncertain client_ref (handover doc G8).
  /// Returns the set of client_refs the server confirmed it already has,
  /// marking each synced. Best-effort: on any failure returns an empty set so
  /// the normal per-item path still runs.
  Future<Set<String>> _reconcileBatch(List<OfflineSaleQueueItem> items) async {
    final refs = items.map((i) => i.clientRef).toList();
    if (refs.isEmpty) return <String>{};
    try {
      final res = await _client
          .post('/sales/verify-batch', body: {'client_refs': refs}).timeout(const Duration(seconds: 20));
      final found = (res['data']?['found'] as List?) ?? const [];
      final synced = <String>{};
      for (final raw in found) {
        final match = raw as Map;
        final ref = (match['client_ref'] ?? '').toString();
        if (ref.isEmpty) continue;
        final invoiceNo = (match['invoice_no'] ?? '').toString();
        await _queue.markSynced(ref, serverInvoiceNo: invoiceNo);
        synced.add(ref);
      }
      return synced;
    } catch (_) {
      // verify-batch unreachable — fall through to per-item handling.
      return <String>{};
    }
  }

  Future<SyncResult?> _tryReconcile(OfflineSaleQueueItem item) async {
    try {
      final res = await _client.post('/sales/verify-batch', body: {
        'client_refs': [item.clientRef],
      }).timeout(const Duration(seconds: 20));

      final found = (res['data']?['found'] as List?) ?? const [];
      if (found.isEmpty) return null; // missing -> safe to retry later, not found yet

      final match = found.first as Map;
      final invoiceNo = (match['invoice_no'] ?? '').toString();
      await _queue.markSynced(item.clientRef, serverInvoiceNo: invoiceNo);
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.synced, invoiceNo: invoiceNo);
    } catch (_) {
      // verify-batch itself failed to reach the server -> still offline.
      return null;
    }
  }
}
