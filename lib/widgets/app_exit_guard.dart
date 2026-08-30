import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:enterprise_pos/api/backup_service.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/screens/settings/backup_restore_screen.dart';
import 'package:enterprise_pos/screens/sync/offline_sync_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Intercepts a desktop application close request and gives the cashier a
/// final operational safety check before CounterIQ exits.
///
/// This intentionally does not auto-close a register or auto-create a backup:
/// both workflows already contain important validation/approval steps. The
/// dialog only surfaces the live state and takes the user to the proper screen.
class AppExitGuard extends StatefulWidget {
  final Widget child;

  const AppExitGuard({super.key, required this.child});

  @override
  State<AppExitGuard> createState() => _AppExitGuardState();
}

class _AppExitGuardState extends State<AppExitGuard> with WidgetsBindingObserver {
  bool _handlingExit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!Platform.isWindows || _handlingExit || !mounted) {
      return _handlingExit ? AppExitResponse.cancel : AppExitResponse.exit;
    }

    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return AppExitResponse.exit;

    _handlingExit = true;
    try {
      // Refresh local/live indicators without making application exit depend on
      // network availability. The dialog can still open with cached state.
      unawaited(_refreshSafetyState());

      final overlayContext = appNavigatorKey.currentState?.overlay?.context;
      if (overlayContext == null) return AppExitResponse.exit;

      final decision = await showDialog<_ExitDecision>(
        context: overlayContext,
        barrierDismissible: false,
        builder: (_) => const _ExitSafetyDialog(),
      );

      switch (decision) {
        case _ExitDecision.exit:
          return AppExitResponse.exit;
        case _ExitDecision.backup:
          _openAfterExitCancelled(
            PosRouteIds.backupRestore,
            (_) => const BackupRestoreScreen(),
          );
          return AppExitResponse.cancel;
        case _ExitDecision.register:
          _openAfterExitCancelled(
            PosRouteIds.registerShift,
            (_) => const RegisterShiftScreen(),
          );
          return AppExitResponse.cancel;
        case _ExitDecision.sync:
          _openAfterExitCancelled(
            PosRouteIds.offlineSync,
            (_) => const OfflineSyncScreen(),
          );
          return AppExitResponse.cancel;
        case _ExitDecision.cancel:
        case null:
          return AppExitResponse.cancel;
      }
    } finally {
      _handlingExit = false;
    }
  }

  Future<void> _refreshSafetyState() async {
    try {
      await context.read<OfflineQueueProvider>().refresh();
    } catch (_) {}
    if (!mounted) return;
    try {
      await context.read<RegisterShiftProvider>().refresh();
    } catch (_) {}
  }

  void _openAfterExitCancelled(String routeId, WidgetBuilder builder) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PosNavigation.openSingleton(routeId: routeId, builder: builder);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _ExitDecision { cancel, backup, register, sync, exit }

class _ExitSafetyDialog extends StatefulWidget {
  const _ExitSafetyDialog();

  @override
  State<_ExitSafetyDialog> createState() => _ExitSafetyDialogState();
}

