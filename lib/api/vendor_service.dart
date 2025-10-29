import 'package:enterprise_pos/api/core/api_client.dart';

class VendorService {
  final ApiClient _client;

  VendorService({required String token}) : _client = ApiClient(token: token);

  /// Get all vendors with pagination & optional search
  Future<Map<String, dynamic>> getVendors({
    int page = 1,
    String? search,
    bool includeBalance = false,
    int? branchId,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (includeBalance) 'include_balance': '1',
      if (branchId != null) 'branch_id': '$branchId',
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

  Future<Map<String, dynamic>> getVendorDetail({
    required int id,
    int? branchId,
  }) async {
    final params = {if (branchId != null) 'branch_id': '$branchId'};
    // GET /api/vendors/{id}?branch_id=..&invoice_limit=..&receipt_limit=..
    final res = await _client.get('/vendors/$id', query: params);
    return res; // expects { data: { vendor:{..}, ar:{..}, aging:{..}, recent:{open_invoices:[], receipts:[]} } }
  }

  Future<Map<String, dynamic>> getVendorPurchases({
    required int id,
    int page = 1,
    int perPage = 1,
    int? branchId,
  }) async {
    final params = {
      'page': '$page',
      'per_page': '$perPage',
      if (branchId != null) 'branch_id': '$branchId',
    };
    return await _client.get('/vendors/$id/purchases', query: params);
  }

  Future<Map<String, dynamic>> getVendorPayments({
    required int id,
    int page = 1,
    int perPage = 1,
    int? branchId,
  }) async {
    final params = {
      'page': '$page',
      'per_page': '$perPage',
      if (branchId != null) 'branch_id': '$branchId',
    };
    return await _client.get('/vendors/$id/payments', query: params);
  }

  Future<Map<String, dynamic>> createPayment({
    required int vendorId,
    required double amount,
    required String method,
    String? reference,
    int? branchId,
  }) async {
    final params = {
      "amount": amount,
      "method": method,
      if (reference != null && reference.isNotEmpty) "reference": reference,
      if (branchId != null) "branch_id": branchId,
    };
    return await _client.post('/vendors/$vendorId/payments', body: params);
  }



  Future<Map<String, dynamic>> getVendorLedger({
    required int id,
    int page = 1,
    int perPage = 10,
    int? branchId,
    String? from,
    String? to,
  }) async {
    final params = {
      'page': '$page',
      'per_page': '$perPage',
      if (branchId != null) 'branch_id': '$branchId',
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };
    return await _client.get('/vendors/$id/ledger', query: params);
  }
}
