import 'package:enterprise_pos/api/core/api_client.dart';

class UsersService {
  final ApiClient _client;
  UsersService({required String token}) : _client = ApiClient(token: token);

  /// List users with pagination + optional search + optional branch filter
  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    int perPage = 20,
    String? search,
    String? branchId,
  }) async {
    final query = {
      "page": page.toString(),
      "per_page": perPage.toString(),
      if (search != null && search.isNotEmpty) "search": search,
      if (branchId != null) "branch_id": branchId.toString(),
    };

    final res = await _client.get("/users", query: query);
    if (res["success"] == true) return res; // keep full response for pagination
    throw Exception(res["message"] ?? "Failed to load users");
  }

  /// Get single user
  Future<Map<String, dynamic>> getUser(int id) async {
    final res = await _client.get("/users/$id");
    if (res["success"] == true) return res["data"];
    throw Exception(res["message"] ?? "Failed to fetch user");
  }

  /// Create user (supports roles sync on create)
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> data) async {
    final res = await _client.post("/users", body: data);
    if (res["success"] == true) return res["data"];
    throw Exception(res["message"] ?? "Failed to create user");
  }

  /// Update user (supports roles sync on update when 'roles' included)
  Future<void> updateUser(int id, Map<String, dynamic> data) async {
    final payload = {...data, "id": id};
    final res = await _client.put("/users/$id", body: payload);
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to update user");
    }
  }

  /// Delete user
  Future<void> deleteUser(int id) async {
    final res = await _client.delete("/users/$id");
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to delete user");
    }
  }

  /// Sync roles to a user
  Future<void> syncUserRoles(int id, List<String> roles) async {
    final res = await _client.post("/users/$id/roles", body: {
      "roles": roles,
    });
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to sync user roles");
    }
  }
}
