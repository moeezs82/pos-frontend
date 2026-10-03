import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_revalidation.dart';

class SalesOrderService {
  final ApiClient _client;

  SalesOrderService({required String token})
      : _client = ApiClient(token: token);

  Future<SalesOrderListResponse> listOrders({
    int page = 1,
    int perPage = 20,
    String? status,
    int? salesmanId,
    int? customerId,
    String? fromDate,
    String? toDate,
    String? search,
  }) async {
    final query = _query({
      'page': page,
      'per_page': perPage,
      'status': status,
      'salesman_id': salesmanId,
      'customer_id': customerId,
      'from_date': fromDate,
      'to_date': toDate,
      'search': search,
    });

    final res = await _client.get('/sales-orders', query: query);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrderListResponse.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to load sales orders');
  }

  Future<PipelineSummary> getSummary({
    String? startDate,
    String? endDate,
    int? salesmanId,
  }) => summary(startDate: startDate, endDate: endDate, salesmanId: salesmanId);

  Future<PipelineSummary> summary({
    String? startDate,
    String? endDate,
    int? salesmanId,
  }) async {
    final query = _query({
      'start_date': startDate,
      'end_date': endDate,
      'salesman_id': salesmanId,
    });

    final res = await _client.get('/sales-orders/summary', query: query);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return PipelineSummary.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to load sales order summary');
  }

  Future<OrderFilterOptions> filterOptions() async {
    final res = await _client.get('/sales-orders/filter-options');
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return OrderFilterOptions.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to load filter options');
  }

  Future<SalesOrder> getOrder(int id) async {
    final res = await _client.get('/sales-orders/$id');
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to load sales order #$id');
  }

  Future<List<SalesOrderEvent>> getEvents(int id) async {
    final res = await _client.get('/sales-orders/$id/events');
    if (res['success'] == true && res['data'] is List) {
      return (res['data'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => SalesOrderEvent.fromJson(e))
          .toList();
    }
    throw Exception(res['message'] ?? 'Failed to load events for order #$id');
  }

  /// Read-only pre-conversion revalidation check.
  /// Safe to call on every screen open or refresh.
  Future<RevalidationReport> revalidate(int id) async {
    final res = await _client.get('/sales-orders/$id/revalidate');
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return RevalidationReport.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to revalidate sales order #$id');
  }

  Future<SalesOrder> createOrder(Map<String, dynamic> body) async {
    final res = await _client.post('/sales-orders', body: body);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to create sales order');
  }

  Future<SalesOrder> updateOrder(int id, Map<String, dynamic> body) async {
    final res = await _client.put('/sales-orders/$id', body: body);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to update sales order #$id');
  }

  Future<SalesOrder> submit(int id, {int? version}) async {
    final res = await _client.post(
      '/sales-orders/$id/submit',
      body: version != null ? {'version': version} : null,
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to submit sales order #$id');
  }

  Future<SalesOrder> returnToDraft(int id, {int? version}) async {
    final res = await _client.post(
      '/sales-orders/$id/return-to-draft',
      body: version != null ? {'version': version} : null,
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to return sales order #$id to draft');
  }

  Future<SalesOrder> approve(int id, {int? version}) async {
    final res = await _client.post(
      '/sales-orders/$id/approve',
      body: version != null ? {'version': version} : null,
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to approve sales order #$id');
  }

  Future<SalesOrder> reject(
    int id, {
    required String reason,
    int? version,
  }) async {
    final res = await _client.post(
      '/sales-orders/$id/reject',
      body: {
        'reason': reason.trim(),
        if (version != null) 'version': version,
      },
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to reject sales order #$id');
  }

  Future<SalesOrder> cancel(
    int id, {
    String? reason,
    int? version,
  }) async {
    final res = await _client.post(
      '/sales-orders/$id/cancel',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (version != null) 'version': version,
      },
    );
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to cancel sales order #$id');
  }

  Future<Map<String, dynamic>> convert(
    int id, {
    String? paymentMethod,
    double? paid,
    List<Map<String, dynamic>>? payments,
    int? version,
    String? creditLimitOverrideReason,
  }) async {
    final body = <String, dynamic>{
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paid != null) 'paid': paid,
      if (payments != null) 'payments': payments,
      if (version != null) 'version': version,
      if (creditLimitOverrideReason != null &&
          creditLimitOverrideReason.trim().isNotEmpty)
        'credit_limit_override_reason': creditLimitOverrideReason.trim(),
    };

    final res = await _client.post('/sales-orders/$id/convert', body: body);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return (res['data'] as Map).cast<String, dynamic>();
    }
    throw Exception(res['message'] ?? 'Failed to convert sales order #$id');
  }

  Future<SalesOrder> reconcile(int id) async {
    final res = await _client.post('/sales-orders/$id/reconcile');
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return SalesOrder.fromJson(res['data'] as Map<String, dynamic>);
    }
    throw Exception(res['message'] ?? 'Failed to reconcile sales order #$id');
  }

  Map<String, String> _query(Map<String, dynamic> values) {
    final out = <String, String>{};
    for (final entry in values.entries) {
      if (entry.value == null) continue;
      final value = entry.value.toString().trim();
      if (value.isEmpty || value == 'null') continue;
      out[entry.key] = value;
    }
    return out;
  }
}
