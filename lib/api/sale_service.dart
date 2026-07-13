import 'package:enterprise_pos/api/core/api_client.dart';

class SaleService {
  final ApiClient _client;

  SaleService({required String token}) : _client = ApiClient(token: token);

  /// Creates a sale. Encodes array params with bracketed keys expected by your API.
  ///
  /// [branchId] is required.
  /// [customerId] and [vendorId] are optional.
  /// items: [{product_id:int, quantity:num, price:num}]
  /// payments: [{amount:num|string, method:String}]
  ///
  /// [clientRef] and [occurredAt] back the offline-sale sync idempotency
  /// contract (handover doc §1.1/§1.3, §2.2): every sale gets a client_ref,
  /// online or offline, and occurred_at preserves the original sale time so
  /// a sale synced later still posts/numbers/reconciles as if it happened
  /// on the day it actually did. Both are optional/additive — omitting them
  /// behaves exactly as before.
  Future<Map<String, dynamic>> createSale({
    String? branchId,
    int? customerId,
    int? vendorId,
    int? userId,
    int? deliveryBoyId,
    String? saleType,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    double discount = 0.0,
    double tax = 0.0,
    Map<String, dynamic>? meta,
    String? clientRef,
    DateTime? occurredAt,
    String? registerShiftClientRef,
  }) async {
    final payload = buildSalePayload(
      customerId: customerId,
      vendorId: vendorId,
      userId: userId,
      deliveryBoyId: deliveryBoyId,
      saleType: saleType,
      items: items,
      payments: payments,
      discount: discount,
      tax: tax,
      meta: meta,
      clientRef: clientRef,
      occurredAt: occurredAt,
      registerShiftClientRef: registerShiftClientRef,
    );

    // Ensure your ApiClient sends JSON (sets Content-Type: application/json)
    final res = await _client.post(
      "/sales",
      body: payload, // let ApiClient json-encode it, or do jsonEncode(payload)
    );
    return res;
  }

  /// Posts an already-built sale payload (from [buildSalePayload]) through
  /// the exact same `POST /sales` endpoint as [createSale]. Used to submit
  /// a queued offline sale during sync (§2.3/§2.4) without a parallel
  /// "import" code path (§3).
  Future<Map<String, dynamic>> createSaleFromPayload(Map<String, dynamic> payload) {
    return _client.post("/sales", body: payload);
  }

  /// Builds the exact same payload createSale() would POST, without
  /// actually sending it. Used by the offline queue (§2.1/§2.3) so a queued
  /// sale can be synced later through this identical shape/code path — no
  /// second "import" format.
  Map<String, dynamic> buildSalePayload({
    String? branchId,
    int? customerId,
    int? vendorId,
    int? userId,
    int? deliveryBoyId,
    String? saleType,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    double discount = 0.0,
    double tax = 0.0,
    Map<String, dynamic>? meta,
    String? clientRef,
    DateTime? occurredAt,
    String? registerShiftClientRef,
  }) {
    return <String, dynamic>{
      // "branch_id": branchId,
      "discount": discount,
      "tax": tax,
      // if (branchId != null) "branch_id": branchId,
      if (customerId != null) "customer_id": customerId,
      if (vendorId != null) "vendor_id": vendorId,
      if (userId != null) "salesman_id": userId,
      if (deliveryBoyId != null) "delivery_boy_id": deliveryBoyId,
      if (saleType != null && saleType.isNotEmpty) "sale_type": saleType,
      if (meta != null) "meta": meta,
      if (clientRef != null) "client_ref": clientRef,
      if (occurredAt != null) "occurred_at": occurredAt.toIso8601String(),
      if (registerShiftClientRef != null) "register_shift_client_ref": registerShiftClientRef,
      "items": items
          .map(
            (it) => {
              "product_id": it["product_id"],
              "quantity": it["quantity"],
              "discount_pct": it["discount_pct"],
              "price": it["price"],
            },
          )
          .toList(),
      "payments": payments
          .map((p) => {"amount": p["amount"], "method": p["method"]})
          .toList(),
    };
  }
}
