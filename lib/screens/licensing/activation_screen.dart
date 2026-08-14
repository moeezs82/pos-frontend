import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/backend_config.dart';
import '../../services/offline_license_service.dart';
import '../../theme/app_theme.dart';

class ActivationScreen extends StatefulWidget {
  final String? initialMessage;
  final VoidCallback onActivated;

  const ActivationScreen({
    super.key,
    required this.onActivated,
    this.initialMessage,
  });

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  late Future<String> _machineCodeFuture;
  bool _importing = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _machineCodeFuture = OfflineLicenseService.machineCode();
    final initial = widget.initialMessage?.trim();
    if (initial != null && initial.isNotEmpty && initial != 'This device has not been activated yet.') {
      _message = initial;
      _messageIsError = true;
    }
  }

  Future<void> _copyMachineCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() {
      _message = 'Machine code copied. Send it to Application Owner to receive this device\'s license file.';
      _messageIsError = false;
    });
  }

  Future<void> _importLicense() async {
    if (_importing) return;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CounterIQ license',
      type: FileType.custom,
      allowedExtensions: const ['ciqlic'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    setState(() {
      _importing = true;
      _message = null;
    });

    final check = await OfflineLicenseService.installLicenseFromPath(path);
    if (!mounted) return;

    setState(() {
      _importing = false;
      _message = check.isValid
          ? 'CounterIQ has been activated for ${check.license?.customer ?? 'this device'}.'
          : check.message ?? 'The selected license could not be activated.';
      _messageIsError = !check.isValid;
    });

    if (check.isValid) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onActivated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor: AppTheme.primarySoft,
                        child: Icon(
                          Icons.verified_user_rounded,
                          size: 38,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Activate CounterIQ',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.navy,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${BackendConfig.mode.toUpperCase()} edition • Offline machine activation',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Send this machine code to Application Owner. You will receive a license file made specifically for this computer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FutureBuilder<String>(
                      future: _machineCodeFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withOpacity(.06),
                              borderRadius: BorderRadius.circular(AppTheme.radius),
                              border: Border.all(color: AppTheme.danger.withOpacity(.25)),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
                                const SizedBox(height: 8),
                                SelectableText(
                                  snapshot.error.toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppTheme.danger),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _machineCodeFuture = OfflineLicenseService.machineCode();
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try again'),
                                ),
                              ],
                            ),
                          );
                        }

                        final code = snapshot.data!;
                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceSoft,
                            borderRadius: BorderRadius.circular(AppTheme.radius),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'MACHINE CODE',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                code,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.navy,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: .6,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => _copyMachineCode(code),
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('Copy machine code'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: (_messageIsError ? AppTheme.danger : AppTheme.success).withOpacity(.06),
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          border: Border.all(
                            color: (_messageIsError ? AppTheme.danger : AppTheme.success).withOpacity(.22),
                          ),
                        ),
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _messageIsError ? AppTheme.danger : AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _importing ? null : _importLicense,
                      icon: _importing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_open_rounded),
                      label: Text(_importing ? 'Checking license...' : 'Import License File'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The license is bound to this Windows computer and can be verified without an internet connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
