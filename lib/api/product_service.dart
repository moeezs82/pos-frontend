import 'package:enterprise_pos/api/core/api_client.dart';

class ProductService {
  final ApiClient _client;

  ProductService({required String token}) : _client = ApiClient(token: token);

  /// Get all products with pagination & search
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    int? vendorId,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
      if (vendorId != null) "vendor_id": vendorId.toString(),
    };
    return await _client.get("/products", query: queryParams);
  }

  /// Create a new product
  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> product,
  ) async {
    final res = await _client.post("/products", body: product);
    // API sometimes wraps inside "data"
    return res["data"] ?? res;
  }

  /// Update existing product
  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> product,
  ) async {
    return await _client.put("/products/$id", body: product);
  }

  /// Get product by barcode
  // Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
  //   final res = await _client.get("/products/by-barcode/$barcode");
  //   return res["data"];
  // }

  Future<Map<String, dynamic>?> getProductByBarcode(
    String barcode, {
    int? vendorId,
  }) async {
    final safeBarcode = Uri.encodeComponent(barcode.trim());
    final path = vendorId != null
        ? "/products/by-barcode/$safeBarcode/$vendorId"
        : "/products/by-barcode/$safeBarcode";

    try {
      final res = await _client.get(path);
      final data = res["data"];
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      // If your ApiClient throws typed errors with status codes, you can
      // check for 404 here and return null. Otherwise, just swallow and return null.
      // Example:
      // if (e is ApiError && e.statusCode == 404) return null;
      return null;
    }
  }

  /// Delete product
  Future<void> deleteProduct(int id) async {
    await _client.delete("/products/$id");
  }
}
