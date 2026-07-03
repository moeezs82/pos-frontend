import 'package:enterprise_pos/api/core/api_client.dart';

class ProductImportReport {
  final int totalRows;
  final int created;
  final int updated;
  final int failed;
  final List<ProductImportRowError> errors;

  ProductImportReport({
    required this.totalRows,
    required this.created,
    required this.updated,
    required this.failed,
    required this.errors,
  });

  factory ProductImportReport.fromJson(Map<String, dynamic> json) {
    final rawErrors = (json['errors'] as List?) ?? const [];
    return ProductImportReport(
      totalRows: (json['total_rows'] as num?)?.toInt() ?? 0,
      created: (json['created'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      errors: rawErrors
          .whereType<Map>()
          .map((e) => ProductImportRowError.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class ProductImportRowError {
  final int row;
  final String? sku;
  final String message;

  ProductImportRowError({required this.row, required this.sku, required this.message});

  factory ProductImportRowError.fromJson(Map<String, dynamic> json) {
    return ProductImportRowError(
      row: (json['row'] as num?)?.toInt() ?? 0,
      sku: json['sku']?.toString(),
      message: (json['message'] ?? 'Unknown error').toString(),
    );
  }
}

class ProductService {
  final ApiClient _client;

  ProductService({required String token}) : _client = ApiClient(token: token);

  /// Get all products with pagination & search
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    int? vendorId,
    int per_page= 20
  }) async {
    final queryParams = {
      "page": page.toString(),
      "per_page": per_page.toString(),
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

  /// Export the current branch's product catalog as CSV or XLSX,
  /// respecting the same filters as [getProducts].
  Future<ApiDownloadResponse> exportProducts({
    String format = 'xlsx',
    String? search,
    int? vendorId,
    int? categoryId,
    int? brandId,
    bool? isActive,
  }) async {
    final query = {
      'format': format,
      if (search != null && search.isNotEmpty) 'search': search,
      if (vendorId != null) 'vendor_id': vendorId.toString(),
      if (categoryId != null) 'category_id': categoryId.toString(),
      if (brandId != null) 'brand_id': brandId.toString(),
      if (isActive != null) 'is_active': isActive ? '1' : '0',
    };
    return _client.download('/products/export', query: query);
  }

  /// Downloads the import template (CSV or XLSX) with the expected
  /// column headers and one example row.
  Future<ApiDownloadResponse> downloadImportTemplate({String format = 'xlsx'}) async {
    return _client.download('/products/import-template', query: {'format': format});
  }

  /// Uploads a CSV/XLSX file for bulk product import. Returns a per-row
  /// success/error report rather than failing the whole batch on one bad row.
  Future<ProductImportReport> importProducts({
    required String filePath,
    required String filename,
  }) async {
    final res = await _client.uploadFile(
      '/products/import',
      filePath: filePath,
      filename: filename,
      fieldName: 'file',
    );
    final data = res['data'] ?? res;
    return ProductImportReport.fromJson(Map<String, dynamic>.from(data));
  }
}
