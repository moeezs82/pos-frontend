import 'package:enterprise_pos/api/core/api_client.dart';

class ReportsService {
  final ApiClient _client;
  ReportsService({required String token}) : _client = ApiClient(token: token);

  /// GET /reports/daily-summary?from=YYYY-MM-DD&to=YYYY-MM-DD&branch_id=&salesman_id=&customer_id=&page=&per_page=
  Future<Map<String, dynamic>> getDailySummary({
    String? from,
    String? to,
    int? branchId,
    int? salesmanId,
    int? customerId,
    int page = 1,
    int perPage = 30,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (branchId != null) 'branch_id': '$branchId',
      if (salesmanId != null) 'salesman_id': '$salesmanId',
      if (customerId != null) 'customer_id': '$customerId',
    };

    final res = await _client.get('/reports/sales/daily-summary', query: query);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load daily summary');
  }

  /// GET /reports/top-bottom?from=&to=&branch_id=&salesman_id=&customer_id=&category_id=&vendor_id=&sort_by=&direction=&page=&per_page=
  Future<Map<String, dynamic>> getTopBottomProducts({
    String? from,
    String? to,
    int? branchId,
    int? salesmanId,
    int? customerId,
    int? categoryId,
    int? vendorId,
    String sortBy = 'revenue', // 'revenue' | 'margin' | 'qty'
    String direction = 'desc', // 'asc' | 'desc'
    int page = 1,
    int perPage = 20,
  }) async {
    final q = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'sort_by': sortBy,
      'direction': direction,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (branchId != null) 'branch_id': '$branchId',
      if (salesmanId != null) 'salesman_id': '$salesmanId',
      if (customerId != null) 'customer_id': '$customerId',
      if (categoryId != null) 'category_id': '$categoryId',
      if (vendorId != null) 'vendor_id': '$vendorId',
    };

    final res = await _client.get('/reports/sales/top-bottom', query: q);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load top/bottom products');
  }

  Future<Map<String, dynamic>> getLedger({
    required String partyType, // 'customer' | 'vendor'
    int? partyId, // nullable now
    String? from, // 'YYYY-MM-DD'
    String? to, // 'YYYY-MM-DD'
    int page = 1,
    int perPage = 15,
    int? branchId,
  }) async {
    final q = <String, String>{
      'party_type': partyType,
      'page': '$page',
      'per_page': '$perPage',
      if (partyId != null) 'party_id': '$partyId', // only send when not null
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (branchId != null) 'branch_id': '$branchId',
    };

    final res = await _client.get('/reports/ledger', query: q);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load ledger');
  }
}
