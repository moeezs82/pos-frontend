import 'package:flutter/material.dart';

/// A branch-configured payment method (Cash, KNET, Card, Cheque, ...).
///
/// This is the single shared shape used by every screen. Do not re-declare
/// fixed method lists elsewhere — read from [PaymentMethodProvider] instead.
class PaymentMethod {
  final int? id;

  /// Immutable machine code, e.g. `knet`. Sent to the backend as `method`.
  final String method;

  /// User-facing name, e.g. `KNET`.
  final String displayName;

  final int? accountId;
  final String? accountCode;
  final String? accountName;

  /// Whether this method changes physical register expected cash.
  final bool affectsCashDrawer;

  final bool isActive;
  final int sortOrder;
  final String? iconKey;

  // Admin-only fields (present on the admin listing).
  final int? branchId;
  final bool isInherited;

  const PaymentMethod({
    this.id,
    required this.method,
    required this.displayName,
    this.accountId,
    this.accountCode,
    this.accountName,
    this.affectsCashDrawer = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.iconKey,
    this.branchId,
    this.isInherited = false,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      method: (json['method'] ?? '').toString(),
      displayName: (json['display_name'] ?? json['method'] ?? '').toString(),
      accountId: json['account_id'] is int
          ? json['account_id'] as int
          : int.tryParse('${json['account_id']}'),
      accountCode: json['account_code']?.toString(),
      accountName: json['account_name']?.toString(),
      affectsCashDrawer: json['affects_cash_drawer'] == true ||
          json['affects_cash_drawer'] == 1 ||
          json['affects_cash_drawer'] == '1',
      isActive: json['is_active'] == null
          ? true
          : (json['is_active'] == true ||
              json['is_active'] == 1 ||
              json['is_active'] == '1'),
      sortOrder: json['sort_order'] is int
          ? json['sort_order'] as int
          : int.tryParse('${json['sort_order']}') ?? 0,
      iconKey: json['icon_key']?.toString(),
      branchId: json['branch_id'] is int
          ? json['branch_id'] as int
          : int.tryParse('${json['branch_id']}'),
      isInherited: json['is_inherited'] == true ||
          json['is_inherited'] == 1 ||
          json['is_inherited'] == '1',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'display_name': displayName,
        'account_id': accountId,
        'account_code': accountCode,
        'account_name': accountName,
        'affects_cash_drawer': affectsCashDrawer,
        'is_active': isActive,
        'sort_order': sortOrder,
        'icon_key': iconKey,
        'branch_id': branchId,
        'is_inherited': isInherited,
      };

  /// A concise map used by offline cache snapshots.
  Map<String, dynamic> toCache() => {
        'method': method,
        'display_name': displayName,
        'account_id': accountId,
        'affects_cash_drawer': affectsCashDrawer ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
        'icon_key': iconKey,
      };

  /// A best-effort icon for the method, from [iconKey] then the code.
  IconData get icon {
    switch ((iconKey ?? method).toLowerCase()) {
      case 'cash':
        return Icons.payments_rounded;
      case 'bank':
      case 'transfer':
        return Icons.account_balance_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      case 'knet':
        return Icons.account_balance_wallet_rounded;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'cheque':
      case 'check':
        return Icons.receipt_long_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  PaymentMethod copyWith({
    String? displayName,
    int? accountId,
    String? accountCode,
    String? accountName,
    bool? affectsCashDrawer,
    bool? isActive,
    int? sortOrder,
    String? iconKey,
  }) {
    return PaymentMethod(
      id: id,
      method: method,
      displayName: displayName ?? this.displayName,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      affectsCashDrawer: affectsCashDrawer ?? this.affectsCashDrawer,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      iconKey: iconKey ?? this.iconKey,
      branchId: branchId,
      isInherited: isInherited,
    );
  }
}
