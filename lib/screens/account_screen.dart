import 'package:enterprise_pos/api/account_service.dart';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_pagination.dart';
import 'package:enterprise_pos/screens/settings/payment_methods_admin_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late AccountService _svc;
  bool _isMasterAdmin = false;

  // data
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _types = [];

  // ui
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  bool? _activeOnly = true; // active by default
  String? _typeCode;        // filter by type
  int _currentPage = 1;
  int _lastPage = 1;
  final int _perPage = 25;

  // scrolling
  final _vCtrl = ScrollController();
  final _hCtrl = ScrollController();

  bool get _enableCrud => _isMasterAdmin;

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
    if (!_isMasterAdmin || auth.token == null) {
      _loading = false;
      return;
    }
    final token = auth.token!;
    _svc = AccountService(token: token);
    _init();
  }

  Future<void> _init() async {
    try {
      final t = await _svc.getAccountTypes();
      setState(() => _types = t);
    } catch (_) {
      // ignore: types can be fetched later
    }
    _fetch(page: 1);
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _svc.getAccounts(
        isActive: _activeOnly == null ? null : _activeOnly!,
        typeCode: _typeCode,
        q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        perPage: _perPage,
        page: page,
      );
      final items = List<Map<String, dynamic>>.from(res["items"] ?? const []);
      final p = Map<String, dynamic>.from(res["pagination"] ?? const {});
      setState(() {
        _items = items;
        _currentPage = (p["current_page"] ?? 1) as int;
        _lastPage = (p["last_page"] ?? 1) as int;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------- UI helpers ----------

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          // Type dropdown
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: _typeCode,
              decoration: const InputDecoration(
                labelText: "Type",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text("All types")),
                ..._types.map((t) => DropdownMenuItem<String>(
                      value: t["code"],
                      child: Text("${t["name"]} (${t["code"]})"),
                    )),
              ],
              onChanged: (v) {
                setState(() {
                  _typeCode = v;
                  _currentPage = 1;
                });
                _fetch(page: 1);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Active filter
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<bool>(
              isExpanded: true,
              value: _activeOnly,
              decoration: const InputDecoration(
                labelText: "Status",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem<bool>(value: true, child: Text("Active only")),
                DropdownMenuItem<bool>(value: false, child: Text("Inactive only")),
                DropdownMenuItem<bool>(value: null, child: Text("All")),
              ],
              onChanged: (v) {
                setState(() {
                  _activeOnly = v;
                  _currentPage = 1;
                });
                _fetch(page: 1);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Search
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: "Search (code/name)",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) {
                setState(() => _currentPage = 1);
                _fetch(page: 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  DataTable _table() {
    return DataTable(
      columnSpacing: 24,
      headingRowHeight: 40,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 44,
      columns: const [
        DataColumn(label: Text("Code")),
        DataColumn(label: Text("Name")),
        DataColumn(label: Text("Type")),
        DataColumn(label: Text("Active")),
        DataColumn(label: Text("Actions")),
      ],
      rows: _items.map((a) {
        final active = (a["is_active"] ?? true) == true;
        final isCore = _coreAccountCodes.contains(a["code"]?.toString());
        return DataRow(cells: [
          DataCell(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a["code"] ?? ""),
              if (isCore) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: 'Protected system account',
                  child: Icon(Icons.lock_rounded, size: 15, color: AppTheme.textMuted),
                ),
              ],
            ],
          )),
          DataCell(Text(a["name"] ?? "")),
          DataCell(Text(a["type"] ?? "")),
          DataCell(Icon(
            active ? Icons.check_circle : Icons.cancel,
            color: active ? Colors.green : Colors.red,
            size: 18,
          )),
          DataCell(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enableCrud && !isCore)
                IconButton(
                  tooltip: "Edit",
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _openCreateEditDialog(row: a),
                ),
              if (_enableCrud && !isCore)
                IconButton(
                  tooltip: active ? "Deactivate" : "Activate",
                  icon: Icon(active ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => _toggleActive(a),
                ),
            ],
          )),
        ]);
      }).toList(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Failed to load accounts"),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _fetch(page: _currentPage),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(child: Text("No accounts found"));
    }

    // vertical + horizontal scrolling with visible scrollbars
    return Scrollbar(
      controller: _vCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vCtrl, // vertical
        padding: const EdgeInsets.all(12),
        child: Scrollbar(
          controller: _hCtrl,
          notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hCtrl, // horizontal
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 900),
              child: _table(),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- CRUD ----------

  Future<void> _openCreateEditDialog({Map<String, dynamic>? row}) async {
    if (!_enableCrud) return;
    final isCore = row != null && _coreAccountCodes.contains(row["code"]?.toString());
    final codeCtrl = TextEditingController(text: row?["code"] ?? "");
    final nameCtrl = TextEditingController(text: row?["name"] ?? "");
    bool isActive = (row?["is_active"] ?? true) == true;
    int? accountTypeId;

    // Pre-select type if editing
    if (row != null && row["type"] != null) {
      final hit = _types.where((t) => t["code"] == row["type"]).toList();
      if (hit.isNotEmpty) accountTypeId = hit.first["id"] as int;
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(row == null ? "Create Account" : "Edit Account"),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  readOnly: isCore,
                  decoration: const InputDecoration(
                    labelText: "Code",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Name",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: accountTypeId,
                  decoration: const InputDecoration(
                    labelText: "Account Type",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _types.map((t) {
                    return DropdownMenuItem<int>(
                      value: t["id"] as int,
                      child: Text("${t["name"]} (${t["code"]})"),
                    );
                  }).toList(),
                  onChanged: isCore ? null : (v) => setStateDialog(() => accountTypeId = v),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  dense: true,
                  title: const Text("Active"),
                  value: isActive,
                  subtitle: isCore ? const Text('Required by system posting and reports') : null,
                  onChanged: isCore ? null : (v) => setStateDialog(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text("Save"),
              onPressed: () async {
                try {
                  if (row == null) {
                    // create
                    if (codeCtrl.text.trim().isEmpty ||
                        nameCtrl.text.trim().isEmpty ||
                        accountTypeId == null) {
                      throw Exception("Code, Name and Type are required.");
                    }
                    await _svc.createAccount(
                      code: codeCtrl.text.trim(),
                      name: nameCtrl.text.trim(),
                      accountTypeId: accountTypeId!,
                      isActive: isActive,
                    );
                  } else {
                    // update
                    await _svc.updateAccount(
                      id: row["id"].toString(),
                      code: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
                      name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                      accountTypeId: accountTypeId,
                      isActive: isActive,
                    );
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    _fetch(page: _currentPage);
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
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
    final currentlyActive = (row["is_active"] ?? true) == true;
    try {
      await _svc.setActive(id: row["id"].toString(), active: !currentlyActive);
      _fetch(page: _currentPage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to change active state: $e")),
        );
      }
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    if (!_isMasterAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chart of Accounts')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Chart of Accounts is available only to Master Admin.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chart of Accounts"),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PaymentMethodsAdminScreen()),
            ),
            icon: const Icon(Icons.account_balance_wallet_rounded),
            label: const Text('Payment methods'),
          ),
          IconButton(
            onPressed: () => _fetch(page: _currentPage),
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _enableCrud
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text("New Account"),
            )
          : null,
      body: Column(
        children: [
          _filters(),
          const SizedBox(height: 8),
          Expanded(child: _body()),
          CBPagination(
            currentPage: _currentPage,
            lastPage: _lastPage,
            onPrev: _currentPage > 1 ? () => _fetch(page: _currentPage - 1) : null,
            onNext: _currentPage < _lastPage ? () => _fetch(page: _currentPage + 1) : null,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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
