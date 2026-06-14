import 'package:enterprise_pos/api/core/api_client.dart';

class DeliveryBoyService {
  final ApiClient _client;

  DeliveryBoyService({required String token}) : _client = ApiClient(token: token);

  /// GET /delivery-boys?search=&page=&per_page=&branch_id=
  /// Returns paginated delivery users with balance and delivery_cash_summary.
  Future<Map<String, dynamic>> getDeliveryBoys({
    int page = 1,
    int perPage = 20,
    String? search,
    int? branchId,
    String role = 'delivery',
  }) async {
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'role': role,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (branchId != null) 'branch_id': '$branchId',
    };

    final res = await _client.get('/delivery-boys', query: query);
    if (res['success'] == true) return res;
    throw Exception(res['message'] ?? 'Failed to load delivery boys');
  }

  /// GET /delivery-boys/{id}/cash-summary
  Future<Map<String, dynamic>> getCashSummary({
    required int id,
    int? branchId,
  }) async {
    final query = <String, String>{
      if (branchId != null) 'branch_id': '$branchId',
    };

    final res = await _client.get('/delivery-boys/$id/cash-summary', query: query);
    if (res['success'] == true) return res;
    throw Exception(res['message'] ?? 'Failed to load delivery boy cash summary');
  }

  /// GET /delivery-boys/{id}/orders
  Future<Map<String, dynamic>> getOrders({
    required int id,
    int page = 1,
    int perPage = 10,
    int? branchId,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (branchId != null) 'branch_id': '$branchId',
    };

    final res = await _client.get('/delivery-boys/$id/orders', query: query);
    if (res['success'] == true) return res;
    throw Exception(res['message'] ?? 'Failed to load delivery boy orders');
  }

  /// GET /delivery-boys/{id}/received
  Future<Map<String, dynamic>> getReceived({
    required int id,
    int page = 1,
    int perPage = 10,
  }) async {
    final res = await _client.get(
      '/delivery-boys/$id/received',
      query: {
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    if (res['success'] == true) return res;
    throw Exception(res['message'] ?? 'Failed to load delivery boy received entries');
  }

  /// POST /delivery-boys/{id}/received
  Future<Map<String, dynamic>> createReceived({
    required int deliveryBoyId,
    required double amount,
  }) async {
    final res = await _client.post(
      '/delivery-boys/$deliveryBoyId/received',
      body: {'amount': amount},
    );
    if (res['success'] == true) return res;
    throw Exception(res['message'] ?? 'Failed to record delivery boy received amount');
  }
}
