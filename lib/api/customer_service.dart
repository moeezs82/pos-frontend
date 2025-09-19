import 'package:enterprise_pos/api/core/api_client.dart';

class CustomerService {
  final ApiClient _client;

  CustomerService({required String token}) : _client = ApiClient(token: token);

  /// Get all customers with pagination & optional search
  Future<Map<String, dynamic>> getCustomers({
    int page = 1,
    String? search,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
    };

    final res = await _client.get("/customers", query: queryParams);

    if (res["success"] == true) {
      // keeping full response because of pagination
      return res;
    }
    throw Exception(res["message"] ?? "Failed to load customers");
  }

  /// Get single customer by ID
  Future<Map<String, dynamic>> getCustomer(int id) async {
    final res = await _client.get("/customers/$id");

    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to fetch customer");
  }

  /// Create a new customer
  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final res = await _client.post("/customers", body: data);

    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to create customer");
  }

  /// Update existing customer
  Future<void> updateCustomer(int id, Map<String, dynamic> data) async {
    final payload = {...data, "id": id};
    final res = await _client.put("/customers/$id", body: payload);

    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to update customer");
    }
  }

  /// Delete customer
  Future<void> deleteCustomer(int id) async {
    final res = await _client.delete("/customers/$id");
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to delete customer");
    }
  }
}
