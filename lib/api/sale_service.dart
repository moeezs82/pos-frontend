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
  Future<Map<String, dynamic>> createSale({
    String? branchId,
    int? customerId,
    int? vendorId,
    int? userId,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    double discount = 0.0,
    double tax = 0.0,
  }) async {
    final payload = <String, dynamic>{
      // "branch_id": branchId,
      "discount": discount,
      "tax": tax,
      if (branchId != null) "branch_id": branchId,
      if (customerId != null) "customer_id": customerId,
      if (vendorId != null) "vendor_id": vendorId,
      if (userId != null) "salesman_id": userId,
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

    // Ensure your ApiClient sends JSON (sets Content-Type: application/json)
    final res = await _client.post(
      "/sales",
      body: payload, // let ApiClient json-encode it, or do jsonEncode(payload)
    );
    return res;
  }
}
