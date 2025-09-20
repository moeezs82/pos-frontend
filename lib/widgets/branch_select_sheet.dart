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
  String _search = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _common = CommonService(token: token);
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final list = await _common.getBranches(search: _search);
      setState(() => _branches = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createBranch() async {
    // your exact fields
    final nameController = TextEditingController();
    final locController = TextEditingController();
    final phoneController = TextEditingController();
    bool isActive = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Branch"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(decoration: const InputDecoration(labelText: "Name"), controller: nameController),
            TextField(decoration: const InputDecoration(labelText: "Location"), controller: locController),
            TextField(decoration: const InputDecoration(labelText: "Phone"), controller: phoneController),
            SwitchListTile(
              title: const Text("Active"),
              value: isActive,
              onChanged: (v) => isActive = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              "name": nameController.text,
              "location": locController.text,
              "phone": phoneController.text,
              "is_active": isActive,
            }),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      final newBranch = await _common.createBranch(result);
      // auto-select new branch globally
      context.read<BranchProvider>().setBranch(
            id: (newBranch['id'] as num).toInt(),
            name: (newBranch['name'] ?? 'Branch').toString(),
          );
      if (!mounted) return;
      Navigator.pop(context, true); // close sheet
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BranchProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.warehouse_outlined),
                const SizedBox(width: 8),
                const Text("Select Branch", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _createBranch,
                  icon: const Icon(Icons.add),
                  label: const Text("Create"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search branch...",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  setState(() => _search = v);
                  _fetch();
                });
              },
            ),
            const SizedBox(height: 12),
            Card(
              color: bp.isAll ? Colors.blueGrey.shade50 : null,
              child: ListTile(
                leading: const Icon(Icons.all_inbox),
                title: const Text("All Branches"),
                trailing: bp.isAll ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  context.read<BranchProvider>().clear();
                  Navigator.pop(context, true);
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _branches.isEmpty
                      ? const Center(child: Text("No branches found"))
                      : ListView.builder(
                          itemCount: _branches.length,
                          itemBuilder: (_, i) {
                            final b = _branches[i];
                            final id = (b['id'] as num).toInt();
                            final name = (b['name'] ?? 'Branch $i').toString();
                            final selected = bp.selectedBranchId == id;
                            return Card(
                              color: selected ? Colors.blueGrey.shade50 : null,
                              child: ListTile(
                                leading: const Icon(Icons.apartment),
                                title: Text(name),
                                subtitle: b['location'] != null ? Text("Location: ${b['location']}") : null,
                                trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                                onTap: () {
                                  context.read<BranchProvider>().setBranch(id: id, name: name);
                                  Navigator.pop(context, true);
                                },
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
}
