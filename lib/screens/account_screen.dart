import 'package:enterprise_pos/api/account_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_pagination.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late AccountService _svc;

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

  // toggle CRUD controls (turn off if backend is read-only)
  final bool _enableCrud = true;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
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
        return DataRow(cells: [
          DataCell(Text(a["code"] ?? "")),
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
              if (_enableCrud)
                IconButton(
                  tooltip: "Edit",
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _openCreateEditDialog(row: a),
                ),
              if (_enableCrud)
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
                  onChanged: (v) => setStateDialog(() => accountTypeId = v),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  dense: true,
                  title: const Text("Active"),
                  value: isActive,
                  onChanged: (v) => setStateDialog(() => isActive = v),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chart of Accounts"),
        actions: [
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
