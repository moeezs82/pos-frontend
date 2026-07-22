import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/forms/user_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = false;
  String _search = '';
  final List<Map<String, dynamic>> _users = [];
  final _searchController = TextEditingController();

  late final UsersService _usersService;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _usersService = UsersService(token: token);
    _fetchUsers(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({bool reset = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    if (reset) {
      _users.clear();
      _page = 1;
    }

    try {
      final response = await _usersService.getUsers(
        page: _page,
        perPage: 20,
        search: _search,
        excludeMasterAdmin: true,
      );

      final responseData = response['data'];
      final pageData = _asMap(responseData) ?? const <String, dynamic>{};
      final rawItems = responseData is List
          ? responseData
          : (pageData['data'] is List ? pageData['data'] as List : const []);
      final items = rawItems
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where((user) => !_isMasterAdminUser(user))
          .toList();

      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(items);
        _page = _readInt(pageData['current_page']) ?? _page;
        _lastPage = _readInt(pageData['last_page']) ?? 1;
        _total = _readInt(pageData['total']) ?? items.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch() {
    setState(() => _search = _searchController.text.trim());
    _fetchUsers(reset: true);
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final id = _readInt(user['id']);
    if (id == null) return;

    try {
      await _usersService.deleteUser(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted successfully')),
      );
      await _fetchUsers(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete user: $e')),
      );
    }
  }

  Future<void> _openForm([Map<String, dynamic>? user]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UserFormScreen(user: user)),
    );
    if (result == true) {
      await _fetchUsers(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserId = _readInt(auth.user?['id']);
    final canManageUsers = auth.hasPermission('manage-users');
    final activeCount = _users.where((u) => _readBool(u['is_active'])).length;
    final inactiveCount = _users.length - activeCount;

    return EnterprisePage(
      title: 'Users',
      subtitle: 'Manage staff accounts and role access. Master admin accounts stay hidden from staff lists.',
      icon: Icons.manage_accounts_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: canManageUsers
          ? [
              FilledButton.icon(
                onPressed: _loading ? null : () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add User'),
              ),
            ]
          : const [],
      floatingActionButton: canManageUsers
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : () => _openForm(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add User'),
            )
          : null,
      bottomNavigationBar: EnterprisePaginationBar(
        page: _page,
        lastPage: _lastPage,
        total: _total,
        loading: _loading,
        onPrevious: _page > 1
            ? () {
                setState(() => _page--);
                _fetchUsers();
              }
            : null,
        onNext: _page < _lastPage
            ? () {
                setState(() => _page++);
                _fetchUsers();
              }
            : null,
      ),
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              SizedBox(
                width: 360,
                child: EnterpriseSearchField(
                  controller: _searchController,
                  hintText: 'Search name, email, phone, or role...',
                  onSubmitted: (_) => _onSearch(),
                  onSearch: _onSearch,
                  onClear: () {
                    _searchController.clear();
                    _onSearch();
                  },
                ),
              ),
              EnterpriseMetricChip(
                label: 'Visible users',
                value: '${_users.length}',
                color: AppTheme.primary,
                icon: Icons.people_alt_rounded,
              ),
              EnterpriseMetricChip(
                label: 'Active',
                value: '$activeCount',
                color: AppTheme.success,
                icon: Icons.check_circle_rounded,
              ),
              EnterpriseMetricChip(
                label: 'Inactive',
                value: '$inactiveCount',
                color: inactiveCount > 0 ? AppTheme.warning : AppTheme.textMuted,
                icon: Icons.pause_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchUsers(reset: true),
              child: _loading && _users.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 70),
                            EnterpriseEmptyState(
                              icon: Icons.person_outline_rounded,
                              title: _search.isEmpty ? 'No users yet' : 'No users matched your search',
                              subtitle: _search.isEmpty
                                  ? 'Create the first staff account for this workspace. Roles are loaded automatically from backend access rules.'
                                  : 'Try another name, email, phone number, or role keyword.',
                              action: canManageUsers
                                  ? FilledButton.icon(
                                      onPressed: () => _openForm(),
                                      icon: const Icon(Icons.person_add_alt_1_rounded),
                                      label: const Text('Add User'),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            final userId = _readInt(user['id']);
                            final manageable =
                                _readBoolWithFallback(user['is_manageable'], true);
                            final canEdit = canManageUsers && manageable;
                            return _UserCard(
                              user: user,
                              isCurrentUser: userId != null && userId == currentUserId,
                              managementBlockReason:
                                  user['management_block_reason']?.toString(),
                              onEdit: canEdit ? () => _openForm(user) : null,
                              onDelete: canEdit && userId != null && userId != currentUserId
                                  ? () async {
                                      final ok = await _confirmDelete(context, user);
                                      if (ok == true) await _deleteUser(user);
                                    }
                                  : null,
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, Map<String, dynamic> user) {
    final name = _clean(user['name']) ?? 'this user';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isCurrentUser;
  final String? managementBlockReason;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _UserCard({
    required this.user,
    required this.isCurrentUser,
    this.managementBlockReason,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = _clean(user['name']) ?? 'Unnamed user';
    final email = _clean(user['email']) ?? 'No email';
    final phone = _clean(user['phone']) ?? 'No phone';
    final roleText = _roleLabel(user);
    final isActive = _readBool(user['is_active']);
    final accent = isActive ? AppTheme.success : AppTheme.warning;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.primarySoft,
              foregroundColor: AppTheme.primary,
              child: Text(
                _initials(name),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.navy,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        const EnterpriseStatusBadge(
                          label: 'YOU',
                          color: AppTheme.info,
                          icon: Icons.person_pin_circle_rounded,
                        ),
                      ],
                      if (managementBlockReason != null) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: managementBlockReason!,
                          child: const EnterpriseStatusBadge(
                            label: 'RESTRICTED',
                            color: AppTheme.warning,
                            icon: Icons.lock_outline_rounded,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _InfoChip(icon: Icons.email_outlined, text: email),
                      _InfoChip(icon: Icons.phone_outlined, text: phone),
                      _InfoChip(icon: Icons.verified_user_outlined, text: roleText),
                      EnterpriseStatusBadge(
                        label: isActive ? 'ACTIVE' : 'INACTIVE',
                        color: accent,
                        icon: isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (onEdit != null || onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'User actions',
                onSelected: (value) {
                  if (value == 'edit') onEdit?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (ctx) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.danger),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: AppTheme.danger)),
                        ],
                      ),
                    ),
                ],
              )
            else if (managementBlockReason != null)
              Tooltip(
                message: managementBlockReason!,
                child: const Icon(Icons.lock_outline_rounded, color: AppTheme.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString());
  return parsed != null && parsed > 0 ? parsed : null;
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'active';
}

bool _readBoolWithFallback(dynamic value, bool fallback) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == '1' || text == 'true' || text == 'yes') return true;
  if (text == '0' || text == 'false' || text == 'no') return false;
  return fallback;
}

String? _clean(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).toList();
  if (parts.isEmpty) return '?';
  return parts.map((p) => p[0].toUpperCase()).join();
}

String _roleLabel(Map<String, dynamic> user) {
  final roles = _roleTexts(user);
  if (roles.isNotEmpty) return roles.join(', ');
  return _clean(user['role_name']) ?? _clean(user['role']) ?? 'No role';
}

List<String> _roleTexts(Map<String, dynamic> user) {
  final values = <String>[];
  void add(dynamic raw) {
    if (raw == null) return;
    if (raw is Iterable) {
      for (final item in raw) {
        add(item);
      }
      return;
    }
    if (raw is Map) {
      add(raw['display_name'] ?? raw['label'] ?? raw['name'] ?? raw['title']);
      return;
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return;
    values.add(_titleCase(_stripBranchSuffix(text)));
  }

  add(user['roles']);
  add(user['role_names']);
  add(user['role_name']);
  add(user['role']);

  return values.toSet().toList();
}

bool _isMasterAdminUser(Map<String, dynamic> user) {
  if (_readBool(user['is_master_admin'])) return true;
  return _roleTexts(user).any(_isMasterRoleName);
}

bool _isMasterRoleName(String value) {
  final normalized = value
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

String _titleCase(String value) {
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
