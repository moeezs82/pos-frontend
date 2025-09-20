import 'package:enterprise_pos/api/core/api_client.dart';

class PurchaseService {
  final ApiClient _client;

  PurchaseService({required String token}) : _client = ApiClient(token: token);

  /// List purchases with pagination, filters and sorting
  /// sortBy: "date" | "total"
  Future<Map<String, dynamic>> getPurchases({
    int page = 1,
    String sortBy = "date",
    String? search,
    int? branchId,
    int? vendorId,
    int? perPage,
  }) async {
    final query = {
      "page": page.toString(),
      "sort_by": sortBy == "total" ? "total" : "date",
      if (search != null && search.isNotEmpty) "search": search,
      if (branchId != null) "branch_id": branchId.toString(),
      if (vendorId != null) "vendor_id": vendorId.toString(),
      if (perPage != null) "per_page": perPage.toString(),
    };

    final res = await _client.get("/purchases", query: query);

    if (res["success"] == true) {
      // keep full payload for pagination meta
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to load purchases");
  }

  /// Get a single purchase with relations
  Future<Map<String, dynamic>> getPurchase(int id) async {
    final res = await _client.get("/purchases/$id");
    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to fetch purchase");
  }

  /// Create a new Purchase (PO). Supports receive_now + payments
  Future<Map<String, dynamic>> createPurchase(
    Map<String, dynamic> payload,
  ) async {
    final res = await _client.post("/purchases", body: payload);
    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to create purchase");
  }

  /// Receive goods (partial allowed)
  /// payload shape:
  /// {
  ///   "reference": "GRN-...",
  ///   "items": [{"product_id": 10, "receive_qty": 3}, ...]
  /// }
  Future<Map<String, dynamic>> receive(
    int purchaseId,
    Map<String, dynamic> payload,
  ) async {
    final res = await _client.post(
      "/purchases/$purchaseId/receive",
      body: payload,
    );
    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to receive items");
  }

  /// Add a payment to a purchase
  /// payload: {"method":"cash","amount":300.0,"tx_ref":"...", "paid_at":"YYYY-MM-DD HH:mm:ss"}
  Future<Map<String, dynamic>> addPayment(
    int purchaseId,
    Map<String, dynamic> payload,
  ) async {
    final res = await _client.post(
      "/purchases/$purchaseId/payments",
      body: payload,
    );
    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to add payment");
  }

  /// Cancel a purchase (only allowed if nothing received)
  Future<void> cancel(int purchaseId) async {
    final res = await _client.post("/purchases/$purchaseId/cancel");
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Failed to cancel purchase");
    }
  }
}
