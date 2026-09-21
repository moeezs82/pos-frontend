import 'package:enterprise_pos/api/backup_service.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/services/local_backup_client_state_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

enum BackupRunOutcome {
  /// A verified .ciqbak was written to the destination the user chose.
  created,

  /// The user closed the Save As dialog without choosing a destination.
  cancelled,

  /// CounterIQ refused to start, e.g. unsynced offline sales on a workstation.
  blocked,

  /// The backup was attempted and failed. The error has already been shown.
  failed,
}

class BackupRunResult {
  final BackupRunOutcome outcome;

  /// Refreshed `/backups/status` payload, present only after a successful run
  /// so a caller that displays recovery history can update without re-fetching.
  final Map<String, dynamic>? status;

  const BackupRunResult(this.outcome, {this.status});

  bool get created => outcome == BackupRunOutcome.created;
}

/// The single "create a backup" workflow.
///
/// Backup & Restore and the scheduled backup reminder both drive this service
/// rather than owning their own copy of the flow, so the destination prompt,
/// the client-state staging rules, the verification step and the result dialog
/// can never drift apart between the two entry points.
///
/// Presentation only: this service coordinates the existing [BackupService]
/// and [LocalBackupClientStateService]. It performs no accounting, inventory
/// or database work of its own.
class BackupRunnerService {
  BackupRunnerService._();

  static final instance = BackupRunnerService._();

  /// Prompts for a destination, has the host create and verify the backup,
  /// streams it to that destination and reports the outcome.
  ///
  /// [onBusy] receives the current operation caption, or null when idle, so
  /// the caller can render its own progress affordance.
  Future<BackupRunResult> run(
    BuildContext context, {
    required BackupService service,
    ValueChanged<String?>? onBusy,
  }) async {
    // A workstation with unsynced sales would otherwise back up a database
    // that does not yet contain them.
    if (BackendConfig.isLocalClient &&
        context.read<OfflineQueueProvider>().pendingCount > 0) {
      showError(
        context,
        'Sync required',
        Exception(
          'This workstation has sales waiting to sync. Sync them to the CounterIQ host before creating the business backup so the backup contains the latest sales.',
        ),
      );
      return const BackupRunResult(BackupRunOutcome.blocked);
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save CounterIQ backup',
      fileName: suggestedFilename(),
      type: FileType.custom,
      allowedExtensions: const ['ciqbak'],
    );
    if (path == null || !context.mounted) {
      return const BackupRunResult(BackupRunOutcome.cancelled);
    }
    final destination =
        path.toLowerCase().endsWith('.ciqbak') ? path : '$path.ciqbak';

    String? staging;
    onBusy?.call(BackendConfig.isLocalClient
        ? 'Creating and downloading a verified backup from the CounterIQ host PC...'
        : 'Creating a verified backup of the database and uploaded files...');
    try {
      // Frontend-owned offline state exists only on the workstation itself. It
      // can safely be embedded when this is the HOST workstation because the
      // staging directory is inside the same CounterIQData tree the backend
      // owns. A LAN client never sends its C:\ path to the host.
      if (BackendConfig.isLocalHost) {
        staging =
            await LocalBackupClientStateService.instance.createStagingSnapshot();
      }

      await service.exportBackupToFile(
        destinationPath: destination,
        clientStateDir: staging,
      );

      Map<String, dynamic> manifest = <String, dynamic>{};
      Map<String, dynamic>? status;
      try {
        status = await service.status();
        final lastBackup = _asMap(status['last_backup']);
        manifest = _asMap(lastBackup['manifest']);
      } catch (_) {
        // The backup itself succeeded. Recovery history is informational.
      }

      if (!context.mounted) {
        return BackupRunResult(BackupRunOutcome.created, status: status);
      }
      onBusy?.call(null);
      await _showBackupCreated(context, destination, manifest);
      return BackupRunResult(BackupRunOutcome.created, status: status);
    } catch (error) {
      if (context.mounted) {
        onBusy?.call(null);
        showError(context, 'Backup failed', error);
      }
      return const BackupRunResult(BackupRunOutcome.failed);
    } finally {
      if (BackendConfig.isLocalHost) {
        await LocalBackupClientStateService.instance.cleanupStaging(staging);
      }
      onBusy?.call(null);
    }
  }

  Future<void> _showBackupCreated(
    BuildContext context,
    String path,
    Map<String, dynamic> manifest,
  ) {
    final counts = _asMap(manifest['counts']);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon:
            const Icon(Icons.verified_rounded, color: AppTheme.success, size: 44),
        title: const Text('Backup created'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CounterIQ verified the backup after writing it.'),
              const SizedBox(height: 12),
              infoRow('Customers', '${counts['customers'] ?? 0}'),
              infoRow('Products', '${counts['products'] ?? 0}'),
              infoRow('Sales', '${counts['sales'] ?? 0}'),
              const SizedBox(height: 12),
              Text(path, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              const Text(
                'Keep at least one backup outside this computer (for example on a USB drive, NAS or cloud-synced folder).',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  static void showError(BuildContext context, String title, Object error) {
    final message = error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|ApiException\([^)]*\)):\s*'), '');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String suggestedFilename() {
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    return 'CounterIQ-Backup-$stamp.ciqbak';
  }

  static Widget infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  static String formatDate(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }
}
