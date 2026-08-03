import 'dart:convert';
import 'dart:math';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/utils/line_errors.dart';
import 'package:enterprise_pos/utils/network_failure.dart';

/// Result of trying to sync one queued sale.
/// - synced        the server has it (fresh create or idempotent replay).
/// - stillOffline  the backend is unreachable; item stays pending.
/// - retrying      a transient server error; item stays pending with backoff.
/// - authRequired  the token was rejected (401/419); sync paused for re-auth.
/// - failed        a terminal/business error; item is dead-lettered.
enum SyncOutcome { synced, stillOffline, retrying, authRequired, contextChanged, failed }

class SyncResult {
  final String clientRef;
  final SyncOutcome outcome;
  final String? invoiceNo;

  /// The customer-facing offline reference returned by the server after sync
  /// (mirrors what the device sent in the sale payload as offline_invoice_no).
  final String? offlineInvoiceNo;
  final String? error;

  SyncResult({
    required this.clientRef,
    required this.outcome,
    this.invoiceNo,
    this.offlineInvoiceNo,
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
  final int branchId;
  final _queue = OfflineSalesQueueService.instance;
  late final ApiClient _client = ApiClient(token: token);

  /// Invoked once when a sync attempt is rejected for auth (401/419) so the
  /// app can prompt re-login. The queued sales are left pending and resume
  /// after a successful sign-in — they are never lost to an expired token.
  final void Function()? onAuthRequired;

  OfflineSyncService({
    required this.token,
    required this.branchId,
    this.onAuthRequired,
  }) {
    if (branchId <= 0) {
      throw ArgumentError.value(branchId, 'branchId', 'A valid branch is required for offline sync.');
    }
  }

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

  /// Syncs everything currently `pending`, oldest occurred_at first.
  /// `failed` (dead-lettered) items are excluded — they need explicit
  /// manager correction via [updatePayloadAndReset] before they can sync.
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
    // Use pending() — not pendingOrFailed() — so dead-lettered (failed) items
    // are never automatically retried. They require explicit manager review and
    // correction via updatePayloadAndReset() before they re-enter the queue.
    final items = await _queue.pending(branchId: branchId);
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
          result.outcome == SyncOutcome.authRequired ||
          result.outcome == SyncOutcome.contextChanged) {
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
    if (item.originBranchId != branchId) {
      const message =
          'Business context changed. This sale remains queued for its original business.';
      await _queue.markPending(item.clientRef, lastError: message);
      return SyncResult(
        clientRef: item.clientRef,
        outcome: SyncOutcome.contextChanged,
        error: message,
      );
    }
    await _queue.markSyncing(item.clientRef);

    try {
      final payload = Map<String, dynamic>.from(item.payload)
        ..['origin_branch_id'] = branchId;
      final res = await _client
          .post('/sales', body: payload)
          .timeout(const Duration(seconds: 20));
      // Covers both a fresh create AND the idempotent-replay response
      // (already_existed: true) — either way the sale is confirmed synced.
      final data = res['data'] as Map? ?? {};
      final sale = data['sale'] as Map? ?? {};
      // invoice_no is also returned at the top level of data for convenience.
      final invoiceNo = (data['invoice_no'] ?? sale['invoice_no'] ?? '').toString();
      final offlineInvoiceNo = (data['offline_invoice_no'] ?? sale['offline_invoice_no'])?.toString();
      await _queue.markSynced(
        item.clientRef,
        serverInvoiceNo: invoiceNo,
        offlineInvoiceNo: offlineInvoiceNo,
      );
      return SyncResult(
        clientRef: item.clientRef,
        outcome: SyncOutcome.synced,
        invoiceNo: invoiceNo,
        offlineInvoiceNo: offlineInvoiceNo,
      );
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
      final code = e.body?['code']?.toString() ?? '';
      if (e.statusCode == 409 && code == 'TENANT_CONTEXT_MISMATCH') {
        const message =
            'Business context changed. This sale remains queued for its original business.';
        await _queue.markPending(item.clientRef, lastError: message);
        return SyncResult(
          clientRef: item.clientRef,
          outcome: SyncOutcome.contextChanged,
          error: message,
        );
      }
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

      // 402 — branch subscription lock. This is a branch-level block, not a
      // problem with the sale payload. Dead-letter immediately with a clear
      // subscription message — retrying will not help until the subscription
      // is fixed by the platform administrator.
      if (e.statusCode == 402) {
        await _queue.bumpAttempts(item.clientRef, item.attempts + 1);
        await _queue.markFailed(item.clientRef, lastError: _humanize(e));
        return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.failed, error: e.message);
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
      case 402:
        // Distinguish the two subscription codes so the message is actionable.
        final code = e.body?['code']?.toString() ?? '';
        if (code == 'BRANCH_SUBSCRIPTION_NOT_CONFIGURED') {
          return 'This branch has no subscription configured. '
              'Contact the platform administrator to activate the branch before sales can be synced.';
        }
        return 'This branch\'s subscription has expired or been suspended. '
            'Contact the administrator to reactivate the subscription before sales can be synced.';
      case 404:
        return 'A product or record in this sale no longer exists on the server.';
      case 409:
        final code = e.body?['code']?.toString() ?? '';
        if (code == 'OFFLINE_INVOICE_NO_COLLISION') {
          final offlineNo = (e.body?['data'] as Map?)?['offline_invoice_no']?.toString() ?? '';
          final conflictingNo = (e.body?['data'] as Map?)?['conflicting_invoice_no']?.toString() ?? '';
          return 'Offline reference number${offlineNo.isNotEmpty ? " $offlineNo" : ""} '
              'is already recorded against a different sale'
              '${conflictingNo.isNotEmpty ? " ($conflictingNo)" : ""}. '
              'Two terminals may share the same register code, or the offline '
              'sequence was reset (reinstall / data clear). '
              'This sale must be manually reconciled — contact your administrator.';
        }
        if (code == 'TENANT_CONTEXT_MISMATCH') {
          return 'The active business changed while this sale was syncing. '
              'Switch back to the original business before retrying it.';
        }
        if (code == 'TENANT_REFERENCE_MISMATCH') {
          return 'This sale reference is already owned by another business context. '
              'The sale was not posted and requires manual reconciliation.';
        }
        return 'This sale conflicts with a business rule on the server: ${e.message}';
      case 422:
        final code = e.body?['code']?.toString() ?? '';
        if (code == 'PARTY_CREDIT_LIMIT_EXCEEDED') {
          final data = e.body?['data'];
          final map = data is Map
              ? data.map((key, value) => MapEntry(key.toString(), value))
              : <String, dynamic>{};
          final party = map['party_type']?.toString() == 'vendor'
              ? 'Vendor'
              : 'Customer';
          final projected = map['projected_balance']?.toString() ?? '?';
          final limit = map['credit_limit']?.toString() ?? '?';
          return 'PARTY_CREDIT_LIMIT_EXCEEDED\n'
              'CREDIT_LIMIT_DATA:${jsonEncode(map)}\n'
              '$party trade balance would become $projected, above the configured limit of $limit. '
              'An authorized user must approve and re-queue this same sale; creating a new invoice is not required.';
        }
        // Append the field bag, one `key: message` per line. The dead-letter
        // row is the only record of WHY this sale was refused — e.message is
        // just the first sentence, and without the keys the review screen
        // cannot tell which cart line the complaint is about.
        // OfflineSaleDetailScreen parses this exact shape.
        final bag = formatBagForStorage(e.body?['errors']);
        if (bag.isNotEmpty) {
          return 'The server rejected this sale: ${e.message}\n$bag';
        }
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
          .post('/sales/verify-batch', body: {'client_refs': refs, 'origin_branch_id': branchId}).timeout(const Duration(seconds: 20));
      final found = (res['data']?['found'] as List?) ?? const [];
      final synced = <String>{};
      for (final raw in found) {
        final match = raw as Map;
        final ref = (match['client_ref'] ?? '').toString();
        if (ref.isEmpty) continue;
        final invoiceNo = (match['invoice_no'] ?? '').toString();
        final offlineInvoiceNo = match['offline_invoice_no']?.toString();
        await _queue.markSynced(
          ref,
          serverInvoiceNo: invoiceNo,
          offlineInvoiceNo: offlineInvoiceNo,
        );
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
        'origin_branch_id': branchId,
      }).timeout(const Duration(seconds: 20));

      final found = (res['data']?['found'] as List?) ?? const [];
      if (found.isEmpty) return null; // missing -> safe to retry later, not found yet

      final match = found.first as Map;
      final invoiceNo = (match['invoice_no'] ?? '').toString();
      final offlineInvoiceNo = match['offline_invoice_no']?.toString();
      await _queue.markSynced(
        item.clientRef,
        serverInvoiceNo: invoiceNo,
        offlineInvoiceNo: offlineInvoiceNo,
      );
      return SyncResult(
        clientRef: item.clientRef,
        outcome: SyncOutcome.synced,
        invoiceNo: invoiceNo,
        offlineInvoiceNo: offlineInvoiceNo,
      );
    } catch (_) {
      // verify-batch itself failed to reach the server -> still offline.
      return null;
    }
  }
}
