import 'dart:async';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/forms/user_form_screen.dart';
import 'package:flutter/material.dart';

class UserPickerSheet extends StatefulWidget {
  final String token;
  final String? branchId;
  const UserPickerSheet({super.key, required this.token, this.branchId});

  @override
  State<UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<UserPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  late UsersService _userService;

  List<Map<String, dynamic>> _users = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";

  @override
  void initState() {
    super.initState();
    _userService = UsersService(token: widget.token);
    _fetchUsers(page: 1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final res = await _userService.getUsers(page: page, search: _search, branchId: widget.branchId);

      // ApiResponse::success => { success, data: { current_page, last_page, data: [...] } }
      final pageData = res['data'] as Map<String, dynamic>;
      final newUsers =
          (pageData['data'] as List).cast<Map<String, dynamic>>();

      setState(() {
        _users = newUsers;
        _page = pageData['current_page'] as int? ?? page;
        _lastPage = pageData['last_page'] as int? ?? page;
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

  Future<void> _quickAddUser() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const UserFormScreen(),
      ),
    );

    // If the form returns `true` just refresh; if it returns a Map, insert & return it.
    if (created == true) {
      await _fetchUsers(page: 1);
      return;
    }
    if (created is Map<String, dynamic>) {
      setState(() {
        _users.insert(0, created);
        _page = 1;
      });
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _search = val.trim());
      _fetchUsers(page: 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          children: [
            // drag handle
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Search
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: "Search user by name, email, phone…",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),

            // Always-visible actions
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.grey.shade100,
                    child: ListTile(
                      leading: const Icon(Icons.clear, color: Colors.red),
                      title: const Text(
                        "No User (Walk-in)",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => Navigator.pop(context, null),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    color: Colors.green.shade50,
                    child: ListTile(
                      leading:
                          const Icon(Icons.add_circle, color: Colors.green),
                      title: const Text(
                        "Quick Add",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: _quickAddUser,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Icon(Icons.person_outline,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                "No users found",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                          onRefresh: () => _fetchUsers(page: _page),
                          child: ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final u = _users[i];
                              final name = (u['name'] ?? '').toString();
                              final email = (u['email'] ?? '').toString();
                              final phone = (u['phone'] ?? '').toString();
                              final isActive = (u['is_active'] == true) ||
                                  (u['is_active'] == 1);

                              // roles could be ["admin", ...] or [{"name": "admin"}, ...]
                              final roles = ((u['roles'] as List?) ?? [])
                                  .map((e) => e is String
                                      ? e
                                      : ((e as Map)['name'] ?? '').toString())
                                  .where((s) => s.isNotEmpty)
                                  .toList();

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => Navigator.pop(context, u),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: theme
                                              .colorScheme.primaryContainer,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : "?",
                                            style: TextStyle(
                                              color: theme.colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name.isEmpty
                                                          ? '—'
                                                          : name,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                  _StatusPill(active: isActive),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                children: [
                                                  if (email.isNotEmpty)
                                                    _InfoRow(
                                                      icon: Icons.email_outlined,
                                                      text: email,
                                                    ),
                                                  if (phone.isNotEmpty)
                                                    _InfoRow(
                                                      icon:
                                                          Icons.phone_outlined,
                                                      text: phone,
                                                    ),
                                                ],
                                              ),
                                              if (roles.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: _RoleChips(roles),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),

            // Pager
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      _page > 1 ? () => _fetchUsers(page: _page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text("Previous"),
                ),
                const SizedBox(width: 16),
                Text("Page $_page of $_lastPage"),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _page < _lastPage
                      ? () => _fetchUsers(page: _page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text("Next"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodySmall?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;
  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = active ? Colors.green.shade50 : Colors.red.shade50;
    final fg = active ? Colors.green.shade800 : Colors.red.shade800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoleChips extends StatelessWidget {
  final List<String> roles;
  const _RoleChips(this.roles);

  @override
  Widget build(BuildContext context) {
    // show up to 4, then +N more button that opens full list bottom sheet
    final preview = roles.take(4).toList();
    final more = roles.length - preview.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...preview.map(
          (r) => Chip(
            label: Text(r, overflow: TextOverflow.ellipsis),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        if (more > 0)
          ActionChip(
            label: Text('+$more more'),
            onPressed: () => _showAllRoles(context, roles),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  void _showAllRoles(BuildContext context, List<String> roles) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              children: [
                const Icon(Icons.security),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Roles (${roles.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: roles
                      .map(
                        (r) => Chip(
                          label: Text(r, overflow: TextOverflow.ellipsis),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
