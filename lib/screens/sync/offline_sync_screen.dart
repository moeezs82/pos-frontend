import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/services/offline_sync_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';

/// Queued-sales list + "Sync Now" / per-row retry (handover doc §2.4).
/// Every sync attempt here goes through the same POST /sales endpoint a
/// normal online sale uses — this screen only orchestrates the queue, it
/// never posts sale data itself.
class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key});

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

class _OfflineSyncScreenState extends State<OfflineSyncScreen> {
  List<OfflineSaleQueueItem> _items = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _loadError;
  final Set<String> _syncingRefs = {};

  late final OfflineSyncService _syncService;

  bool _authExpired = false;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _syncService = OfflineSyncService(
      token: token,
      onAuthRequired: () {
        // Token rejected mid-sync (handover doc G4). The queued sales stay
        // safely pending; the cashier just needs to sign in again.
        if (!mounted) return;
        _authExpired = true;
        AppFeedback.error(
          context,
          'Your session has expired. Please sign out and sign in again — your unsynced sales are safe and will sync after you do.',
        );
      },
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    // Guarded so a local-DB problem shows a real error with a Retry button
    // instead of spinning forever — this is what silently hung before the
    // Windows sqlite backend was wired up correctly.
    try {
      final all = await OfflineSalesQueueService.instance.all();
      if (!mounted) return;
      setState(() {
        // Newest first for display; sync order (oldest occurred_at first)
        // is handled internally by OfflineSyncService.
        _items = all.reversed.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshBadge() async {
    if (!mounted) return;
    await context.read<OfflineQueueProvider>().refresh();
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _authExpired = false;
    });
    try {
      var synced = 0, failed = 0, retrying = 0;
      // Manual "Sync Now" forces a full flush — ignore per-item backoff
      // windows since the cashier explicitly asked to try right now.
      final results = await _syncService.syncAll(respectBackoff: false);
      for (final r in results) {
        switch (r.outcome) {
          case SyncOutcome.synced:
            synced++;
            break;
          case SyncOutcome.failed:
            failed++;
            break;
          case SyncOutcome.retrying:
            retrying++;
            break;
          case SyncOutcome.stillOffline:
          case SyncOutcome.authRequired:
            break;
        }
      }
      await _load();
      await _refreshBadge();
      if (!mounted) return;

      final last = results.isNotEmpty ? results.last.outcome : null;
      if (_authExpired || last == SyncOutcome.authRequired) {
        // The onAuthRequired callback already surfaced the re-auth message.
      } else if (last == SyncOutcome.stillOffline) {
        AppFeedback.warning(context, "Still offline — couldn't reach the backend. $synced synced before stopping.");
      } else if (failed > 0) {
        AppFeedback.warning(context, "$synced synced, $failed need manual review, $retrying will retry.");
      } else if (retrying > 0) {
        AppFeedback.info(context, "$synced synced. $retrying will retry automatically shortly.");
      } else if (synced > 0) {
        AppFeedback.success(context, "$synced sale(s) synced successfully.");
      } else {
        AppFeedback.info(context, "Nothing to sync.");
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _retryOne(OfflineSaleQueueItem item) async {
    setState(() => _syncingRefs.add(item.clientRef));
    try {
      final result = await _syncService.syncOne(item);
      await _load();
      await _refreshBadge();
      if (!mounted) return;
      switch (result.outcome) {
        case SyncOutcome.synced:
          AppFeedback.success(context, "Synced as ${result.invoiceNo}.");
          break;
        case SyncOutcome.stillOffline:
          AppFeedback.warning(context, "Still offline — couldn't reach the backend.");
          break;
        case SyncOutcome.retrying:
          AppFeedback.info(context, "Server busy — this sale will retry automatically shortly.");
          break;
        case SyncOutcome.authRequired:
          // onAuthRequired already showed the re-auth message.
          break;
        case SyncOutcome.failed:
          AppFeedback.error(context, "Needs review: ${result.error}");
          break;
      }
    } finally {
      if (mounted) setState(() => _syncingRefs.remove(item.clientRef));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrFailed = _items.where((i) => i.status != OfflineSaleStatus.synced).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Sales Sync'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load the offline queue.\n$_loadError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.surfaceSoft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pendingOrFailed == 0
                              ? 'All sales are synced.'
                              : '$pendingOrFailed sale(s) waiting to sync.',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: (_syncing || pendingOrFailed == 0) ? null : _syncAll,
                        icon: _syncing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync_rounded),
                        label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No offline sales recorded yet.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _QueueRow(
                            item: _items[i],
                            busy: _syncingRefs.contains(_items[i].clientRef),
                            onRetry: () => _retryOne(_items[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final OfflineSaleQueueItem item;
  final bool busy;
  final VoidCallback onRetry;

  const _QueueRow({required this.item, required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final canRetry = item.status == OfflineSaleStatus.pending || item.status == OfflineSaleStatus.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _StatusDot(status: item.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayCustomerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '${_formatDateTime(item.occurredAt)}  •  \$${item.displayTotal.toStringAsFixed(2)}'
                  '${item.attempts > 0 ? '  •  ${item.attempts} attempt${item.attempts == 1 ? '' : 's'}' : ''}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                if (item.status == OfflineSaleStatus.synced && item.serverInvoiceNo != null) ...[
                  const SizedBox(height: 2),
                  Text('Synced as ${item.serverInvoiceNo}', style: const TextStyle(color: AppTheme.success, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
                if (item.status != OfflineSaleStatus.synced && item.lastError != null && item.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.status == OfflineSaleStatus.failed ? item.lastError! : 'Queued: ${item.lastError}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.status == OfflineSaleStatus.failed ? AppTheme.danger : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: item.status == OfflineSaleStatus.failed ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canRetry)
            busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Retry',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _StatusDot extends StatelessWidget {
  final OfflineSaleStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      OfflineSaleStatus.pending => (AppTheme.warning, Icons.schedule_rounded),
      OfflineSaleStatus.syncing => (AppTheme.info, Icons.sync_rounded),
      OfflineSaleStatus.synced => (AppTheme.success, Icons.check_circle_rounded),
      OfflineSaleStatus.failed => (AppTheme.danger, Icons.error_rounded),
    };
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
