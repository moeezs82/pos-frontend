import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/models/product_unit.dart' show QuantityRule;
import 'package:enterprise_pos/screens/sales/parts/sale_return_source_dialog.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

class SaleReturnService {
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

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Future<Map<String, String>?> askReturnSource({
    required BuildContext context,
    String initialInvoice = '',
    String initialReason = '',
    String? fallbackInitialInvoice,
  }) {
    final seededInvoice = initialInvoice.trim().isNotEmpty
        ? initialInvoice.trim()
        : (fallbackInitialInvoice ?? '').trim();
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReturnSourceDialog(
        initialInvoice: seededInvoice,
        initialReason: initialReason,
      ),
    );
  }

  static Future<Map<String, dynamic>?> chooseReturnSourceItem({
    required BuildContext context,
    required List<dynamic> candidates,
  }) async {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1 && candidates.first is Map) {
      return Map<String, dynamic>.from(candidates.first as Map);
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select original sale line'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final row = Map<String, dynamic>.from(candidates[index] as Map);
              return ListTile(
                title: Text((row['product_name'] ?? 'Product').toString()),
                subtitle: Text(
                  'Sold ${row['sold_qty']} • Returned ${row['returned_qty']} • Returnable ${row['returnable_qty']}',
                ),
                trailing: Text(
                  AppCurrency.format(_metaNum(row['return_credit'])),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
      ),
    );
  }

  static Future<bool> linkReturnForRow({
    required BuildContext context,
    required SaleService saleService,
    required List<Map<String, dynamic>> items,
    required int index,
    required double quantity,
    required double? packagingQuantity,
    required String? initialReturnInvoice,
    required void Function(Map<String, dynamic>?) onCustomerSelected,
    required void Function(Map<String, dynamic> updatedRow) onRowUpdated,
    required VoidCallback onResetPayments,
    required void Function(Map<String, dynamic> restoredRow) onRowRestore,
  }) async {
    if (index < 0 || index >= items.length || quantity <= 0) return false;
    final current = Map<String, dynamic>.from(items[index]);
    final productId = _metaInt(current['product_id']);
    if (productId == null || productId <= 0) return false;

    final wasLinked = current['original_sale_item_id'] != null;
    final requestedPackagingId = _metaInt(current['packaging_id']);
    double? requestedPackagingQuantity;
    if (requestedPackagingId != null) {
      final factor = _metaNum(current['packaging_factor_snapshot']);
      if (factor <= 0) {
        AppFeedback.warning(
          context,
          'This package conversion is invalid. Re-select the selling unit before returning it.',
        );
        return false;
      }
      requestedPackagingQuantity = packagingQuantity;
      if (requestedPackagingQuantity == null ||
          requestedPackagingQuantity <= 0 ||
          !QuantityRule.isWhole(requestedPackagingQuantity)) {
        AppFeedback.warning(
          context,
          'Package return quantity must be a positive whole package count.',
        );
        return false;
      }
      requestedPackagingQuantity = _roundTo(requestedPackagingQuantity, 4);
    }
    String invoice = (current['return_source_invoice'] ?? '').toString().trim();
    String reason = (current['return_reason'] ?? '').toString().trim();
    if (!wasLinked) {
      String defaultInvoice = (initialReturnInvoice ?? '').trim();
      for (final row in items) {
        if (row['original_sale_item_id'] != null) {
          defaultInvoice = (row['return_source_invoice'] ?? '').toString();
          break;
        }
      }
      final request = await askReturnSource(
        context: context,
        initialInvoice: defaultInvoice,
        fallbackInitialInvoice: initialReturnInvoice,
      );
      if (!context.mounted) return false;
      if (request == null) {
        return false;
      }
      invoice = request['invoice']!;
      reason = request['reason']!;
    }

    for (int i = 0; i < items.length; i++) {
      if (i == index) continue;
      final otherInvoice =
          (items[i]['return_source_invoice'] ?? '').toString().trim();
      if (items[i]['original_sale_item_id'] != null &&
          otherInvoice.isNotEmpty &&
          otherInvoice != invoice) {
        AppFeedback.warning(
          context,
          'All returned items in one transaction must come from the same original invoice ($otherInvoice).',
        );
        return false;
      }
    }

    try {
      final data = await saleService.getReturnSource(
        invoice: invoice,
        productId: productId,
        quantity: quantity,
        packagingId: requestedPackagingId,
        packagingQuantity: requestedPackagingQuantity,
      );
      if (!context.mounted) return false;
      final candidates = data['items'] is List
          ? data['items'] as List
          : const <dynamic>[];
      Map<String, dynamic>? picked;
      if (wasLinked) {
        final existingId = _metaInt(current['original_sale_item_id']);
        for (final raw in candidates) {
          if (raw is Map && _metaInt(raw['sale_item_id']) == existingId) {
            picked = Map<String, dynamic>.from(raw);
            break;
          }
        }
      }
      picked ??= await chooseReturnSourceItem(
        context: context,
        candidates: candidates,
      );
      if (!context.mounted || picked == null) {
        return false;
      }
      final sale = data['sale'] is Map
          ? Map<String, dynamic>.from(data['sale'] as Map)
          : <String, dynamic>{};
      final sourceSaleId = _metaInt(sale['id']);
      if (sourceSaleId == null) {
        throw Exception('Original sale could not be resolved.');
      }

      final customer = sale['customer'];
      if (customer is Map) {
        onCustomerSelected(Map<String, dynamic>.from(customer));
      } else {
        onCustomerSelected(null);
      }

      final authoritativeQty = _metaNum(picked['quantity']);
      if (authoritativeQty <= 0) {
        throw Exception(
          'The original invoice returned an invalid return quantity.',
        );
      }
      final updated = Map<String, dynamic>.from(current)
        ..['original_sale_id'] = sourceSaleId
        ..['original_sale_item_id'] = _metaInt(picked['sale_item_id'])
        ..['return_source_invoice'] = (sale['invoice_no'] ?? invoice).toString()
        ..['return_reason'] = reason
        ..['returnable_quantity'] = _metaNum(picked['returnable_qty'])
        ..['return_original_outstanding'] = _metaNum(sale['outstanding'])
        ..['return_credit'] = _metaNum(picked['return_credit'])
        ..['return_merchandise_subtotal'] =
            _metaNum(picked['merchandise_subtotal'])
        ..['return_invoice_discount'] =
            _metaNum(picked['invoice_discount_allocated'])
        ..['return_tax'] = _metaNum(picked['tax_allocated'])
        ..['return_linked_quantity'] = authoritativeQty
        ..['price'] = _metaNum(picked['original_price'])
        ..['discount_pct'] = _metaNum(picked['line_discount'])
        ..['extra_discount'] = _metaNum(picked['extra_discount_allocated'])
        ..['discount_type'] =
            (picked['discount_type'] ?? 'percentage').toString()
        ..['quantity'] = -authoritativeQty
        ..['total'] = -_metaNum(picked['return_credit']).abs();

      if (requestedPackagingId != null) {
        final returnPackagingId = _metaInt(picked['return_packaging_id']);
        final returnFactor =
            _metaNum(picked['return_packaging_factor_snapshot']);
        final packageReturnQty =
            _metaNum(picked['return_packaging_quantity']);
        if (returnPackagingId != requestedPackagingId ||
            returnFactor <= 0 ||
            packageReturnQty <= 0 ||
            !QuantityRule.isWhole(packageReturnQty)) {
          throw Exception(
            'The selected return package changed or is no longer valid. Refresh the product and choose the package again.',
          );
        }
        final expectedBaseQty = _roundTo(packageReturnQty * returnFactor, 3);
        if ((expectedBaseQty - authoritativeQty).abs() > 0.0005) {
          throw Exception(
            'The selected return package no longer matches the requested base quantity. Refresh the product and try again.',
          );
        }
        final returnName =
            (picked['return_packaging_name_snapshot'] ?? '').toString().trim();
        if (returnName.isEmpty) {
          throw Exception('The selected return package snapshot is incomplete.');
        }

        updated['packaging_id'] = returnPackagingId;
        updated['packaging_name_snapshot'] = returnName;
        final returnShort =
            (picked['return_packaging_short_name_snapshot'] ?? '')
                .toString()
                .trim();
        if (returnShort.isEmpty) {
          updated.remove('packaging_short_name_snapshot');
        } else {
          updated['packaging_short_name_snapshot'] = returnShort;
        }
        updated['packaging_factor_snapshot'] = returnFactor;
        updated['packaging_quantity'] = -packageReturnQty;

        final originalBasePrice = _metaNum(picked['original_price']);
        updated['packaging_unit_price'] =
            _roundTo(originalBasePrice * returnFactor, 4);
        final returnDiscountType =
            (picked['discount_type'] ?? 'percentage').toString().toLowerCase();
        if (returnDiscountType == 'fixed') {
          updated['packaging_discount_snapshot'] = _roundTo(
            _metaNum(picked['line_discount']) * returnFactor,
            4,
          );
        } else {
          updated.remove('packaging_discount_snapshot');
        }
      }

      onRowUpdated(updated);
      onResetPayments();
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final message = e is ApiException
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
      AppFeedback.error(context, message);

      if (index >= items.length) return false;
      if (wasLinked) {
        final previous = _metaNum(current['return_linked_quantity']);
        final restored = Map<String, dynamic>.from(current);
        if (previous > 0) restored['quantity'] = -previous;
        onRowRestore(restored);
      } else {
        onRowRestore(Map<String, dynamic>.from(current));
      }
      return false;
    }
  }
}
