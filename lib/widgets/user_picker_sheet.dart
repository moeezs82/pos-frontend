import 'dart:async';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/forms/user_form_screen.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:flutter/material.dart';

class UserPickerSheet extends StatefulWidget {
  final String token;
  final String? branchId;
  final String? role;
  final String title;
  final String searchHint;
  final bool allowQuickAdd;

  const UserPickerSheet({
    super.key,
    required this.token,
    this.branchId,
    this.role,
    this.title = 'Select User',
    this.searchHint = 'Search user by name, email, phone…',
    this.allowQuickAdd = true,
  });

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
  bool _loading = false; // only true blocking case: zero cache on first ever open
  bool _silentRefreshing = false;
  String _search = "";

  String get _cacheKey => UserPickCache.keyFor(branchId: widget.branchId, role: widget.role);

  @override
  void initState() {
    super.initState();
    _userService = UsersService(token: widget.token);

    // Cache-first: instantly show whatever's cached for this branch+role
    // bucket (could be warmed by a prefetch on sale-screen open), then
    // always silently re-check per product decision.
    final cached = UserPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      _users = cached.items;
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
    } else {
      _loading = true;
    }
    _fetchUsers(page: 1, silent: cached != null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({int page = 1, bool silent = false}) async {
    if (silent) {
      setState(() => _silentRefreshing = true);
    } else {
      setState(() => _loading = true);
    }
    try {
      final entry = _search.isEmpty
          // Unfiltered fetch — safe to store in the shared bucket that
          // other screens/autocomplete fields read via peek().
          ? await UserPickCache.cache.refresh(
              _cacheKey,
              () => UserPickCache.fetchPage(
                _userService,
                page: page,
                search: _search,
                branchId: widget.branchId,
                role: widget.role,
              ),
              requestKey: '$_cacheKey::$_search::$page',
            )
          // Filtered (search) fetch — must not overwrite the shared
          // bucket, or every other salesman/delivery field would start
          // showing only this search's results. Apply locally only.
          : await UserPickCache.fetchPage(
              _userService,
              page: page,
              search: _search,
              branchId: widget.branchId,
              role: widget.role,
            );

      if (!mounted) return;
      setState(() {
        _users = entry.items;
        _page = entry.currentPage;
        _lastPage = entry.lastPage;
      });
    } catch (e) {
      // Only surface an error if we have nothing at all to show — a failed
      // silent refresh with existing cached data just stays quiet.
      if (mounted && _users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _silentRefreshing = false;
      });
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
      UserPickCache.cache.insertInto(
        _cacheKey,
        created,
        matchesExisting: (u) => u['id']?.toString() == created['id']?.toString(),
      );
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  void _onSearchChanged(String val) {
    final query = val.trim();

    final cached = UserPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      final q = query.toLowerCase();
      final filtered = q.isEmpty
          ? cached.items
          : cached.items.where((u) {
              final name = (u['name'] ?? '').toString().toLowerCase();
              final phone = (u['phone'] ?? '').toString().toLowerCase();
              final email = (u['email'] ?? '').toString().toLowerCase();
              return name.contains(q) || phone.contains(q) || email.contains(q);
            }).toList();
      setState(() => _users = filtered);
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _search = query);
      _fetchUsers(page: 1, silent: cached != null);
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
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

            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: widget.searchHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_silentRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
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
                      title: Text(
                        widget.role == 'delivery' ? "No Delivery Boy" : "No User (Walk-in)",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => Navigator.pop(context, null),
                    ),
                  ),
                ),
                if (widget.allowQuickAdd) ...[
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
              ],
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: (_loading && _users.isEmpty)
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
                              final balance = _toDouble(u['balance']);
                              final isActive = (u['is_active'] == true) ||
                                  (u['is_active'] == 1);

                              // roles could be ["admin", ...] or [{"name": "admin"}, ...]
                              final roles = ((u['roles'] as List?) ?? [])
                                  .map((e) {
                                    if (e is String) return e;
                                    if (e is Map) {
                                      return (e['display_name'] ?? e['label'] ?? e['name'] ?? '').toString();
                                    }
                                    return '';
                                  })
                                  .map(_stripBranchSuffix)
                                  .where((s) => s.isNotEmpty && !_isMasterRoleName(s))
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
                                              if (widget.role == 'delivery')
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 8),
                                                  child: Text(
                                                    'Balance: ${balance.toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      color: balance > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
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


bool _isMasterAdminUser(Map<String, dynamic> user) {
  if (_readBool(user['is_master_admin'])) return true;
  final roles = ((user['roles'] as List?) ?? [])
      .map((e) {
        if (e is String) return e;
        if (e is Map) return (e['display_name'] ?? e['label'] ?? e['name'] ?? '').toString();
        return '';
      })
      .map(_stripBranchSuffix)
      .toList();
  return roles.any(_isMasterRoleName);
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
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
