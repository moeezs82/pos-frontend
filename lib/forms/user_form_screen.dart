import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/role_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UserFormScreen extends StatefulWidget {
  final Map<String, dynamic>? user; // pass full user from list when editing
  const UserFormScreen({super.key, this.user});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  static const List<String> _permissionGroupOrder = [
    'Sales',
    'Products & Inventory',
    'Customers',
    'Party Payments',
    'Party Credit Control',
    'Vendors & Purchases',
    'Cash & Accounting',
    'Reports',
    'Register & Shifts',
    'Delivery',
    'Users & Access',
    'Other',
  ];

  static const Map<String, String> _permissionLabels = {
    'view-sales': 'View Sales',
    'create-sales': 'Create Sales',
    'view-sale-profit': 'View Sale Profit',
    'manage-sales': 'Edit Sales & Payments',
    'refund-sale': 'Process Returns & Refunds',
    'view-products': 'View Products',
    'manage-products': 'Manage Products',
    'view-stock': 'View Stock',
    'adjust-stock': 'Adjust Stock',
    'view-customers': 'View Customers',
    'manage-customers': 'Manage Customers',
    'manage-receipts': 'Receive Customer Payments',
    'view-vendors': 'View Vendors',
    'manage-vendors': 'Manage Vendors',
    'view-purchases': 'View Purchases',
    'manage-purchases': 'Manage Purchases & Claims',
    'manage-payments': 'Pay Vendors',
    'reverse-party-payments': 'Reverse Party Payments',
    'override-party-credit-limit': 'Override Party Credit Limit',
    'view-party-credit-limit-audits': 'View Credit Control Audits',
    'view-cashbook': 'View Cash Ledger & Day Book',
    'manage-cashbook': 'Record & Void Cash Entries',
    'view-reports': 'View Reports',
    'view-register-shifts': 'View Register Shifts',
    'open-register-shift': 'Open Register Shift',
    'close-own-register-shift': 'Close Own Register Shift',
    'record-shift-cash-movement': 'Record Shift Cash In/Out',
    'manage-register-shifts': 'Manage Registers & All Shifts',
    'approve-shift-variance': 'Approve Closing Variance',
    'approve-shift-cash-movement': 'Approve Cash Movement',
    'view-delivery': 'View Delivery Operations',
    'manage-delivery': 'Manage Delivery Assignments',
    'receive-delivery-cash': 'Receive Delivery Cash',
    'view-users': 'View Users',
    'manage-users': 'Manage Users',
    'view-roles': 'View Roles',
    'manage-roles': 'Manage Roles & Permissions',
  };

  String _permissionLabel(String key) => _permissionLabels[key] ??
      key.split('-').map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');

  String _fallbackPermissionGroup(String key) {
    if ({
      'view-sales',
      'create-sales',
      'view-sale-profit',
      'manage-sales',
      'refund-sale',
    }.contains(key)) {
      return 'Sales';
    }
    if ({
      'view-products',
      'manage-products',
      'view-stock',
      'adjust-stock',
      'view-categories',
      'manage-categories',
      'view-brands',
      'manage-brands',
    }.contains(key)) {
      return 'Products & Inventory';
    }
    if ({'view-customers', 'manage-customers'}.contains(key)) {
      return 'Customers';
    }
    if ({'manage-receipts', 'manage-payments', 'reverse-party-payments'}.contains(key)) {
      return 'Party Payments';
    }
    if ({'override-party-credit-limit', 'view-party-credit-limit-audits'}.contains(key)) {
      return 'Party Credit Control';
    }
    if ({
      'view-vendors',
      'manage-vendors',
      'view-purchases',
      'manage-purchases',
    }.contains(key)) {
      return 'Vendors & Purchases';
    }
    if ({'view-cashbook', 'manage-cashbook'}.contains(key)) {
      return 'Cash & Accounting';
    }
    if (key == 'view-reports') return 'Reports';
    if (key.contains('register-shift') ||
        key.contains('shift-cash') ||
        key.contains('shift-variance')) {
      return 'Register & Shifts';
    }
    if (key.contains('delivery')) return 'Delivery';
    if (key.contains('user') || key.contains('role')) return 'Users & Access';
    return 'Other';
  }
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _isActive = true;
  // Roles/permissions
  final Set<String> _pickedRoles = {};
  List<Map<String, dynamic>> _allRoles = [];
  final _roleSearch = TextEditingController();
  String _roleQuery = '';

  late UsersService _usersApi;
  late RolesService _rolesApi;
  bool _loading = true;
  bool _saving = false;
  bool _creatingRole = false;

  bool get _isEditingCurrentUser {
    final currentId = _readInt(context.read<AuthProvider>().user?['id']);
    final editedId = _readInt(widget.user?['id']);
    return currentId != null && editedId != null && currentId == editedId;
  }

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _usersApi = UsersService(token: token);
    _rolesApi = RolesService(token: token);

    if (widget.user != null) {
      final u = widget.user!;
      _name.text = u['name'] ?? '';
      _email.text = u['email'] ?? '';
      _phone.text = u['phone'] ?? '';
      _isActive = (u['is_active'] == true) || (u['is_active'] == 1);

      final roles = (u['roles'] as List?) ?? [];
      _pickedRoles.addAll(
        roles
            .map((e) => (e is String) ? e : (e['display_name'] ?? e['label'] ?? e['name'] ?? ''))
            .map((s) => _stripBranchSuffix(s.toString()))
            .where((s) => s.toString().isNotEmpty)
            .cast<String>(),
      );
    }

    _loadRoles();
  }


  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _roleSearch.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final res = await _rolesApi.getRoles(page: 1, perPage: 200);
      // ApiResponse::success => {'success':true,'data': {pagination}}
      final data = res['data'];
      final rawItems = data is List
          ? data
          : (data is Map && data['data'] is List ? data['data'] as List : const []);
      final items = rawItems
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .map((role) => {
                ...role,
                'name': _stripBranchSuffix((role['display_name'] ?? role['label'] ?? role['name'] ?? '').toString()),
              })
          .where((role) => !_isMasterRoleName((role['name'] ?? '').toString()))
          .toList();
      setState(() => _allRoles = items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load roles: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final selectedRoleIds = _allRoles
          .where((role) => _pickedRoles.contains((role['name'] ?? '').toString()))
          .map((role) => _readInt(role['id']))
          .whereType<int>()
          .toList();

      final isOwnAccount = _isEditingCurrentUser;
      final payload = <String, dynamic>{
        "name": _name.text.trim(),
        "email": _email.text.trim(),
        "phone": _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        "password": widget.user == null
            ? _password.text
            : (_password.text.isEmpty ? null : _password.text),
        if (!isOwnAccount) "is_active": _isActive,
        // Backend injects the active branch from the logged-in user's branch context.
        // Do not send branch_id from the frontend so branch users never see branch logic.
        if (!isOwnAccount && selectedRoleIds.isNotEmpty) "role_ids": selectedRoleIds,
        if (!isOwnAccount && selectedRoleIds.isEmpty) "roles": _pickedRoles.toList(),
      };

      if (widget.user == null) {
        await _usersApi.createUser(payload);
      } else {
        final id = widget.user!['id'] as int;
        await _usersApi.updateUser(id, payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tf({
    required TextEditingController c,
    required String label,
    TextInputType kt = TextInputType.text,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: kt,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      validator: validator,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllPermissions() async {
    final res = await _rolesApi.availablePermissions(
      guardName: 'web',
      all: true,
      perPage: 500,
    );

    final data = res['data'];
    List permsRaw;
    if (data is List) {
      permsRaw = data;
    } else if (data is Map && data['data'] is List) {
      permsRaw = data['data'] as List; // paginated style
    } else {
      permsRaw = const [];
    }

    final auth = context.read<AuthProvider>();
    final permissions = <Map<String, dynamic>>[];
    for (final raw in permsRaw) {
      final item = raw is Map
          ? raw.cast<String, dynamic>()
          : <String, dynamic>{'name': raw.toString()};
      final key = (item['name'] ?? item['key'] ?? '').toString().trim();
      if (key.isEmpty || !auth.hasPermission(key)) continue;

      permissions.add({
        ...item,
        'name': key,
        'label': (item['label'] ?? _permissionLabel(key)).toString(),
        'group': (item['group'] ?? _fallbackPermissionGroup(key)).toString(),
        'description': (item['description'] ?? '').toString(),
      });
    }

    permissions.sort((a, b) {
      final aGroup = (a['group'] ?? 'Other').toString();
      final bGroup = (b['group'] ?? 'Other').toString();
      final aIndex = _permissionGroupOrder.indexOf(aGroup);
      final bIndex = _permissionGroupOrder.indexOf(bGroup);
      final groupCompare = (aIndex < 0 ? 999 : aIndex)
          .compareTo(bIndex < 0 ? 999 : bIndex);
      if (groupCompare != 0) return groupCompare;
      return (a['label'] ?? '').toString().compareTo((b['label'] ?? '').toString());
    });
    return permissions;
  }

  Widget _buildPermissionSelector({
    required List<Map<String, dynamic>> permissions,
    required Set<String> selected,
    required String query,
    required StateSetter setLocal,
  }) {
    final theme = Theme.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    final allNames = permissions
        .map((permission) => permission['name'].toString())
        .toSet();
    final allSelected = allNames.isNotEmpty && allNames.every(selected.contains);
    final anySelected = allNames.any(selected.contains);

    final visible = permissions.where((permission) {
      if (normalizedQuery.isEmpty) return true;
      final searchable = [
        permission['name'],
        permission['label'],
        permission['group'],
        permission['description'],
      ].join(' ').toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList();

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final permission in visible) {
      final group = (permission['group'] ?? 'Other').toString();
      grouped.putIfAbsent(group, () => []).add(permission);
    }

    final orderedGroups = grouped.keys.toList()
      ..sort((a, b) {
        final aIndex = _permissionGroupOrder.indexOf(a);
        final bIndex = _permissionGroupOrder.indexOf(b);
        final orderCompare = (aIndex < 0 ? 999 : aIndex)
            .compareTo(bIndex < 0 ? 999 : bIndex);
        return orderCompare != 0 ? orderCompare : a.compareTo(b);
      });

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: CheckboxListTile(
            value: allSelected ? true : (anySelected ? null : false),
            tristate: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Select all permissions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${selected.length} of ${allNames.length} selected'),
            secondary: selected.isEmpty
                ? null
                : TextButton(
                    onPressed: () => setLocal(selected.clear),
                    child: const Text('Clear all'),
                  ),
            onChanged: (_) {
              setLocal(() {
                if (allSelected) {
                  selected.removeAll(allNames);
                } else {
                  selected.addAll(allNames);
                }
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: grouped.isEmpty
              ? const Center(
                  child: Text(
                    'No permissions match your search',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Scrollbar(
                  child: ListView.separated(
                    itemCount: orderedGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final group = orderedGroups[index];
                      final visibleGroupPermissions = grouped[group]!;
                      final allGroupNames = permissions
                          .where((permission) => permission['group'] == group)
                          .map((permission) => permission['name'].toString())
                          .toSet();
                      final selectedInGroup =
                          allGroupNames.where(selected.contains).length;
                      final groupFullySelected = allGroupNames.isNotEmpty &&
                          selectedInGroup == allGroupNames.length;
                      final groupPartiallySelected =
                          selectedInGroup > 0 && !groupFullySelected;

                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: groupPartiallySelected || groupFullySelected
                                ? theme.colorScheme.primary.withOpacity(0.55)
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          key: ValueKey('$group-$normalizedQuery'),
                          initiallyExpanded: normalizedQuery.isNotEmpty ||
                              groupPartiallySelected ||
                              groupFullySelected,
                          tilePadding: const EdgeInsets.only(left: 8, right: 12),
                          childrenPadding: const EdgeInsets.only(bottom: 6),
                          leading: Checkbox(
                            value: groupFullySelected
                                ? true
                                : (groupPartiallySelected ? null : false),
                            tristate: true,
                            onChanged: (_) {
                              setLocal(() {
                                if (groupFullySelected) {
                                  selected.removeAll(allGroupNames);
                                } else {
                                  selected.addAll(allGroupNames);
                                }
                              });
                            },
                          ),
                          title: Text(
                            group,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '$selectedInGroup of ${allGroupNames.length} selected',
                          ),
                          children: visibleGroupPermissions.map((permission) {
                            final key = permission['name'].toString();
                            final description =
                                (permission['description'] ?? '').toString();
                            return CheckboxListTile(
                              dense: true,
                              value: selected.contains(key),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding:
                                  const EdgeInsets.only(left: 18, right: 16),
                              title: Text(
                                (permission['label'] ?? _permissionLabel(key))
                                    .toString(),
                              ),
                              subtitle: description.isEmpty
                                  ? null
                                  : Text(
                                      description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onChanged: (checked) {
                                setLocal(() {
                                  if (checked == true) {
                                    selected.add(key);
                                  } else {
                                    selected.remove(key);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredRoles {
    final q = _roleQuery.trim().toLowerCase();
    if (q.isEmpty) return _allRoles;
    return _allRoles.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final perms = ((r['permissions'] as List?) ?? [])
          .map((e) => ((e is Map) ? (e['name'] ?? '') : e).toString())
          .join(',')
          .toLowerCase();
      return name.contains(q) || perms.contains(q);
    }).toList();
  }

  Future<void> _openCreateRoleDialog() async {
    if (!context.read<AuthProvider>().hasPermission('manage-roles')) return;

    // 1) Load all permissions from API
    setState(() => _creatingRole = true);
    List<Map<String, dynamic>> allPermissions = [];

    try {
      allPermissions = await _fetchAllPermissions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load permissions: $e')),
        );
      }
      if (mounted) setState(() => _creatingRole = false);
      return;
    }

    if (mounted) setState(() => _creatingRole = false);

    // 2) Open dialog for role name + permission selection
    final nameCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final createdRole = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Set<String> pickedPerms = {};
        String query = '';

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Create Role'),
              content: SizedBox(
                width: 640,
                height: 560,
                child: Column(
                  children: [
                    // Role name
                    Form(
                      key: formKey,
                      child: TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Role name',
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Role name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Permission search
                    TextField(
                      controller: searchCtrl,
                      onChanged: (v) =>
                          setLocal(() => query = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search permissions…',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: _buildPermissionSelector(
                        permissions: allPermissions,
                        selected: pickedPerms,
                        query: query,
                        setLocal: setLocal,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    try {
                      final role = await _rolesApi.createRole(
                        name: nameCtrl.text.trim(),
                        permissions: pickedPerms.toList(),
                      );
                      Navigator.of(ctx).pop(role);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to create role: $e'),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    searchCtrl.dispose();

    // 3) After dialog: update roles list + auto-select
    if (createdRole != null && mounted) {
      final rolePayload = (createdRole['role'] is Map)
          ? (createdRole['role'] as Map).cast<String, dynamic>()
          : createdRole;
      final newName = _stripBranchSuffix((rolePayload['display_name'] ?? rolePayload['label'] ?? rolePayload['name'] ?? '').toString());
      rolePayload['name'] = newName;

      if (newName.isNotEmpty && !_isMasterRoleName(newName)) {
        setState(() {
          _allRoles.insert(0, rolePayload);
          _pickedRoles.add(newName); // auto-assign new role to this user
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role created successfully')),
      );
    }
  }

  Future<void> _openEditRoleDialog(Map<String, dynamic> role) async {
    if (!_readBoolWithFallback(role['can_edit'], false) ||
        !context.read<AuthProvider>().hasPermission('manage-roles')) {
      final reason = role['edit_block_reason']?.toString() ?? 'You are not allowed to edit this role.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    setState(() => _creatingRole = true);

    List<Map<String, dynamic>> allPermissions;
    try {
      allPermissions = await _fetchAllPermissions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load permissions: $e')),
        );
      }
      if (mounted) setState(() => _creatingRole = false);
      return;
    }
    if (mounted) setState(() => _creatingRole = false);

    final roleId = role['id'] as int;
    final originalName = (role['name'] ?? '').toString();
    final currentPerms = ((role['permissions'] as List?) ?? [])
        .map((p) => p is Map ? (p['name'] ?? '') : p.toString())
        .where((s) => s.toString().isNotEmpty)
        .cast<String>()
        .toSet();

    final nameCtrl = TextEditingController(text: originalName);
    final searchCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    Set<String> savedPerms = {...currentPerms};
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String query = '';

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Edit Role'),
              content: SizedBox(
                width: 640,
                height: 560,
                child: Column(
                  children: [
                    Form(
                      key: formKey,
                      child: TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Role name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Role name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (v) =>
                          setLocal(() => query = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search permissions…',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildPermissionSelector(
                        permissions: allPermissions,
                        selected: savedPerms,
                        query: query,
                        setLocal: setLocal,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    try {
                      await _rolesApi.updateRole(
                        roleId,
                        name: nameCtrl.text.trim(),
                        permissions: savedPerms.toList(),
                      );
                      Navigator.of(ctx).pop(true);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update role: $e'),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    final updatedName = nameCtrl.text.trim();
    nameCtrl.dispose();
    searchCtrl.dispose();

    if (updated == true && mounted) {
      final newName = _stripBranchSuffix(updatedName);

      setState(() {
        final idx = _allRoles.indexWhere((r) => r['id'] == roleId);
        if (idx != -1) {
          _allRoles[idx] = {
            ..._allRoles[idx],
            'name': newName,
            'permissions': savedPerms.toList(),
          };
        }

        // If this role was selected for this user and name changed, update the set
        if (originalName != newName && _pickedRoles.remove(originalName)) {
          _pickedRoles.add(newName);
        }
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role updated')));
    }
  }

  Future<void> _confirmDeleteRole(Map<String, dynamic> role) async {
    if (!_readBoolWithFallback(role['can_edit'], false) ||
        !context.read<AuthProvider>().hasPermission('manage-roles')) {
      final reason = role['edit_block_reason']?.toString() ?? 'You are not allowed to delete this role.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    final roleId = role['id'] as int;
    final roleName = (role['name'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text(
          'Are you sure you want to delete the role "$roleName"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _rolesApi.deleteRole(roleId);
      if (!mounted) return;

      setState(() {
        _allRoles.removeWhere((r) => r['id'] == roleId);
        _pickedRoles.remove(roleName); // if assigned to this user
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Role "$roleName" deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete role: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.user != null;
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final canManageRoles = auth.hasPermission('manage-roles');
    final isOwnAccount = _isEditingCurrentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit User" : "New User"),
        centerTitle: true,
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: BranchIndicator(tappable: false),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // ——— User basics
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppTheme.border,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'User details',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _tf(
                              c: _name,
                              label: "Name *",
                              validator: (v) =>
                                  v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 12),
                            _tf(
                              c: _email,
                              label: "Email *",
                              kt: TextInputType.emailAddress,
                              validator: (v) =>
                                  v == null || v.isEmpty ? "Required" : null,
                            ),
                            const SizedBox(height: 12),
                            _tf(c: _phone, label: "Phone"),
                            const SizedBox(height: 12),
                            if (!isEdit)
                              _tf(
                                c: _password,
                                label: "Password *",
                                obscure: true,
                                validator: (v) => v == null || v.length < 6
                                    ? "Min 6 chars"
                                    : null,
                              )
                            else
                              _tf(
                                c: _password,
                                label: "Password (leave blank to keep)",
                                obscure: true,
                              ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active'),
                              value: _isActive,
                              onChanged: isOwnAccount ? null : (v) => setState(() => _isActive = v),
                              subtitle: isOwnAccount
                                  ? const Text('You cannot deactivate your own account.')
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ——— Roles + permissions
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppTheme.border,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Roles & Permissions',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Tooltip(
                                  message:
                                      'Selected: ${_pickedRoles.length} role(s)',
                                  child: Chip(
                                    label: Text(
                                      '${_pickedRoles.length} selected',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (canManageRoles)
                                  OutlinedButton.icon(
                                  onPressed: _creatingRole
                                      ? null
                                      : _openCreateRoleDialog, // 👈 NEW
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('New role'),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // role search
                            TextField(
                              controller: _roleSearch,
                              decoration: InputDecoration(
                                hintText: "Search role or permission...",
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => _roleQuery = v),
                            ),
                            const SizedBox(height: 12),

                            // list of role cards
                            if (_filteredRoles.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Center(
                                  child: Text(
                                    'No roles match your search',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredRoles.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final r = _filteredRoles[i];
                                  final id = r['id'] as int?;
                                  final name = r['name'] as String? ?? '—';
                                  final permsRaw =
                                      (r['permissions'] as List?) ?? [];
                                  final perms = permsRaw
                                      .map(
                                        (e) => (e is Map)
                                            ? (e['name'] ?? '')
                                            : e.toString(),
                                      )
                                      .where((s) => s.toString().isNotEmpty)
                                      .cast<String>()
                                      .toList();

                                  final selected = _pickedRoles.contains(name);
                                  final assignable = _readBoolWithFallback(r['is_assignable'], true);
                                  final canEditRole = canManageRoles && _readBoolWithFallback(r['can_edit'], false);
                                  final roleBlocked = isOwnAccount || !assignable;
                                  final blockReason = isOwnAccount
                                      ? 'You cannot change the role assigned to your own account.'
                                      : r['assignment_block_reason']?.toString();

                                  final preview = perms.take(4).toList();
                                  final moreCount =
                                      (perms.length - preview.length);

                                  return _RoleCard(
                                    name: name,
                                    permissions: perms,
                                    selected: selected,
                                    onChanged: roleBlocked ? null : (v) {
                                      setState(() {
                                        if (v) {
                                          _pickedRoles.add(name);
                                        } else {
                                          _pickedRoles.remove(name);
                                        }
                                      });
                                    },
                                    preview: preview,
                                    moreCount: moreCount,
                                    blockedReason: blockReason,
                                    onEdit: id == null || !canEditRole
                                        ? null
                                        : () => _openEditRoleDialog(r),
                                    onDelete: id == null || !canEditRole
                                        ? null
                                        : () => _confirmDeleteRole(r),
                                  );
                                },
                              ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: Text(
                        _saving
                            ? 'Saving…'
                            : (isEdit ? 'Update User' : 'Create User'),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}


int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString());
  return parsed != null && parsed > 0 ? parsed : null;
}

bool _readBoolWithFallback(dynamic value, bool fallback) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

bool _isMasterRoleName(String value) {
  final normalized = _stripBranchSuffix(value)
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized == 'master admin' || normalized == 'super admin';
}

String _stripBranchSuffix(String value) {
  return value.replaceFirst(RegExp(r'\s-\s.*\s\[branch:\d+\]$', caseSensitive: false), '').trim();
}

class _RoleCard extends StatefulWidget {
  final String name;
  final List<String> permissions;
  final bool selected;
  final void Function(bool selected)? onChanged;
  final String? blockedReason;

  // presentation
  final List<String> preview;
  final int moreCount;

  // NEW:
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _RoleCard({
    required this.name,
    required this.permissions,
    required this.selected,
    required this.onChanged,
    required this.preview,
    required this.moreCount,
    this.blockedReason,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: widget.onChanged == null ? null : () => widget.onChanged!(!widget.selected),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: widget.selected ? 1.6 : 1,
          ),
          color: widget.selected
              ? theme.colorScheme.primaryContainer.withOpacity(0.25)
              : theme.colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Checkbox(
                  value: widget.selected,
                  onChanged: widget.onChanged == null ? null : (v) => widget.onChanged!(v ?? false),
                ),
                if (widget.onChanged == null)
                  Tooltip(
                    message: widget.blockedReason ?? 'This role is above your permission level.',
                    child: const Icon(Icons.lock_outline, size: 20),
                  ),
                Expanded(
                  child: Text(
                    widget.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onEdit != null || widget.onDelete != null)
                  PopupMenuButton<String>(
                    tooltip: 'Manage role',
                    onSelected: (value) {
                      if (value == 'edit') {
                        widget.onEdit?.call();
                      } else if (value == 'delete') {
                        widget.onDelete?.call();
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (widget.onEdit != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                      if (widget.onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ],
                          ),
                        ),
                    ],
                  ),
                if (widget.permissions.isNotEmpty)
                  IconButton(
                    splashRadius: 22,
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    tooltip: 'Show permissions',
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Preview row (3 chips max) + “+N more” + “View all”
            if (widget.permissions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6, // ✅ no overlapping
                children: [
                  for (final p in widget.preview)
                    Chip(
                      label: Text(p, overflow: TextOverflow.ellipsis),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  if (widget.moreCount > 0)
                    ActionChip(
                      label: Text('+${widget.moreCount} more'),
                      onPressed: () => setState(() => _expanded = true),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (widget.permissions.length > 12)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_full, size: 18),
                      label: const Text('View all'),
                      onPressed: () => _showAllPermissionsSheet(context),
                    ),
                ],
              ),

            // Expanded – scrollable chips in a constrained area
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                  ), // ✅ caps height
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6, // ✅ safe spacing
                        children: widget.permissions.map((p) {
                          return Chip(
                            label: Text(p, overflow: TextOverflow.ellipsis),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllPermissionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final controller = TextEditingController();
        List<String> filtered = List.from(widget.permissions);

        void applyFilter(String q) {
          q = q.trim().toLowerCase();
          filtered = q.isEmpty
              ? List.from(widget.permissions)
              : widget.permissions
                    .where((p) => p.toLowerCase().contains(q))
                    .toList();
          (ctx as Element).markNeedsBuild();
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_open),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.name} • ${widget.permissions.length} permissions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: applyFilter,
                decoration: InputDecoration(
                  hintText: 'Search permission…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: filtered
                          .map(
                            (p) => Chip(
                              label: Text(p, overflow: TextOverflow.ellipsis),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
