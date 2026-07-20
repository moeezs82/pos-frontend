import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_feature_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Master Admin screen: Module & Workflow Settings (per branch).
///
/// Navigation: Branch Control → "Module & Workflow Settings".
/// Only visible to Master Admin. Requires a branch to be selected.
class BranchFeatureSettingsScreen extends StatefulWidget {
  const BranchFeatureSettingsScreen({super.key});

  @override
  State<BranchFeatureSettingsScreen> createState() =>
      _BranchFeatureSettingsScreenState();
}

class _BranchFeatureSettingsScreenState
    extends State<BranchFeatureSettingsScreen> {
  int? _selectedBranchId;
  String? _selectedBranchName;

  bool _deliveryEnabled = true;
  bool _saleVendorEnabled = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-select the Master Admin's currently active branch, if any.
    final auth = context.read<AuthProvider>();
    final branchId = auth.activeBranchId;
    if (branchId != null) {
      _selectedBranchId = branchId;
      final branch = auth.user?['branch'] as Map?;
      _selectedBranchName = branch?['name']?.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
    }
  }

  // ── Load ─────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (_selectedBranchId == null) return;
    final token = context.read<AuthProvider>().token!;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final features = await context
          .read<BranchFeatureProvider>()
          .loadForBranch(_selectedBranchId!, token);

      setState(() {
        _deliveryEnabled = features['delivery_enabled'] ?? true;
        _saleVendorEnabled = features['sale_vendor_enabled'] ?? true;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedBranchId == null || _saving) return;
    final token = context.read<AuthProvider>().token!;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await context.read<BranchFeatureProvider>().save(
        _selectedBranchId!,
        {
          'delivery_enabled': _deliveryEnabled,
          'sale_vendor_enabled': _saleVendorEnabled,
        },
        token,
      );

      if (mounted) {
        AppFeedback.success(context, 'Settings saved for ${_selectedBranchName ?? 'branch'}.');
      }
    } catch (e) {
      final msg = _extractError(e);
      setState(() => _error = msg);
      if (mounted) AppFeedback.error(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Delivery toggle with safety confirm ──────────────────────────────

  Future<void> _onDeliveryToggle(bool value) async {
    if (!value) {
      // Warn before disabling.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Disable Delivery Module?'),
          content: const Text(
            'Delivery assignments, delivery-boy cash collection, and delivery '
            'reports will be hidden for this branch.\n\n'
            'All historical delivery data is preserved.\n\n'
            'Make sure all delivery boys have settled their outstanding cash '
            'before disabling.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _deliveryEnabled = value);
  }

  // ── Branch picker ─────────────────────────────────────────────────────

  Future<void> _pickBranch() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BranchPickerSheet(),
    );
    if (result == null || !mounted) return;
    final id = int.tryParse(result['id']?.toString() ?? '');
    if (id == null) return;
    setState(() {
      _selectedBranchId = id;
      _selectedBranchName = result['name']?.toString();
    });
    await _loadSettings();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isMasterAdmin) {
      return const Scaffold(
        body: Center(child: Text('Only Master Admin can access module settings.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Module & Workflow Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BranchSelector(
              branchName: _selectedBranchName,
              onTap: _pickBranch,
            ),
            const SizedBox(height: 16),
            if (_selectedBranchId == null)
              EnterprisePanel(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, color: AppTheme.textMuted),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Select a branch to view and edit its module settings.',
                        style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            else if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _ErrorPanel(
                message: _error!,
                onRetry: _loadSettings,
              )
            else ...[
              _FeatureSwitch(
                icon: Icons.delivery_dining_rounded,
                title: 'Delivery Module',
                subtitle:
                    'Enable delivery assignments, delivery-boy cash collection and delivery reporting.',
                value: _deliveryEnabled,
                onChanged: _onDeliveryToggle,
              ),
              const SizedBox(height: 12),
              _FeatureSwitch(
                icon: Icons.storefront_outlined,
                title: 'Vendor Field on Sale',
                subtitle:
                    'Allow vendor selection while creating a sale. Purchases and vendor accounting are unaffected.',
                value: _saleVendorEnabled,
                onChanged: (v) => setState(() => _saleVendorEnabled = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save Settings'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _extractError(Object e) {
    final s = e.toString();
    // Extract Laravel validation messages when present.
    final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(s);
    if (match != null) return match.group(1)!;
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _BranchSelector extends StatelessWidget {
  final String? branchName;
  final VoidCallback onTap;

  const _BranchSelector({required this.branchName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configuring branch',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  branchName ?? 'Tap to select branch',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _FeatureSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? AppTheme.primarySoft : AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: value ? AppTheme.primary : AppTheme.textMuted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 32),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A lightweight branch picker bottom sheet for the settings screen.
/// Lists all branches and pops with the selected branch map.
class _BranchPickerSheet extends StatefulWidget {
  const _BranchPickerSheet();

  @override
  State<_BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends State<_BranchPickerSheet> {
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final token = context.read<AuthProvider>().token!;
      final svc = CommonService(token: token);
      final list = await svc.getBranches();
      setState(() {
        _branches = list;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _branches
        : _branches
            .where((b) => (b['name'] ?? '').toString().toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Select Branch to Configure',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.navy),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search branches…',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: controller,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final b = filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.apartment_rounded, color: AppTheme.primary),
                          title: Text(b['name']?.toString() ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: b['location'] != null
                              ? Text(b['location'].toString())
                              : null,
                          onTap: () => Navigator.pop(context, b),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
