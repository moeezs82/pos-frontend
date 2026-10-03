import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SalesOrderStatus {
  static const String draft = 'DRAFT';
  static const String submitted = 'SUBMITTED';
  static const String approved = 'APPROVED';
  static const String converted = 'CONVERTED';
  static const String rejected = 'REJECTED';
  static const String cancelled = 'CANCELLED';

  static const List<String> all = [
    draft,
    submitted,
    approved,
    converted,
    rejected,
    cancelled,
  ];

  static String label(String? status) {
    switch (status?.toUpperCase()) {
      case draft:
        return 'Draft';
      case submitted:
        return 'Pending Approval';
      case approved:
        return 'Approved';
      case converted:
        return 'Invoiced';
      case rejected:
        return 'Rejected';
      case cancelled:
        return 'Cancelled';
      default:
        return status ?? 'Unknown';
    }
  }

  static Color color(String? status) {
    switch (status?.toUpperCase()) {
      case draft:
        return AppTheme.warning;
      case submitted:
        return AppTheme.info;
      case approved:
        return AppTheme.success;
      case converted:
        return AppTheme.primary;
      case rejected:
      case cancelled:
        return AppTheme.danger;
      default:
        return AppTheme.textMuted;
    }
  }
}

class CustomerSummary {
  final int id;
  final String name;
  final String phone;
  final String? address;

  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    return CustomerSummary(
      id: _toInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        if (address != null) 'address': address,
      };
}

class UserSummary {
  final int id;
  final String name;
  final String email;

