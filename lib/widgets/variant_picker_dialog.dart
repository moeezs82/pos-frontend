import 'package:enterprise_pos/services/app_currency.dart' show AppCurrency;
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// POS-first selector for a variable-product family.
///
/// [variants] always contains real product rows. The dialog only chooses one
/// row and returns it; sale payloads, offline queueing, stock and accounting
/// continue to use that child's existing product_id.
class VariantPickerDialog extends StatefulWidget {
  final String groupName;
  final List<Map<String, dynamic>> variants;
  final String customerType;

  const VariantPickerDialog({
    super.key,
    required this.groupName,
    required this.variants,
    this.customerType = 'retail',
  });

  @override
  State<VariantPickerDialog> createState() => _VariantPickerDialogState();
}

class _VariantPickerDialogState extends State<VariantPickerDialog> {
  String? _selectedColor;

  List<Map<String, dynamic>> get _activeVariants => widget.variants
      .where(_isActive)
      .toList(growable: false);

  List<String> get _colors {
    final values = <String>[];
    for (final variant in _activeVariants) {
      final value = _text(variant['variant_color']);
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values;
  }

  List<String> get _sizes {
    final values = <String>[];
    for (final variant in _activeVariants) {
      final value = _text(variant['variant_size']);
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values;
  }

  @override
  void initState() {
    super.initState();
    final colors = _colors;
    if (colors.isNotEmpty) _selectedColor = colors.first;
  }

  @override
  Widget build(BuildContext context) {
    final variants = _activeVariants;
    final colors = _colors;
    final sizes = _sizes;
    final useColorSizePicker = variants.isNotEmpty &&
        variants.every((v) =>
            _text(v['variant_size']).isNotEmpty &&
            _text(v['variant_color']).isNotEmpty);
    final offline = variants.isNotEmpty && variants.every((v) => v['_offline'] == true);

    final visibleVariants = useColorSizePicker && _selectedColor != null
        ? variants
            .where((v) => _text(v['variant_color']) == _selectedColor)
            .toList(growable: false)
        : variants;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, variants.length, offline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (useColorSizePicker) ...[
                      _sectionLabel(colors.length == 1 ? 'Color' : 'Choose color'),
                      const SizedBox(height: 9),
                      if (colors.length == 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _StaticAttributeChip(
                            icon: Icons.palette_outlined,
                            label: colors.first,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: colors.map((color) {
                            final selected = color == _selectedColor;
                            final count = variants
                                .where((v) => _text(v['variant_color']) == color)
                                .length;
                            return ChoiceChip(
                              selected: selected,
                              onSelected: (_) => setState(() => _selectedColor = color),
                              avatar: Icon(
                                Icons.circle,
                                size: 9,
                                color: selected ? AppTheme.primary : AppTheme.borderStrong,
                              ),
                              label: Text('$color  ·  $count'),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 20),
                    ],
                    _sectionLabel(
                      useColorSizePicker ? 'Choose size' : 'Choose variant',
                    ),
                    const SizedBox(height: 9),
                    _buildVariantGrid(
                      context,
                      visibleVariants,
                      sizeOnlyLabel: useColorSizePicker,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            offline
                                ? 'Using the last synced offline catalog. The selected SKU will sync as its normal product when connectivity returns.'
                                : 'Select the exact variant to add it to the sale.',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    int variantCount,
    bool offline,
  ) {
    final range = _priceRange(_activeVariants);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: AppTheme.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 7,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      variantCount == 1 ? '1 variant' : '$variantCount variants',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (range.isNotEmpty) ...[
                      const Text('•', style: TextStyle(color: AppTheme.borderStrong)),
                      Text(
                        range,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                    if (SalePricing.isWholesale(widget.customerType)) ...[
                      const Text('•', style: TextStyle(color: AppTheme.borderStrong)),
                      const Text(
                        'Wholesale pricing',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (offline) ...[
                      const Text('•', style: TextStyle(color: AppTheme.borderStrong)),
                      const Text(
                        'Offline catalog',
                        style: TextStyle(
                          color: AppTheme.warning,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantGrid(
    BuildContext context,
    List<Map<String, dynamic>> variants, {
    required bool sizeOnlyLabel,
  }) {
    if (variants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No active variants are available for this selection.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 560
            ? (width - 20) / 3
            : width >= 380
                ? (width - 10) / 2
                : width;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: variants.map((variant) {
            final size = _text(variant['variant_size']);
            final color = _text(variant['variant_color']);
            final label = sizeOnlyLabel && size.isNotEmpty
                ? size
                : _variantChoiceLabel(variant);
            return SizedBox(
              width: itemWidth,
              child: _VariantOptionCard(
                label: label,
                secondary: sizeOnlyLabel && color.isNotEmpty && _colors.length <= 1
                    ? color
                    : null,
                price: AppCurrency.format(
                  SalePricing.effectiveProductPrice(
                    variant,
                    customerType: widget.customerType,
                  ),
                ),
                stock: _stockQuantity(variant),
                onTap: () => Navigator.pop(context, variant),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.navy,
        fontSize: 12.5,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  static bool _isActive(Map<String, dynamic> variant) {
    final raw = variant['is_active'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw.toString().trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';


  static String _variantChoiceLabel(Map<String, dynamic> variant) {
    final size = _text(variant['variant_size']);
    final color = _text(variant['variant_color']);
    final parts = <String>[
      if (size.isNotEmpty) size,
      if (color.isNotEmpty) color,
    ];
    return parts.isEmpty ? _fallbackVariantLabel(variant) : parts.join(' • ');
  }
  static String _fallbackVariantLabel(Map<String, dynamic> variant) {
    final name = _text(variant['name']);
    return name.isEmpty ? 'Variant' : name;
  }

  static double? _stockQuantity(Map<String, dynamic> variant) {
    dynamic raw = variant['branch_stock'] ??
        variant['stock'] ??
        variant['quantity_in_stock'];
    if (raw is Map) {
      raw = raw['quantity'] ?? raw['qty'] ?? raw['in_stock'];
    }
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  String _priceRange(List<Map<String, dynamic>> variants) {
    final prices = variants
        .map((v) => SalePricing.effectiveProductPrice(
              v,
              customerType: widget.customerType,
            ))
        .toList();
    if (prices.isEmpty) return '';
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    if ((max - min).abs() < 0.000001) return AppCurrency.format(min);
    return '${AppCurrency.format(min)} – ${AppCurrency.format(max)}';
  }
}

class _StaticAttributeChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StaticAttributeChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primary.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantOptionCard extends StatelessWidget {
  final String label;
  final String? secondary;
  final String price;
  final double? stock;
  final VoidCallback onTap;

  const _VariantOptionCard({
    required this.label,
    required this.price,
    required this.onTap,
    this.secondary,
    this.stock,
  });

  @override
  Widget build(BuildContext context) {
    final stockText = stock == null
        ? null
        : '${_compactQty(stock!)} in stock';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderStrong),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (secondary != null && secondary!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        secondary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (stockText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        stockText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (secondary != null && secondary!.isNotEmpty && stockText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        stockText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _compactQty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}