class _ExitSafetyDialogState extends State<_ExitSafetyDialog> {
  Map<String, dynamic>? _backupStatus;
  bool _loadingBackup = false;
  bool _backupStatusFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBackupStatus());
  }

  Future<void> _loadBackupStatus() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final canAccessBackup = auth.hasAnyPermission(const [
      'create-backups',
      'restore-backups',
    ]);
    if (!BackendConfig.isLocal || !Platform.isWindows || !canAccessBackup || auth.token == null) {
      return;
    }

    setState(() => _loadingBackup = true);
    try {
      final status = await BackupService(token: auth.token!)
          .status()
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() => _backupStatus = status);
    } catch (_) {
      if (!mounted) return;
      setState(() => _backupStatusFailed = true);
    } finally {
      if (mounted) setState(() => _loadingBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final offline = context.watch<OfflineQueueProvider>();
    final register = context.watch<RegisterShiftProvider>();

    final pending = offline.pendingCount;
    final hasActiveShift = register.hasActiveShift;
    final closePending = register.hasPendingCloseRequest;
    final canOpenRegister = auth.hasAnyPermission(const [
      'view-register-shifts',
      'open-register-shift',
      'close-own-register-shift',
      'manage-register-shifts',
    ]);
    final canCreateBackup = BackendConfig.isLocal && auth.hasPermission('create-backups');
    final canAccessBackup = BackendConfig.isLocal && auth.hasAnyPermission(const [
      'create-backups',
      'restore-backups',
    ]);

    final lastBackup = _asMap(_backupStatus?['last_backup']);
    final lastBackupAt = DateTime.tryParse(lastBackup['at']?.toString() ?? '')?.toLocal();

    final backupTone = lastBackupAt != null
        ? AppTheme.success
        : _backupStatusFailed
            ? AppTheme.warning
            : AppTheme.danger;
    final backupTitle = lastBackupAt != null
        ? 'Backup recorded'
        : _loadingBackup
            ? 'Checking backup status...'
            : _backupStatusFailed
                ? 'Backup status unavailable'
                : canAccessBackup
                    ? 'No backup recorded yet'
                    : 'Backup access restricted';
    final backupDetail = lastBackupAt != null
        ? 'Last successful backup: ${_formatDate(lastBackupAt)}'
        : _loadingBackup
            ? 'Checking the latest successful CounterIQ backup.'
            : _backupStatusFailed
                ? 'CounterIQ could not confirm the latest backup right now.'
                : canAccessBackup
                    ? 'Create a backup before leaving if today’s work is not protected yet.'
                    : 'An authorized user should confirm the business backup schedule.';

    final registerTone = closePending
        ? AppTheme.warning
        : hasActiveShift
            ? AppTheme.warning
            : AppTheme.success;
    final registerTitle = closePending
        ? 'Register close awaiting approval'
        : hasActiveShift
            ? 'Register shift is still open'
            : 'No open register shift';
    final registerDetail = closePending
        ? 'A closing request is pending manager approval. Review it before ending the shift.'
        : hasActiveShift
            ? 'If your shift is finished, close and reconcile the register before leaving.'
            : 'There is no active register shift assigned to this session.';

    final syncTone = pending > 0 ? AppTheme.danger : AppTheme.success;
    final syncTitle = pending > 0
        ? '$pending sale${pending == 1 ? '' : 's'} waiting to sync'
        : 'Sales are synced';
    final syncDetail = pending > 0
        ? 'Sync pending sales to the CounterIQ host before leaving so no workstation data is left behind.'
        : 'There are no offline sales waiting to be sent to the host.';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.power_settings_new_rounded, color: AppTheme.warning),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Before closing CounterIQ'),
                  SizedBox(height: 3),
                  Text(
                    'Make sure today’s work is safely completed before you exit.',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SafetyRow(
                icon: Icons.backup_rounded,
                color: backupTone,
                title: backupTitle,
                detail: backupDetail,
                loading: _loadingBackup,
                actionLabel: canCreateBackup ? 'Backup & Restore' : null,
                onAction: canCreateBackup
                    ? () => Navigator.of(context).pop(_ExitDecision.backup)
                    : null,
              ),
              const SizedBox(height: 10),
              _SafetyRow(
                icon: Icons.point_of_sale_rounded,
                color: registerTone,
                title: registerTitle,
                detail: registerDetail,
                actionLabel: hasActiveShift && canOpenRegister ? 'Open Register' : null,
                onAction: hasActiveShift && canOpenRegister
                    ? () => Navigator.of(context).pop(_ExitDecision.register)
                    : null,
              ),
              const SizedBox(height: 10),
              _SafetyRow(
                icon: pending > 0 ? Icons.sync_problem_rounded : Icons.cloud_done_rounded,
                color: syncTone,
                title: syncTitle,
                detail: syncDetail,
                actionLabel: pending > 0 ? 'Review Sync' : null,
                onAction: pending > 0
                    ? () => Navigator.of(context).pop(_ExitDecision.sync)
                    : null,
              ),
              if (pending > 0 || hasActiveShift || lastBackupAt == null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.warning.withOpacity(.22)),
                  ),
                  child: const Text(
                    'You can still close CounterIQ if you are not ending the shift. Open registers are not closed automatically.',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.35),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ExitDecision.cancel),
            child: const Text('Continue Working'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(context).pop(_ExitDecision.exit),
            icon: const Icon(Icons.power_settings_new_rounded),
            label: const Text('Close CounterIQ Anyway'),
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  static String _formatDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final difference = today.difference(date).inDays;
    final time = DateFormat('hh:mm a').format(value);
    if (difference == 0) return 'Today, $time';
    if (difference == 1) return 'Yesterday, $time';
    return DateFormat('dd MMM yyyy, hh:mm a').format(value);
  }
}

class _SafetyRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  const _SafetyRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        color: Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.35),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
