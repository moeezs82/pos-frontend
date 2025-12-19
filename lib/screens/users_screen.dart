import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/forms/user_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
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
  bool _loading = false;
  String _search = "";
  final List<dynamic> _users = [];
  final _searchController = TextEditingController();

  late UsersService _usersService;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _usersService = UsersService(token: token);
    _fetchUsers(reset: true);
  }

  Future<void> _fetchUsers({bool reset = false}) async {
    setState(() => _loading = true);

    if (reset) {
      _users.clear();
      _page = 1;
    }

    try {
      final branchId = context.read<BranchProvider?>()?.selectedBranchId as String?;
      final data = await _usersService.getUsers(
        page: _page,
        search: _search,
        branchId: branchId,
      );

      // 👇 adjust according to your backend pagination structure
      final pageData = data['data']; // ApiResponse::success returns {'data': pagination}
      _users
        ..clear()
        ..addAll((pageData['data'] as List).cast<Map<String, dynamic>>());

      setState(() {
        _page = pageData['current_page'];
        _lastPage = pageData['last_page'];
      });
    } catch (e) {
      debugPrint("Error loading users: $e");
    }

    setState(() => _loading = false);
  }

  void _onSearch() {
    setState(() => _search = _searchController.text.trim());
    _fetchUsers(reset: true);
  }

  Future<void> _onRefresh() async {
    await _fetchUsers(reset: true);
  }

  Future<void> _deleteUser(int id) async {
    try {
      await _usersService.deleteUser(id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User deleted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete user: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Users"),
        // actions: const [Padding(padding: EdgeInsets.only(right: 8.0), child: BranchIndicator(tappable: false))],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserFormScreen()),
          );
          if (result == true) {
            _fetchUsers(reset: true);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("Add User"),
      ),

      bottomNavigationBar: _users.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: _page > 1
                        ? () {
                            setState(() => _page--);
                            _fetchUsers();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text("Previous"),
                  ),
                  Text("Page $_page / $_lastPage"),
                  ElevatedButton.icon(
                    onPressed: _page < _lastPage
                        ? () {
                            setState(() => _page++);
                            _fetchUsers();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text("Next"),
                  ),
                ],
              ),
            )
          : null,

      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search users...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _onSearch,
                  icon: const Icon(Icons.search),
                  label: const Text("Search"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Icon(Icons.person_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 12),
                              Center(child: Text("No users found", style: TextStyle(color: Colors.grey))),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final u = _users[index];
                              final name = u['name'] ?? '—';
                              final email = u['email'] ?? '—';
                              final phone = u['phone'] ?? '—';
                              final isActive = (u['is_active'] == true) || (u['is_active'] == 1);
                              final roles = ((u['roles'] as List?) ?? [])
                                  .map((e) => (e is String) ? e : (e['name'] ?? ''))
                                  .where((s) => s.toString().isNotEmpty)
                                  .join(', ');

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : "?",
                                      style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                                    ),
                                  ),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    "Phone: $phone | Email: $email\nRoles: $roles | Status: ${isActive ? 'active' : 'inactive'}",
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: SizedBox(
                                    width: 70,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        GestureDetector(
                                          child: Icon(Icons.edit, size: 20, color: theme.colorScheme.primary),
                                          onTap: () async {
                                            final result = await Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => UserFormScreen(user: u)),
                                            );
                                            if (result == true) _fetchUsers(reset: true);
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        GestureDetector(
                                          child: const Icon(Icons.delete, size: 20, color: Colors.red),
                                          onTap: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text("Delete User"),
                                                content: Text("Are you sure you want to delete '$name'?"),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _deleteUser(u['id'] as int);
                                              _fetchUsers(reset: true);
                                            }
                                          },
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
          ],
        ),
      ),
    );
  }
}
