import 'dart:async';
import 'dart:io';

import 'package:enterprise_pos/api/backup_service.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/backup_runner_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Host-only scheduled backup reminder.
///
/// This is a REMINDER, not an automatic backup: CounterIQ never writes a
/// backup without the operator choosing a destination, because the whole point
/// of the file is that it leaves this computer.
///
/// Placement rules, in order:
///  - Host Windows workstation only. A LAN client is not where the shared
///    database lives, and the reminder would be noise on every till.
///  - Only users holding `create-backups`, so a cashier is never shown a
///    dialog they cannot action.
///  - Only while the host screen is the current route, so the dialog can never
///    interrupt a sale, purchase or register operation in progress. It simply
///    waits until the user returns.
///  - Never blocking. Even when escalated the dialog can be dismissed; a POS
///    till must not be held hostage by a housekeeping prompt.
class BackupReminderGate extends StatefulWidget {
  const BackupReminderGate({super.key});

  @override
  State<BackupReminderGate> createState() => _BackupReminderGateState();
}

// A 6-hour default cadence means "once per app launch" is not enough: a till
// that never closes CounterIQ would see the reminder at login and never again.
// The gate therefore re-checks on a timer. Thirty minutes is ample resolution
// for a 6-hour interval and costs one loopback request.
const Duration _recheckInterval = Duration(minutes: 30);

/// Fallback used only when the host could not record a snooze, so a failed
/// snooze cannot turn into a dialog on every timer tick.
const Duration _localSnoozeFallback = Duration(hours: 1);

class _BackupReminderGateState extends State<BackupReminderGate> {
  Timer? _timer;
  bool _dialogOpen = false;
  bool _checking = false;
  bool _busyShown = false;
  DateTime? _suppressUntil;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(_recheckInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _supported => BackendConfig.isLocalHost && Platform.isWindows;

  Future<void> _check() async {
    if (!_supported || _checking || _dialogOpen || !mounted) return;
    final suppress = _suppressUntil;
    if (suppress != null && DateTime.now().isBefore(suppress)) return;

    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || !auth.hasPermission('create-backups')) return;

    // Never surface over a pushed route. A reminder that lands on top of a
    // half-finished sale is worse than a late reminder.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    _checking = true;
    try {
      final service = BackupService(token: token);
      final state = await service.reminder();
      if (!mounted || state['due'] != true) return;
      await _showReminder(service, state);
    } catch (_) {
      // The reminder is advisory. A transient backend hiccup must never
      // surface an error dialog on the home screen.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showReminder(
    BackupService service,
    Map<String, dynamic> state,
  ) async {
    final escalated = state['escalated'] == true;
    final lastBackupAt = state['last_backup_at']?.toString();
    final hours = (state['hours_since_backup'] as num?)?.toDouble();

    _dialogOpen = true;
    try {
      final backUpNow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            escalated
                ? Icons.warning_amber_rounded
                : Icons.backup_outlined,
            color: escalated ? AppTheme.danger : AppTheme.primary,
            size: 44,
          ),
          title: Text(escalated ? 'Your backup is overdue' : 'Time to back up'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ageSentence(lastBackupAt, hours),
                  style: TextStyle(
                    fontWeight: escalated ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Creating a backup takes a moment and asks where to save the file. '
                  'Keep at least one copy outside this computer.',
                ),
                if (lastBackupAt != null) ...[
                  const SizedBox(height: 12),
                  BackupRunnerService.infoRow(
                    'Last backup',
                    BackupRunnerService.formatDate(lastBackupAt),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.backup_rounded),
              label: const Text('Back Up Now'),
            ),
          ],
        ),
      );
      if (!mounted) return;

      if (backUpNow == true) {
        final result = await BackupRunnerService.instance.run(
          context,
          service: service,
          onBusy: _showBusy,
        );
        // Closing the Save As dialog is a deferral, not a decision to back up.
        if (result.outcome == BackupRunOutcome.created) return;
      }
      await _snooze(service);
    } finally {
      _dialogOpen = false;
    }
  }

  /// The runner reports progress; on the home screen there is no inline
  /// overlay to drive, so render it as a modal barrier of its own.
  void _showBusy(String? text) {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (text == null) {
      if (_busyShown) {
        _busyShown = false;
        navigator.pop();
      }
      return;
    }
    if (_busyShown) return;
    _busyShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Do not close CounterIQ during this operation.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snooze(BackupService service) async {
    try {
      await service.snoozeReminder();
      _suppressUntil = null;
    } catch (_) {
      // The host could not record the snooze. Suppress locally so "Later"
      // still means later, instead of the dialog returning on the next tick.
      _suppressUntil = DateTime.now().add(_localSnoozeFallback);
    }
  }

  static String _ageSentence(String? lastBackupAt, double? hours) {
    if (lastBackupAt == null || hours == null) {
      return 'This CounterIQ installation has never been backed up. '
          'A backup protects every branch, all accounting history and your product images.';
    }
    if (hours < 48) {
      final whole = hours.round();
      return 'Your last backup was $whole ${whole == 1 ? 'hour' : 'hours'} ago.';
    }
    final days = (hours / 24).floor();
    return 'Your last backup was $days ${days == 1 ? 'day' : 'days'} ago.';
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
