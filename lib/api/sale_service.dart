import 'package:enterprise_pos/api/core/api_client.dart';

class SaleService {
  final ApiClient _client;

  SaleService({required String token}) : _client = ApiClient(token: token);

  /// Loads the current effective posted invoice state for the audited Edit Sale flow.
  Future<Map<String, dynamic>> getSale(int saleId, {bool includeBalance = true}) {
    return _client.get(
      "/sales/$saleId",
      query: {if (includeBalance) "include_balance": "1"},
    );
  }

  /// Applies one atomic desired-state amendment to a posted sale. Existing
  /// item versions and payment documents are preserved by the backend.
  Future<Map<String, dynamic>> amendSale(
    int saleId,
    Map<String, dynamic> payload,
  ) {
    return _client.post("/sales/$saleId/amendments", body: payload);
  }

  /// Immutable amendment/revision history used by Sale Detail.
  Future<Map<String, dynamic>> getAmendments(int saleId) {
    return _client.get("/sales/$saleId/amendments");
  }

  /// Corrects a posted sale receipt without mutating it in place. The backend
  /// reverses the original receipt/journal and optionally creates a replacement
  /// receipt inside one database transaction.
  Future<Map<String, dynamic>> correctSaleReceipt(
    int saleId,
    int receiptId,
    Map<String, dynamic> payload,
  ) {
    return _client.post(
      "/sales/$saleId/receipts/$receiptId/correct",
      body: payload,
    );
  }

  /// Operational warehouse/packing summary. The backend aggregates only the
  /// current active positive sale-item quantities for the working branch.
  Future<Map<String, dynamic>> getPickingList({
    String? dateFrom,
    String? dateTo,
    int? customerId,
    int? saleSourceId,
    String? search,
    List<int>? saleIds,
  }) async {
    final query = <String, String>{
      if (dateFrom != null && dateFrom.trim().isNotEmpty) 'date_from': dateFrom.trim(),
      if (dateTo != null && dateTo.trim().isNotEmpty) 'date_to': dateTo.trim(),
      if (customerId != null) 'customer_id': '$customerId',
      if (saleSourceId != null) 'sale_source_id': '$saleSourceId',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (saleIds != null && saleIds.isNotEmpty) 'sale_ids': saleIds.join(','),
    };
    final res = await _client.get('/sales/picking-list', query: query);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    throw Exception(res['message'] ?? 'Failed to generate picking list');
  }

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
    int? saleSourceId,
    int? areaId,
    String? areaName,
    String? saleType,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    Map<String, dynamic>? refund,
    double discount = 0.0,
    double tax = 0.0,
    double delivery = 0.0,
    Map<String, dynamic>? meta,
    String? clientRef,
    DateTime? occurredAt,
    String? registerShiftClientRef,
    String? offlineInvoiceNo,
    int? originBranchId,
    String? creditLimitOverrideReason,
  }) async {
    final payload = buildSalePayload(
      customerId: customerId,
      vendorId: vendorId,
      userId: userId,
      deliveryBoyId: deliveryBoyId,
      saleSourceId: saleSourceId,
      areaId: areaId,
      areaName: areaName,
      saleType: saleType,
      items: items,
      payments: payments,
      refund: refund,
      discount: discount,
      tax: tax,
      delivery: delivery,
      meta: meta,
      clientRef: clientRef,
      occurredAt: occurredAt,
      registerShiftClientRef: registerShiftClientRef,
      offlineInvoiceNo: offlineInvoiceNo,
      originBranchId: originBranchId,
      creditLimitOverrideReason: creditLimitOverrideReason,
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
    int? saleSourceId,
    int? areaId,
    String? areaName,
    String? saleType,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    Map<String, dynamic>? refund,
    double discount = 0.0,
    double tax = 0.0,
    double delivery = 0.0,
    Map<String, dynamic>? meta,
    String? clientRef,
    DateTime? occurredAt,
    String? registerShiftClientRef,
    int? originBranchId,
    String? creditLimitOverrideReason,
    /// Customer-friendly offline receipt reference (e.g. "OFF-B1-MAIN-20260714-0001").
    /// Stored permanently on the sale for traceability. Never used as the official
    /// invoice number — that is always allocated by InvoiceSequenceService.
    String? offlineInvoiceNo,
  }) {
    return <String, dynamic>{
      // "branch_id": branchId,
      "discount": discount,
      "tax": tax,
      "delivery": delivery,
      // if (branchId != null) "branch_id": branchId,
      if (customerId != null) "customer_id": customerId,
      if (vendorId != null) "vendor_id": vendorId,
      if (userId != null) "salesman_id": userId,
      if (deliveryBoyId != null) "delivery_boy_id": deliveryBoyId,
      if (saleSourceId != null) "sale_source_id": saleSourceId,
      // Always send area_id, including null, so the backend can distinguish a
      // deliberate "No area" selection from an older client that omitted the
      // field and should inherit the customer's default area.
      "area_id": areaId,
      if (areaId != null && areaName != null && areaName.trim().isNotEmpty)
        "area_name": areaName.trim(),
      if (saleType != null && saleType.isNotEmpty) "sale_type": saleType,
      if (meta != null) "meta": meta,
      if (clientRef != null) "client_ref": clientRef,
      if (originBranchId != null) "origin_branch_id": originBranchId,
      if (creditLimitOverrideReason != null && creditLimitOverrideReason.trim().isNotEmpty)
        "credit_limit_override": {"reason": creditLimitOverrideReason.trim()},
      if (occurredAt != null) "occurred_at": occurredAt.toIso8601String(),
      if (registerShiftClientRef != null) "register_shift_client_ref": registerShiftClientRef,
      if (offlineInvoiceNo != null) "offline_invoice_no": offlineInvoiceNo,
      "items": items
          .map(
            (it) => {
              "product_id":    it["product_id"],
              "quantity":      it["quantity"],
              "price":         it["price"],
              "discount_pct":  it["discount_pct"],
              "discount_type": it["discount_type"] ?? "percentage",
            },
          )
          .toList(),
      // Preserve every payment property — not just amount/method — so a
      // KNET/card/bank reference, note, paid date and per-payment client_ref
      // survive to the backend (and offline replay).
      "payments": payments
          .map((p) => <String, dynamic>{
                "amount": p["amount"],
                "method": p["method"],
                if (p["reference"] != null &&
                    p["reference"].toString().trim().isNotEmpty)
                  "reference": p["reference"],
                if (p["note"] != null && p["note"].toString().trim().isNotEmpty)
                  "note": p["note"],
                if (p["paid_at"] != null) "paid_at": p["paid_at"],
                if (p["client_ref"] != null) "client_ref": p["client_ref"],
              })
          .toList(),
      if (refund != null) "refund": refund,
    };
  }
}
