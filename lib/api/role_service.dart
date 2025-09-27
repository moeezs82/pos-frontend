import 'package:enterprise_pos/api/core/api_client.dart';

class RolesService {
  final ApiClient _client;
  RolesService({required String token}) : _client = ApiClient(token: token);

  /// List roles with pagination + optional search
  Future<Map<String, dynamic>> getRoles({
    int page = 1,
    int perPage = 50,
    String? search,
  }) async {
    final query = {
      "page": page.toString(),
      "per_page": perPage.toString(),
      if (search != null && search.isNotEmpty) "search": search,
    };

    final res = await _client.get("/roles", query: query);
    if (res["success"] == true) return res; // keep full response for pagination
    throw Exception(res["message"] ?? "Failed to load roles");
  }

  /// Get single role
  Future<Map<String, dynamic>> getRole(int id) async {
    final res = await _client.get("/roles/$id");
    if (res["success"] == true) return res["data"];
    throw Exception(res["message"] ?? "Failed to fetch role");
  }

  /// Create role (attach permissions by names)
  Future<Map<String, dynamic>> createRole({
    required String name,
    List<String>? permissions,
  }) async {
    final res = await _client.post("/roles", body: {
      "name": name,
      if (permissions != null) "permissions": permissions,
    });
    if (res["success"] == true) return res["data"];
    throw Exception(res["message"] ?? "Failed to create role");
  }

  /// Update role (and optionally resync permissions)
  Future<void> updateRole(
    int id, {
    required String name,
    List<String>? permissions,
  }) async {
    final res = await _client.put("/roles/$id", body: {
      "id": id,
      "name": name,
      if (permissions != null) "permissions": permissions,
    });
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to update role");
    }
  }

  /// Delete role
  Future<void> deleteRole(int id) async {
    final res = await _client.delete("/roles/$id");
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to delete role");
    }
  }

  /// All/filtered permissions (for role form)
  Future<Map<String, dynamic>> availablePermissions({
    String guardName = 'web',
    String? search,
    bool all = true,
    int perPage = 200,
  }) async {
    final query = {
      "guard_name": guardName,
      if (search != null && search.isNotEmpty) "search": search,
      if (all) "all": "1",
      "per_page": perPage.toString(),
    };

    final res = await _client.get("/roles/permissions", query: query);
    if (res["success"] == true) return res; // may be list or paginated in res["data"]
    throw Exception(res["message"] ?? "Failed to load permissions");
  }

  /// Sync permissions (names) to a role
  Future<void> syncPermissions(int roleId, List<String> permissions) async {
    final res = await _client.post("/roles/$roleId/permissions", body: {
      "permissions": permissions,
    });
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to sync permissions");
    }
  }
}
