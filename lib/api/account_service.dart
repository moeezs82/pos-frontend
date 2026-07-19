import 'package:enterprise_pos/api/core/api_client.dart';

class AccountService {
  final ApiClient _client;
  AccountService({required String token}) : _client = ApiClient(token: token);

  /// GET /account-types  -> [{id, name, code}]
  Future<List<Map<String, dynamic>>> getAccountTypes() async {
    final res = await _client.get("/accounts/types");
    if (res["success"] == true) {
      final list = (res["data"] as List?) ?? const [];
      return list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// GET /accounts?is_active=1&type_code=EXPENSE&q=bank&per_page=25&page=1
  ///
  /// Returns:
  /// {
  ///   success: true,
  ///   data: {
  ///     items: [{id, code, name, type, is_active}, ...],  // paginated shape
  ///     pagination: { total, per_page, current_page, last_page }
  ///   }
  /// }
  /// OR (non-paginated):
  /// {
  ///   success: true,
  ///   data: [{id, code, name, type, is_active}, ...]
  /// }
  Future<Map<String, dynamic>> getAccounts({
    bool? isActive,
    String? typeCode,
    String? q,
    int? perPage,
    int page = 1,
  }) async {
    final query = <String, String>{
      if (isActive != null) "is_active": isActive ? "1" : "0",
      if (typeCode != null && typeCode.isNotEmpty) "type_code": typeCode,
      if (q != null && q.isNotEmpty) "q": q,
      if (perPage != null) "per_page": perPage.toString(),
      "page": page.toString(),
    };

    final res = await _client.get("/accounts", query: query);
    if (res["success"] == true) {
      final data = res["data"];
      if (data is List) {
        return {
          "items": List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e))),
          "pagination": {
            "total": data.length,
            "per_page": data.length,
            "current_page": 1,
            "last_page": 1,
          }
        };
      } else if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    }
    throw Exception(res["message"] ?? "Failed to load accounts");
  }

  /// GET /accounts/expense-options
  ///
  /// Operational, read-only list of EXPENSE accounts an authorized user may
  /// pick as a manual "Other Expense" posting target. The backend already
  /// applies active + EXPENSE + non-system filtering, so no client-side
  /// account-type filtering is needed.
  ///
  /// Returns: [{id, code, name, type, is_active}, ...]
  /// Throws on any non-success envelope (401/403/422/network) so the caller can
  /// distinguish "empty" from "failed" — never silently returns [].
  Future<List<Map<String, dynamic>>> getExpenseOptions() async {
    final res = await _client.get("/accounts/expense-options");
    if (res["success"] == true) {
      final data = res["data"];
      final list = data is Map ? (data["items"] as List? ?? const []) : const [];
      return list
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(res["message"] ?? "Failed to load expense accounts");
  }

  /// POST /accounts  (optional CRUD)
  Future<Map<String, dynamic>> createAccount({
    required String code,
    required String name,
    required int accountTypeId,
    bool isActive = true,
  }) async {
    final res = await _client.post("/accounts", body: {
      "code": code,
      "name": name,
      "account_type_id": accountTypeId.toString(),
      "is_active": isActive ? "1" : "0",
    });
    if (res["success"] == true) return Map<String, dynamic>.from(res["data"]);
    throw Exception(res["message"] ?? "Failed to create account");
  }

  /// PUT /accounts/{id} (optional CRUD)
  Future<Map<String, dynamic>> updateAccount({
    required String id,
    String? code,
    String? name,
    int? accountTypeId,
    bool? isActive,
  }) async {
    final body = <String, String>{
      if (code != null) "code": code,
      if (name != null) "name": name,
      if (accountTypeId != null) "account_type_id": accountTypeId.toString(),
      if (isActive != null) "is_active": isActive ? "1" : "0",
    };
    final res = await _client.put("/accounts/$id", body: body);
    if (res["success"] == true) return Map<String, dynamic>.from(res["data"]);
    throw Exception(res["message"] ?? "Failed to update account");
  }

  /// PUT /accounts/{id}/activate or /deactivate (optional)
  Future<void> setActive({required String id, required bool active}) async {
    final path = active ? "/accounts/$id/activate" : "/accounts/$id/deactivate";
    final res = await _client.put(path, body: {});
    if (res["success"] == true) return;
    throw Exception(res["message"] ?? "Failed to change active state");
  }

  Future<List<Map<String, dynamic>>> getPaymentMappings({required int branchId}) async {
    final res = await _client.get(
      "/accounts/payment-mappings",
      query: {"branch_id": branchId.toString()},
    );
    if (res["success"] == true) {
      final data = res["data"] as Map? ?? const {};
      final rows = data["mappings"] as List? ?? const [];
      return rows
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception(res["message"] ?? "Failed to load payment account mappings");
  }

  Future<Map<String, dynamic>> updatePaymentMapping({
    required int branchId,
    required String method,
    required int accountId,
  }) async {
    final res = await _client.put(
      "/accounts/payment-mappings/$branchId/$method",
      body: {"account_id": accountId},
    );
    if (res["success"] == true) {
      return Map<String, dynamic>.from(res["data"] as Map);
    }
    throw Exception(res["message"] ?? "Failed to update payment account mapping");
  }
}
