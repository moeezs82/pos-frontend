import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_batch.dart';
import 'package:enterprise_pos/models/sales_order_revalidation.dart';

/// Sends [items] in chunks of at most [cap], aggregating per-order outcomes.
///
/// A chunk the server rejects as malformed (422, e.g. no open register shift)
/// fails every order in it with the server's message. A chunk that errors for
/// any other reason (network, 5xx) is recorded as `unknown`, never `failed`:
/// the server may have processed part of it.
Future<BatchOutcome> runBatchChunks({
  required List<BatchRef> items,
  required int cap,
  required Future<Map<String, dynamic>> Function(List<BatchRef> chunk) send,
  void Function(int doneChunks, int totalChunks)? onProgress,
}) async {
  final outcome = BatchOutcome();
  final chunks = chunkList(items, cap);
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    try {
      final res = await send(chunk);
      final data = res['data'];
      if (res['success'] == true && data is Map<String, dynamic>) {
        outcome.addResponse(data);
      } else {
        outcome.unknown.addAll(chunk.map((r) => r.id));
        outcome.unknownReason = res['message']?.toString();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 422) {
        for (final r in chunk) {
          outcome.failed.add(BatchFailure(
            id: r.id,
            orderNumber: '',
            code: 'VALIDATION_FAILED',
            message: e.message,
          ));
        }
      } else {
        outcome.unknown.addAll(chunk.map((r) => r.id));
        outcome.unknownReason = e.message;
      }
    } catch (e) {
      outcome.unknown.addAll(chunk.map((r) => r.id));
      outcome.unknownReason = e.toString().replaceFirst('Exception: ', '');
    }
    onProgress?.call(i + 1, chunks.length);
  }
  return outcome;
}

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
    String? sortBy,
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
      'sort_by': sortBy,
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

  // ── Batch operations ──────────────────────────────────────────────────────

  /// Pre-flight triage verdicts, chunked to the server cap.
  Future<List<BatchVerdict>> batchRevalidate(List<int> ids) async {
    final out = <BatchVerdict>[];
    for (final chunk in chunkList(ids, kBatchRevalidateCap)) {
      final res = await _client.post('/sales-orders/batch/revalidate', body: {
        'items': chunk.map((id) => {'id': id}).toList(),
      });
      final data = res['data'];
      if (res['success'] != true || data is! Map<String, dynamic>) {
        throw Exception(res['message'] ?? 'Failed to pre-check sales orders');
      }
      out.addAll((data['results'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BatchVerdict.fromJson));
    }
    return out;
  }

  /// Runs one bulk [action] over [items], chunked to the server cap.
  ///
  /// [paymentMode] (`credit` | `full`) is required for [BatchAction.convert]
  /// and has no default: the server refuses to guess how money changed hands.
  Future<BatchOutcome> batchAction(
    BatchAction action,
    List<BatchRef> items, {
    String? reason,
    String? paymentMode,
    String? paymentMethod,
    String? stopAt,
    void Function(int doneChunks, int totalChunks)? onProgress,
  }) {
    return runBatchChunks(
      items: items,
      cap: action.cap,
      onProgress: onProgress,
      send: (chunk) => _client.post('/sales-orders/batch/${action.path}', body: {
        'items': chunk.map((r) => r.toJson()).toList(),
        if (reason != null) 'reason': reason,
        if (paymentMode != null) 'payment_mode': paymentMode,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (stopAt != null) 'stop_at': stopAt,
      }),
    );
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
