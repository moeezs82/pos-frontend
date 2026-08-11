import 'package:enterprise_pos/services/app_currency.dart' show AppCurrency;
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Dialog that renders a size × color matrix from a set of variant product
/// records belonging to one group. The cashier taps a cell to select that
/// specific variant product, which is then returned to the caller.
///
/// Usage:
/// ```dart
/// final picked = await showDialog<Map<String, dynamic>>(
///   context: context,
///   builder: (_) => VariantPickerDialog(
///     groupName: 'Classic T-Shirt',
///     variants: listOfProductMaps,
///   ),
/// );
/// if (picked != null) _addToCart(picked);
/// ```
///
/// Each element in [variants] is a raw product map as returned by the API
/// (or the offline catalog cache). Required keys:
///   id, name, price, variant_size (nullable), variant_color (nullable),
///   is_active (1/0 or bool).
class VariantPickerDialog extends StatelessWidget {
  final String groupName;
  final List<Map<String, dynamic>> variants;

  const VariantPickerDialog({
    super.key,
    required this.groupName,
    required this.variants,
  });

  @override
  Widget build(BuildContext context) {
    // Extract unique sizes and colors (preserving insertion order).
    final sizes = <String>[];
    final colors = <String>[];
    for (final v in variants) {
      final size = v['variant_size']?.toString() ?? '';
      final color = v['variant_color']?.toString() ?? '';
      if (size.isNotEmpty && !sizes.contains(size)) sizes.add(size);
      if (color.isNotEmpty && !colors.contains(color)) colors.add(color);
    }

    final hasSizes = sizes.isNotEmpty;
    final hasColors = colors.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: const BoxDecoration(
                color: AppTheme.navy,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      groupName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Matrix ──────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: hasSizes && hasColors
                    ? _buildMatrix(context, sizes, colors)
                    : _buildFlatList(context, variants),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Size × Color grid. Each cell is one variant; grey = inactive/out-of-stock.
  Widget _buildMatrix(
      BuildContext context, List<String> sizes, List<String> colors) {
    final colCount = colors.length;

    return Table(
      columnWidths: {
        // First column = size label
        0: const IntrinsicColumnWidth(),
        // Rest = color columns (equal width)
        for (var i = 1; i <= colCount; i++) i: const FlexColumnWidth(),
      },
      children: [
        // Header row: color labels
        TableRow(
          children: [
            const SizedBox.shrink(), // empty corner
            ...colors.map((c) => _headerCell(c)),
          ],
        ),
        // Data rows: one per size
        ...sizes.map((size) => TableRow(
              children: [
                // Row header: size label
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                  child: Text(
                    size,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppTheme.navy),
                  ),
                ),
                // One cell per color
                ...colors.map((color) {
                  final variant = _findVariant(size, color);
                  return _MatrixCell(
                    variant: variant,
                    onTap: variant != null && _isActive(variant)
                        ? () => Navigator.pop(context, variant)
                        : null,
                  );
                }),
              ],
            )),
      ],
    );
  }

  /// Flat list for groups that only use size OR only color (no matrix).
  Widget _buildFlatList(
      BuildContext context, List<Map<String, dynamic>> vList) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: vList.map((v) {
        final active = _isActive(v);
        final label = _variantLabel(v);
        final price = AppCurrency.format(v['price'] ?? 0);
        return _FlatChip(
          label: label,
          price: price,
          enabled: active,
          onTap: active ? () => Navigator.pop(context, v) : null,
        );
      }).toList(),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted),
      ),
    );
  }

  Map<String, dynamic>? _findVariant(String size, String color) {
    for (final v in variants) {
      if ((v['variant_size']?.toString() ?? '') == size &&
          (v['variant_color']?.toString() ?? '') == color) {
        return v;
      }
    }
    return null;
  }

  static bool _isActive(Map<String, dynamic> v) {
    return v['is_active'] == 1 || v['is_active'] == true;
  }

  static String _variantLabel(Map<String, dynamic> v) {
    final size = v['variant_size']?.toString() ?? '';
    final color = v['variant_color']?.toString() ?? '';
    final parts = [if (size.isNotEmpty) size, if (color.isNotEmpty) color];
    return parts.isEmpty ? v['name']?.toString() ?? '—' : parts.join(' / ');
  }
}

// ── Matrix cell ───────────────────────────────────────────────────────────────

class _MatrixCell extends StatelessWidget {
  final Map<String, dynamic>? variant;
  final VoidCallback? onTap;

  const _MatrixCell({this.variant, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (variant == null) {
      return Container(
        margin: const EdgeInsets.all(3),
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppTheme.border, style: BorderStyle.none),
        ),
        child: const Center(
          child: Text('—',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textMuted)),
        ),
      );
    }

    final active = onTap != null;
    final price = AppCurrency.format(variant!['price'] ?? 0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        height: 52,
        decoration: BoxDecoration(
          color: active ? Colors.white : AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? AppTheme.primary : AppTheme.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                price,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? AppTheme.navy : AppTheme.textMuted),
              ),
              if (!active)
                const Text('N/A',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Flat chip (size-only or color-only groups) ────────────────────────────────

class _FlatChip extends StatelessWidget {
  final String label;
  final String price;
  final bool enabled;
  final VoidCallback? onTap;

  const _FlatChip({
    required this.label,
    required this.price,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  enabled ? AppTheme.primary : AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: enabled ? AppTheme.navy : AppTheme.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              price,
              style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? AppTheme.primary
                      : AppTheme.textMuted),
            ),
            if (!enabled)
              const Text('Inactive',
                  style: TextStyle(
                      fontSize: 10, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
