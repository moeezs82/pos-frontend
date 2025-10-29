import 'package:enterprise_pos/api/core/api_client.dart';

class CustomerService {
  final ApiClient _client;

  CustomerService({required String token}) : _client = ApiClient(token: token);

  /// Get all customers with pagination & optional search
  Future<Map<String, dynamic>> getCustomers({
    int page = 1,
    String? search,
    int? branchId,
    bool? includeBalance,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
      if (branchId != null) 'branch_id': branchId.toString(),
      if (includeBalance == true) 'include_balance': '1',
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

  Future<Map<String, dynamic>> getCustomerDetail({
    required int id,
    int? branchId,
  }) async {
    final params = {if (branchId != null) 'branch_id': '$branchId'};
    // GET /api/customers/{id}?branch_id=..&invoice_limit=..&receipt_limit=..
    final res = await _client.get('/customers/$id', query: params);
    return res; // expects { data: { customer:{..}, ar:{..}, aging:{..}, recent:{open_invoices:[], receipts:[]} } }
  }

  Future<Map<String, dynamic>> getCustomerSales({
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
    return await _client.get('/customers/$id/sales', query: params);
  }

  Future<Map<String, dynamic>> getCustomerReceipts({
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
    return await _client.get('/customers/$id/receipts', query: params);
  }
  Future<Map<String, dynamic>> createReceipt({
    required int customerId,
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
    return await _client.post('/customers/$customerId/receipts', body: params);
  }

  Future<Map<String, dynamic>> getCustomerLedger({
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
    return await _client.get('/customers/$id/ledger', query: params);
  }
}
