import 'dart:io';

import 'package:enterprise_pos/api/backup_service.dart';
import 'package:enterprise_pos/config/backend_config.dart';
import 'package:enterprise_pos/services/backend_startup_service.dart';
import 'package:enterprise_pos/services/local_backup_client_state_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _checkingRecovery = false;
  bool _recoveryAvailable = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _checkRecoveryAvailability();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkRecoveryAvailability() async {
    if (!BackendConfig.isLocalHost || !Platform.isWindows) return;
    if (mounted) setState(() => _checkingRecovery = true);
    try {
      final available = await BackupService().recoveryAvailable();
      if (mounted) setState(() => _recoveryAvailable = available);
    } catch (_) {
      // Login must remain usable even if the optional recovery probe fails.
    } finally {
      if (mounted) setState(() => _checkingRecovery = false);
    }
  }

  Future<void> _restoreFreshInstallation() async {
    if (!_recoveryAvailable || _loading) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CounterIQ backup',
      type: FileType.custom,
      allowedExtensions: const ['ciqbak'],
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final service = BackupService();
      final uploaded = await service.uploadRecoveryBackup(path);
      final uploadToken = uploaded['upload_token']?.toString().trim() ?? '';
      final manifest = uploaded['manifest'] is Map<String, dynamic>
          ? uploaded['manifest'] as Map<String, dynamic>
          : <String, dynamic>{};
      if (uploadToken.isEmpty) {
        throw Exception('CounterIQ did not return a valid recovery token.');
      }
      if (!mounted) return;
      final counts = manifest['counts'] is Map ? manifest['counts'] as Map : const {};
      final branches = (manifest['branches'] as List?)?.map((e) => e.toString()).join(', ') ?? '';
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.restore_rounded, color: AppTheme.warning, size: 44),
          title: const Text('Restore CounterIQ from backup?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This fresh installation will be replaced with the complete data from the selected backup.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text('Customers: ${counts['customers'] ?? 0}'),
              Text('Products: ${counts['products'] ?? 0}'),
              Text('Sales: ${counts['sales'] ?? 0}'),
              if (branches.isNotEmpty) Text('Businesses: $branches'),
              const SizedBox(height: 12),
              const Text('After recovery, sign in using a user account contained in the restored backup.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore Backup')),
          ],
        ),
      );
      if (confirmed != true) return;

      await service.restoreRecoveryUpload(uploadToken);
      await BackendStartupService.waitForRestoreRestart();
      final clientResult = await LocalBackupClientStateService.instance.applyPendingRestore();
      if (!mounted) return;
      setState(() {
        _recoveryAvailable = false;
        _notice = clientResult.licenseNote == null
            ? 'Backup restored successfully. Sign in using an account from the restored CounterIQ database.'
            : 'Backup restored successfully. ${clientResult.licenseNote}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = 'Invalid email or password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.navy.withOpacity(.06),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.point_of_sale_rounded, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CounterIQ POS', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                              SizedBox(height: 2),
                              Text('Sign in to continue', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_notice != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.success.withOpacity(.16)),
                        ),
                        child: Text(_notice!, style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.danger.withOpacity(.16)),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter your email address' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                      validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: auth.rememberMe,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remember me', style: TextStyle(fontWeight: FontWeight.w600)),
                      onChanged: (val) => auth.setRememberMe(val ?? false),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login_rounded),
                      label: Text(_loading ? 'Signing in...' : 'Login'),
                    ),
                    if (BackendConfig.isLocalHost && (_recoveryAvailable || _checkingRecovery)) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loading || _checkingRecovery || !_recoveryAvailable
                            ? null
                            : _restoreFreshInstallation,
                        icon: _checkingRecovery
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.restore_rounded),
                        label: const Text('Restore CounterIQ Backup'),
                      ),
                      const Text(
                        'Available on a fresh local installation before the first user is created.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
                const SizedBox(height: 18),
                const Text(
                  'Powered by A Developers',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
