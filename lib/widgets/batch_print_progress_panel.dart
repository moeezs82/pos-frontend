import 'dart:io';

import 'package:flutter/material.dart';

import 'package:enterprise_pos/services/batch_print_job_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Floating progress panel — shown while a batch print job is running.
// Survives navigation; the parent (e.g. CounterIQDesktopShell or a root
// Stack) keeps it alive and visible.
// ---------------------------------------------------------------------------

class BatchPrintProgressPanel extends StatelessWidget {
  const BatchPrintProgressPanel({
    super.key,
    required this.job,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpenFolder,
  });

  final BatchPrintJob job;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final void Function(String path)? onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) => _PanelContent(
        job: job,
        onCancel: onCancel,
        onDismiss: onDismiss,
        onOpenFolder: onOpenFolder,
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.job,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpenFolder,
  });

  final BatchPrintJob job;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final void Function(String path)? onOpenFolder;

  Color get _statusColor {
    if (job.status == BatchPrintJobStatus.cancelled) return AppTheme.textMuted;
    if (job.isDone && job.failed > 0) return AppTheme.warning;
    if (job.isDone) return AppTheme.success;
    return AppTheme.primary;
  }

  String get _statusLabel {
    switch (job.status) {
      case BatchPrintJobStatus.queued:
        return 'Preparing…';
      case BatchPrintJobStatus.running:
        return 'Printing ${job.processed} / ${job.totalCount}';
      case BatchPrintJobStatus.cancelled:
        return 'Cancelled (${job.completed} printed)';
      case BatchPrintJobStatus.done:
        if (job.failed == 0) return '${job.completed} invoices printed ✓';
        return '${job.completed} printed · ${job.failed} failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppTheme.border),
            _buildProgressBody(),
            if (job.isDone && job.errors.isNotEmpty) ...[
              const Divider(height: 1, color: AppTheme.border),
              _buildErrorSummary(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 7),
      child: Row(
        children: [
          Icon(
            job.isDone && job.failed == 0
                ? Icons.check_circle_rounded
                : Icons.print_rounded,
            size: 17,
            color: _statusColor,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Batch Print Job',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
          ),
          if (!job.isDone)
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                foregroundColor: AppTheme.danger,
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 11)),
            )
          else
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _statusLabel,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _statusColor,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: job.isDone ? (job.failed == 0 ? 1.0 : null) : job.progress,
              minHeight: 5,
              backgroundColor: AppTheme.surfaceSoft,
              color: _statusColor,
            ),
          ),
          if (job.lastPrintedInvoice != null) ...[
            const SizedBox(height: 5),
            Text(
              'Last: ${job.lastPrintedInvoice}',
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorSummary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: AppTheme.warning),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '${job.errors.length} invoice${job.errors.length == 1 ? '' : 's'} failed',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _showErrorDetail(context),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
            child: const Text('View', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _showErrorDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Print Errors'),
        content: SizedBox(
          width: 480,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: job.errors.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.border),
            itemBuilder: (_, i) {
              final err = job.errors[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      err.invoiceNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      err.message,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact status chip — shown in the app bar / header when on other screens.
// ---------------------------------------------------------------------------

class BatchPrintStatusChip extends StatelessWidget {
  const BatchPrintStatusChip({
    super.key,
    required this.job,
    required this.onTap,
  });

  final BatchPrintJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) {
        if (job.isDone && job.errors.isEmpty) return const SizedBox.shrink();
        final color = job.isDone ? AppTheme.warning : AppTheme.primary;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!job.isDone)
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: color,
                    ),
                  )
                else
                  Icon(Icons.warning_amber_rounded, size: 13, color: color),
                const SizedBox(width: 5),
                Text(
                  job.isDone
                      ? '${job.errors.length} print error${job.errors.length == 1 ? '' : 's'}'
                      : 'Printing ${job.processed}/${job.totalCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Utility: open a folder in the OS file explorer (Windows).
// ---------------------------------------------------------------------------

Future<void> openFolderInExplorer(String folderPath) async {
  try {
    await Process.run('explorer', [folderPath]);
  } catch (e) {
    debugPrint('[BATCH-PRINT] Could not open folder: $e');
  }
}