  const UserSummary({
    required this.id,
    required this.name,
    required this.email,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: _toInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
      };
}

class SalesOrderItem {
  final int id;
  final int salesOrderId;
  final int productId;
  final String productName;
  final String productSku;
  final int? productVariationId;
  final int? productPackagingId;
  final String? packagingNameSnapshot;
  final String? packagingShortNameSnapshot;
  final double? packagingFactorSnapshot;
  final double? packagingQuantity;
  final double? packagingUnitPrice;
  final double? packagingDiscountSnapshot;
  final double quantity;
  final double unitPrice;
  final double unitCost;
  final double discount;
  final double taxRate;
  final double subtotal;
  final double total;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  const SalesOrderItem({
    required this.id,
    required this.salesOrderId,
    required this.productId,
    this.productName = '',
    this.productSku = '',
    this.productVariationId,
    this.productPackagingId,
    this.packagingNameSnapshot,
    this.packagingShortNameSnapshot,
    this.packagingFactorSnapshot,
    this.packagingQuantity,
    this.packagingUnitPrice,
    this.packagingDiscountSnapshot,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0.0,
    this.discount = 0.0,
    this.taxRate = 0.0,
    required this.subtotal,
    required this.total,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) {
    return SalesOrderItem(
      id: _toInt(json['id']) ?? 0,
      salesOrderId: _toInt(json['sales_order_id']) ?? 0,
      productId: _toInt(json['product_id']) ?? 0,
      productName: json['product_name']?.toString() ?? '',
      productSku: json['product_sku']?.toString() ?? '',
      productVariationId: _toInt(json['product_variation_id']),
      productPackagingId: _toInt(json['product_packaging_id']),
      packagingNameSnapshot: json['packaging_name_snapshot']?.toString(),
      packagingShortNameSnapshot: json['packaging_short_name_snapshot']?.toString(),
      packagingFactorSnapshot: _toDoubleNullable(json['packaging_factor_snapshot']),
      packagingQuantity: _toDoubleNullable(json['packaging_quantity']),
      packagingUnitPrice: _toDoubleNullable(json['packaging_unit_price']),
      packagingDiscountSnapshot: _toDoubleNullable(json['packaging_discount_snapshot']),
      quantity: _toDouble(json['quantity']),
      unitPrice: _toDouble(json['unit_price']),
      unitCost: _toDouble(json['unit_cost']),
      discount: _toDouble(json['discount']),
      taxRate: _toDouble(json['tax_rate']),
      subtotal: _toDouble(json['subtotal']),
      total: _toDouble(json['total']),
      notes: json['notes']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sales_order_id': salesOrderId,
        'product_id': productId,
        'product_name': productName,
        'product_sku': productSku,
        if (productVariationId != null)
          'product_variation_id': productVariationId,
        if (productPackagingId != null)
          'product_packaging_id': productPackagingId,
        if (packagingNameSnapshot != null)
          'packaging_name_snapshot': packagingNameSnapshot,
        if (packagingShortNameSnapshot != null)
          'packaging_short_name_snapshot': packagingShortNameSnapshot,
        if (packagingFactorSnapshot != null)
          'packaging_factor_snapshot': packagingFactorSnapshot,
        if (packagingQuantity != null)
          'packaging_quantity': packagingQuantity,
        if (packagingUnitPrice != null)
          'packaging_unit_price': packagingUnitPrice,
        if (packagingDiscountSnapshot != null)
          'packaging_discount_snapshot': packagingDiscountSnapshot,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'discount': discount,
        'tax_rate': taxRate,
        'subtotal': subtotal,
        'total': total,
        if (notes != null) 'notes': notes,
      };
}

class SalesOrderEvent {
  final int id;
  final int salesOrderId;
  final int userId;
  final UserSummary? user;
  final String action;
  final String? fromStatus;
  final String? toStatus;
  final String? notes;
  final String? createdAt;

  const SalesOrderEvent({
    required this.id,
    required this.salesOrderId,
    required this.userId,
    this.user,
    required this.action,
    this.fromStatus,
    this.toStatus,
    this.notes,
    this.createdAt,
  });

  factory SalesOrderEvent.fromJson(Map<String, dynamic> json) {
    return SalesOrderEvent(
      id: _toInt(json['id']) ?? 0,
      salesOrderId: _toInt(json['sales_order_id']) ?? 0,
      userId: _toInt(json['user_id']) ?? 0,
      user: json['user'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['user'])
          : null,
      action: json['action']?.toString() ?? '',
      fromStatus: json['from_status']?.toString(),
      toStatus: json['to_status']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class SalesOrder {
  final int id;
  final int branchId;
  final String orderNumber;
  final int customerId;
  final CustomerSummary? customer;
  final int salesmanId;
  final UserSummary? salesman;
  final String status;
  final String orderDate;
  final String? deliveryDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String? notes;
  final String? rejectionReason;
  final String? submittedAt;
  final String? approvedAt;
  final int? approvedBy;
  final UserSummary? approver;
  final String? convertedAt;
  final int? convertedBy;
  final UserSummary? converter;
  final int? convertedSaleId;
  final String? saleClientRef;
  final int version;
  final int createdBy;
  final String? deviceUuid;
  final List<SalesOrderItem> items;
  final List<SalesOrderEvent> events;
  final String? createdAt;
  final String? updatedAt;

  const SalesOrder({
    required this.id,
    required this.branchId,
    required this.orderNumber,
    required this.customerId,
    this.customer,
    required this.salesmanId,
    this.salesman,
    required this.status,
    required this.orderDate,
    this.deliveryDate,
    required this.subtotal,
    this.discount = 0.0,
    this.tax = 0.0,
    required this.total,
    this.notes,
    this.rejectionReason,
    this.submittedAt,
    this.approvedAt,
    this.approvedBy,
    this.approver,
    this.convertedAt,
    this.convertedBy,
    this.converter,
    this.convertedSaleId,
    this.saleClientRef,
    this.version = 1,
    this.createdBy = 0,
    this.deviceUuid,
    this.items = const [],
    this.events = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool get isDraft => status == SalesOrderStatus.draft;
  bool get isSubmitted => status == SalesOrderStatus.submitted;
  bool get isApproved => status == SalesOrderStatus.approved;
  bool get isConverted => status == SalesOrderStatus.converted;
  bool get isRejected => status == SalesOrderStatus.rejected;
  bool get isCancelled => status == SalesOrderStatus.cancelled;
  bool get isTerminal => isConverted || isCancelled;

  bool get isStale {
    final dateStr = submittedAt ?? createdAt;
    if (dateStr == null) return false;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return false;
    return DateTime.now().toUtc().difference(parsed.toUtc()).inHours > 48;
  }

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    return SalesOrder(
      id: _toInt(json['id']) ?? 0,
      branchId: _toInt(json['branch_id']) ?? 0,
      orderNumber: json['order_number']?.toString() ?? '',
      customerId: _toInt(json['customer_id']) ?? 0,
      customer: json['customer'] is Map<String, dynamic>
          ? CustomerSummary.fromJson(json['customer'])
          : null,
      salesmanId: _toInt(json['salesman_id']) ?? 0,
      salesman: json['salesman'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['salesman'])
          : null,
      status: (json['status']?.toString() ?? SalesOrderStatus.draft).toUpperCase(),
      orderDate: json['order_date']?.toString() ?? '',
      deliveryDate: json['delivery_date']?.toString(),
      subtotal: _toDouble(json['subtotal']),
      discount: _toDouble(json['discount']),
      tax: _toDouble(json['tax']),
      total: _toDouble(json['total']),
      notes: json['notes']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      submittedAt: json['submitted_at']?.toString(),
      approvedAt: json['approved_at']?.toString(),
      approvedBy: _toInt(json['approved_by']),
      approver: json['approver'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['approver'])
          : null,
      convertedAt: json['converted_at']?.toString(),
      convertedBy: _toInt(json['converted_by']),
      converter: json['converter'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['converter'])
          : null,
      convertedSaleId: _toInt(json['converted_sale_id']),
      saleClientRef: json['sale_client_ref']?.toString(),
      version: _toInt(json['version']) ?? 1,
      createdBy: _toInt(json['created_by']) ?? 0,
      deviceUuid: json['device_uuid']?.toString(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => SalesOrderItem.fromJson(e))
          .toList(),
      events: (json['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => SalesOrderEvent.fromJson(e))
          .toList(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}

/// Pre-fill payload passed to CreateSaleScreen when converting an approved
/// sales order into a finalized sale invoice.
class SalesOrderPrefill {
  final SalesOrder order;
  final String? creditLimitOverrideReason;

  const SalesOrderPrefill({
    required this.order,
    this.creditLimitOverrideReason,
  });
}

class SalesOrderListResponse {
  final List<SalesOrder> orders;
  final int total;
  final int page;
  final int perPage;
  final int lastPage;

  const SalesOrderListResponse({
    required this.orders,
    required this.total,
    required this.page,
    required this.perPage,
    required this.lastPage,
  });

  factory SalesOrderListResponse.fromJson(Map<String, dynamic> json) {
    final rawList = (json['sales_orders'] ?? json['data']) as List<dynamic>? ?? const [];
    final orders = rawList
        .whereType<Map<String, dynamic>>()
        .map((e) => SalesOrder.fromJson(e))
        .toList();

    final total = _toInt(json['total']) ?? orders.length;
    final perPage = _toInt(json['per_page']) ?? (orders.isEmpty ? 20 : orders.length);
    final page = _toInt(json['page']) ?? _toInt(json['current_page']) ?? 1;
    final lastPage = _toInt(json['last_page']) ??
        (perPage > 0 ? (total / perPage).ceil().clamp(1, 999999) : 1);

    return SalesOrderListResponse(
      orders: orders,
      total: total,
      page: page,
      perPage: perPage,
      lastPage: lastPage,
    );
  }
}

class DateRange {
  final String? startDate;
  final String? endDate;

  const DateRange({this.startDate, this.endDate});

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      startDate: json['start_date']?.toString(),
      endDate: json['end_date']?.toString(),
    );
  }
}

class StatusSummary {
  final String status;
  final int count;
  final double orderValue;
  final double? invoicedValue;

  const StatusSummary({
    required this.status,
    required this.count,
    required this.orderValue,
    this.invoicedValue,
  });

  factory StatusSummary.fromJson(Map<String, dynamic> json) {
    return StatusSummary(
      status: json['status']?.toString() ?? '',
      count: _toInt(json['count']) ?? 0,
      orderValue: _toDouble(json['order_value']),
      invoicedValue: json['invoiced_value'] != null
          ? _toDouble(json['invoiced_value'])
          : null,
    );
  }
}

class SummaryTotals {
  final double bookedValue;
  final double invoicedValue;
  final int pendingApproval;

  const SummaryTotals({
    required this.bookedValue,
    required this.invoicedValue,
    required this.pendingApproval,
  });

  factory SummaryTotals.fromJson(Map<String, dynamic> json) {
    return SummaryTotals(
      bookedValue: _toDouble(json['booked_value']),
      invoicedValue: _toDouble(json['invoiced_value']),
      pendingApproval: _toInt(json['pending_approval']) ?? 0,
    );
  }
}

class PipelineSummary {
  final DateRange range;
  final List<StatusSummary> byStatus;
  final SummaryTotals totals;

  const PipelineSummary({
    required this.range,
    required this.byStatus,
    required this.totals,
  });

  factory PipelineSummary.fromJson(Map<String, dynamic> json) {
    return PipelineSummary(
      range: json['range'] is Map<String, dynamic>
          ? DateRange.fromJson(json['range'])
          : const DateRange(),
      byStatus: (json['by_status'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => StatusSummary.fromJson(e))
          .toList(),
      totals: json['totals'] is Map<String, dynamic>
          ? SummaryTotals.fromJson(json['totals'])
          : const SummaryTotals(bookedValue: 0, invoicedValue: 0, pendingApproval: 0),
    );
  }
}

class OrderFilterOptionRef {
  final int id;
  final String name;
  final bool? isActive;

  const OrderFilterOptionRef({
    required this.id,
    required this.name,
    this.isActive,
  });

  factory OrderFilterOptionRef.fromJson(Map<String, dynamic> json) {
    return OrderFilterOptionRef(
      id: _toInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      isActive: json['is_active'] != null ? _toBool(json['is_active']) : null,
    );
  }
}

class CustomerFilterOptionRef {
  final int id;
  final String name;
  final String? phone;

  const CustomerFilterOptionRef({
    required this.id,
    required this.name,
    this.phone,
  });

  factory CustomerFilterOptionRef.fromJson(Map<String, dynamic> json) {
    return CustomerFilterOptionRef(
      id: _toInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
    );
  }
}

class OrderFilterOptions {
  final List<String> statuses;
  final List<OrderFilterOptionRef> salesmen;
  final List<CustomerFilterOptionRef> customers;

  const OrderFilterOptions({
    this.statuses = const [],
    this.salesmen = const [],
    this.customers = const [],
  });

  factory OrderFilterOptions.fromJson(Map<String, dynamic> json) {
    return OrderFilterOptions(
      statuses: (json['statuses'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      salesmen: (json['salesmen'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => OrderFilterOptionRef.fromJson(e))
          .toList(),
      customers: (json['customers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => CustomerFilterOptionRef.fromJson(e))
          .toList(),
    );
  }
}

// Serialization helpers
int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

double? _toDoubleNullable(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'1', 'true', 'yes', 'on'}
      .contains(value?.toString().trim().toLowerCase());
}
