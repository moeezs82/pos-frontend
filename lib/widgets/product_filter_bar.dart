import 'package:flutter/material.dart';
import 'package:enterprise_pos/theme/app_theme.dart';

/// One selectable value of a [ProductFilterBar] dropdown.
class FilterOption<T> {
  final T value;
  final String label;
  const FilterOption(this.value, this.label);
}

/// Sort keys understood by the product list endpoint.
///
/// `stock_desc`, `stock_asc`, `most_sold`, `least_sold`, `latest_sold`;
/// `null` is the server default order.
class ProductSortKeys {
  ProductSortKeys._();

  static const all = <String>[
    'stock_desc',
    'stock_asc',
    'most_sold',
    'least_sold',
    'latest_sold',
  ];

  /// `sort_by` request value for [key] (null = server default).
  static String? sortByOf(String? key) {
    switch (key) {
      case 'stock_desc':
      case 'stock_asc':
        return 'stock';
      case 'most_sold':
      case 'least_sold':
      case 'latest_sold':
        return key;
    }
    return null;
  }

  /// `sort_order` request value for [key].
  static String? sortOrderOf(String? key) {
    switch (key) {
      case 'stock_desc':
        return 'desc';
      case 'stock_asc':
        return 'asc';
    }
    return null;
  }

  static String labelOf(String? key) {
    switch (key) {
      case 'stock_desc':
        return 'Stock: High to Low';
      case 'stock_asc':
        return 'Stock: Low to High';
      case 'most_sold':
        return 'Most Sold';
      case 'least_sold':
        return 'Least Sold';
      case 'latest_sold':
        return 'Latest Sold';
    }
    return 'Default order';
  }

  static String hintOf(String? key) {
    switch (key) {
      case 'most_sold':
      case 'least_sold':
        return 'Based on the last 30 days of sales';
      case 'latest_sold':
        return 'Sold in the last 24 hours first, newest sale on top';
    }
    return '';
  }

  static IconData iconOf(String? key) {
    switch (key) {
      case 'stock_desc':
        return Icons.arrow_downward_rounded;
      case 'stock_asc':
        return Icons.arrow_upward_rounded;
      case 'most_sold':
        return Icons.trending_up_rounded;
      case 'least_sold':
        return Icons.trending_down_rounded;
      case 'latest_sold':
        return Icons.history_rounded;
    }
    return Icons.swap_vert_rounded;
  }
}

/// Compact filter + sort bar for the sale / purchase product browser.
///
/// Collapsed it is a single slim row (Filters button with an active-count
/// badge, Sort menu, a one-line summary of what is applied, and Clear), so the
/// product grid keeps almost all of the panel. The four dropdowns open in a
/// drawer below the row only when the user asks for them.
class ProductFilterBar extends StatefulWidget {
  final List<FilterOption<int?>> categories;
  final List<FilterOption<int?>> brands;
  final List<FilterOption<int?>> vendors;
  final int? categoryId;
  final int? brandId;
  final int? vendorId;
  final String? stockStatus;
  final String? sortKey;
  final bool initialExpanded;

  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<int?> onBrandChanged;
  final ValueChanged<int?> onVendorChanged;
  final ValueChanged<String?> onStockStatusChanged;
  final ValueChanged<String?> onSortChanged;
  final VoidCallback onClear;
  final ValueChanged<bool>? onExpandedChanged;

  const ProductFilterBar({
    super.key,
    required this.categories,
    required this.brands,
    required this.vendors,
    required this.categoryId,
    required this.brandId,
    required this.vendorId,
    required this.stockStatus,
    required this.sortKey,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onVendorChanged,
    required this.onStockStatusChanged,
    required this.onSortChanged,
    required this.onClear,
    this.initialExpanded = false,
    this.onExpandedChanged,
  });

  @override
  State<ProductFilterBar> createState() => _ProductFilterBarState();
}

class _ProductFilterBarState extends State<ProductFilterBar> {
  static const _stockOptions = <FilterOption<String?>>[
    FilterOption<String?>(null, 'All Stock'),
    FilterOption<String?>('in_stock', 'In Stock'),
    FilterOption<String?>('low_stock', 'Low Stock'),
    FilterOption<String?>('out_of_stock', 'Out of Stock'),
  ];

  late bool _expanded = widget.initialExpanded;

  int get _activeFilterCount =>
      (widget.categoryId != null ? 1 : 0) +
      (widget.brandId != null ? 1 : 0) +
      (widget.vendorId != null ? 1 : 0) +
      (widget.stockStatus != null ? 1 : 0);

  bool get _anyActive => _activeFilterCount > 0 || widget.sortKey != null;

  String? _labelFor(List<FilterOption<int?>> options, int? id) {
    if (id == null) return null;
    for (final o in options) {
      if (o.value == id) return o.label;
    }
    return null;
  }

