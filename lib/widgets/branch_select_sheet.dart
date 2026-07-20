import 'dart:async';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BranchSelectSheet extends StatefulWidget {
  const BranchSelectSheet({super.key});

  @override
  State<BranchSelectSheet> createState() => _BranchSelectSheetState();
}

class _BranchSelectSheetState extends State<BranchSelectSheet> {
  late CommonService _common;
  List<Map<String, dynamic>> _branches = [];
  bool _loading = false;
  bool _switching = false;
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _common = CommonService(token: token);
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final list = await _common.getBranches(search: _search);
      if (mounted) setState(() => _branches = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchTo({required int? id, String? name, String? currency}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isMasterAdmin) return;

    setState(() => _switching = true);
    try {
      final data = await auth.switchBranch(id);
      if (!mounted) return;

      final activeBranch = _asMap(data['active_branch']) ?? _asMap(data['branch']);
      context.read<BranchProvider>().syncFromAuthUser(
            auth.user,
            activeBranch: activeBranch,
          );

      // Fallback if backend returned user without nested branch.
      if (activeBranch == null) {
        context.read<BranchProvider>().setBranch(id: id, name: name, currency: currency);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to ${name ?? 'Branch #$id'} and locked workspace to this branch.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _createBranch() async {
    if (!context.read<AuthProvider>().isMasterAdmin) return;

    final result = await _branchDialog();
    if (result == null) return;

    try {
      final newBranch = await _common.createBranch(result);
      final id = _readInt(newBranch['id']);
      final name = (newBranch['name'] ?? 'Branch').toString();
      final currency = (newBranch['currency'] ?? result['currency'] ?? 'KD').toString();
      await _fetch();
      if (id != null) {
        await _switchTo(id: id, name: name, currency: currency);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _editBranch(Map<String, dynamic> branch) async {
    if (!context.read<AuthProvider>().isMasterAdmin) return;

    final id = _readInt(branch['id']);
    if (id == null) return;
    final result = await _branchDialog(branch: branch);
    if (result == null) return;

    try {
      final updated = await _common.updateBranch(id, result);
      await _fetch();
      if (!mounted) return;

      final branchProvider = context.read<BranchProvider>();
      if (branchProvider.selectedBranchId == id) {
        final auth = context.read<AuthProvider>();
        await auth.refreshMe();
        if (!mounted) return;
        branchProvider.syncFromAuthUser(auth.user);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${updated['name'] ?? result['name']} updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<Map<String, dynamic>?> _branchDialog({Map<String, dynamic>? branch}) async {
    final nameController = TextEditingController(text: branch?['name']?.toString() ?? '');
    final locController = TextEditingController(text: branch?['location']?.toString() ?? '');
    final phoneController = TextEditingController(text: branch?['phone']?.toString() ?? '');
    final currencyController = TextEditingController(text: branch?['currency']?.toString() ?? 'KD');
    bool isActive = branch == null || branch['is_active'] == true || branch['is_active'] == 1;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(branch == null ? 'Add Branch' : 'Edit Branch'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(decoration: const InputDecoration(labelText: 'Name'), controller: nameController),
              TextField(decoration: const InputDecoration(labelText: 'Location'), controller: locController),
              TextField(decoration: const InputDecoration(labelText: 'Phone'), controller: phoneController),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  hintText: 'KD, AED, USD, \$, € …',
                  helperText: 'Used on all prices, reports, receipts and barcode labels.',
                ),
                controller: currencyController,
                maxLength: 20,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: isActive,
                onChanged: (v) => setLocal(() => isActive = v),
              ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final currency = currencyController.text.trim();
                if (name.isEmpty || currency.isEmpty) return;
                Navigator.pop(ctx, {
                  'name': name,
                  'location': locController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'currency': currency,
                  'is_active': isActive,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    locController.dispose();
    phoneController.dispose();
    currencyController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BranchProvider>();
    final auth = context.watch<AuthProvider>();
    final canSwitch = auth.isMasterAdmin;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.warehouse_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Working Branch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        canSwitch
                            ? 'This is the only place where master admin can switch branch. The backend will then return data for that branch only.'
                            : 'Normal users cannot switch branch. They work only inside their assigned branch.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (canSwitch)
                  TextButton.icon(
                    onPressed: _switching ? null : _createBranch,
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!canSwitch) ...[
              Card(
                color: Colors.amber.shade50,
                child: const ListTile(
                  leading: Icon(Icons.lock_outline_rounded),
                  title: Text('Branch switching locked'),
                  subtitle: Text('Your user is already assigned to a branch by master admin.'),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text('No branch selection is available for normal users.'),
                ),
              ),
            ] else ...[
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search branch...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    setState(() => _search = v);
                    _fetch();
                  });
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Stack(
                  children: [
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _branches.isEmpty
                            ? const Center(child: Text('No branches found'))
                            : ListView.builder(
                                itemCount: _branches.length,
                                itemBuilder: (_, i) {
                                  final b = _branches[i];
                                  final id = _readInt(b['id']);
                                  if (id == null) return const SizedBox.shrink();
                                  final name = (b['name'] ?? 'Branch $id').toString();
                                  final currency = (b['currency'] ?? 'KD').toString();
                                  final selected = bp.selectedBranchId == id;
                                  return Card(
                                    color: selected ? Colors.blueGrey.shade50 : null,
                                    child: ListTile(
                                      enabled: !_switching,
                                      leading: const Icon(Icons.apartment),
                                      title: Text(name),
                                      subtitle: b['location'] != null && b['location'].toString().trim().isNotEmpty
                                          ? Text('Location: ${b['location']}')
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(currency, style: Theme.of(context).textTheme.labelMedium),
                                          IconButton(
                                            tooltip: 'Edit branch',
                                            onPressed: _switching ? null : () => _editBranch(b),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                          if (selected) const Icon(Icons.check, color: Colors.green),
                                        ],
                                      ),
                                      onTap: _switching ? null : () => _switchTo(id: id, name: name, currency: currency),
                                    ),
                                  );
                                },
                              ),
                    if (_switching)
                      Container(
                        color: Colors.white.withOpacity(.45),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString());
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
