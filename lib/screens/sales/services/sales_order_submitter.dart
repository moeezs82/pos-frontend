import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_validator.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';

class SalesOrderPrefillData {
  final String? customerId;
  final Map<String, dynamic>? customer;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int? salesmanId;
  final Map<String, dynamic>? salesman;
  final List<Map<String, dynamic>> items;
  final String? discount;
  final String? tax;
  final String? notes;
  final DateTime? deliveryDate;

  const SalesOrderPrefillData({
    required this.customerId,
    required this.customer,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.salesmanId,
    required this.salesman,
    required this.items,
    this.discount,
    this.tax,
    this.notes,
    this.deliveryDate,
  });
}

class SalesOrderSubmitter {
  static double _rowNum(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0.0;

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Extracts form-state prefill data from an existing SalesOrder.
  static SalesOrderPrefillData parseOrder(SalesOrder order) {
    final customer = order.customer;
    final customerId = customer?.id.toString();
    final customerMap = customer != null
        ? <String, dynamic>{
            'id': customer.id,
            'name': customer.name,
            'phone': customer.phone,
            if (customer.address != null) 'address': customer.address,
          }
        : null;

    final salesmanMap = order.salesman != null
        ? <String, dynamic>{
            'id': order.salesman!.id,
            'name': order.salesman!.name,
            'email': order.salesman!.email,
          }
        : null;

    final items = order.items.map((it) {
      final hasPkg = it.isPackaged;
      return <String, dynamic>{
        'product_id': it.productId,
        'name': it.productName.isNotEmpty ? it.productName : 'Product #${it.productId}',
        'sku': it.productSku,
        'quantity': hasPkg ? (it.packagingQuantity ?? it.quantity) : it.quantity,
        'price': hasPkg ? (it.packagingUnitPrice ?? it.unitPrice) : it.unitPrice,
        'discount_pct': 0.0,
        'extra_discount': it.discount,
        'discount_type': 'fixed',
        'total': it.total,
        if (hasPkg) ...{
          'packaging_id': it.productPackagingId,
          'packaging_name_snapshot': it.packagingNameSnapshot,
          'packaging_factor_snapshot': it.packagingFactorSnapshot,
          'packaging_quantity': it.packagingQuantity,
          'packaging_unit_price': it.packagingUnitPrice,
        },
        SaleProfitCalculator.unitCostKey: it.unitCost,
        SaleProfitCalculator.estimatedKey: false,
        SaleProfitCalculator.sourceKey: 'Sales order snapshot',
      };
    }).toList();

    return SalesOrderPrefillData(
      customerId: customerId,
      customer: customerMap,
      customerName: customer?.name ?? '',
      customerPhone: customer?.phone ?? '',
      customerAddress: customer?.address ?? '',
      salesmanId: order.salesmanId > 0 ? order.salesmanId : null,
      salesman: salesmanMap,
      items: items,
      discount: order.discount > 0 ? order.discount.toStringAsFixed(2) : null,
      tax: order.tax > 0 ? order.tax.toStringAsFixed(2) : null,
      notes: (order.notes != null && order.notes!.isNotEmpty) ? order.notes : null,
      deliveryDate: order.deliveryDate != null ? DateTime.tryParse(order.deliveryDate!) : null,
    );
  }

  /// Extracts form-state prefill data from an approved SalesOrderPrefill.
  static SalesOrderPrefillData parsePrefill(SalesOrderPrefill prefill) {
    final order = prefill.order;
    final customer = order.customer;
    final customerId = customer?.id.toString();
    final customerMap = customer != null
        ? <String, dynamic>{
            'id': customer.id,
            'name': customer.name,
            'phone': customer.phone,
            if (customer.address != null) 'address': customer.address,
          }
        : null;

    final salesmanMap = order.salesman != null
        ? <String, dynamic>{
            'id': order.salesman!.id,
            'name': order.salesman!.name,
            'email': order.salesman!.email,
          }
        : null;

    final items = order.items.map((it) {
      return <String, dynamic>{
        'product_id': it.productId,
        'name': it.productName.isNotEmpty ? it.productName : 'Product #${it.productId}',
        'sku': it.productSku,
        'quantity': it.quantity,
        'price': it.unitPrice,
        'discount_pct': 0.0,
        'extra_discount': it.discount,
        'discount_type': 'fixed',
        'total': it.total,
        SaleProfitCalculator.unitCostKey: it.unitCost,
        SaleProfitCalculator.estimatedKey: false,
        SaleProfitCalculator.sourceKey: 'Sales order snapshot',
      };
    }).toList();

    return SalesOrderPrefillData(
      customerId: customerId,
      customer: customerMap,
      customerName: customer?.name ?? '',
      customerPhone: customer?.phone ?? '',
      customerAddress: customer?.address ?? '',
      salesmanId: order.salesmanId > 0 ? order.salesmanId : null,
      salesman: salesmanMap,
      items: items,
      discount: order.discount > 0 ? order.discount.toStringAsFixed(2) : null,
      tax: order.tax > 0 ? order.tax.toStringAsFixed(2) : null,
    );
  }

  /// Displays the confirmation dialog when attempting to edit an already-approved sales order.
  static Future<bool> confirmApprovedOrderDemotion(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
            SizedBox(width: 10),
            Text('Demote Approved Order?'),
          ],
        ),
        content: const Text(
          'This order is approved. Saving changes returns it to Submitted and it will need approval again.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Proceed & Return to Submitted'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  static double _roundTo(double value, int scale) {
    var factor = 1.0;
    for (var i = 0; i < scale; i++) {
      factor *= 10;
    }
    return (value * factor).roundToDouble() / factor;
  }

  /// Collapses the POS cart's discount model (percentage / per-unit fixed /
  /// per-pack fixed / extra) into the single whole-line money figure the
  /// Sales Order API expects (`CreateOrderItemInput.Discount`).
  ///
  /// Mirrors SaleCartMutator.cartLineTotal() — keep the two in step.
  static double lineDiscountMoney(Map<String, dynamic> it) {
    final discountType =
        (it['discount_type'] ?? 'percentage').toString().toLowerCase();
    final extra = _rowNum(it['extra_discount']);
    final pct = _rowNum(it['discount_pct']).clamp(0.0, 100.0) / 100.0;
    double lineDisc;

    if (it['packaging_id'] != null) {
      final packQty = _rowNum(it['packaging_quantity']);
      final packPrice = _rowNum(it['packaging_unit_price']);
      final gross = _roundTo(packQty * packPrice, 2);
      lineDisc = discountType == 'fixed'
          ? _roundTo(packQty * _rowNum(it['packaging_discount_snapshot']), 2)
          : _roundTo(gross * pct, 2);
    } else {
      final qty = _rowNum(it['quantity']);
      final gross = _roundTo(qty * _rowNum(it['price']), 2);
      lineDisc = discountType == 'fixed'
          ? _roundTo(_rowNum(it['discount_pct']) * qty, 2)
          : _roundTo(gross * pct, 2);
    }

    final total = lineDisc + extra;
    return total.isFinite && total > 0 ? _roundTo(total, 2) : 0.0;
  }

  /// Translates cart rows into the Sales Order items contract.
  ///
  /// Packaged cart rows are already canonical (base-unit `quantity`/`price`
  /// plus pack-level fields), so they pass through untouched — no arithmetic.
  static List<Map<String, dynamic>> buildItemsPayload(
    List<Map<String, dynamic>> items,
  ) {
    return items.map((it) {
      final prodId = _metaInt(it['product_id']) ?? 0;
      final packagingId = _metaInt(it['packaging_id']);
      final qty = _rowNum(it['quantity']);
      final price = _rowNum(it['price']);
      final discount = lineDiscountMoney(it);
      final taxRate = _rowNum(it['tax_rate']);
      final notes = it['notes']?.toString();

      final packQty = _rowNum(it['packaging_quantity']);
      final packPrice = _rowNum(it['packaging_unit_price']);
      if (packagingId != null &&
          packagingId > 0 &&
          packQty > 0 &&
          packPrice > 0) {
        return <String, dynamic>{
          'product_id': prodId,
          'product_packaging_id': packagingId,
          'packaging_quantity': packQty,
          'packaging_unit_price': packPrice,
          'quantity': qty,
          'unit_price': price,
          'discount': discount,
          'tax_rate': taxRate,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        };
      }
      return <String, dynamic>{
        'product_id': prodId,
        'quantity': qty,
        'unit_price': price,
        'discount': discount,
        'tax_rate': taxRate,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
    }).toList();
  }

  /// Assembles the complete JSON body for creating or updating a sales order.
  static Map<String, dynamic> buildOrderPayload({
    required int customerId,
    required int salesmanId,
    required DateTime? deliveryDate,
    required String notes,
    required List<Map<String, dynamic>> itemsPayload,
    required bool submitForApproval,
    required int? editOrderVersion,
  }) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final deliveryDateStr =
        deliveryDate != null ? dateFmt.format(deliveryDate) : null;

    return <String, dynamic>{
      'customer_id': customerId,
      if (salesmanId > 0) 'salesman_id': salesmanId,
      'order_date': dateFmt.format(DateTime.now()),
      if (deliveryDateStr != null) 'delivery_date': deliveryDateStr,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      'items': itemsPayload,
      'status': submitForApproval ? 'SUBMITTED' : 'DRAFT',
      if (editOrderVersion != null) 'version': editOrderVersion,
    };
  }

  /// Validates cart, prompts demotion confirmation if needed, and sends create/update request.
  static Future<bool> executeSalesOrderSubmit({
    required BuildContext context,
    required String? selectedCustomerId,
    required String customerPhone,
    required Future<bool> Function() onResolveCustomerByPhone,
    required FocusNode customerFocusNode,
    required List<Map<String, dynamic>> items,
    required SalesOrder? editSalesOrder,
    required void Function(bool submitting) onSubmittingChanged,
    required AuthProvider auth,
    required int? selectedUserId,
    required DateTime? deliveryDate,
    required String notes,
    required bool submitForApproval,
  }) async {
    if (selectedCustomerId == null && customerPhone.trim().isNotEmpty) {
      final canContinue = await onResolveCustomerByPhone();
      if (!canContinue) return false;
    }
    if (selectedCustomerId == null) {
      AppFeedback.warning(context, "Please select a customer for this sales order.");
      customerFocusNode.requestFocus();
      return false;
    }
    if (items.isEmpty) {
      AppFeedback.warning(context, "Add at least 1 item before saving sales order.");
      return false;
    }

    final quantityViolation = SaleCartValidator.firstQuantityViolation(items);
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return false;
    }

    // Demotion guard when editing an APPROVED order (§5)
    if (editSalesOrder != null &&
        editSalesOrder.status == SalesOrderStatus.approved) {
      final confirmed = await confirmApprovedOrderDemotion(context);
      if (!confirmed) return false;
    }

    onSubmittingChanged(true);

    final currentUserId = int.tryParse(auth.user?['id']?.toString() ?? '0') ?? 0;
    final salesmanId = selectedUserId ?? currentUserId;
    final customerId = int.tryParse(selectedCustomerId) ?? 0;

    final itemsPayload = buildItemsPayload(items);
    final body = buildOrderPayload(
      customerId: customerId,
      salesmanId: salesmanId,
      deliveryDate: deliveryDate,
      notes: notes,
      itemsPayload: itemsPayload,
      submitForApproval: submitForApproval,
      editOrderVersion: editSalesOrder?.version,
    );

    try {
      final service = SalesOrderService(token: auth.token!);
      final SalesOrder saved;
      if (editSalesOrder != null) {
        saved = await service.updateOrder(editSalesOrder.id, body);
      } else {
        saved = await service.createOrder(body);
      }
      // Report what the server actually stored, not what was requested.
      final isSubmitted = saved.status == SalesOrderStatus.submitted;
      AppFeedback.success(
        context,
        isSubmitted
            ? 'Sales order #${saved.orderNumber} submitted for approval.'
            : 'Sales order #${saved.orderNumber} saved as draft.',
      );
      return true;
    } catch (e) {
      onSubmittingChanged(false);
      if (e is ApiException) {
        if (e.statusCode == 409) {
          AppFeedback.error(context, 'Version conflict: this sales order was modified by another user.');
          return false;
        }
        if (e.statusCode == 422) {
          SaleCartValidator.applyServerLineErrors(items, e);
          AppFeedback.error(context, SaleCartValidator.describeRejection(items, e));
          return false;
        }
        AppFeedback.error(context, e.message);
        return false;
      }
      AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }
}
