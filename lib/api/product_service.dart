import 'package:path/path.dart' as p;
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
    int? categoryId,
    int? brandId,
    int per_page = 20,
  }) async {
    final queryParams = {
      "page": page.toString(),
      "per_page": per_page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
      if (vendorId != null) "vendor_id": vendorId.toString(),
      if (categoryId != null) "category_id": categoryId.toString(),
      if (brandId != null) "brand_id": brandId.toString(),
    };
    return await _client.get("/products", query: queryParams);
  }

  /// Converts a product payload map to multipart-friendly string fields.
  /// Booleans become '1'/'0'. Nulls are kept as null (omitted by the client).
  /// Collections (List/Map) are skipped — multipart can't encode them.
  Map<String, String?> _toFields(Map<String, dynamic> product) {
    final fields = <String, String?>{};
    for (final entry in product.entries) {
      final v = entry.value;
      if (v == null) {
        fields[entry.key] = null;
      } else if (v is bool) {
        fields[entry.key] = v ? '1' : '0';
      } else if (v is List || v is Map) {
        // Skip nested collections — the API doesn't need them via multipart.
      } else {
        fields[entry.key] = v.toString();
      }
    }
    return fields;
  }

  /// Create a new product.
  /// Pass [imagePath] to attach an image file (jpg/png/webp).
  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> product, {
    String? imagePath,
  }) async {
    if (imagePath == null) {
      final res = await _client.post("/products", body: product);
      return res["data"] ?? res;
    }
    final res = await _client.multipartWithFields(
      'POST',
      '/products',
      filePath: imagePath,
      filename: p.basename(imagePath),
      fields: _toFields(product),
    );
    return res["data"] ?? res;
  }

  /// Update existing product.
  /// Pass [imagePath] to replace the image, or [removeImage]=true to clear it.
  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> product, {
    String? imagePath,
    bool removeImage = false,
  }) async {
    if (imagePath == null && !removeImage) {
      return await _client.put("/products/$id", body: product);
    }
    final fields = _toFields(product);
    if (removeImage) fields['remove_image'] = '1';
    final res = await _client.multipartWithFields(
      'PUT',
      '/products/$id',
      filePath: imagePath,
      filename: imagePath != null ? p.basename(imagePath) : null,
      fields: fields,
    );
    return res["data"] ?? res;
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

  /// Load one complete product record for edit/print actions from management UI.
  Future<Map<String, dynamic>> getProduct(int id) async {
    final res = await _client.get("/products/$id");
    final data = res["data"];
    if (data is Map) {
      final product = data["product"];
      if (product is Map) return Map<String, dynamic>.from(product);
      return Map<String, dynamic>.from(data);
    }
    throw Exception('Product not found');
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

  // ── Identifier generation ─────────────────────────────────────────────────
  //
  // Both methods call the backend rather than generating locally, which
  // guarantees uniqueness within the caller's branch at the moment of
  // generation.  The backend loops until a unique value is found, so the
  // result is always safe to submit as-is (barring a race between generation
  // and the final save, which the backend validates again on write).

  /// Generates a unique SKU for a simple product in the caller's branch.
  ///
  /// [productName] is used to build a human-readable prefix (e.g. "T-Shirt"
  /// → "TSH-…").  An empty name falls back to the "SKU" prefix on the backend.
  Future<String> generateSKU({required String productName}) async {
    final res = await _client.post('/products/generate-sku', body: {
      'group_name': productName, // backend reuses the group_name field
      'size': '',
      'color': '',
    });
    final data = res['data'];
    if (data is Map) return (data['sku'] ?? '').toString();
    return '';
  }

  /// Generates a unique 13-digit EAN-style barcode in the caller's branch.
  Future<String> generateBarcode() async {
    final res = await _client.post('/products/generate-barcode', body: {});
    final data = res['data'];
    if (data is Map) return (data['barcode'] ?? '').toString();
    return '';
  }
}
