import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/utils/network_failure.dart';

enum SyncOutcome { synced, stillOffline, failed }

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
/// endpoint/code path a normal online sale uses (handover doc §2.4, §3 —
/// there is no separate "bulk import" endpoint). Also handles the
/// verify-batch reconciliation for ambiguous (timed-out) sync attempts.
class OfflineSyncService {
  final String token;
  final _queue = OfflineSalesQueueService.instance;
  late final ApiClient _client = ApiClient(token: token);

  OfflineSyncService({required this.token});

  /// Syncs everything currently pending/failed, oldest occurred_at first
  /// (keeps same-day invoice numbering roughly chronological, §1.3/§2.4).
  /// Stops as soon as the backend looks unreachable again — no point
  /// hammering a still-down server — but keeps going past a single item's
  /// validation failure so one bad row doesn't block the rest of the batch.
  Future<List<SyncResult>> syncAll({void Function(SyncResult result)? onEach}) async {
    final items = await _queue.pendingOrFailed();
    final results = <SyncResult>[];
    for (final item in items) {
      final result = await syncOne(item);
      results.add(result);
      onEach?.call(result);
      if (result.outcome == SyncOutcome.stillOffline) break;
    }
    return results;
  }

  /// Syncs a single queued sale — used both by the batch loop above and by
  /// the sync screen's per-row "Retry" action.
  Future<SyncResult> syncOne(OfflineSaleQueueItem item) async {
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
      if (isNetworkFailure(e)) {
        // Ambiguous: the request may never have reached the server, or it
        // may have been saved and only the response was lost. Reconcile via
        // verify-batch before deciding whether it's safe to retry (§1.4).
        final reconciled = await _tryReconcile(item);
        if (reconciled != null) return reconciled;

        await _queue.markPending(item.clientRef, lastError: 'Still offline: $e');
        return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.stillOffline, error: e.toString());
      }

      // A real validation/server error (e.g. HTTP 422 — a product in this
      // offline sale was deleted in the meantime). This needs a human
      // decision, so don't auto-retry forever.
      await _queue.markFailed(item.clientRef, lastError: e.toString());
      return SyncResult(clientRef: item.clientRef, outcome: SyncOutcome.failed, error: e.toString());
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
