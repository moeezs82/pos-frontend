/// A unit of measure, and the one rule that matters at the till: whether a
/// product measured in it may carry a fractional quantity.
///
/// This is the single shared shape. Do not re-derive "can this product take a
/// decimal?" anywhere else — read [ProductUnit.allowDecimal], or use
/// [QuantityRule] which also handles the product-has-no-unit case.
class ProductUnit {
  final int id;
  final String name;
  final String? shortName;

  /// Whether quantities for products using this unit may have a fractional
  /// part. The rule is about GRANULARITY, NOT SIGN: with this false, -1 is
  /// still a valid inline return but -1.5 is not.
  final bool allowDecimal;

  final bool isActive;

  const ProductUnit({
    required this.id,
    required this.name,
    this.shortName,
    this.allowDecimal = defaultAllowDecimal,
    this.isActive = true,
  });

  /// What to assume when the field is absent.
  ///
  /// TRUE, deliberately. A product record cached before this feature shipped
  /// has no `allow_decimal`, and an offline till may run on that cache for
  /// days. Defaulting to false would suddenly reject quantities the cashier
  /// entered fine yesterday, with no way to tell why. Permissive here is safe
  /// because the BACKEND is authoritative — it re-validates on sync and will
  /// reject anything genuinely illegal.
  static const bool defaultAllowDecimal = true;

