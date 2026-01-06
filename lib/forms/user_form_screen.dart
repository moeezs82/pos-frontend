import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/role_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UserFormScreen extends StatefulWidget {
  final Map<String, dynamic>? user; // pass full user from list when editing
  const UserFormScreen({super.key, this.user});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _isActive = true;
  int? _branchId;

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

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _usersApi = UsersService(token: token);
    _rolesApi = RolesService(token: token);

    _branchId = context.read<BranchProvider?>()?.selectedBranchId as int?;

    if (widget.user != null) {
      final u = widget.user!;
      _name.text = u['name'] ?? '';
      _email.text = u['email'] ?? '';
      _phone.text = u['phone'] ?? '';
      _isActive = (u['is_active'] == true) || (u['is_active'] == 1);
      _branchId = u['branch_id'] ?? _branchId;

      final roles = (u['roles'] as List?) ?? [];
      _pickedRoles.addAll(
        roles
            .map((e) => (e is String) ? e : (e['name'] ?? ''))
            .where((s) => s.toString().isNotEmpty)
            .cast<String>(),
      );
    }

    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final res = await _rolesApi.getRoles(page: 1, perPage: 200);
      // ApiResponse::success => {'success':true,'data': {pagination}}
      final data = res['data'] as Map<String, dynamic>;
      final items = (data['data'] as List).cast<Map<String, dynamic>>();
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
      final payload = {
        "name": _name.text.trim(),
        "email": _email.text.trim(),
        "phone": _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        "password": widget.user == null
            ? _password.text
            : (_password.text.isEmpty ? null : _password.text),
        "is_active": _isActive,
        "branch_id": _branchId, // if accepted by backend
        "roles": _pickedRoles.toList(),
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

  Future<List<String>> _fetchAllPermissions() async {
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

    final perms = permsRaw
        .map((p) => p is Map ? (p['name'] ?? '') : p.toString())
        .where((s) => s.toString().isNotEmpty)
        .cast<String>()
        .toList();

    perms.sort();
    return perms;
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
    final theme = Theme.of(context);

    // 1) Load all permissions from API
    setState(() => _creatingRole = true);
    List<String> allPermissions = [];

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
            final filtered = allPermissions
                .where((p) => p.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return AlertDialog(
              title: const Text('Create Role'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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

                      // Permissions chips
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Permissions (${pickedPerms.length} selected)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: filtered.isEmpty
                                  ? [
                                      const Text(
                                        'No permissions match your search',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ]
                                  : filtered.map((permName) {
                                      final selected = pickedPerms.contains(
                                        permName,
                                      );
                                      return FilterChip(
                                        label: Text(
                                          permName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        selected: selected,
                                        onSelected: (v) {
                                          setLocal(() {
                                            if (v) {
                                              pickedPerms.add(permName);
                                            } else {
                                              pickedPerms.remove(permName);
                                            }
                                          });
                                        },
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      );
                                    }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                          backgroundColor: theme.colorScheme.error,
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

    // 3) After dialog: update roles list + auto-select
    if (createdRole != null && mounted) {
      setState(() {
        _allRoles.insert(0, createdRole);
        final newName = (createdRole['name'] ?? '').toString();
        if (newName.isNotEmpty) {
          _pickedRoles.add(newName); // auto-assign new role to this user
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role created successfully')),
      );
    }
  }

  Future<void> _openEditRoleDialog(Map<String, dynamic> role) async {
    final theme = Theme.of(context);
    setState(() => _creatingRole = true);

    List<String> allPermissions;
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

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Set<String> pickedPerms = {...currentPerms};
        String query = '';

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final filtered = allPermissions
                .where((p) => p.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return AlertDialog(
              title: const Text('Edit Role'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Permissions (${pickedPerms.length} selected)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: filtered.isEmpty
                                  ? [
                                      const Text(
                                        'No permissions match your search',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ]
                                  : filtered.map((permName) {
                                      final selected = pickedPerms.contains(
                                        permName,
                                      );
                                      return FilterChip(
                                        label: Text(
                                          permName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        selected: selected,
                                        onSelected: (v) {
                                          setLocal(() {
                                            if (v) {
                                              pickedPerms.add(permName);
                                            } else {
                                              pickedPerms.remove(permName);
                                            }
                                          });
                                        },
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      );
                                    }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                        permissions: pickedPerms.toList(),
                      );
                      Navigator.of(ctx).pop(true);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update role: $e'),
                          backgroundColor: theme.colorScheme.error,
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

    if (updated == true && mounted) {
      final newName = nameCtrl.text.trim();

      setState(() {
        final idx = _allRoles.indexWhere((r) => r['id'] == roleId);
        if (idx != -1) {
          _allRoles[idx] = {
            ..._allRoles[idx],
            'name': newName,
            'permissions': currentPerms.toList(), // or re-fetch later if needed
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
    final theme = Theme.of(context);
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
              backgroundColor: theme.colorScheme.error,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit User" : "New User"),
        centerTitle: true,
        actions: [
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
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
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
                                  color: theme.colorScheme.primary,
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
                              onChanged: (v) => setState(() => _isActive = v),
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
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
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
                                  color: theme.colorScheme.primary,
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

                                  final preview = perms.take(4).toList();
                                  final moreCount =
                                      (perms.length - preview.length);

                                  return _RoleCard(
                                    name: name,
                                    permissions: perms,
                                    selected: selected,
                                    onChanged: (v) {
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
                                    onEdit: id == null
                                        ? null
                                        : () => _openEditRoleDialog(r),
                                    onDelete: id == null
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

class _RoleCard extends StatefulWidget {
  final String name;
  final List<String> permissions;
  final bool selected;
  final void Function(bool selected) onChanged;

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
      onTap: () => widget.onChanged(!widget.selected),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
                  onChanged: (v) => widget.onChanged(v ?? false),
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
