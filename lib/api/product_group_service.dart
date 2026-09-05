import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/product_packaging.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class ProductGroupSummary {
  final int id;
  final String name;
  final String? secondaryName;
  final String? imageUrl;
  final bool isActive;
  final int variantCount;
  final double? minPrice;
  final double? maxPrice;
  final double totalStock;
  final String? createdAt;
  final String? updatedAt;

  const ProductGroupSummary({
    required this.id,
    required this.name,
    this.secondaryName,
    this.imageUrl,
    required this.isActive,
    required this.variantCount,
    this.minPrice,
    this.maxPrice,
    required this.totalStock,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductGroupSummary.fromJson(Map<String, dynamic> j) {
    return ProductGroupSummary(
      id: _i(j['id']),
      name: (j['name'] ?? '').toString(),
      secondaryName: j['secondary_name']?.toString(),
      imageUrl: j['image_url']?.toString(),
      isActive: j['is_active'] == 1 || j['is_active'] == true,
      variantCount: _i(j['variant_count']),
      minPrice: _d(j['min_price']),
      maxPrice: _d(j['max_price']),
      totalStock: _d(j['total_stock']) ?? 0.0,
      createdAt: j['created_at']?.toString(),
      updatedAt: j['updated_at']?.toString(),
    );
  }

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Per-variant row payload for create / add-variant.
class VariantInput {
  String size;
  String color;
  String secondaryName;
  String sku;
  String barcode;
  double price;
  double costPrice;
  double wholesalePrice;
  double stock;
  int reorderLevel;
  double taxRate;
  bool taxInclusive;
  double discount;
  String discountType;
  List<ProductPackaging> packagings;

  VariantInput({
    this.size = '',
    this.color = '',
    this.secondaryName = '',
    this.sku = '',
    this.barcode = '',
    this.price = 0.0,
    this.costPrice = 0.0,
    this.wholesalePrice = 0.0,
    this.stock = 0.0,
    this.reorderLevel = 0,
    this.taxRate = 0.0,
    this.taxInclusive = false,
    this.discount = 0.0,
    this.discountType = 'percentage',
    List<ProductPackaging>? packagings,
  }) : packagings = packagings?.map((p) => p.copy()).toList() ?? <ProductPackaging>[];

  Map<String, dynamic> toJson() => {
        'size': size,
        'color': color,
        if (secondaryName.trim().isNotEmpty) 'secondary_name': secondaryName.trim(),
        if (sku.isNotEmpty) 'sku': sku,
        if (barcode.isNotEmpty) 'barcode': barcode,
        'price': price,
        'cost_price': costPrice,
        'wholesale_price': wholesalePrice,
        'stock': stock,
        'reorder_level': reorderLevel,
        'tax_rate': taxRate,
        'tax_inclusive': taxInclusive,
        'discount': discount,
        'discount_type': discountType,
        'packagings': packagings.map((p) => p.toJson()).toList(),
      };
}

// ── Service ───────────────────────────────────────────────────────────────────

class ProductGroupService {
  final ApiClient _client;

  ProductGroupService({required String token})
      : _client = ApiClient(token: token);

  /// POST /api/v1/products/variable — create group + variants atomically.
  Future<Map<String, dynamic>> createVariableProduct({
    required String name,
    String secondaryName = '',
    bool isActive = true,
    int? categoryId,
    int? brandId,
    int? vendorId,
    int? unitId,
    double taxRate = 0.0,
    bool taxInclusive = false,
    String discountType = 'percentage',
    required List<VariantInput> variants,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (secondaryName.trim().isNotEmpty) 'secondary_name': secondaryName.trim(),
      'is_active': isActive,
      if (categoryId != null) 'category_id': categoryId,
      if (brandId != null) 'brand_id': brandId,
      if (vendorId != null) 'vendor_id': vendorId,
      if (unitId != null) 'unit_id': unitId,
      'tax_rate': taxRate,
      'tax_inclusive': taxInclusive,
      'discount_type': discountType,
      'variants': variants.map((v) => v.toJson()).toList(),
    };
    final res = await _client.post('/products/variable', body: body);
    return res['data'] ?? res;
  }

  /// GET /api/v1/products/groups — paginated group listing with aggregates.
  Future<Map<String, dynamic>> listGroups({
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final res = await _client.get('/products/groups', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    });
    // Response is data[0] (same envelope as products index).
    final data = res['data'];
    if (data is List && data.isNotEmpty) return Map<String, dynamic>.from(data.first as Map);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// GET /api/v1/products/groups/{id} — group detail with all variants.
  Future<Map<String, dynamic>> showGroup(int id) async {
    final res = await _client.get('/products/groups/$id');
    return Map<String, dynamic>.from(res['data'] ?? res);
  }

  /// PUT /api/v1/products/groups/{id} — update group metadata.
  /// Shared family fields (name/category/brand/unit/vendor/tax/is_active) are
  /// cascaded atomically to existing child products by the backend. For the
  /// nullable FK fields, ID 0 is the explicit "clear" value on update.
  Future<Map<String, dynamic>> updateGroup(
    int id, {
    String? name,
    String? secondaryName,
    bool? isActive,
    String? imageUrl,
    int? categoryId,
    int? brandId,
    int? unitId,
    int? vendorId,
    double? taxRate,
    bool? taxInclusive,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (secondaryName != null) 'secondary_name': secondaryName.trim(),
      if (isActive != null) 'is_active': isActive,
      if (imageUrl != null) 'image_url': imageUrl,
      if (categoryId != null) 'category_id': categoryId,
      if (brandId != null) 'brand_id': brandId,
      if (unitId != null) 'unit_id': unitId,
      if (vendorId != null) 'vendor_id': vendorId,
      if (taxRate != null) 'tax_rate': taxRate,
      if (taxInclusive != null) 'tax_inclusive': taxInclusive,
    };
    final res = await _client.put('/products/groups/$id', body: body);
    return Map<String, dynamic>.from(res['data'] ?? res);
  }

  /// POST /api/v1/products/groups/{id}/variants — add a variant to an existing group.
  Future<Map<String, dynamic>> addVariant(int groupId, VariantInput variant) async {
    final res = await _client.post('/products/groups/$groupId/variants',
        body: variant.toJson());
    return Map<String, dynamic>.from(res['data'] ?? res);
  }

  /// PUT /api/v1/products/groups/{gid}/variants/{pid} — edit variant pricing/details.
  Future<Map<String, dynamic>> updateVariant(
    int groupId,
    int productId,
    Map<String, dynamic> changes,
  ) async {
    final res = await _client.put(
        '/products/groups/$groupId/variants/$productId',
        body: changes);
    return Map<String, dynamic>.from(res['data'] ?? res);
  }

  /// DELETE /api/v1/products/groups/{gid}/variants/{pid} — remove a variant.
  Future<void> removeVariant(int groupId, int productId) async {
    await _client.delete('/products/groups/$groupId/variants/$productId');
  }

  /// GET /api/v1/products/management — unified simple+variable catalog for management UI.
  Future<Map<String, dynamic>> managementCatalog({
    int page = 1,
    int perPage = 20,
    String? search,
    String? type, // "simple", "variable", or null for all
  }) async {
    final res = await _client.get('/products/management', query: {
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
      if (type != null && type.isNotEmpty) 'type': type,
    });
    final data = res['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// POST /api/v1/products/generate-sku — generate a unique SKU for a variant.
  Future<String> generateSKU({
    required String groupName,
    String size = '',
    String color = '',
  }) async {
    final res = await _client.post('/products/generate-sku', body: {
      'group_name': groupName,
      'size': size,
      'color': color,
    });
    final data = res['data'];
    if (data is Map) return (data['sku'] ?? '').toString();
    return '';
  }

  /// POST /api/v1/products/generate-barcode — generate a unique barcode.
  Future<String> generateBarcode() async {
    final res = await _client.post('/products/generate-barcode', body: {});
    final data = res['data'];
    if (data is Map) return (data['barcode'] ?? '').toString();
    return '';
  }
}

// ── ManagementItem — represents one row in the unified management catalog ─────

class ManagementItem {
  final String type; // "simple" or "variable"
  final int? id; // product_id for simple
  final int? groupId; // group_id for variable
  final String name;
  final String? secondaryName;
  final String? sku;
  final String? barcode;
  final double? price;
  final double? costPrice;
  final String? brandName;
  final String? categoryName;
  final bool isActive;
  final int variantCount;
  final double totalStock;
  final double? minPrice;
  final double? maxPrice;

  const ManagementItem({
    required this.type,
    this.id,
    this.groupId,
    required this.name,
    this.secondaryName,
    this.sku,
    this.barcode,
    this.price,
    this.costPrice,
    this.brandName,
    this.categoryName,
    required this.isActive,
    required this.variantCount,
    required this.totalStock,
    this.minPrice,
    this.maxPrice,
  });

  factory ManagementItem.fromJson(Map<String, dynamic> j) {
    return ManagementItem(
      type: (j['type'] ?? 'simple').toString(),
      id: _iNull(j['id']),
      groupId: _iNull(j['group_id']),
      name: (j['name'] ?? '').toString(),
      secondaryName: j['secondary_name']?.toString(),
      sku: j['sku']?.toString(),
      barcode: j['barcode']?.toString(),
      price: _dNull(j['price']),
      costPrice: _dNull(j['cost_price']),
      brandName: j['brand_name']?.toString(),
      categoryName: j['category_name']?.toString(),
      isActive: j['is_active'] == 1 || j['is_active'] == true,
      variantCount: _i(j['variant_count']),
      totalStock: _d(j['total_stock']) ?? 0.0,
      minPrice: _dNull(j['min_price']),
      maxPrice: _dNull(j['max_price']),
    );
  }

  bool get isVariable => type == 'variable';

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int? _iNull(dynamic v) {
    if (v == null) return null;
    return _i(v);
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double? _dNull(dynamic v) => _d(v);
}
