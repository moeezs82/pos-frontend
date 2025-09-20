import 'package:enterprise_pos/api/core/api_client.dart';

class VendorService {
  final ApiClient _client;

  VendorService({required String token}) : _client = ApiClient(token: token);

  /// Get all vendors with pagination & optional search
  Future<Map<String, dynamic>> getVendors({
    int page = 1,
    String? search,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
    };

    final res = await _client.get("/vendors", query: queryParams);

    if (res["success"] == true) {
      // keeping full response because of pagination
      return res;
    }
    throw Exception(res["message"] ?? "Failed to load vendors");
  }

  /// Get single vendor by ID
  Future<Map<String, dynamic>> getVendor(int id) async {
    final res = await _client.get("/vendors/$id");

    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to fetch vendor");
  }

  /// Create a new vendor
  Future<Map<String, dynamic>> createVendor(Map<String, dynamic> data) async {
    final res = await _client.post("/vendors", body: data);

    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to create vendor");
  }

  /// Update existing vendor
  Future<void> updateVendor(int id, Map<String, dynamic> data) async {
    final payload = {...data, "id": id};
    final res = await _client.put("/vendors/$id", body: payload);

    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to update vendor");
    }
  }

  /// Delete vendor
  Future<void> deleteVendor(int id) async {
    final res = await _client.delete("/vendors/$id");
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to delete vendor");
    }
  }
}
