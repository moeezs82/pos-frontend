import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The product-browser filters a cashier last applied on a screen.
class ProductPanelFilters {
  final int? categoryId;
  final int? brandId;
  final int? vendorId;
  final String? stockStatus;
  final String? sortKey;
  final bool expanded;

  const ProductPanelFilters({
    this.categoryId,
    this.brandId,
    this.vendorId,
    this.stockStatus,
    this.sortKey,
    this.expanded = false,
  });

  /// True when at least one filter or sort is set (the open/closed state of
  /// the filter drawer alone is not a filter).
  bool get hasFilters =>
      categoryId != null ||
      brandId != null ||
      vendorId != null ||
      stockStatus != null ||
      sortKey != null;
}

/// Remembers [ProductPanelFilters] on this device for 24 hours so leaving the
/// sale / purchase screen and coming back does not make the cashier re-apply
/// them. Purely a front-end convenience: it only stores which filter was
/// chosen, never products, and a stale or corrupt entry is silently dropped.
///
/// Keyed per screen ([scope], e.g. `sale` / `purchase`) and per branch because
/// category, brand and vendor ids belong to one branch.
class ProductPanelFilterStore {
  ProductPanelFilterStore._();

  static const Duration ttl = Duration(hours: 24);

  static String _key(String scope, int? branchId) =>
      'product_panel_filters_v1::$scope::${branchId ?? 'none'}';

  static Future<ProductPanelFilters?> load(String scope, int? branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(scope, branchId));
      if (raw == null) return null;
      final map = jsonDecode(raw);
      if (map is! Map) {
        await prefs.remove(_key(scope, branchId));
        return null;
      }
      final savedAt =
          DateTime.fromMillisecondsSinceEpoch((map['saved_at'] as num).toInt());
      if (DateTime.now().difference(savedAt) > ttl) {
        await prefs.remove(_key(scope, branchId));
        return null;
      }
      int? asInt(dynamic v) => v is num ? v.toInt() : null;
      String? asStr(dynamic v) =>
          v is String && v.trim().isNotEmpty ? v : null;
      return ProductPanelFilters(
        categoryId: asInt(map['category_id']),
        brandId: asInt(map['brand_id']),
        vendorId: asInt(map['vendor_id']),
        stockStatus: asStr(map['stock_status']),
        sortKey: asStr(map['sort_key']),
        expanded: map['expanded'] == true,
      );
    } catch (e) {
      debugPrint('ProductPanelFilterStore.load failed: $e');
      return null;
    }
  }

  /// Saves [filters]; saving an empty selection removes the entry instead.
  static Future<void> save(
    String scope,
    int? branchId,
    ProductPanelFilters filters,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!filters.hasFilters && !filters.expanded) {
        await prefs.remove(_key(scope, branchId));
        return;
      }
      await prefs.setString(
        _key(scope, branchId),
        jsonEncode({
          'saved_at': DateTime.now().millisecondsSinceEpoch,
          'category_id': filters.categoryId,
          'brand_id': filters.brandId,
          'vendor_id': filters.vendorId,
          'stock_status': filters.stockStatus,
          'sort_key': filters.sortKey,
          'expanded': filters.expanded,
        }),
      );
    } catch (e) {
      debugPrint('ProductPanelFilterStore.save failed: $e');
    }
  }

  /// Removes everything remembered for this screen and branch.
  static Future<void> clear(String scope, int? branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(scope, branchId));
    } catch (e) {
      debugPrint('ProductPanelFilterStore.clear failed: $e');
    }
  }
}
