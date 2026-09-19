import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_update_config.dart';
import '../services/app_update_service.dart';
import '../services/app_navigator.dart';

/// Performs one non-blocking update check after the application is usable.
///
/// Update server failures are intentionally silent during startup so CounterIQ
/// remains fully usable when GitHub/the internet is unavailable. User-facing
/// errors are shown only after the user explicitly starts an update.
class AppUpdateCoordinator extends StatefulWidget {
  final Widget child;

  const AppUpdateCoordinator({super.key, required this.child});

  @override
  State<AppUpdateCoordinator> createState() => _AppUpdateCoordinatorState();
}

class _AppUpdateCoordinatorState extends State<AppUpdateCoordinator> {
  bool _started = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;

    if (!Platform.isWindows || !AppUpdateConfig.isEnabled) return;

    // Let login/home finish its initial frame and avoid competing with startup
    // dialogs/snackbars. The check itself stays completely non-blocking.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    try {
      final result = await AppUpdateService.checkForUpdate();
      if (!mounted || result == null || !result.isUpdateAvailable) return;
      await _showUpdateDialog(result);
    } catch (_) {
      // Startup update checks are best-effort by design. A failed update server
      // must never prevent sales, login, licensing, or local backend startup.
    }
  }

  Future<void> _showUpdateDialog(UpdateCheckResult result) async {
    if (_dialogOpen || !mounted) return;
    final dialogContext = appNavigatorKey.currentState?.overlay?.context;
    if (dialogContext == null) return;

    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: !result.isMandatory,
        builder: (_) => _UpdateAvailableDialog(result: result),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateAvailableDialog extends StatefulWidget {
  final UpdateCheckResult result;

  const _UpdateAvailableDialog({required this.result});

  @override
  State<_UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<_UpdateAvailableDialog> {
  bool _downloading = false;
  bool _launching = false;
  UpdateDownloadProgress? _progress;
  String? _error;

  UpdateManifest get manifest => widget.result.manifest;

  Future<void> _downloadAndInstall() async {
    if (_downloading || _launching) return;

    setState(() {
      _downloading = true;
      _progress = const UpdateDownloadProgress(0, null);
      _error = null;
    });

    try {
      final installer = await AppUpdateService.downloadAndVerify(
        manifest,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;

      setState(() {
        _downloading = false;
        _launching = true;
      });

      await AppUpdateService.launchInstaller(installer);
      if (!mounted) return;

      // Do not forcibly exit here. The existing Inno installer owns process
      // shutdown and will close CounterIQ/backend once UAC is accepted. If the
      // customer cancels UAC, CounterIQ therefore remains open and usable.
      setState(() => _launching = false);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _launching = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _downloading || _launching;
    final progress = _progress;
    final fraction = progress?.fraction;

    return PopScope(
      canPop: !widget.result.isMandatory && !busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.system_update_alt_rounded, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.result.isMandatory
                      ? 'CounterIQ Update Required'
                      : 'CounterIQ Update Available'),
                  const SizedBox(height: 4),
                  Text(
                    widget.result.isMandatory
                        ? 'This version must be updated before continuing with future releases.'
                        : 'A newer CounterIQ version is ready to install.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _VersionRow(label: 'Current Version', value: AppUpdateConfig.currentVersion),
                const SizedBox(height: 6),
                _VersionRow(label: 'New Version', value: manifest.version),
                if (manifest.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('What’s New', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...manifest.releaseNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text('•'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(note)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Downloading CounterIQ ${manifest.version}...',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: fraction),
                  const SizedBox(height: 8),
                  Text(
                    _progressText(progress),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_launching) ...[
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(child: Text('Starting verified CounterIQ installer...')),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!widget.result.isMandatory)
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton.icon(
            onPressed: busy ? null : _downloadAndInstall,
            icon: const Icon(Icons.download_rounded),
            label: Text(_error == null ? 'Download & Update' : 'Retry Update'),
          ),
        ],
      ),
    );
  }

  static String _progressText(UpdateDownloadProgress? progress) {
    if (progress == null) return 'Preparing download...';
    final received = _formatBytes(progress.receivedBytes);
    final total = progress.totalBytes;
    if (total == null || total <= 0) return received;
    final percent = ((progress.receivedBytes / total) * 100).clamp(0, 100).round();
    return '$received / ${_formatBytes(total)}  •  $percent%';
  }

  static String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String value;

  const _VersionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 126,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