  String get _summary {
    final parts = <String>[
      if (_labelFor(widget.categories, widget.categoryId) != null)
        _labelFor(widget.categories, widget.categoryId)!,
      if (_labelFor(widget.brands, widget.brandId) != null)
        _labelFor(widget.brands, widget.brandId)!,
      if (_labelFor(widget.vendors, widget.vendorId) != null)
        _labelFor(widget.vendors, widget.vendorId)!,
      if (widget.stockStatus != null)
        _stockOptions
            .firstWhere(
              (o) => o.value == widget.stockStatus,
              orElse: () => const FilterOption<String?>(null, ''),
            )
            .label,
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(' · ');
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final count = _activeFilterCount;
    final summary = _summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _BarButton(
                icon: Icons.tune_rounded,
                label: 'Filters',
                badge: count > 0 ? '$count' : null,
                active: _expanded || count > 0,
                trailing: _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                tooltip: _expanded ? 'Hide filters' : 'Show filters',
                onTap: _toggle,
              ),
              const SizedBox(width: 6),
              _SortMenu(
                selected: widget.sortKey,
                onChanged: widget.onSortChanged,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: !_expanded && summary.isNotEmpty
                    ? Tooltip(
                        message: summary,
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF666666),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_anyActive) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Clear all filters and sorting',
                  child: InkWell(
                    onTap: widget.onClear,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.filter_alt_off_rounded,
                        size: 16,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildDropdowns(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdowns() {
    final category = _BarDropdown<int?>(
      value: widget.categoryId,
      allLabel: 'All Categories',
      options: widget.categories,
      onChanged: widget.onCategoryChanged,
    );
    final brand = _BarDropdown<int?>(
      value: widget.brandId,
      allLabel: 'All Brands',
      options: widget.brands,
      onChanged: widget.onBrandChanged,
    );
    final vendor = _BarDropdown<int?>(
      value: widget.vendorId,
      allLabel: 'All Vendors',
      options: widget.vendors,
      onChanged: widget.onVendorChanged,
    );
    final stock = _BarDropdown<String?>(
      value: widget.stockStatus,
      allLabel: 'All Stock',
      options: const [
        FilterOption<String?>('in_stock', 'In Stock'),
        FilterOption<String?>('low_stock', 'Low Stock'),
        FilterOption<String?>('out_of_stock', 'Out of Stock'),
      ],
      onChanged: widget.onStockStatusChanged,
    );
    return LayoutBuilder(
      builder: (context, c) {
        // Wide panel: one row of four. Narrow panel: two rows of two.
        if (c.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: category),
              const SizedBox(width: 6),
              Expanded(child: brand),
              const SizedBox(width: 6),
              Expanded(child: vendor),
              const SizedBox(width: 6),
              Expanded(child: stock),
            ],
          );
        }
        return Column(
          children: [
            Row(children: [
              Expanded(child: category),
              const SizedBox(width: 6),
              Expanded(child: brand),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: vendor),
              const SizedBox(width: 6),
              Expanded(child: stock),
            ]),
          ],
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool active;
  final IconData? trailing;
  final String tooltip;
  final VoidCallback onTap;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.badge,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppTheme.primary : const Color(0xFF333333);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary.withOpacity(.08) : Colors.white,
            border: Border.all(
              color: active ? AppTheme.primary : const Color(0xFFCCCCCC),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _SortMenu({required this.selected, required this.onChanged});

  // PopupMenuButton cannot return null for "default", so use a sentinel.
  static const _defaultKey = '__default__';

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    final fg = active ? AppTheme.primary : const Color(0xFF333333);
    return PopupMenuButton<String>(
      tooltip: 'Sort products',
      position: PopupMenuPosition.under,
      onSelected: (key) => onChanged(key == _defaultKey ? null : key),
      itemBuilder: (context) => [
        for (final key in <String?>[null, ...ProductSortKeys.all])
          PopupMenuItem<String>(
            value: key ?? _defaultKey,
            height: 38,
            child: Row(
              children: [
                Icon(
                  ProductSortKeys.iconOf(key),
                  size: 16,
                  color: key == selected
                      ? AppTheme.primary
                      : const Color(0xFF555555),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ProductSortKeys.labelOf(key),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: key == selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (ProductSortKeys.hintOf(key).isNotEmpty)
                        Text(
                          ProductSortKeys.hintOf(key),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF777777),
                          ),
                        ),
                    ],
                  ),
                ),
                if (key == selected)
                  const Icon(Icons.check_rounded,
                      size: 16, color: AppTheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(.08) : Colors.white,
          border: Border.all(
            color: active ? AppTheme.primary : const Color(0xFFCCCCCC),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ProductSortKeys.iconOf(selected), size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              active ? ProductSortKeys.labelOf(selected) : 'Sort',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

class _BarDropdown<T> extends StatelessWidget {
  final T value;
  final String allLabel;
  final List<FilterOption<T>> options;
  final ValueChanged<T?> onChanged;

  const _BarDropdown({
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // A remembered value can outlive its option (list still loading, or the
    // category was deleted). Show "All" instead of failing the dropdown.
    final known = value == null || options.any((o) => o.value == value);
    final T? effective = known ? value : null;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: effective != null ? AppTheme.primary : const Color(0xFFCCCCCC),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: effective,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF666666),
          ),
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF333333),
            fontWeight: FontWeight.w600,
          ),
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text(allLabel, overflow: TextOverflow.ellipsis),
            ),
            for (final o in options)
              if (o.value != null)
                DropdownMenuItem<T?>(
                  value: o.value,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
