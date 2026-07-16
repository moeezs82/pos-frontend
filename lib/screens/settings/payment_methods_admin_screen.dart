import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/api/account_service.dart';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/payment_method_service.dart';
import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';

/// Master-Admin, per-branch payment method configuration. Replaces the fixed
/// four-row Branch Payment Mappings screen with a dynamic list where methods
/// (KNET, Cheque, ...) can be added, edited, remapped, ordered, activated and
/// deactivated for each branch independently.
class PaymentMethodsAdminScreen extends StatefulWidget {
  const PaymentMethodsAdminScreen({super.key});

  @override
  State<PaymentMethodsAdminScreen> createState() => _PaymentMethodsAdminScreenState();
}

class _PaymentMethodsAdminScreenState extends State<PaymentMethodsAdminScreen> {
  late final PaymentMethodService _pmApi;
  late final AccountService _accountsApi;
  late final CommonService _commonApi;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _assetAccounts = [];
  List<PaymentMethod> _methods = [];
  int? _branchId;
  int? _busyId; // method id currently mutating

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final token = auth.token ?? '';
    _pmApi = PaymentMethodService(token: token);
    _accountsApi = AccountService(token: token);
    _commonApi = CommonService(token: token);

    if (!(context.read<BranchProvider>().isMasterAdmin)) {
      _loading = false;
      _error = 'Payment methods are configurable only by Master Admin.';
    } else {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _commonApi.getBranches(),
        _accountsApi.getAccounts(isActive: true, typeCode: 'ASSET', perPage: 100),
      ]);
      final branches = results[0] as List<Map<String, dynamic>>;
      final accountsRes = results[1] as Map<String, dynamic>;
      final accounts = List<Map<String, dynamic>>.from(
        (accountsRes['items'] as List?) ?? const [],
      );

      final preferred = context.read<BranchProvider>().selectedBranchId;
      final selected = branches.any((b) => _asInt(b['id']) == preferred)
          ? preferred
          : (branches.isEmpty ? null : _asInt(branches.first['id']));

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _assetAccounts = accounts;
        _branchId = selected;
      });

      if (selected != null) {
        await _loadMethods(selected);
      } else {
        setState(() {
          _loading = false;
          _error = 'No branches are available.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMethods(int branchId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _pmApi.getAllForBranch(branchId);
      if (!mounted || _branchId != branchId) return;
      setState(() {
        _methods = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _branchId != branchId) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleActive(PaymentMethod m) async {
    if (m.id == null) return;
    setState(() => _busyId = m.id);
    try {
      await _pmApi.setActive(m.id!, !m.isActive);
      if (_branchId != null) await _loadMethods(_branchId!);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        actions: [
          if (_branchId != null)
            IconButton(
              tooltip: 'Add method',
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      floatingActionButton: _branchId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Method'),
            ),
      body: Column(
        children: [
          _branchSelector(),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _branchSelector() {
    return Container(
      color: AppTheme.surfaceSoft,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.store_mall_directory_rounded, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          const Text('Branch', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _branches
                  .map((b) => DropdownMenuItem<int>(
                        value: _asInt(b['id']),
                        child: Text('${b['name'] ?? 'Branch ${b['id']}'}'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null || v == _branchId) return;
                setState(() => _branchId = v);
                _loadMethods(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
        ),
      );
    }
    if (_methods.isEmpty) {
      return const Center(child: Text('No payment methods configured for this branch yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _methods.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _methodCard(_methods[i]),
    );
  }

  Widget _methodCard(PaymentMethod m) {
    final busy = _busyId == m.id;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Icon(m.icon, color: m.isActive ? AppTheme.primary : AppTheme.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _chip(m.method, AppTheme.surfaceSoft, AppTheme.textMuted),
                      if (m.affectsCashDrawer) ...[
                        const SizedBox(width: 6),
                        _chip('drawer', const Color(0xFFFEF3C7), AppTheme.warning),
                      ],
                      if (!m.isActive) ...[
                        const SizedBox(width: 6),
                        _chip('inactive', const Color(0xFFFEE2E2), AppTheme.danger),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${m.accountCode ?? '—'} · ${m.accountName ?? 'No account'}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _openEditor(m);
                  if (v == 'toggle') _toggleActive(m);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(m.isActive ? 'Deactivate' : 'Activate'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _openEditor(PaymentMethod? existing) async {
    if (_branchId == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MethodEditorDialog(
        branchId: _branchId!,
        existing: existing,
        assetAccounts: _assetAccounts,
        api: _pmApi,
      ),
    );
    if (saved == true && _branchId != null) {
      await _loadMethods(_branchId!);
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class _MethodEditorDialog extends StatefulWidget {
  final int branchId;
  final PaymentMethod? existing;
  final List<Map<String, dynamic>> assetAccounts;
  final PaymentMethodService api;

  const _MethodEditorDialog({
    required this.branchId,
    required this.existing,
    required this.assetAccounts,
    required this.api,
  });

  @override
  State<_MethodEditorDialog> createState() => _MethodEditorDialogState();
}

class _MethodEditorDialogState extends State<_MethodEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _sort;
  int? _accountId;
  bool _drawer = false;
  bool _active = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.displayName ?? '');
    _code = TextEditingController(text: e?.method ?? '');
    _sort = TextEditingController(text: (e?.sortOrder ?? 0).toString());
    _accountId = e?.accountId;
    _drawer = e?.affectsCashDrawer ?? false;
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      setState(() => _error = 'Please select a posting account.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await widget.api.update(
          widget.existing!.id!,
          displayName: _name.text.trim(),
          accountId: _accountId,
          affectsCashDrawer: _drawer,
          isActive: _active,
          sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
        );
      } else {
        await widget.api.create(
          branchId: widget.branchId,
          method: _code.text.trim().toLowerCase(),
          displayName: _name.text.trim(),
          accountId: _accountId!,
          affectsCashDrawer: _drawer,
          isActive: _active,
          sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Payment Method' : 'Add Payment Method'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Display name', hintText: 'e.g. KNET'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  enabled: !_isEdit, // machine code is immutable once created
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Machine code',
                    hintText: 'e.g. knet',
                    helperText: _isEdit
                        ? 'Immutable once created'
                        : 'Lowercase letters, numbers, - and _',
                  ),
                  validator: (v) {
                    if (_isEdit) return null;
                    final s = (v ?? '').trim().toLowerCase();
                    if (s.isEmpty) return 'Required';
                    if (!RegExp(r'^[a-z0-9_\-]+$').hasMatch(s)) return 'Invalid code';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Posting account (asset)'),
                  items: widget.assetAccounts
                      .map((a) => DropdownMenuItem<int>(
                            value: _asInt(a['id']),
                            child: Text('${a['code']} · ${a['name']}', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Affects cash drawer'),
                  subtitle: const Text('Changes physical register expected cash'),
                  value: _drawer,
                  onChanged: (v) => setState(() => _drawer = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Available for new transactions'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _sort,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Sort order'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
