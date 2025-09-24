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
    required int branchId,
    int? customerId,
    int? vendorId,
    List<Map<String, dynamic>> items = const [],
    List<Map<String, dynamic>> payments = const [],
    double discount = 0.0,
    double tax = 0.0,
  }) async {
    final Map<String, String> body = {
      "branch_id": branchId.toString(),
      "discount": discount.toString(),
      "tax": tax.toString(),
      if (customerId != null) "customer_id": customerId.toString(),
      if (vendorId != null) "vendor_id": vendorId.toString(),
    };

    // items[i][...]
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      body["items[$i][product_id]"] = it["product_id"].toString();
      body["items[$i][quantity]"] = it["quantity"].toString();
      body["items[$i][price]"] = it["price"].toString();
    }

    // payments[j][...]
    for (int j = 0; j < payments.length; j++) {
      final p = payments[j];
      body["payments[$j][amount]"] = p["amount"].toString();
      body["payments[$j][method]"] = p["method"].toString();
    }

    // POST /sales via ApiClient (form-encoded or JSON as your ApiClient implements)
    final res = await _client.post("/sales", body: body);
    return res;
  }
}
