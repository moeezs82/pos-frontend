import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_amendment_dialog.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_validator.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';

class AmendmentResetValues {
  final List<Map<String, dynamic>> items;
  final String discount;
  final String tax;
  final String delivery;
  final int? vendorId;
  final Map<String, dynamic>? vendor;
  final int? userId;
  final Map<String, dynamic>? user;
  final int? deliveryBoyId;
  final Map<String, dynamic>? deliveryBoy;
  final int? saleSourceId;

  const AmendmentResetValues({
    required this.items,
    required this.discount,
    required this.tax,
    required this.delivery,
    required this.vendorId,
    required this.vendor,
    required this.userId,
    required this.user,
    required this.deliveryBoyId,
    required this.deliveryBoy,
    required this.saleSourceId,
  });
}

class LoadedSaleForEdit {
  final Map<String, dynamic> rawSale;
  final int revision;
  final double originalTotal;
  final double existingNetPaid;
  final List<Map<String, dynamic>> items;
  final int? customerId;
  final Map<String, dynamic>? customer;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int? vendorId;
  final Map<String, dynamic>? vendor;
  final int? salesmanId;
  final Map<String, dynamic>? salesman;
  final int? deliveryBoyId;
  final Map<String, dynamic>? deliveryBoy;
  final int? saleSourceId;
  final int? areaId;
  final String? branchId;
  final Map<String, dynamic>? branch;
  final double discount;
  final double tax;
  final double delivery;

  const LoadedSaleForEdit({
    required this.rawSale,
    required this.revision,
    required this.originalTotal,
    required this.existingNetPaid,
    required this.items,
    required this.customerId,
    required this.customer,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.vendorId,
    required this.vendor,
    required this.salesmanId,
    required this.salesman,
    required this.deliveryBoyId,
    required this.deliveryBoy,
    required this.saleSourceId,
    required this.areaId,
    required this.branchId,
    required this.branch,
    required this.discount,
    required this.tax,
    required this.delivery,
  });
}

