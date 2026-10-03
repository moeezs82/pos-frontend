import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SaleMetaBuilder {
  static String _metaText(dynamic value) => (value ?? '').toString().trim();

  static double _metaNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static Map<String, dynamic>? partySnapshot(
    Map<String, dynamic>? source, {
    dynamic id,
    String fallbackName = '',
  }) {
    if (source == null && id == null && fallbackName.trim().isEmpty) {
      return null;
    }

    dynamic read(String key) => source == null ? null : source[key];

    final firstName = _metaText(read('first_name'));
    final lastName = _metaText(read('last_name'));
    final directName = _metaText(read('name'));
    final fallback = fallbackName.trim();
    final combinedName = directName.isNotEmpty
        ? directName
        : [firstName, lastName].where((v) => v.isNotEmpty).join(' ').trim();

    final snapshot = <String, dynamic>{};
    final resolvedId = id ?? read('id');
    if (resolvedId != null) snapshot['id'] = resolvedId;

    final resolvedName = combinedName.isNotEmpty ? combinedName : fallback;
    if (resolvedName.isNotEmpty) snapshot['name'] = resolvedName;

    for (final key in const [
      'first_name',
      'last_name',
      'phone',
      'mobile',
      'email',
      'address'
    ]) {
      final value = _metaText(read(key));
      if (value.isNotEmpty) snapshot[key] = value;
    }

    return snapshot.isEmpty ? null : snapshot;
  }

  static Map<String, dynamic> buildSaleMeta({
    required BuildContext context,
    required String? effectiveBranchId,
    required Map<String, dynamic>? selectedBranch,
    required Map<String, dynamic>? selectedCustomer,
    required String? selectedCustomerId,
    required String walkInCustomerName,
    required String walkInPhone,
    required List<String> selectedCustomerSecondaryPhones,
    required String walkInAddress,
    required int? selectedAreaId,
    required String? selectedAreaName,
    required Map<String, dynamic>? selectedUser,
    required int? selectedUserId,
    required Map<String, dynamic>? selectedDeliveryBoy,
    required int? selectedDeliveryBoyId,
    required Map<String, dynamic>? selectedVendor,
    required int? selectedVendorId,
    required int? selectedSaleSourceId,
    required String? selectedSaleSourceName,
    required double subtotal,
    required double discount,
    required double tax,
    required double shipping,
    required double total,
    required double paid,
    required double balance,
    required double cashReceived,
    required double changeAmount,
    required List<Map<String, dynamic>> paymentsToSend,
  }) {
    final pmProvider = context.read<PaymentMethodProvider>();
    final typedPayments = paymentsToSend.map((payment) {
      final ref = _metaText(payment['reference']);
      final code = _metaText(payment['method']).isEmpty
          ? 'cash'
          : _metaText(payment['method']);
      return <String, dynamic>{
        'method': code,
        'label': pmProvider.displayNameFor(code),
        'amount': _metaNum(payment['amount']),
        if (ref.isNotEmpty) 'reference': ref,
      };
    }).toList(growable: false);

    final snapshotPrimaryPhone = selectedCustomerId != null
        ? (selectedCustomer?['phone'] ?? walkInPhone).toString().trim()
        : walkInPhone.trim();
    final snapshotSecondaryPhones = selectedCustomerId != null
        ? selectedCustomerSecondaryPhones
        : const <String>[];

    final customerSnapshot = <String, dynamic>{
      if (selectedCustomerId != null) 'id': selectedCustomerId,
      if ((selectedCustomer?['customer_code'] ?? '').toString().trim().isNotEmpty)
        'customer_code': selectedCustomer!['customer_code'],
      if (selectedCustomer != null)
        'customer_type': SalePricing.normalizeCustomerType(
          selectedCustomer['customer_type'],
        ),
      'name': selectedCustomer != null
          ? [
              _metaText(selectedCustomer['first_name']),
              _metaText(selectedCustomer['last_name']),
            ].where((v) => v.isNotEmpty).join(' ').trim()
          : (walkInCustomerName.trim().isEmpty
              ? 'Walk-in customer'
              : walkInCustomerName.trim()),
      'phone': snapshotPrimaryPhone,
      'phone_numbers': snapshotSecondaryPhones,
      'address': walkInAddress.trim(),
      if (selectedAreaId != null) 'area_id': selectedAreaId,
      if (selectedAreaName != null) 'area_name': selectedAreaName,
      if (selectedCustomer != null &&
          selectedCustomer.containsKey('credit_limit'))
        'credit_limit': selectedCustomer['credit_limit'],
      if (selectedCustomer?['credit_limit_mode'] != null)
        'credit_limit_mode': selectedCustomer!['credit_limit_mode'],
      if ((selectedCustomer?['balance'] ??
              selectedCustomer?['trade_balance']) !=
          null)
        'trade_balance': selectedCustomer?['balance'] ??
            selectedCustomer?['trade_balance'],
    };

    final meta = <String, dynamic>{
      'customer_snapshot': customerSnapshot,
      'print_customer_phone_numbers': snapshotSecondaryPhones.isNotEmpty,
      'branch_snapshot': {
        if (effectiveBranchId != null && effectiveBranchId.isNotEmpty)
          'id': effectiveBranchId,
        if (selectedBranch != null) ...{
          if (selectedBranch['name'] != null)
            'name': selectedBranch['name'],
          if (selectedBranch['location'] != null)
            'location': selectedBranch['location'],
        },
      },
      'salesman_snapshot': partySnapshot(
        selectedUser,
        id: selectedUserId,
        fallbackName: _metaText(selectedUser?['name']),
      ),
      'delivery_boy_snapshot': partySnapshot(
        selectedDeliveryBoy,
        id: selectedDeliveryBoyId,
        fallbackName: _metaText(selectedDeliveryBoy?['name']),
      ),
      'vendor_snapshot': partySnapshot(
        selectedVendor,
        id: selectedVendorId,
      ),
      if (selectedSaleSourceId != null)
        'sale_source_snapshot': {
          'id': selectedSaleSourceId,
          'name': (selectedSaleSourceName ?? 'Counter').toString(),
        },
      if (selectedAreaId != null)
        'sale_area_snapshot': {
          'id': selectedAreaId,
          if (selectedAreaName != null) 'name': selectedAreaName,
        },
      'totals_snapshot': {
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'delivery': shipping,
        'total': total,
        'paid': paid,
        'balance': balance,
      },
      'payments_snapshot': typedPayments,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
      'delivery': shipping,
      'sale_type': selectedDeliveryBoyId != null ? 'delivery' : 'counter',
    };

    meta.removeWhere((_, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty));
    return meta;
  }
}
