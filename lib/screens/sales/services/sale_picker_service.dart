import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/product_stock.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';

class SalePickerService {
  /// Opens the full customer browse sheet.
  static Future<Map<String, dynamic>?> openCustomerSheet(
    BuildContext context, {
    required String token,
  }) {
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );
  }

  /// Opens the full vendor browse sheet.
  static Future<Map<String, dynamic>?> openVendorSheet(
    BuildContext context, {
    required String token,
  }) {
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorPickerSheet(token: token),
    );
  }

  /// Opens the salesman/user browse sheet.
  static Future<Map<String, dynamic>?> openUserSheet(
    BuildContext context, {
    required String token,
    required String branchId,
  }) {
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(token: token, branchId: branchId),
    );
  }

  /// Opens the delivery boy browse sheet.
  static Future<Map<String, dynamic>?> openDeliveryBoySheet(
    BuildContext context, {
    required String token,
    required String branchId,
  }) {
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(
        token: token,
        branchId: branchId,
        role: 'delivery',
        title: 'Select Delivery Boy',
        searchHint: 'Search delivery boy by name, email, phone…',
        allowQuickAdd: false,
      ),
    );
  }

  /// Opens the multi-product picker grid sheet with preselected quantities and profit metadata.
  static Future<List<Map<String, dynamic>>?> openMultiProductPicker({
    required BuildContext context,
    required String token,
    required List<Map<String, dynamic>> items,
    required int? vendorId,
    required String customerType,
    required bool isMasterAdmin,
    required bool hasActiveBranch,
  }) async {
    if (isMasterAdmin && !hasActiveBranch) {
      AppFeedback.warning(
        context,
        'Please select a working branch from Branch Control before selecting items.',
      );
      return null;
    }

    final baseRows = items
        .where((it) {
          final q = it['quantity'];
          final qty = (q is num) ? q.toDouble() : (double.tryParse(q?.toString() ?? '') ?? 0.0);
          return it['packaging_id'] == null && qty >= 0;
        })
        .toList(growable: false);

    final alreadySelectedIds = baseRows
        .map((e) => int.tryParse(e["product_id"]?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toList();

    // F2 edits the base-unit row only. A Box/Carton row for the same product
    // must never pre-fill or overwrite this picker quantity.
    final alreadySelectedQty = <int, double>{
      for (final it in baseRows)
        (int.tryParse(it["product_id"]?.toString() ?? '') ?? 0):
            (double.tryParse(it["quantity"]?.toString() ?? '') ?? 1.0),
    }..removeWhere((k, _) => k == 0);

    return ProductPickerGridSheet.openMulti(
      context,
      token: token,
      vendorId: vendorId,
      customerType: customerType,
      alreadySelectedIds: alreadySelectedIds,
      alreadySelectedQty: alreadySelectedQty,
      alreadySelectedProducts: baseRows.map((item) {
        return {
          'id': item['product_id'],
          'name': item['name'],
          'secondary_name': item['secondary_name'],
          'price': item['price'],
          'cost_price': item['cost_price'],
          'wholesale_price': item['wholesale_price'],
          SaleProfitCalculator.unitCostKey:
              item[SaleProfitCalculator.unitCostKey],
          SaleProfitCalculator.estimatedKey:
              item[SaleProfitCalculator.estimatedKey],
          SaleProfitCalculator.sourceKey:
              item[SaleProfitCalculator.sourceKey],
          ...ProductStock.toTransactionRowFields(item),
        };
      }).toList(),
    );
  }
}