class SaleAmendmentService {
  static double _editNum(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0.0;

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

  static Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static List<dynamic> _listValue(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  /// Parses raw sale JSON returned by GET /sales/:id into [LoadedSaleForEdit].
  static LoadedSaleForEdit parseLoadedSale({
    required Map<String, dynamic> sale,
    required double Function({
      required double price,
      required double qty,
      required double discPct,
      required String discountType,
      required double extraDiscount,
    }) lineTotalCalculator,
  }) {
    final items = <Map<String, dynamic>>[];
    for (final raw in _listValue(sale['items'])) {
      final line = _mapValue(raw);
      final product = _mapValue(line['product']);
      final productId = int.tryParse(
            (line['product_id'] ?? product['id'] ?? '').toString(),
          ) ??
          0;
      if (productId <= 0) continue;
      final qty = _editNum(line['quantity']);
      final price = _editNum(line['price']);
      final discount = _editNum(line['discount']);
      final discountType = (line['discount_type'] ?? 'percentage').toString();
      final unitCost = _editNum(line['unit_cost']);
      final packagingId = int.tryParse(line['packaging_id']?.toString() ?? '');
      final row = <String, dynamic>{
        ...product,
        'sale_item_id': int.tryParse(line['id']?.toString() ?? ''),
        'product_id': productId,
        'name': (product['name'] ?? 'Product #$productId').toString(),
        'secondary_name': product['secondary_name'],
        'quantity': qty,
        'price': price,
        'discount_pct': discount,
        'extra_discount': _editNum(line['extra_discount']),
        'discount_type': discountType,
        if (packagingId != null) ...{
          'packaging_id': packagingId,
          'packaging_name_snapshot': line['packaging_name_snapshot'],
          'packaging_short_name_snapshot': line['packaging_short_name_snapshot'],
          'packaging_factor_snapshot': line['packaging_factor_snapshot'],
          'packaging_quantity': line['packaging_quantity'],
          'packaging_unit_price': line['packaging_unit_price'],
          'packaging_discount_snapshot': line['packaging_discount_snapshot'],
        },
        SaleProfitCalculator.unitCostKey: unitCost,
        SaleProfitCalculator.estimatedKey: true,
        SaleProfitCalculator.sourceKey:
            'Posted cost snapshot; final amendment COGS is confirmed by the server',
      };
      row['total'] = packagingId != null
          ? _editNum(line['total'])
          : lineTotalCalculator(
              price: price,
              qty: qty,
              discPct: discount,
              discountType: discountType,
              extraDiscount: _editNum(line['extra_discount']),
            );
      items.add(row);
    }

    if (items.isEmpty) {
      throw const FormatException(
        'This invoice has no active sale items and cannot be amended here.',
      );
    }

    final customer = _mapValue(sale['customer']);
    final vendor = _mapValue(sale['vendor']);
    final salesman = _mapValue(sale['salesman']);
    final deliveryBoy = _mapValue(sale['delivery_boy']);
    final branch = _mapValue(sale['branch']);
    final meta = _mapValue(sale['meta']);
    final customerSnapshot = _mapValue(meta['customer_snapshot']);
    final customerId = int.tryParse(sale['customer_id']?.toString() ?? '');
    final vendorId = int.tryParse(sale['vendor_id']?.toString() ?? '');
    final salesmanId = int.tryParse(sale['salesman_id']?.toString() ?? '');
    final deliveryBoyId =
        int.tryParse(sale['delivery_boy_id']?.toString() ?? '');
    final saleSourceId =
        int.tryParse(sale['sale_source_id']?.toString() ?? '');
    final saleAreaId = int.tryParse(sale['area_id']?.toString() ?? '');

    String customerName;
    String customerPhone;
    String address;

    if (customerId != null) {
      customerName = [
        (customer['first_name'] ?? '').toString(),
        (customer['last_name'] ?? '').toString(),
      ].where((v) => v.trim().isNotEmpty).join(' ').trim();
      customerPhone = (customer['phone'] ?? '').toString();
      address = (customer['address'] ?? '').toString();
    } else {
      customerName =
          (customerSnapshot['name'] ?? 'Walk-in customer').toString();
      customerPhone = (customerSnapshot['phone'] ?? '').toString();
      address = (customerSnapshot['address'] ?? '').toString();
    }

    final selectedCustomerForEdit = customerId == null
        ? null
        : <String, dynamic>{
            ...customer,
            if (customerSnapshot.containsKey('phone_numbers'))
              'phone_numbers': customerSnapshot['phone_numbers'],
          };

    return LoadedSaleForEdit(
      rawSale: sale,
      revision: int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0,
      originalTotal: _editNum(sale['total']),
      existingNetPaid: _editNum(sale['net_paid']),
      items: items,
      customerId: customerId,
      customer: selectedCustomerForEdit,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: address,
      vendorId: vendorId,
      vendor: vendorId == null ? null : vendor,
      salesmanId: salesmanId,
      salesman: salesmanId == null ? null : salesman,
      deliveryBoyId: deliveryBoyId,
      deliveryBoy: deliveryBoyId == null ? null : deliveryBoy,
      saleSourceId: saleSourceId,
      areaId: saleAreaId,
      branchId: sale['branch_id']?.toString(),
      branch: branch.isEmpty ? null : branch,
      discount: _editNum(sale['discount']),
      tax: _editNum(sale['tax']),
      delivery: _editNum(sale['delivery']),
    );
  }

  /// Builds the desired-state JSON amendment payload for POST /sales/:id/amend.
  static Map<String, dynamic> buildAmendmentPayload({
    required int editRevision,
    required AmendmentReviewDecision decision,
    required List<Map<String, dynamic>> items,
    required double discount,
    required double tax,
    required double delivery,
    required int? selectedVendorId,
    required int? selectedUserId,
    required int? selectedDeliveryBoyId,
    required int? selectedSaleSourceId,
  }) {
    return <String, dynamic>{
      'expected_revision': editRevision,
      'reason': decision.reason,
      'items': items.map((item) {
        final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
        return <String, dynamic>{
          if (id != null) 'sale_item_id': id,
          'product_id':
              int.tryParse(item['product_id']?.toString() ?? '') ?? 0,
          'quantity': _editNum(item['quantity']),
          'price': _editNum(item['price']),
          'discount_pct': item['packaging_id'] != null &&
                  (item['discount_type'] ?? 'percentage').toString() == 'fixed'
              ? (_metaNullableNum(item['packaging_discount_snapshot']) ??
                  _editNum(item['discount_pct']))
              : _editNum(item['discount_pct']),
          'discount_type':
              (item['discount_type'] ?? 'percentage').toString(),
          'extra_discount': _editNum(item['extra_discount']),
          if (item['packaging_id'] != null) ...{
            'packaging_id': _metaInt(item['packaging_id']),
            'packaging_name_snapshot': item['packaging_name_snapshot'],
            'packaging_short_name_snapshot':
                item['packaging_short_name_snapshot'],
            'packaging_factor_snapshot':
                _editNum(item['packaging_factor_snapshot']),
            'packaging_quantity': _editNum(item['packaging_quantity']),
            'packaging_unit_price': _editNum(item['packaging_unit_price']),
            if ((item['discount_type'] ?? 'percentage').toString() == 'fixed')
              'packaging_discount_snapshot':
                  _metaNullableNum(item['packaging_discount_snapshot']) ??
                      _editNum(item['discount_pct']),
          },
        };
      }).toList(growable: false),
      'discount': discount,
      'tax': tax,
      'delivery': delivery,
      'vendor_id': selectedVendorId,
      'salesman_id': selectedUserId,
      'delivery_boy_id': selectedDeliveryBoyId,
      'sale_source_id': selectedSaleSourceId,
      if (decision.settlementAction != 'none')
        'settlement': <String, dynamic>{
          'action': decision.settlementAction,
          'amount': decision.settlementAmount,
          'method': decision.settlementMethod,
          if (decision.reference.trim().isNotEmpty)
            'reference': decision.reference.trim(),
          'note': 'Sale amendment revision ${editRevision + 1}',
        },
    };
  }

  /// Computes restored values for resetting an amendment draft.
  static AmendmentResetValues computeResetValues({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> originalItems,
  }) {
    final vendorId = int.tryParse(sale['vendor_id']?.toString() ?? '');
    final userId = int.tryParse(sale['salesman_id']?.toString() ?? '');
    final deliveryBoyId =
        int.tryParse(sale['delivery_boy_id']?.toString() ?? '');
    return AmendmentResetValues(
      items: originalItems
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: true),
      discount: _editNum(sale['discount']).toStringAsFixed(2),
      tax: _editNum(sale['tax']).toStringAsFixed(2),
      delivery: _editNum(sale['delivery']).toStringAsFixed(2),
      vendorId: vendorId,
      vendor: vendorId == null ? null : _mapValue(sale['vendor']),
      userId: userId,
      user: userId == null ? null : _mapValue(sale['salesman']),
      deliveryBoyId: deliveryBoyId,
      deliveryBoy:
          deliveryBoyId == null ? null : _mapValue(sale['delivery_boy']),
      saleSourceId: int.tryParse(sale['sale_source_id']?.toString() ?? ''),
    );
  }

  /// Handles preflight validation, user review modal, override handling, and
  /// executing the PUT/POST /sales/:id/amend request.
  static Future<bool> executeAmendment({
    required BuildContext context,
    required SaleService saleService,
    required int? editSaleId,
    required Map<String, dynamic>? editSale,
    required int editRevision,
    required double originalTotal,
    required double existingNetPaid,
    required String? selectedBranchId,
    required int? selectedSaleSourceId,
    required int? selectedVendorId,
    required int? selectedUserId,
    required int? selectedDeliveryBoyId,
    required String? selectedCustomerId,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> originalItems,
    required double discount,
    required double tax,
    required double delivery,
    required double Function(Map<String, dynamic> item) lineTotalCalculator,
    required void Function(bool submitting) onSubmittingChanged,
  }) async {
    if (editSale == null || editSaleId == null) {
      AppFeedback.error(context, 'The posted sale is not loaded yet.');
      return false;
    }
    final invoiceBranchId = int.tryParse(selectedBranchId ?? '');
    final workingBranchId = context.read<BranchProvider>().selectedBranchId;
    if (invoiceBranchId == null || workingBranchId != invoiceBranchId) {
      AppFeedback.warning(
        context,
        'This invoice belongs to Branch #${invoiceBranchId ?? '-'}.'
        ' Switch back to that branch before saving this amendment.',
      );
      return false;
    }
    if (items.isEmpty) {
      AppFeedback.warning(
        context,
        'A posted invoice must keep at least one item. Use the return/void workflow to reverse the entire invoice.',
      );
      return false;
    }
    final quantityViolation = SaleCartValidator.firstQuantityViolation(items);
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return false;
    }

    double subtotal = 0;
    for (final item in items) {
      subtotal += lineTotalCalculator(item);
    }
    final revisedTotal = subtotal - discount + tax + delivery;
    if (revisedTotal < -0.004) {
      AppFeedback.warning(
        context,
        'The revised invoice total cannot be negative. Use the return/refund workflow instead.',
      );
      return false;
    }

    final sourceChanged =
        int.tryParse(editSale['sale_source_id']?.toString() ?? '') !=
            selectedSaleSourceId;
    final diff = AmendmentDiff.compute(
      originalItems: originalItems,
      currentItems: items,
      sourceChanged: sourceChanged,
    );
    final saleLevelChanged =
        (_editNum(editSale['discount']) - discount).abs() > .004 ||
            (_editNum(editSale['tax']) - tax).abs() > .004 ||
            (_editNum(editSale['delivery']) - delivery).abs() > .004 ||
            int.tryParse(editSale['vendor_id']?.toString() ?? '') !=
                selectedVendorId ||
            int.tryParse(editSale['salesman_id']?.toString() ?? '') !=
                selectedUserId ||
            int.tryParse(editSale['delivery_boy_id']?.toString() ?? '') !=
                selectedDeliveryBoyId ||
            sourceChanged;
    if (!diff.hasChanges && !saleLevelChanged) {
      AppFeedback.info(context, 'There are no changes to save.');
      return false;
    }

    final profit = SaleProfitCalculator.invoice(
      items: items,
      invoiceDiscount: discount,
      shippingRevenue: delivery,
      tax: tax,
    );
    final pm = context.read<PaymentMethodProvider>();
    final paymentMethods = pm.activeMethods
        .map((m) => AmendmentPaymentMethod(m.method, m.displayName))
        .toList(growable: false);
    final decision = await showDialog<AmendmentReviewDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaleAmendmentReviewDialog(
        invoiceNo: (editSale['invoice_no'] ?? editSaleId).toString(),
        revision: editRevision,
        originalTotal: originalTotal,
        revisedTotal: revisedTotal,
        netPaid: existingNetPaid,
        customerAttached: selectedCustomerId != null,
        deliverySale: selectedDeliveryBoyId != null,
        diff: diff,
        profit: context.read<AuthProvider>().hasPermission('view-sale-profit')
            ? profit
            : null,
        paymentMethods: paymentMethods,
      ),
    );
    if (decision == null) return false;

