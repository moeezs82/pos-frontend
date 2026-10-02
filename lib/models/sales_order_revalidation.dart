import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';

class RevalidationIssue {
  final String code;
  final String field;
  final String message;
  final Map<String, dynamic> data;

  const RevalidationIssue({
    required this.code,
    required this.field,
    required this.message,
    this.data = const {},
  });

  factory RevalidationIssue.fromJson(Map<String, dynamic> json) {
    return RevalidationIssue(
      code: json['code']?.toString() ?? '',
      field: json['field']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      data: json['data'] is Map<String, dynamic>
          ? (json['data'] as Map<String, dynamic>)
          : (json['data'] is Map
              ? (json['data'] as Map).cast<String, dynamic>()
              : const {}),
    );
  }

  int? get lineNumber {
    if (!field.startsWith('items.')) return null;
    final parts = field.split('.');
    if (parts.length >= 2) {
      final index = int.tryParse(parts[1]);
      if (index != null) return index + 1; // 1-based line number
    }
    return null;
  }
}

class RevalidationCredit {
  final String partyType;
  final int partyId;
  final double? creditLimit;
  final double balance;
  final double projectedBalance;
  final double exceededBy;
  final String mode;
  final bool canOverride;

  const RevalidationCredit({
    required this.partyType,
    required this.partyId,
    this.creditLimit,
    required this.balance,
    required this.projectedBalance,
    required this.exceededBy,
    required this.mode,
    required this.canOverride,
  });

  factory RevalidationCredit.fromJson(Map<String, dynamic> json) {
    return RevalidationCredit(
      partyType: json['party_type']?.toString() ?? 'customer',
      partyId: _toInt(json['party_id']) ?? 0,
      creditLimit: _toDoubleOrNull(json['credit_limit']),
      balance: _toDouble(json['balance']),
      projectedBalance: _toDouble(json['projected_balance']),
      exceededBy: _toDouble(json['exceeded_by']),
      mode: json['mode']?.toString() ?? 'warning',
      canOverride: _toBool(json['can_override']),
    );
  }

  CreditLimitIssue toCreditLimitIssue() {
    return CreditLimitIssue(
      partyType: partyType,
      partyId: partyId,
      limit: creditLimit ?? 0.0,
      balanceBefore: balance,
      projectedBalance: projectedBalance,
      exceededBy: exceededBy,
      mode: mode,
      canOverride: canOverride,
      overrideUsed: false,
    );
  }
}

class RevalidationConverter {
  final bool hasOpenRegisterShift;

  const RevalidationConverter({
    this.hasOpenRegisterShift = false,
  });

  factory RevalidationConverter.fromJson(Map<String, dynamic> json) {
    return RevalidationConverter(
      hasOpenRegisterShift: _toBool(json['has_open_register_shift']),
    );
  }
}

class RevalidationReport {
  final int salesOrderId;
  final String orderNumber;
  final String status;
  final bool applicable;
  final double ageHours;
  final bool stale;
  final bool canConvert;
  final List<RevalidationIssue> blocking;
  final List<RevalidationIssue> warnings;
  final RevalidationCredit? credit;
  final RevalidationConverter converter;
  final String checkedAt;

  const RevalidationReport({
    required this.salesOrderId,
    required this.orderNumber,
    required this.status,
    required this.applicable,
    required this.ageHours,
    required this.stale,
    required this.canConvert,
    this.blocking = const [],
    this.warnings = const [],
    this.credit,
    this.converter = const RevalidationConverter(),
    required this.checkedAt,
  });

  bool get hasBlockingIssues => blocking.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isClean => blocking.isEmpty && warnings.isEmpty;

  factory RevalidationReport.fromJson(Map<String, dynamic> json) {
    return RevalidationReport(
      salesOrderId: _toInt(json['sales_order_id']) ?? 0,
      orderNumber: json['order_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      applicable: _toBool(json['applicable']),
      ageHours: _toDouble(json['age_hours']),
      stale: _toBool(json['stale']),
      canConvert: _toBool(json['can_convert']),
      blocking: (json['blocking'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => RevalidationIssue.fromJson(e))
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => RevalidationIssue.fromJson(e))
          .toList(),
      credit: json['credit'] is Map<String, dynamic>
          ? RevalidationCredit.fromJson(json['credit'])
          : null,
      converter: json['converter'] is Map<String, dynamic>
          ? RevalidationConverter.fromJson(json['converter'])
          : const RevalidationConverter(),
      checkedAt: json['checked_at']?.toString() ?? '',
    );
  }
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

double? _toDoubleOrNull(dynamic value) {
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
