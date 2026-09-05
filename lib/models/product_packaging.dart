import 'package:enterprise_pos/models/product_unit.dart';

/// Product-specific packaging conversion layered on top of a canonical base
/// unit. Inventory is never stored in this package; [baseQuantity] says how
/// many base units one package represents.
class ProductPackaging {
  final int? id;
  final String name;
  final String? shortName;
  final double baseQuantity;
  final double? retailPrice;
  final double? wholesalePrice;
  final bool isActive;
  final int sortOrder;

  const ProductPackaging({
    this.id,
    required this.name,
    this.shortName,
    required this.baseQuantity,
    this.retailPrice,
    this.wholesalePrice,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory ProductPackaging.fromJson(Map<String, dynamic> json) {
    return ProductPackaging(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString().trim(),
      shortName: _clean(json['short_name']),
      baseQuantity: _asDouble(json['base_quantity']) ?? 0,
      retailPrice: _asDouble(json['retail_price']),
      wholesalePrice: _asDouble(json['wholesale_price']),
      isActive: ProductUnit.parseBool(json['is_active'], true),
      sortOrder: _asInt(json['sort_order']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'short_name': _clean(shortName),
        'base_quantity': baseQuantity,
        'retail_price': retailPrice,
        'wholesale_price': wholesalePrice,
        'is_active': isActive,
      };

  ProductPackaging copyWith({
    int? id,
    String? name,
    String? shortName,
    bool clearShortName = false,
    double? baseQuantity,
    double? retailPrice,
    bool clearRetailPrice = false,
    double? wholesalePrice,
    bool clearWholesalePrice = false,
    bool? isActive,
    int? sortOrder,
  }) {
    return ProductPackaging(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: clearShortName ? null : (shortName ?? this.shortName),
      baseQuantity: baseQuantity ?? this.baseQuantity,
      retailPrice: clearRetailPrice ? null : (retailPrice ?? this.retailPrice),
      wholesalePrice: clearWholesalePrice
          ? null
          : (wholesalePrice ?? this.wholesalePrice),
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  ProductPackaging copy() => copyWith();

  double effectiveRetailPrice(double baseRetailPrice) =>
      retailPrice ?? (baseRetailPrice * baseQuantity);

  double effectiveWholesalePrice(double baseWholesalePrice) =>
      wholesalePrice ?? (baseWholesalePrice * baseQuantity);

  static List<ProductPackaging> listFromJson(Object? value) {
    if (value is! List) return <ProductPackaging>[];
    return value
        .whereType<Map>()
        .map((item) => ProductPackaging.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static String? _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