    final payload = buildAmendmentPayload(
      editRevision: editRevision,
      decision: decision,
      items: items,
      discount: discount,
      tax: tax,
      delivery: delivery,
      selectedVendorId: selectedVendorId,
      selectedUserId: selectedUserId,
      selectedDeliveryBoyId: selectedDeliveryBoyId,
      selectedSaleSourceId: selectedSaleSourceId,
    );

    onSubmittingChanged(true);
    Object? submitError;
    Map<String, dynamic>? response;
    try {
      try {
        response = await saleService
            .amendSale(editSaleId, payload)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        submitError = e;
      }

      final creditIssue = submitError == null
          ? null
          : CreditLimitIssue.fromException(submitError);
      if (creditIssue != null) {
        final auth = context.read<AuthProvider>();
        if (!creditIssue.canOverride ||
            !auth.hasPermission('override-party-credit-limit')) {
          AppFeedback.error(context, creditIssue.summary);
          return false;
        }
        final overrideReason = await showCreditLimitOverrideDialog(
          context,
          creditIssue,
        );
        if (overrideReason == null) return false;
        payload['credit_limit_override'] = {'reason': overrideReason};
        submitError = null;
        try {
          response = await saleService
              .amendSale(editSaleId, payload)
              .timeout(const Duration(seconds: 20));
        } catch (e) {
          submitError = e;
        }
      }

      if (submitError != null) {
        final e = submitError;
        if (e is ApiException && e.statusCode == 409) {
          AppFeedback.error(
            context,
            'This invoice was changed on another terminal. Your draft was not saved. Reload the invoice before applying it again.',
          );
        } else if (e is ApiException) {
          SaleCartValidator.applyServerLineErrors(items, e);
          AppFeedback.error(context, SaleCartValidator.describeRejection(items, e));
        } else {
          AppFeedback.error(
            context,
            'Sale amendment was not saved. Posted-sale editing requires an online server connection. $e',
          );
        }
        return false;
      }

      final amendment = _mapValue(_mapValue(response?['data'])['amendment']);
      final revision =
          amendment['revision_no']?.toString() ?? '${editRevision + 1}';
      AppFeedback.success(
        context,
        'Sale amended successfully • Revision $revision. Original financial history was preserved.',
      );
      return true;
    } finally {
      onSubmittingChanged(false);
    }
  }
}
