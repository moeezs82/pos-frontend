import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/services/app_currency.dart' show AppCurrency;
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/quick_variant_create_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum VariantPickerMode { sale, purchase }

class TransactionVariantSelection {
  final Map<String, dynamic> product;
  final double quantity;

  const TransactionVariantSelection({
    required this.product,
    required this.quantity,
  });
}

class VariantPickerResult {
  final List<TransactionVariantSelection> selections;
  final bool catalogChanged;

  const VariantPickerResult({
    this.selections = const [],
    this.catalogChanged = false,
  });
}

/// Shared transaction-first selector for a variable-product family.
///
/// Sale and Purchase both use this dialog so variant UX cannot drift between
/// transaction types. Every selected row is still a real child product; sale
/// and purchase payloads continue to use the existing product_id contract.
class VariantPickerDialog extends StatefulWidget {
  final int groupId;
  final String groupName;
  final List<Map<String, dynamic>> variants;
  final VariantPickerMode mode;
  final String token;
  final String customerType;
  final bool canCreateVariant;
  final Map<int, double> existingCartQuantities;

  const VariantPickerDialog({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.variants,
    required this.mode,
    required this.token,
    this.customerType = 'retail',
    this.canCreateVariant = false,
    this.existingCartQuantities = const <int, double>{},
  });

  @override
  State<VariantPickerDialog> createState() => _VariantPickerDialogState();
}

