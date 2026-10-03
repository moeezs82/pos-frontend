import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/screens/sales/parts/cart_product_search.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/product_stock.dart';

class SaleProductQueryService {
  static double _tp(Map m) {
    for (final k in const [
      'tp',
      'sell_price',
      'price',
      'unit_price',
      'default_price',
    ]) {
      final v = m[k];
      if (v != null) {
        final n = double.tryParse(v.toString());
        if (n != null) return n;
      }
    }
    return 0.0;
  }

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Queries products online via [ProductService] or falls back to the
  /// local offline [CatalogCacheService] SQLite replica.
  static Future<List<ProductRef>> queryProducts({
    required ProductService productService,
    required String query,
    required int? vendorId,
    required int? branchId,
  }) async {
    try {
      final res = await productService.getProducts(
        page: 1,
        search: query,
        vendorId: vendorId,
      );
      final data = res['data'];
      List list = const [];

      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map && first['products'] is List) {
          list = first['products'] as List;
        }
      }

      return list
          .map<ProductRef>((raw) {
            final m = raw as Map<String, dynamic>;
            return ProductRef(
              id: _metaInt(m['id'] ?? m['product_id']) ?? 0,
              name: (m['name'] ?? m['title'] ?? 'Unnamed').toString(),
              tp: _tp(m),
              sku: (m['sku'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['sku'].toString().trim(),
              barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['barcode'].toString().trim(),
              stock: ProductStock.quantity(m),
              raw: m,
            );
          })
          .toList(growable: false);
    } catch (_) {
      try {
        final offlineRows = await CatalogCacheService.instance.searchProducts(
          query,
          branchId: branchId,
          vendorId: vendorId,
          limit: 50,
        );
        return offlineRows.map<ProductRef>((m) {
          double tp = 0;
          for (final k in const ['price', 'tp', 'sell_price', 'unit_price']) {
            final v = m[k];
            if (v != null) {
              final n = double.tryParse(v.toString());
              if (n != null) {
                tp = n;
                break;
              }
            }
          }
          return ProductRef(
            id: _metaInt(m['id']) ?? 0,
            name: (m['name'] ?? 'Unnamed').toString(),
            tp: tp,
            sku: (m['sku'] ?? '').toString().trim().isEmpty
                ? null
                : m['sku'].toString().trim(),
            barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                ? null
                : m['barcode'].toString().trim(),
            stock: null,
            raw: m,
          );
        }).toList(growable: false);
      } catch (_) {
        return const <ProductRef>[];
      }
    }
  }

  /// Looks up product by barcode online or falls back to local SQLite cache.
  static Future<Map<String, dynamic>?> lookupByBarcode({
    required ProductService productService,
    required String barcode,
    required int? vendorId,
    required int? branchId,
  }) async {
    Map<String, dynamic>? product;
    try {
      product = await productService.getProductByBarcode(
        barcode,
        vendorId: vendorId,
      );
    } catch (_) {
      product = null;
    }
    product ??= await CatalogCacheService.instance.productByBarcode(
      barcode,
      branchId: branchId,
      vendorId: vendorId,
    );
    return product;
  }
}