  factory ProductUnit.fromJson(Map<String, dynamic> json) {
    return ProductUnit(
      id: _asInt(json['id']) ?? 0,
      name: (json['name'] as String?)?.trim() ?? '',
      shortName: (json['short_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['short_name'] as String).trim(),
      allowDecimal: parseBool(json['allow_decimal'], defaultAllowDecimal),
      isActive: parseBool(json['is_active'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'short_name': shortName,
        'allow_decimal': allowDecimal,
        'is_active': isActive,
      };

  ProductUnit copyWith({
    int? id,
    String? name,
    String? shortName,
    bool? allowDecimal,
    bool? isActive,
  }) {
    return ProductUnit(
      id: id ?? this.id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      allowDecimal: allowDecimal ?? this.allowDecimal,
      isActive: isActive ?? this.isActive,
    );
  }

  /// What to show beside a quantity field, e.g. "kg".
  String get label => shortName?.isNotEmpty == true ? shortName! : name;

  /// Tolerant boolean parsing.
  ///
  /// The API sends a real JSON boolean, but a value round-tripped through the
  /// local SQLite cache comes back as 1/0, and older payloads may carry
  /// "1"/"true". All of them have to mean the same thing, and a value that is
  /// absent or unrecognised falls back to [fallback] rather than throwing —
  /// a parse failure must never take the till offline.
  static bool parseBool(Object? value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v.isEmpty) return fallback;
      if (v == '1' || v == 'true' || v == 'yes') return true;
      if (v == '0' || v == 'false' || v == 'no') return false;
    }
    return fallback;
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ProductUnit &&
      other.id == id &&
      other.name == name &&
      other.shortName == shortName &&
      other.allowDecimal == allowDecimal &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, shortName, allowDecimal, isActive);

  @override
  String toString() => 'ProductUnit($id, $name, allowDecimal: $allowDecimal)';
}

/// The quantity contract for one product, resolved from whatever shape that
/// product arrived in.
///
/// Sale and purchase screens hold products as loose `Map<String, dynamic>`
/// (from the API, from the offline catalogue cache, or rebuilt from a queued
/// sale). This class is the one place that variety is dealt with.
class QuantityRule {
  final int? unitId;
  final String unitName;
  final bool allowDecimal;

  const QuantityRule({
    this.unitId,
    this.unitName = '',
    this.allowDecimal = ProductUnit.defaultAllowDecimal,
  });

  /// The rule for a product with no unit information at all.
  static const QuantityRule permissive = QuantityRule();

  /// Reads the rule out of a product map.
  ///
  /// Accepts, in order of preference:
  ///   * a nested `unit` object (what /products and /catalog return);
  ///   * flat `unit_allow_decimal` / `allow_decimal` columns (what the local
  ///     cache table stores once flattened).
  ///
  /// Anything unrecognised yields [permissive] — see
  /// [ProductUnit.defaultAllowDecimal] for why that direction.
  factory QuantityRule.fromProduct(Map<String, dynamic>? product) {
    if (product == null) return permissive;

    final nested = product['unit'];
    if (nested is Map) {
      final unit = ProductUnit.fromJson(Map<String, dynamic>.from(nested));
      return QuantityRule(
        unitId: unit.id == 0 ? null : unit.id,
        unitName: unit.name,
        allowDecimal: unit.allowDecimal,
      );
    }

    // Flattened cache row.
    final flat = product.containsKey('unit_allow_decimal')
        ? product['unit_allow_decimal']
        : product['allow_decimal'];
    if (flat != null) {
      return QuantityRule(
        unitId: ProductUnit._asInt(product['unit_id']),
        unitName: (product['unit_name'] as String?) ?? '',
        allowDecimal:
            ProductUnit.parseBool(flat, ProductUnit.defaultAllowDecimal),
      );
    }

    return QuantityRule(
      unitId: ProductUnit._asInt(product['unit_id']),
      unitName: (product['unit_name'] as String?) ?? '',
    );
  }

  factory QuantityRule.fromUnit(ProductUnit? unit) {
    if (unit == null) return permissive;
    return QuantityRule(
      unitId: unit.id,
      unitName: unit.name,
      allowDecimal: unit.allowDecimal,
    );
  }

  /// Number of decimal places the schema stores. Matches DECIMAL(18,4) on the
  /// backend; the whole-number test is performed at exactly this scale.
  static const int scale = 4;

  /// Whether [quantity] is mathematically a whole number at the stored scale.
  ///
  /// Rounding to the scale FIRST is what makes this correct. A quantity the
  /// cashier reached by tapping "+" repeatedly, or one recomputed from a line
  /// total, can arrive as 2.9999999999999996; a naive `q == q.truncate()`
  /// would reject it. Collapsing representation noise first means the test
  /// runs on the value that will actually be persisted — the same approach the
  /// Go backend uses, so client and server always agree.
  static bool isWhole(num quantity) {
    final q = quantity.toDouble();
    if (q.isNaN || q.isInfinite) return false;
    final factor = _pow10(scale);
    final scaled = (q * factor).roundToDouble() / factor;
    return scaled == scaled.truncateToDouble();
  }

  static double _pow10(int n) {
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  /// Whether this rule permits [quantity]. Sign is irrelevant.
  bool allows(num quantity) => allowDecimal || isWhole(quantity);

  /// The message to show when [allows] is false. Mirrors the backend wording so
  /// the cashier sees the same sentence whether the rejection came from the
  /// field, the cart, or the server.
  String get message => unitName.isEmpty
      ? 'Decimal quantity is not allowed for the selected product unit.'
      : 'Decimal quantity is not allowed for unit "$unitName".';

  /// Validates a raw text entry. Returns null when acceptable, otherwise the
  /// error to display. Empty input is left to the caller's required-check.
  String? validateText(String? text) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = num.tryParse(raw);
    if (parsed == null) return 'Enter a valid quantity.';
    return allows(parsed) ? null : message;
  }

  /// The step a +/- button should move by. Whole units cannot step by 0.5.
  double get step => allowDecimal ? 0.5 : 1;

  /// Formats a quantity for display: no trailing ".0" on whole units.
  String format(num quantity) {
    if (!allowDecimal || isWhole(quantity)) {
      return quantity.toDouble().truncateToDouble().toStringAsFixed(0);
    }
    var s = quantity.toDouble().toStringAsFixed(scale);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  @override
  bool operator ==(Object other) =>
      other is QuantityRule &&
      other.unitId == unitId &&
      other.unitName == unitName &&
      other.allowDecimal == allowDecimal;

  @override
  int get hashCode => Object.hash(unitId, unitName, allowDecimal);

  @override
  String toString() =>
      'QuantityRule(unit: $unitName, allowDecimal: $allowDecimal)';
}
