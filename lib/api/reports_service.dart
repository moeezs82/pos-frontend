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

  // GET /reports/cashbook-daily?from=&to=&branch_id=&include_bank=&account_ids[]=&page=&per_page=
  Future<Map<String, dynamic>> getCashbookDaily({
    String? from, // 'YYYY-MM-DD'
    String? to, // 'YYYY-MM-DD'
    int? branchId,
    bool? includeBank, // default true if null (server default)
    List<int>? accountIds, // optional override for cash/bank accounts
    int? page, // optional; when null server may return full range
    int perPage = 1000,
  }) async {
    final q = <String, dynamic>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (branchId != null) 'branch_id': '$branchId',
      if (includeBank != null) 'include_bank': includeBank ? '1' : '0',
      if (page != null) 'page': '$page',
      'per_page': '$perPage',
    };

    // encode account_ids[] as repeated params
    if (accountIds != null && accountIds.isNotEmpty) {
      int i = 0;
      for (final id in accountIds) {
        q['account_ids[$i]'] = '$id';
        i++;
      }
    }

    final res = await _client.get(
      '/reports/cashbook-daily',
      query: q.map((k, v) => MapEntry(k, v.toString())),
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load cashbook report');
  }

  // GET /reports/stock-movement?from=&to=&product_id[]=&type[]=&include_value=&inventory_account_code=&page=&per_page=&order=
  Future<Map<String, dynamic>> getStockMovement({
    String? from, // 'YYYY-MM-DD'
    String? to, // 'YYYY-MM-DD'
    List<int>? productIds, // multi
    List<String>?
    types, // e.g. ['purchase','sale','return','transfer','adjustment']
    bool? includeValue, // default false
    String inventoryAccountCode = '1400',
    int page = 1,
    int perPage = 20,
    String order = 'asc', // 'asc'|'desc'
  }) async {
    final q = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'order': order,
      'inventory_account_code': inventoryAccountCode,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (includeValue != null) 'include_value': includeValue ? '1' : '0',
    };

    // encode product_id[] and type[] as repeated params
    if (productIds != null && productIds.isNotEmpty) {
      for (var i = 0; i < productIds.length; i++) {
        q['product_id[$i]'] = '${productIds[i]}';
      }
    }
    if (types != null && types.isNotEmpty) {
      for (var i = 0; i < types.length; i++) {
        q['type[$i]'] = types[i];
      }
    }

    final res = await _client.get('/reports/stock-movement', query: q);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load stock movement');
  }

  // GET /reports/pnl?from=&to=&branch_id=
  Future<Map<String, dynamic>> getProfitAndLoss({
    String? from, // 'YYYY-MM-DD'
    String? to, // 'YYYY-MM-DD'
    int? branchId,
  }) async {
    final q = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (branchId != null) 'branch_id': '$branchId',
    };

    final res = await _client.get('/reports/profit-loss', query: q);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to load P&L report');
  }
}
