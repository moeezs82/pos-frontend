import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/screens/sync/offline_sale_detail_screen.dart';
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
    try {
      final all = await OfflineSalesQueueService.instance.all();
      if (!mounted) return;
      setState(() {
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
        // onAuthRequired callback already surfaced the re-auth message.
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

  /// Opens the full detail screen for ANY dead-lettered sale.
  ///
  /// The detail screen lets a manager view the complete invoice, then either:
  ///   • Create as New Sale — posts a replica with a fresh client_ref, no
  ///     offline_invoice_no, and removes the dead-lettered row on success.
  ///   • Discard — hard-deletes the row after confirmation.
  ///
  /// Returns `true` when the queue changed so we reload the list.
  Future<void> _viewDetails(OfflineSaleQueueItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OfflineSaleDetailScreen(item: item),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      await _refreshBadge();
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
                              itemBuilder: (_, i) {
                                final item = _items[i];
                                final isCollision = _isCollisionError(item);
                                return _QueueRow(
                                  item: item,
                                  busy: _syncingRefs.contains(item.clientRef),
                                  isCollision: isCollision,
                                  onRetry: () => _retryOne(item),
                                  onViewDetails: item.status == OfflineSaleStatus.failed
                                      ? () => _viewDetails(item)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  /// True when a dead-lettered item failed specifically due to an
  /// offline_invoice_no collision — i.e., the error requires assigning a
  /// new reference number rather than fixing a business-validation field.
  bool _isCollisionError(OfflineSaleQueueItem item) {
    final err = item.lastError ?? '';
    return item.status == OfflineSaleStatus.failed &&
        (err.contains('already recorded against a different sale') ||
         err.contains('OFFLINE_INVOICE_NO_COLLISION'));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Queue row
// ─────────────────────────────────────────────────────────────────────────────

class _QueueRow extends StatelessWidget {
  final OfflineSaleQueueItem item;
  final bool busy;
  final bool isCollision;
  final VoidCallback onRetry;

  /// Non-null for all failed items — opens the full detail / replay screen.
  final VoidCallback? onViewDetails;

  const _QueueRow({
    required this.item,
    required this.busy,
    required this.onRetry,
    this.isCollision = false,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final canRetry = item.status == OfflineSaleStatus.pending ||
        item.status == OfflineSaleStatus.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.status == OfflineSaleStatus.failed
              ? (isCollision
                  ? AppTheme.warning.withOpacity(.5)
                  : AppTheme.danger.withOpacity(.3))
              : AppTheme.border,
          width: item.status == OfflineSaleStatus.failed ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _StatusDot(status: item.status, isCollision: isCollision),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.displayCustomerName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    // Show collision chip for ref-collision dead letters.
                    if (isCollision)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppTheme.warning.withOpacity(.4)),
                        ),
                        child: const Text(
                          'REF COLLISION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.warning,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDateTime(item.occurredAt)}  •  '
                  '${AppCurrency.format(item.displayTotal)}'
                  '${item.attempts > 0 ? '  •  ${item.attempts} attempt${item.attempts == 1 ? '' : 's'}' : ''}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.offlineInvoiceNo != null &&
                    item.status != OfflineSaleStatus.synced) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Receipt ref: ${item.offlineInvoiceNo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isCollision
                          ? AppTheme.warning
                          : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (item.status == OfflineSaleStatus.synced &&
                    item.serverInvoiceNo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Synced as ${item.serverInvoiceNo}',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (item.status != OfflineSaleStatus.synced &&
                    item.lastError != null &&
                    item.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.status == OfflineSaleStatus.failed
                        ? item.lastError!
                        : 'Queued: ${item.lastError}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.status == OfflineSaleStatus.failed
                          ? AppTheme.danger
                          : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: item.status == OfflineSaleStatus.failed
                          ? FontWeight.w600
                          : FontWeight.w500,
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
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // View Details — opens the full invoice + replay screen.
                      // Available for all failed items regardless of error type.
                      if (onViewDetails != null)
                        Tooltip(
                          message: 'View details & recovery options',
                          child: IconButton(
                            onPressed: onViewDetails,
                            icon: const Icon(
                                Icons.receipt_long_rounded, size: 20),
                            color: AppTheme.info,
                          ),
                        ),
                      Tooltip(
                        message: item.status == OfflineSaleStatus.failed
                            ? 'Retry as-is (without editing)'
                            : 'Retry',
                        child: IconButton(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ),
                    ],
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


// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final OfflineSaleStatus status;
  final bool isCollision;

  const _StatusDot({required this.status, this.isCollision = false});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = isCollision
        ? (AppTheme.warning, Icons.swap_horiz_rounded)
        : switch (status) {
            OfflineSaleStatus.pending => (AppTheme.warning, Icons.schedule_rounded),
            OfflineSaleStatus.syncing => (AppTheme.info, Icons.sync_rounded),
            OfflineSaleStatus.synced  => (AppTheme.success, Icons.check_circle_rounded),
            OfflineSaleStatus.failed  => (AppTheme.danger, Icons.error_rounded),
          };
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
