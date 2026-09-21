import 'dart:io';

import 'package:enterprise_pos/api/backup_service.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/screens/login_screen.dart';
import 'package:enterprise_pos/services/backend_startup_service.dart';
import 'package:enterprise_pos/services/backup_runner_service.dart';
import 'package:enterprise_pos/services/connectivity_auto_sync_service.dart';
import 'package:enterprise_pos/services/local_backup_client_state_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  BackupService? _service;
  bool _loading = true;
  bool _busy = false;
  String? _operationText;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _reminder;
  bool _savingReminder = false;

  bool get _canCreate => context.read<AuthProvider>().hasPermission('create-backups');
  bool get _canRestore => context.read<AuthProvider>().hasPermission('restore-backups');

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.token != null) _service = BackupService(token: auth.token!);
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!BackendConfig.isLocal || !Platform.isWindows || _service == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final status = await _service!.status();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      // The main actions surface their own errors. Status history is optional.
    }
    try {
      final reminder = await _service!.reminder();
      if (!mounted) return;
      setState(() => _reminder = reminder);
    } catch (_) {
      // Reminder settings are advisory; the card hides itself if unavailable.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createBackup() async {
    if (_busy || !_canCreate || _service == null) return;
    final result = await BackupRunnerService.instance.run(
      context,
      service: _service!,
      onBusy: (text) {
        if (!mounted) return;
        setState(() {
          _busy = text != null;
          _operationText = text;
        });
      },
    );
    if (!mounted) return;
    if (result.status != null) setState(() => _status = result.status);
  }


  Future<void> _restoreBackup() async {
    if (_busy || !_canRestore || _service == null) return;
    if (context.read<OfflineQueueProvider>().pendingCount > 0) {
      _showError(
        'Sync required',
        Exception(
          'This workstation has sales waiting to sync. Sync them before restoring a backup. Also close CounterIQ on every other workstation before the restore.',
        ),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CounterIQ backup',
      type: FileType.custom,
      allowedExtensions: const ['ciqbak'],
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    try {
      setState(() {
        _busy = true;
        _operationText = BackendConfig.isLocalClient
            ? 'Uploading and verifying the backup on the CounterIQ host PC...'
            : 'Checking backup integrity and compatibility...';
      });

      final uploaded = await _service!.uploadBackup(path);
      final uploadToken = uploaded['upload_token']?.toString().trim() ?? '';
      final manifest = _asMap(uploaded['manifest']);
      if (uploadToken.isEmpty) {
        throw Exception('CounterIQ did not return a valid restore token.');
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _operationText = null;
      });

      final confirmed = await _confirmRestore(path, manifest);
      if (!confirmed || !mounted) return;

      String? staging;
      try {
        setState(() {
          _busy = true;
          _operationText = 'Creating a safety backup before restore...';
        });

        if (BackendConfig.isLocalHost) {
          staging = await LocalBackupClientStateService.instance
              .createStagingSnapshot();
        }

        final result = await _service!.restoreUploadedBackup(
          uploadToken: uploadToken,
          currentClientStateDir: staging,
        );
        final safetyPath = result['safety_backup_path']?.toString();
        if (!mounted) return;

        ConnectivityAutoSyncService.instance.stop();
        setState(() => _operationText =
            'Restarting the CounterIQ host and applying the verified backup...');

        // The authoritative Go desktop runtime supervises/restarts itself. This
        // works whether restore was started on the host PC or a permitted LAN
        // workstation; Flutter never needs to locate counteriq-backend.exe.
        await BackendStartupService.waitForRestoreRestart();

        ClientRestoreResult clientResult = const ClientRestoreResult(
          applied: false,
          licenseRestored: false,
        );
        if (BackendConfig.isLocalHost) {
          clientResult = await LocalBackupClientStateService.instance
              .applyPendingRestore();
        }

        await context.read<AuthProvider>().forceLogout();
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.check_circle_rounded,
                color: AppTheme.success, size: 46),
            title: const Text('Restore completed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CounterIQ restored the shared business database and uploaded files successfully. '
                  'For security, sign in again using a user from the restored backup.',
                ),
                if (BackendConfig.isLocalClient) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Other CounterIQ workstations should also sign in again. Keep all workstations '
                    'closed during a restore so no unsynced sale is created against the old database.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (safetyPath != null && safetyPath.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Automatic safety backup on host:\n$safetyPath',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                if (clientResult.licenseNote != null) ...[
                  const SizedBox(height: 12),
                  Text(clientResult.licenseNote!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue to Login'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } finally {
        if (BackendConfig.isLocalHost) {
          await LocalBackupClientStateService.instance.cleanupStaging(staging);
        }
      }
    } catch (error) {
      if (mounted) _showError('Restore failed', error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _operationText = null;
        });
      }
    }
  }

  Future<bool> _confirmRestore(String path, Map<String, dynamic> manifest) async {
    final counts = _asMap(manifest['counts']);
    final branches = (manifest['branches'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final created = _formatDate(manifest['created_at']?.toString());
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore_rounded, color: AppTheme.warning, size: 44),
        title: const Text('Restore complete CounterIQ backup?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This replaces the entire shared CounterIQ business database on the host PC, including every branch, '
                  'accounting history, sales, purchases, products, stock and uploaded product images.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _infoRow('Backup created', created),
                _infoRow('Database version', manifest['schema_migration']?.toString() ?? '-'),
                _infoRow('Branches', '${counts['branches'] ?? branches.length}'),
                _infoRow('Customers', '${counts['customers'] ?? 0}'),
                _infoRow('Products', '${counts['products'] ?? 0}'),
                _infoRow('Sales', '${counts['sales'] ?? 0}'),
                _infoRow('Purchases', '${counts['purchases'] ?? 0}'),
                if (branches.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Businesses: ${branches.join(', ')}'),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Close CounterIQ on every other workstation before continuing and make sure there are no unsynced offline sales. '
                  'CounterIQ will first create an automatic safety backup on the host. After restore, all users must sign in again.',
                ),
                const SizedBox(height: 10),
                Text(path, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore Backup'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showError(String title, Object error) =>
      BackupRunnerService.showError(context, title, error);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.hasPermission('create-backups');
    final canRestore = auth.hasPermission('restore-backups');

    if (!BackendConfig.isLocal || !Platform.isWindows) {
      return const Scaffold(
        body: Center(child: Text('Backup & Restore is available only in the local Windows edition (host or LAN client).')),
      );
    }

    final scopeText = BackendConfig.isLocalClient
        ? 'A CounterIQ backup is created by the host PC and downloaded to this workstation. It contains the complete shared business database for all branches and all uploaded product images.'
        : 'A CounterIQ backup contains the complete local business database for all branches, uploaded product images, and this host workstation\'s critical offline recovery state.';

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_rounded, color: AppTheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(scopeText)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ActionCard(
                icon: Icons.backup_rounded,
                title: 'Create Backup',
                subtitle:
                    'Create one verified .ciqbak file that can be stored on USB, external storage, NAS, OneDrive or another safe location.',
                enabled: canCreate && !_busy,
                buttonText: 'Create Backup',
                onPressed: _createBackup,
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.restore_rounded,
                title: 'Restore Backup',
                subtitle:
                    'Restore the complete shared CounterIQ database on the host PC. A safety backup of the current host data is created automatically first.',
                enabled: canRestore && !_busy,
                buttonText: 'Restore Backup',
                danger: true,
                onPressed: _restoreBackup,
              ),
              if (!canRestore && canCreate) ...[
                const SizedBox(height: 10),
                const Text(
                  'Your role can create backups but cannot restore them. Restore access can be granted separately from Roles & Permissions.',
                ),
              ],
              const SizedBox(height: 16),
              _buildReminderCard(),
              const SizedBox(height: 24),
              _buildStatusCard(),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_operationText ?? 'Working...', textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            const Text('Do not close CounterIQ during this operation.', textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setReminderInterval(String interval) async {
    if (_service == null || _savingReminder) return;
    setState(() => _savingReminder = true);
    try {
      final updated = await _service!.updateReminder(interval);
      if (!mounted) return;
      setState(() => _reminder = updated);
    } catch (error) {
      if (mounted) _showError('Could not update reminder', error);
    } finally {
      if (mounted) setState(() => _savingReminder = false);
    }
  }

  Widget _buildReminderCard() {
    final reminder = _reminder;
    if (reminder == null) return const SizedBox.shrink();

    final canEdit = reminder['can_edit'] == true;
    final interval = reminder['interval']?.toString() ?? 'every_6_hours';
    final options = (reminder['options'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final hours = (reminder['hours_since_backup'] as num?)?.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule_rounded, color: AppTheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Backup Reminder',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              canEdit
                  ? 'CounterIQ reminds this host PC to back up. It never creates a backup on its own \u2014 you always choose where the file is saved.'
                  : 'CounterIQ reminds this host PC to back up. Only Master Admin can change how often.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(width: 170, child: Text('Remind me', style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: options.contains(interval) ? interval : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                          value: option,
                          child: Text(_intervalLabel(option)),
                        ),
                    ],
                    onChanged: (canEdit && !_savingReminder)
                        ? (value) {
                            if (value != null) _setReminderInterval(value);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _infoRow('Last backup', _reminderAgeText(hours)),
            if (reminder['snoozed_until'] != null)
              _infoRow('Postponed until',
                  _formatDate(reminder['snoozed_until']?.toString())),
          ],
        ),
      ),
    );
  }

  static String _reminderAgeText(double? hours) {
    if (hours == null) return 'Never backed up';
    if (hours < 48) {
      final whole = hours.round();
      return '$whole ${whole == 1 ? 'hour' : 'hours'} ago';
    }
    final days = (hours / 24).floor();
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }

  static String _intervalLabel(String value) {
    switch (value) {
      case 'every_6_hours':
        return 'Every 6 hours';
      case 'every_12_hours':
        return 'Every 12 hours';
      case 'daily':
        return 'Daily';
      case 'every_3_days':
        return 'Every 3 days';
      case 'weekly':
        return 'Weekly';
      case 'every_15_days':
        return 'Every 15 days';
      case 'monthly':
        return 'Monthly';
      case 'off':
        return 'Off';
      default:
        return value;
    }
  }

  Widget _buildStatusCard() {
    if (_loading) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()));
    }
    final last = _asMap(_status?['last_backup']);
    final restored = _asMap(_status?['last_restore']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recovery History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _infoRow('Last successful backup', last.isEmpty ? 'Not recorded yet' : _formatDate(last['at']?.toString())),
            _infoRow('Last restore', restored.isEmpty ? 'Never' : _formatDate(restored['at']?.toString())),
            if (last['path'] != null) ...[
              const SizedBox(height: 8),
              Text(last['path'].toString(), style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _infoRow(String label, String value) =>
      BackupRunnerService.infoRow(label, value);

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, val) => MapEntry(key.toString(), val));
    return <String, dynamic>{};
  }

  static String _formatDate(String? raw) =>
      BackupRunnerService.formatDate(raw);
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String buttonText;
  final VoidCallback onPressed;
  final bool danger;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.buttonText,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: (danger ? AppTheme.warning : AppTheme.primary).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: danger ? AppTheme.warning : AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon),
              label: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
