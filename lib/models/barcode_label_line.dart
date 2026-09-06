/// Composable barcode label design.
///
/// A barcode label used to be four fixed booleans printed in a hardcoded
/// order. A branch now describes its own label as an ordered list of lines,
/// each naming what it prints, the branch's own prefix word for it, and how
/// big it should be relative to the other lines.
///
/// Nothing in here is financial. The discount and sale price lines are derived
/// at print time from the product's own `discount` / `discount_type`, so a
/// printed label can never disagree with what the register actually charges.
library;

/// What a single label line prints.
enum BarcodeLabelField {
  shopName('shop_name', 'Shop name', 'Your branch name from Printer Settings'),
  productName('product_name', 'Product name', 'Product or product family name'),
  variantDetails('variant_details', 'Variant details', 'For example "Black / M"'),
  price('price', 'Price', 'The product price before any discount'),
  discount('discount', 'Discount', 'Only prints when the product has a discount'),
  salePrice('sale_price', 'Sale price', 'Price after the discount, worked out at print time'),
  barcode('barcode', 'Barcode symbol', 'The scannable bars'),
  barcodeValue('barcode_value', 'Barcode number', 'The digits printed under the bars'),
  sku('sku', 'SKU', 'The product stock keeping unit'),
  customText('custom_text', 'Custom text', 'A fixed line you type once, printed on every label');

  const BarcodeLabelField(this.wire, this.title, this.hint);

  /// The value stored in `printer_settings.barcode_label_lines`.
  final String wire;
  final String title;
  final String hint;

  /// This line draws the Code 128 symbol rather than a run of text.
  bool get isGraphic => this == BarcodeLabelField.barcode;

  /// A prefix word (for example "MRP:") makes sense in front of this line.
  bool get supportsLabelWord =>
      this != BarcodeLabelField.barcode && this != BarcodeLabelField.shopName;

  /// `custom_text` carries its whole content in the label word, so an empty
  /// label word means the line has nothing to print.
  bool get labelWordIsContent => this == BarcodeLabelField.customText;

  static BarcodeLabelField? fromWire(String? value) {
    final wire = (value ?? '').trim();
    for (final field in BarcodeLabelField.values) {
      if (field.wire == wire) return field;
    }
    return null;
  }
}

/// Relative text size for one line. The renderer treats these as weights, not
/// absolute point sizes: every line is scaled down together so the whole design
/// fits whatever physical label the branch configured.
enum BarcodeLabelTextSize {
  small('small', 'Small'),
  normal('normal', 'Normal'),
  large('large', 'Large');

  const BarcodeLabelTextSize(this.wire, this.title);

  final String wire;
  final String title;

  static BarcodeLabelTextSize fromWire(String? value) {
    final wire = (value ?? '').trim();
    for (final size in BarcodeLabelTextSize.values) {
      if (size.wire == wire) return size;
    }
    return BarcodeLabelTextSize.normal;
  }
}

class BarcodeLabelLine {
  final BarcodeLabelField field;

  /// The branch's own prefix word, for example "MRP:" or "قیمت:". Free text so
  /// a shop can label the line in whatever language its customers read.
  final String label;
  final bool enabled;
  final BarcodeLabelTextSize size;

  const BarcodeLabelLine({
    required this.field,
    this.label = '',
    this.enabled = true,
    this.size = BarcodeLabelTextSize.normal,
  });

  BarcodeLabelLine copyWith({
    BarcodeLabelField? field,
    String? label,
    bool? enabled,
    BarcodeLabelTextSize? size,
  }) =>
      BarcodeLabelLine(
        field: field ?? this.field,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        size: size ?? this.size,
      );

  Map<String, dynamic> toJson() => {
        'field': field.wire,
        'label': label,
        'enabled': enabled,
        'size': size.wire,
      };

  /// Returns null for an unrecognised field so a label designed by a NEWER
  /// client simply drops the lines this build does not understand instead of
  /// refusing to print at all.
  static BarcodeLabelLine? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final field = BarcodeLabelField.fromWire(raw['field']?.toString());
    if (field == null) return null;
    return BarcodeLabelLine(
      field: field,
      label: (raw['label'] ?? '').toString(),
      enabled: raw['enabled'] == null || raw['enabled'] == true || raw['enabled'] == 1,
      size: BarcodeLabelTextSize.fromWire(raw['size']?.toString()),
    );
  }

  static List<BarcodeLabelLine> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final out = <BarcodeLabelLine>[];
    for (final entry in raw) {
      final line = BarcodeLabelLine.fromJson(entry);
      if (line != null) out.add(line);
    }
    return out;
  }

  /// The design a branch gets when it has never opened the label builder.
  ///
  /// This reproduces the label CounterIQ printed before the builder existed —
  /// name, variant, bars, digits, price — so upgrading a branch does not
  /// silently change what comes out of its printer. `legacyShow*` carries the
  /// branch's existing four booleans across.
  static List<BarcodeLabelLine> fromLegacyFlags({
    required bool showName,
    required bool showVariantDetails,
    required bool showValue,
    required bool showPrice,
  }) =>
      [
        BarcodeLabelLine(
          field: BarcodeLabelField.productName,
          enabled: showName,
        ),
        BarcodeLabelLine(
          field: BarcodeLabelField.variantDetails,
          enabled: showVariantDetails,
          size: BarcodeLabelTextSize.small,
        ),
        const BarcodeLabelLine(field: BarcodeLabelField.barcode),
        BarcodeLabelLine(
          field: BarcodeLabelField.barcodeValue,
          enabled: showValue,
          size: BarcodeLabelTextSize.small,
        ),
        BarcodeLabelLine(
          field: BarcodeLabelField.price,
          enabled: showPrice,
          size: BarcodeLabelTextSize.large,
        ),
      ];

  /// The four legacy booleans implied by a design, so an older Flutter client
  /// reading the same branch during a rolling update still prints sensibly.
  static bool legacyFlag(List<BarcodeLabelLine> lines, BarcodeLabelField field) {
    for (final line in lines) {
      if (line.field == field) return line.enabled;
    }
    return false;
  }
}
