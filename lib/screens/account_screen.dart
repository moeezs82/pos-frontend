import 'package:enterprise_pos/api/account_service.dart';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/settings/payment_methods_admin_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  static const int _perPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 56;

  late AccountService _svc;
  bool _isMasterAdmin = false;
  List<Map<String, dynamic>> _types = [];

  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  final _searchCtrl = TextEditingController();
  final _vCtrl = ScrollController();

  bool? _activeOnly = true;
  String? _typeCode;
  int _lastPage = 1;
  int _total = 0;
  String? _error;

  bool get _enableCrud => _isMasterAdmin;
  bool get _initialLoading => _loadingPages.contains(1) && _pages.isEmpty;

  static const _coreAccountCodes = {
    '1000', '1010', '1200', '1210', '1400',
    '2000', '2100', '2105', '2205', '3100',
    '4000', '5100', '5205',
  };

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _isMasterAdmin = auth.isMasterAdmin;
    if (!_isMasterAdmin || auth.token == null) return;
    _svc = AccountService(token: auth.token!);
    _vCtrl.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    try {
      final t = await _svc.getAccountTypes();
      if (mounted) setState(() => _types = t);
    } catch (_) {}
    await _resetAndLoad();
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    if (!mounted || !_isMasterAdmin) return;
    setState(() {
      _pages.clear();
      _loadingPages.clear();
      _lastPage = 1;
      _total = 0;
      _error = null;
    });
    await _loadPage(1, force: true);
    if (_vCtrl.hasClients) _vCtrl.jumpTo(0);
  }

  Future<void> _loadPage(int page, {bool force = false}) async {
    if (!_isMasterAdmin || page < 1) return;
    if (_pages.isNotEmpty && page > _lastPage) return;
    if (!force && (_pages.containsKey(page) || _loadingPages.contains(page))) return;

    if (mounted) setState(() => _loadingPages.add(page));
    try {
      final res = await _svc.getAccounts(
        isActive: _activeOnly,
        typeCode: _typeCode,
        q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        perPage: _perPage,
        page: page,
      );
      final items = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final p = Map<String, dynamic>.from(res['pagination'] ?? const {});
      final current = (p['current_page'] as num?)?.toInt() ?? page;
      final last = (p['last_page'] as num?)?.toInt() ?? 1;
      final total = (p['total'] as num?)?.toInt() ??
          (last <= 1 ? items.length : (last - 1) * _perPage + items.length);
      if (!mounted) return;
      setState(() {
        _pages[current] = items;
        _lastPage = last < 1 ? 1 : last;
        _total = total < items.length ? items.length : total;
        _loadingPages.remove(page);
        _error = null;
        _evictFarPages(_visiblePageEstimate());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages.remove(page);
        _error = e.toString();
      });
    }
  }

  int _visiblePageEstimate() {
    if (!_vCtrl.hasClients || _total == 0) return 1;
    final index = (_vCtrl.offset / _rowExtent).floor().clamp(0, _total - 1);
    return (index ~/ _perPage) + 1;
  }

  void _evictFarPages(int anchor) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()
      ..sort((a, b) => (b - anchor).abs().compareTo((a - anchor).abs()));
    for (final key in keys) {
      if (_pages.length <= _maxCachedPages) break;
      if ((key - anchor).abs() <= 1) continue;
      _pages.remove(key);
    }
  }

  void _onScroll() {
    if (!_vCtrl.hasClients || _total == 0) return;
    final first = (_vCtrl.offset / _rowExtent).floor().clamp(0, _total - 1);
    final count = (_vCtrl.position.viewportDimension / _rowExtent).ceil() + 8;
    final lastIndex = (first + count).clamp(0, _total - 1);
    final firstPage = (first ~/ _perPage) + 1;
    final lastPage = (lastIndex ~/ _perPage) + 1;
    for (var page = firstPage; page <= lastPage; page++) {
      _loadPage(page);
    }
    if (lastPage < _lastPage) _loadPage(lastPage + 1);
    if (firstPage > 1) _loadPage(firstPage - 1);
    if (_pages.length > _maxCachedPages && mounted) {
      setState(() => _evictFarPages(firstPage));
    }
  }

  Map<String, dynamic>? _accountAt(int index) {
    final page = (index ~/ _perPage) + 1;
    final local = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(page));
      return null;
    }
    return local < rows.length ? rows[local] : null;
  }

  Future<void> _openCreateEditDialog({Map<String, dynamic>? row}) async {
    if (!_enableCrud) return;
    final isCore = row != null && _coreAccountCodes.contains(row['code']?.toString());
    final codeCtrl = TextEditingController(text: row?['code'] ?? '');
    final nameCtrl = TextEditingController(text: row?['name'] ?? '');
    bool isActive = (row?['is_active'] ?? true) == true;
    int? accountTypeId;
    if (row != null && row['type'] != null) {
      final hit = _types.where((t) => t['code'] == row['type']).toList();
      if (hit.isNotEmpty) accountTypeId = (hit.first['id'] as num).toInt();
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(row == null ? 'Create Account' : 'Edit Account'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  readOnly: isCore,
                  decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: accountTypeId,
                  decoration: const InputDecoration(labelText: 'Account Type', border: OutlineInputBorder(), isDense: true),
                  items: _types.map((t) => DropdownMenuItem<int>(
                    value: (t['id'] as num).toInt(),
                    child: Text('${t['name']} (${t['code']})'),
                  )).toList(),
                  onChanged: isCore ? null : (v) => setStateDialog(() => accountTypeId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  title: const Text('Active'),
                  value: isActive,
                  subtitle: isCore ? const Text('Required by system posting and reports') : null,
                  onChanged: isCore ? null : (v) => setStateDialog(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save'),
              onPressed: () async {
                try {
                  if (row == null) {
                    if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty || accountTypeId == null) {
                      throw Exception('Code, Name and Type are required.');
                    }
                    await _svc.createAccount(
                      code: codeCtrl.text.trim(),
                      name: nameCtrl.text.trim(),
                      accountTypeId: accountTypeId!,
                      isActive: isActive,
                    );
                  } else {
                    await _svc.updateAccount(
                      id: row['id'].toString(),
                      code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
                      name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                      accountTypeId: accountTypeId,
                      isActive: isActive,
                    );
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                  await _resetAndLoad();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    if (!_enableCrud) return;
    final currentlyActive = (row['is_active'] ?? true) == true;
    try {
      await _svc.setActive(id: row['id'].toString(), active: !currentlyActive);
      await _resetAndLoad();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to change active state: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMasterAdmin) {
      return const EnterprisePage(
        title: 'Chart of Accounts',
        subtitle: 'System and operational ledger accounts.',
        icon: Icons.account_balance_outlined,
        child: Center(child: Text('Chart of Accounts is available only to Master Admin.')),
      );
    }

    return EnterprisePage(
      title: 'Chart of Accounts',
      subtitle: 'Maintain posting accounts while protecting the core system accounts used by reports and transactions.',
      icon: Icons.account_balance_outlined,
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentMethodsAdminScreen())),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Payment Methods'),
        ),
        OutlinedButton.icon(
          onPressed: _resetAndLoad,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
        if (_enableCrud)
          FilledButton.icon(
            onPressed: () => _openCreateEditDialog(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Account'),
          ),
      ],
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _typeCode,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('All types')),
                    ..._types.map((t) => DropdownMenuItem<String>(
                      value: t['code']?.toString(),
                      child: Text('${t['name']} (${t['code']})'),
                    )),
                  ],
                  onChanged: (v) { setState(() => _typeCode = v); _resetAndLoad(); },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<bool>(
                  isExpanded: true,
                  value: _activeOnly,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem<bool>(value: true, child: Text('Active only')),
                    DropdownMenuItem<bool>(value: false, child: Text('Inactive only')),
                    DropdownMenuItem<bool>(value: null, child: Text('All')),
                  ],
                  onChanged: (v) { setState(() => _activeOnly = v); _resetAndLoad(); },
                ),
              ),
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _resetAndLoad(),
                  decoration: InputDecoration(
                    hintText: 'Search code or account name…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isEmpty ? null : IconButton(
                      onPressed: () { _searchCtrl.clear(); _resetAndLoad(); setState(() {}); },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text('$_total accounts', style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null && _pages.isEmpty
                      ? _errorState()
                      : _total == 0
                          ? const Center(child: Text('No accounts found'))
                          : Column(
                              children: [
                                _tableHeader(),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _vCtrl,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller: _vCtrl,
                                      itemExtent: _rowExtent,
                                      cacheExtent: _rowExtent * 12,
                                      itemCount: _total,
                                      itemBuilder: (_, index) {
                                        final row = _accountAt(index);
                                        return row == null ? _loadingRow() : _accountRow(row);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppTheme.surfaceSoft,
        child: const Row(
          children: [
            SizedBox(width: 120, child: Text('CODE', style: _headerStyle)),
            SizedBox(width: 18),
            Expanded(flex: 35, child: Text('ACCOUNT', style: _headerStyle)),
            SizedBox(width: 18),
            Expanded(flex: 22, child: Text('TYPE', style: _headerStyle)),
            SizedBox(width: 18),
            SizedBox(width: 120, child: Text('STATUS', style: _headerStyle)),
            SizedBox(width: 18),
            SizedBox(width: 110, child: Text('ACTIONS', style: _headerStyle)),
          ],
        ),
      );

  Widget _accountRow(Map<String, dynamic> row) {
    final active = (row['is_active'] ?? true) == true;
    final isCore = _coreAccountCodes.contains(row['code']?.toString());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Row(children: [
              Flexible(child: Text(row['code']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800))),
              if (isCore) ...[
                const SizedBox(width: 6),
                const Tooltip(message: 'Protected system account', child: Icon(Icons.lock_rounded, size: 14, color: AppTheme.textMuted)),
              ],
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(flex: 35, child: Text(row['name']?.toString() ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 18),
          Expanded(flex: 22, child: Text(row['type']?.toString() ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 18),
          SizedBox(width: 120, child: _statusBadge(active)),
          const SizedBox(width: 18),
          SizedBox(
            width: 110,
            child: Row(
              children: [
                if (_enableCrud && !isCore)
                  IconButton(tooltip: 'Edit', onPressed: () => _openCreateEditDialog(row: row), icon: const Icon(Icons.edit_outlined, size: 18)),
                if (_enableCrud && !isCore)
                  IconButton(
                    tooltip: active ? 'Deactivate' : 'Activate',
                    onPressed: () => _toggleActive(row),
                    icon: Icon(active ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool active) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: (active ? AppTheme.success : AppTheme.textMuted).withOpacity(.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(active ? 'Active' : 'Inactive', style: TextStyle(color: active ? AppTheme.success : AppTheme.textMuted, fontWeight: FontWeight.w800, fontSize: 11)),
        ),
      );

  Widget _loadingRow() => const DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 32),
            const SizedBox(height: 8),
            const Text('Failed to load accounts', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _resetAndLoad, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      );

  static const TextStyle _headerStyle = TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: .25);
}

class BranchPaymentMappingsScreen extends StatefulWidget {
  const BranchPaymentMappingsScreen({super.key});

  @override
  State<BranchPaymentMappingsScreen> createState() => _BranchPaymentMappingsScreenState();
}

class _BranchPaymentMappingsScreenState extends State<BranchPaymentMappingsScreen> {
  static const _methods = ['cash', 'card', 'bank', 'wallet'];

  late AccountService _accountsApi;
  late CommonService _commonApi;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _assetAccounts = [];
  Map<String, Map<String, dynamic>> _mappings = {};
  int? _branchId;
  bool _loading = true;
  String? _error;
  String? _savingMethod;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (!auth.isMasterAdmin || auth.token == null) {
      _loading = false;
      _error = 'Branch payment mappings are available only to Master Admin.';
      return;
    }
    _accountsApi = AccountService(token: auth.token!);
    _commonApi = CommonService(token: auth.token!);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final results = await Future.wait([
        _commonApi.getBranches(),
        _accountsApi.getAccounts(isActive: true),
      ]);
      final branches = results[0] as List<Map<String, dynamic>>;
      final accountResult = results[1] as Map<String, dynamic>;
      final accounts = List<Map<String, dynamic>>.from(accountResult['items'] ?? const []);
      final preferred = context.read<BranchProvider>().selectedBranchId;
      final selected = branches.any((b) => _asInt(b['id']) == preferred)
          ? preferred
          : (branches.isEmpty ? null : _asInt(branches.first['id']));

      if (!mounted) return;
      setState(() {
        _branches = branches;
        _assetAccounts = accounts.where((a) => a['type']?.toString() == 'ASSET').toList();
        _branchId = selected;
        _loading = selected != null;
        _error = selected == null ? 'No branches are available.' : null;
      });
      if (selected != null) await _loadMappings(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMappings(int branchId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _accountsApi.getPaymentMappings(branchId: branchId);
      if (!mounted || _branchId != branchId) return;
      setState(() {
        _mappings = {for (final row in rows) row['method'].toString(): row};
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

  Future<void> _save(String method, int accountId) async {
    final branchId = _branchId;
    if (branchId == null || _savingMethod != null) return;
    setState(() => _savingMethod = method);
    try {
      await _accountsApi.updatePaymentMapping(
        branchId: branchId,
        method: method,
        accountId: accountId,
      );
      await _loadMappings(branchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_label(method)} account mapping updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingMethod = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Payment Mappings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _branchId == null ? null : () => _loadMappings(_branchId!),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose the asset account used when each payment method posts cash for a branch.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _branchId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Branch',
                prefixIcon: Icon(Icons.apartment_rounded),
                border: OutlineInputBorder(),
              ),
              items: _branches.map((branch) {
                final id = _asInt(branch['id'])!;
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(branch['name']?.toString() ?? 'Branch #$id'),
                );
              }).toList(),
              onChanged: (id) {
                if (id == null || id == _branchId) return;
                setState(() => _branchId = id);
                _loadMappings(id);
              },
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 40, color: AppTheme.danger),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      if (_branchId != null)
                        OutlinedButton.icon(
                          onPressed: () => _loadMappings(_branchId!),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _methods.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final method = _methods[index];
                    final mapping = _mappings[method];
                    final selectedId = _asInt(mapping?['account_id']);
                    final inherited = mapping?['is_inherited'] == true;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppTheme.primarySoft,
                              child: Icon(_icon(method), color: AppTheme.primary),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 150,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_label(method), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(
                                    inherited ? 'Copied from default' : 'Configured for branch',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _assetAccounts.any((a) => _asInt(a['id']) == selectedId) ? selectedId : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Posting account',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _assetAccounts.map((account) {
                                  final id = _asInt(account['id'])!;
                                  return DropdownMenuItem<int>(
                                    value: id,
                                    child: Text('${account['code']} — ${account['name']}'),
                                  );
                                }).toList(),
                                onChanged: _savingMethod == null
                                    ? (id) {
                                        if (id != null && id != selectedId) _save(method, id);
                                      }
                                    : null,
                              ),
                            ),
                            if (_savingMethod == method) ...[
                              const SizedBox(width: 12),
                              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _label(String method) => '${method[0].toUpperCase()}${method.substring(1)}';

  static IconData _icon(String method) => switch (method) {
        'cash' => Icons.payments_rounded,
        'card' => Icons.credit_card_rounded,
        'bank' => Icons.account_balance_rounded,
        _ => Icons.account_balance_wallet_rounded,
      };
}
