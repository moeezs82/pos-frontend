import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/models/product_unit.dart' show QuantityRule;
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

class SaleUnitConversionService {
  static double _roundTo(double value, int scale) {
    var factor = 1.0;
    for (var i = 0; i < scale; i++) {
      factor *= 10;
    }
    return (value * factor).roundToDouble() / factor;
  }

  static double _metaNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double? _metaNullableNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String compactNumber(num value, {int scale = 4}) {
    if (QuantityRule.isWhole(value)) return value.toInt().toString();
    var text = value.toDouble().toStringAsFixed(scale);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  }

  static List<ProductPackaging> activePackagings(Map<String, dynamic> item) {
    final values = ProductPackaging.listFromJson(item['packagings'])
        .where((p) => p.id != null && p.isActive && p.baseQuantity > 0)
        .toList(growable: false);
    values.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return values;
  }

  static ProductPackaging? snapshotPackaging(Map<String, dynamic> item) {
    final id = _metaInt(item['packaging_id']);
    final factor = _metaNum(item['packaging_factor_snapshot']);
    final name = (item['packaging_name_snapshot'] ?? '').toString().trim();
    if (id == null || factor <= 0 || name.isEmpty) return null;
    return ProductPackaging(
      id: id,
      name: name,
      shortName: (item['packaging_short_name_snapshot'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : item['packaging_short_name_snapshot'].toString().trim(),
      baseQuantity: factor,
      retailPrice: _metaNullableNum(item['packaging_unit_price']),
      isActive: true,
    );
  }

  static String packagingDisplayLabel(
    ProductPackaging packaging,
    QuantityRule rule,
  ) {
    final unit =
        rule.unitName.trim().isEmpty ? 'base unit' : rule.unitName.trim();
    final short = (packaging.shortName ?? '').trim();
    final title =
        short.isEmpty || short.toLowerCase() == packaging.name.toLowerCase()
            ? packaging.name
            : '${packaging.name} ($short)';
    return '$title = ${compactNumber(packaging.baseQuantity)} $unit';
  }

  static Map<String, dynamic>? changeSellingUnitQuick({
    required BuildContext context,
    required List<Map<String, dynamic>> items,
    required int index,
    required int? packagingId,
    required bool isEditing,
    required String? customerType,
    required void Function(int) onEditDeferred,
    required double Function(Map<String, dynamic>) calculateCartLineTotal,
  }) {
    if (index < 0 || index >= items.length) return null;
    final current = Map<String, dynamic>.from(items[index]);
    final currentPackagingId = _metaInt(current['packaging_id']);
    if ((packagingId == null && currentPackagingId == null) ||
        (packagingId != null && currentPackagingId == packagingId)) {
      return null;
    }

    if (isEditing && current['sale_item_id'] != null) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!context.mounted || index < 0 || index >= items.length) return;
        onEditDeferred(index);
      });
      return null;
    }

    final rule = QuantityRule.fromProduct(current);
    final wasPackaged = current['packaging_id'] != null;
    final displayedQty = wasPackaged
        ? (_metaNullableNum(current['packaging_quantity']) ?? 0)
        : _metaNum(current['quantity']);
    final discountType = (current['discount_type'] ?? 'percentage').toString();
    final displayedDiscount = discountType == 'fixed' && wasPackaged
        ? (_metaNullableNum(current['packaging_discount_snapshot']) ??
            _metaNum(current['discount_pct']) *
                _metaNum(current['packaging_factor_snapshot']))
        : _metaNum(current['discount_pct']);

    if (packagingId == null) {
      if (!rule.allows(displayedQty)) {
        AppFeedback.warning(context, rule.message);
        return null;
      }
      final next = Map<String, dynamic>.from(current);
      next['quantity'] = _roundTo(displayedQty, 3);
      next['price'] = SalePricing.effectiveProductPrice(
        current,
        customerType: customerType,
      );
      next['discount_pct'] = displayedDiscount;
      next.remove('packaging_id');
      next.remove('packaging_name_snapshot');
      next.remove('packaging_short_name_snapshot');
      next.remove('packaging_factor_snapshot');
      next.remove('packaging_quantity');
      next.remove('packaging_unit_price');
      next.remove('packaging_discount_snapshot');
      next['total'] = calculateCartLineTotal(next);
      return next;
    }

    ProductPackaging? selected;
    for (final packaging in activePackagings(current)) {
      if (packaging.id == packagingId) {
        selected = packaging;
        break;
      }
    }
    if (selected == null) {
      AppFeedback.warning(
        context,
        'That packaging is no longer available. Refresh the product and try again.',
      );
      return null;
    }
    if (displayedQty <= 0 || !QuantityRule.isWhole(displayedQty)) {
      final unitLabel =
          rule.unitName.trim().isEmpty ? 'the base unit' : rule.unitName.trim();
      AppFeedback.warning(
        context,
        'Package quantity must be a positive whole number. Use $unitLabel for loose quantity.',
      );
      return null;
    }

    final factor = selected.baseQuantity;
    final baseQty = _roundTo(displayedQty * factor, 3);
    if (!rule.allows(baseQty)) {
      AppFeedback.warning(context, rule.message);
      return null;
    }
    final packagePrice = SalePricing.effectivePackagingPrice(
      current,
      selected,
      customerType: customerType,
    );
    var nextDiscount = displayedDiscount;
    if ((discountType == 'percentage' && nextDiscount > 100) ||
        (discountType == 'fixed' && nextDiscount > packagePrice + 0.0004)) {
      nextDiscount = 0;
      AppFeedback.info(
        context,
        'The previous discount was not valid for the selected selling unit, so it was reset to 0.',
      );
    }

    final next = Map<String, dynamic>.from(current);
    next['quantity'] = baseQty;
    next['price'] = _roundTo(packagePrice / factor, 4);
    next['discount_type'] = discountType;
    if (discountType == 'fixed') {
      next['discount_pct'] = _roundTo(nextDiscount / factor, 4);
      next['packaging_discount_snapshot'] = _roundTo(nextDiscount, 4);
    } else {
      next['discount_pct'] = nextDiscount;
      next.remove('packaging_discount_snapshot');
    }
    next['packaging_id'] = selected.id;
    next['packaging_name_snapshot'] = selected.name;
    final short = (selected.shortName ?? '').trim();
    if (short.isEmpty) {
      next.remove('packaging_short_name_snapshot');
    } else {
      next['packaging_short_name_snapshot'] = short;
    }
    next['packaging_factor_snapshot'] = factor;
    next['packaging_quantity'] = displayedQty;
    next['packaging_unit_price'] = packagePrice;
    next['total'] = calculateCartLineTotal(next);
    return next;
  }
}