class _VariantPickerDialogState extends State<VariantPickerDialog> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final Map<int, double> _addQuantities = <int, double>{};

  late final ProductGroupService _groupService;

  List<Map<String, dynamic>> _variants = <Map<String, dynamic>>[];
  String _search = '';
  String? _selectedColor;
  bool _catalogChanged = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _groupService = ProductGroupService(token: widget.token);
    _variants = widget.variants
        .where(_isActive)
        .map((v) => Map<String, dynamic>.from(v))
        .toList(growable: false);
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next != _search && mounted) setState(() => _search = next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _activeVariants =>
      _variants.where(_isActive).toList(growable: false);

  bool get _offlineOnly => _activeVariants.isNotEmpty &&
      _activeVariants.every((v) => v['_offline'] == true);

  bool get _canCreateNow => widget.canCreateVariant && !_offlineOnly;

  List<String> get _colors {
    final values = <String>[];
    for (final variant in _activeVariants) {
      final value = _text(variant['variant_color']);
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<Map<String, dynamic>> get _visibleVariants {
    final q = _search.toLowerCase();
    return _activeVariants.where((variant) {
      if (_selectedColor != null &&
          _text(variant['variant_color']) != _selectedColor) {
        return false;
      }
      if (q.isEmpty) return true;
      final haystack = <String>[
        _text(variant['variant_size']),
        _text(variant['variant_color']),
        _text(variant['sku']),
        _text(variant['barcode']),
        _text(variant['name']),
        _text(variant['secondary_name']),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList(growable: false);
  }

  int get _selectedVariantCount =>
      _addQuantities.values.where((q) => q > 0).length;

  double get _selectedQuantity => _addQuantities.values
      .where((q) => q > 0)
      .fold<double>(0, (sum, q) => sum + q);

  Future<bool> _refreshVariants({int? autoSelectProductId}) async {
    setState(() => _refreshing = true);
    try {
      final data = await _groupService.showGroup(widget.groupId);
      final raw = data['products'] as List? ?? const [];
      final fresh = raw
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .where(_isActive)
          .toList();
      if (!mounted) return false;
      setState(() {
        if (fresh.isNotEmpty) _variants = fresh;
        if (autoSelectProductId != null) {
          _addQuantities[autoSelectProductId] = 1;
        }
      });
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _createVariant() async {
    if (!_canCreateNow) return;
    final created = await showDialog<QuickVariantCreateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuickVariantCreateDialog(
        groupId: widget.groupId,
        groupName: widget.groupName,
        purchaseMode: widget.mode == VariantPickerMode.purchase,
        token: widget.token,
      ),
    );
    if (created == null || !mounted) return;

    _catalogChanged = true;
    final id = _asInt(created.product['id']);
    if (id == null || id <= 0) {
      await _refreshVariants();
      return;
    }

    // Prefer the authoritative group payload so stock/image/relations are
    // immediately identical to a normal catalog refresh. If that refresh
    // fails, retain the API-created product locally and still let the operator
    // continue the transaction without creating the variant twice.
    final refreshed = await _refreshVariants(autoSelectProductId: id);
    if (!refreshed && mounted) {
      setState(() {
        _variants = <Map<String, dynamic>>[
          ..._variants.where((v) => _asInt(v['id']) != id),
          Map<String, dynamic>.from(created.product),
        ];
        _addQuantities[id] = 1;
      });
      AppFeedback.warning(
        context,
        'Variant created and selected. The family list will fully refresh on the next catalog request.',
      );
    }

    if (created.imageUploadFailed && mounted) {
      AppFeedback.warning(
        context,
        'Variant created and selected, but its image could not be uploaded. The image can be retried from Product Management.',
      );
    }
  }

  void _changeQuantity(int productId, double delta) {
    final current = _addQuantities[productId] ?? 0;
    final next = (current + delta).clamp(0, 999999).toDouble();
    setState(() {
      if (next <= 0) {
        _addQuantities.remove(productId);
      } else {
        _addQuantities[productId] = next;
      }
    });
  }

  void _applySelection() {
    final selected = <TransactionVariantSelection>[];
    for (final variant in _activeVariants) {
      final id = _asInt(variant['id']);
      if (id == null) continue;
      final qty = _addQuantities[id] ?? 0;
      if (qty <= 0) continue;
      selected.add(TransactionVariantSelection(
        product: Map<String, dynamic>.from(variant),
        quantity: qty,
      ));
    }
    Navigator.pop(
      context,
      VariantPickerResult(
        selections: selected,
        catalogChanged: _catalogChanged,
      ),
    );
  }

  void _closeWithoutAdding() {
    Navigator.pop(
      context,
      VariantPickerResult(catalogChanged: _catalogChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final variants = _activeVariants;
    final colors = _colors;
    final totalStock = _totalStock(variants);
    final range = _priceOrCostRange(variants);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _selectedQuantity > 0 ? _applySelection : () {},
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(
                  variantCount: variants.length,
                  totalStock: totalStock,
                  range: range,
                ),
                _buildControls(colors),
                _buildColumnHeader(),
                Expanded(
                  child: _refreshing
                      ? const Center(child: CircularProgressIndicator())
                      : _buildVariantRows(),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required int variantCount,
    required double? totalStock,
    required String range,
  }) {
    final transactionLabel =
        widget.mode == VariantPickerMode.sale ? 'Sale' : 'Purchase';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 15),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
              Icons.account_tree_outlined,
              color: AppTheme.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
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
                    ),
                    const SizedBox(width: 8),
                    _smallTag(transactionLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 7,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '$variantCount variant${variantCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('•',
                        style: TextStyle(color: AppTheme.borderStrong)),
                    Text(
                      totalStock == null
                          ? 'Stock unavailable'
                          : 'Total stock ${_compactQty(totalStock)}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (range.isNotEmpty) ...[
                      const Text('•',
                          style: TextStyle(color: AppTheme.borderStrong)),
                      Text(
                        '${widget.mode == VariantPickerMode.sale ? 'Price' : 'Cost'} $range',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                    if (widget.mode == VariantPickerMode.sale &&
                        SalePricing.isWholesale(widget.customerType)) ...[
                      const Text('•',
                          style: TextStyle(color: AppTheme.borderStrong)),
                      const Text(
                        'Wholesale pricing',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (_offlineOnly) ...[
                      const Text('•',
                          style: TextStyle(color: AppTheme.borderStrong)),
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
            onPressed: _closeWithoutAdding,
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(List<String> colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      color: AppTheme.surfaceSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search size, color, SKU or barcode...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close_rounded, size: 17),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                  ),
                ),
              ),
              if (widget.canCreateVariant) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _canCreateNow ? _createVariant : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('New Variant'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(128, 43),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (widget.canCreateVariant && !_canCreateNow) ...[
            const SizedBox(height: 7),
            const Text(
              'Creating catalog variants requires an online connection.',
              style: TextStyle(
                color: AppTheme.warning,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (colors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                ChoiceChip(
                  selected: _selectedColor == null,
                  onSelected: (_) => setState(() => _selectedColor = null),
                  label: Text('All · ${_activeVariants.length}'),
                ),
                ...colors.map((color) {
                  final count = _activeVariants
                      .where((v) => _text(v['variant_color']) == color)
                      .length;
                  return ChoiceChip(
                    selected: _selectedColor == color,
                    onSelected: (_) => setState(() => _selectedColor = color),
                    label: Text('$color · $count'),
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnHeader() {
    final amountLabel = widget.mode == VariantPickerMode.sale ? 'PRICE' : 'COST';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 58, child: Text('IMAGE', style: _headerStyle)),
          const SizedBox(width: 10),
          const Expanded(flex: 4, child: Text('VARIANT', style: _headerStyle)),
          const Expanded(flex: 3, child: Text('SKU / BARCODE', style: _headerStyle)),
          const SizedBox(width: 100, child: Text('STOCK', style: _headerStyle)),
          SizedBox(width: 125, child: Text(amountLabel, style: _headerStyle)),
          const SizedBox(width: 124, child: Text('ADD QTY', style: _headerStyle)),
        ],
      ),
    );
  }

  Widget _buildVariantRows() {
    final variants = _visibleVariants;
    if (variants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 34, color: AppTheme.textMuted),
              const SizedBox(height: 8),
              const Text(
                'No variants match this filter.',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_canCreateNow) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _createVariant,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Create New Variant'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: variants.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.border),
      itemBuilder: (context, index) => _buildVariantRow(variants[index]),
    );
  }

  Widget _buildVariantRow(Map<String, dynamic> variant) {
    final id = _asInt(variant['id']);
    final size = _text(variant['variant_size']);
    final color = _text(variant['variant_color']);
    final variantName = <String>[
      if (size.isNotEmpty) size,
      if (color.isNotEmpty) color,
    ].join(' · ');
    final displayName = variantName.isEmpty
        ? (_text(variant['name']).isEmpty ? 'Variant' : _text(variant['name']))
        : variantName;
    final secondary = _text(variant['secondary_name']);
    final sku = _text(variant['sku']);
    final barcode = _text(variant['barcode']);
    final stock = _stockQuantity(variant);
    final imageUrl = _text(variant['image_url']);
    final addQty = id == null ? 0.0 : (_addQuantities[id] ?? 0);
    final inCart = id == null ? 0.0 : (widget.existingCartQuantities[id] ?? 0);
    final amount = widget.mode == VariantPickerMode.sale
        ? SalePricing.effectiveProductPrice(
            variant,
            customerType: widget.customerType,
          )
        : _purchaseCost(variant);

    return Container(
      color: addQty > 0 ? AppTheme.primarySoft.withOpacity(.35) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: _variantImage(imageUrl),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (inCart > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Already in ${widget.mode == VariantPickerMode.sale ? 'sale' : 'purchase'}: ${_compactQty(inCart)}',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sku.isEmpty ? '—' : sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (barcode.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    barcode,
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
          SizedBox(width: 100, child: _stockBadge(stock)),
          SizedBox(
            width: 125,
            child: Text(
              AppCurrency.format(amount),
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 124,
            child: id == null
                ? const Text('—')
                : _quantityControl(
                    addQty,
                    onMinus: () => _changeQuantity(id, -1),
                    onPlus: () => _changeQuantity(id, 1),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _variantImage(String imageUrl) {
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.border),
      ),
      child: imageUrl.isEmpty
          ? const Icon(Icons.inventory_2_outlined,
              color: AppTheme.textMuted, size: 21)
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ),
    );
  }

  Widget _stockBadge(double? stock) {
    if (stock == null) {
      return const Text(
        '—',
        style: TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final color = stock <= 0
        ? AppTheme.danger
        : stock <= 5
            ? AppTheme.warning
            : AppTheme.success;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(.28)),
        ),
        child: Text(
          _compactQty(stock),
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _quantityControl(
    double quantity, {
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    if (quantity <= 0) {
      return OutlinedButton.icon(
        onPressed: onPlus,
        icon: const Icon(Icons.add_rounded, size: 15),
        label: const Text('Add'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(92, 34),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          foregroundColor: AppTheme.primary,
          side: const BorderSide(color: AppTheme.borderStrong),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(.35)),
      ),
      child: Row(
        children: [
          _qtyButton(Icons.remove_rounded, onMinus),
          Expanded(
            child: Text(
              _compactQty(quantity),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.navy,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          _qtyButton(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 31,
        height: 34,
        child: Icon(icon, size: 16, color: AppTheme.primary),
      ),
    );
  }

  Widget _buildFooter() {
    final target = widget.mode == VariantPickerMode.sale ? 'Sale' : 'Purchase';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 3,
              children: [
                Text(
                  'Selected: $_selectedVariantCount variant${_selectedVariantCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Add quantity: ${_compactQty(_selectedQuantity)}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _closeWithoutAdding,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 9),
          FilledButton.icon(
            onPressed: _selectedQuantity > 0 ? _applySelection : null,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
            label: Text(
              _selectedQuantity > 0
                  ? 'Add ${_compactQty(_selectedQuantity)} to $target'
                  : 'Add to $target',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(172, 42),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }

  String _priceOrCostRange(List<Map<String, dynamic>> variants) {
    final values = variants
        .map((v) => widget.mode == VariantPickerMode.sale
            ? SalePricing.effectiveProductPrice(
                v,
                customerType: widget.customerType,
              )
            : _purchaseCost(v))
        .toList();
    if (values.isEmpty) return '';
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    if ((max - min).abs() < .000001) return AppCurrency.format(min);
    return '${AppCurrency.format(min)} – ${AppCurrency.format(max)}';
  }

  static double? _totalStock(List<Map<String, dynamic>> variants) {
    var total = 0.0;
    for (final variant in variants) {
      final stock = _stockQuantity(variant);
      if (stock == null) return null;
      total += stock;
    }
    return total;
  }

  static double _purchaseCost(Map<String, dynamic> product) {
    for (final key in const [
      'purchase_price',
      'cost_price',
      'tp',
      'unit_price',
      'price',
    ]) {
      final value = _asDouble(product[key]);
      if (value != null) return value;
    }
    return 0;
  }

  static bool _isActive(Map<String, dynamic> variant) {
    final raw = variant['is_active'];
    if (raw == null) return true;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw.toString().trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  static double? _stockQuantity(Map<String, dynamic> variant) {
    dynamic raw = variant['branch_stock'] ??
        variant['stock'] ??
        variant['quantity_in_stock'];
    if (raw is Map) {
      raw = raw['quantity'] ?? raw['qty'] ?? raw['in_stock'];
    }
    if (raw == null && variant['stocks'] is List) {
      final stocks = variant['stocks'] as List;
      if (stocks.isNotEmpty && stocks.first is Map) {
        final first = stocks.first as Map;
        raw = first['quantity'] ?? first['qty'] ?? first['in_stock'];
      }
    }
    return _asDouble(raw);
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _compactQty(double value) {
    if ((value - value.roundToDouble()).abs() < .000001) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}

const TextStyle _headerStyle = TextStyle(
  color: AppTheme.textMuted,
  fontSize: 9.5,
  fontWeight: FontWeight.w900,
  letterSpacing: .35,
);
