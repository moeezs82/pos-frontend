import 'dart:async';

import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/models/barcode_label_line.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/barcode_batch_print_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MultiProductBarcodePrintDialog extends StatefulWidget {
  final PrinterConfig config;
  final ProductGroupService groupService;
  final ProductService productService;
  final bool canManageProducts;

  const MultiProductBarcodePrintDialog({
    super.key,
    required this.config,
    required this.groupService,
    required this.productService,
    required this.canManageProducts,
  });

  @override
  State<MultiProductBarcodePrintDialog> createState() =>
      _MultiProductBarcodePrintDialogState();
}

class _BulkSelection {
  final int productId;
  final Map<String, dynamic> product;
  final String productName;
  final String variantDetails;
  final TextEditingController quantity;

  _BulkSelection({
    required this.productId,
    required this.product,
    required this.productName,
    this.variantDetails = '',
    int initialQuantity = 1,
  }) : quantity = TextEditingController(text: initialQuantity.toString());

  void dispose() => quantity.dispose();
}

class _GroupLoadState {
  final String groupName;
  bool loading;
  String? error;
  List<Map<String, dynamic>> variants;

  _GroupLoadState({
    required this.groupName,
    this.loading = false,
    this.error,
    this.variants = const [],
  });
}

class _MultiProductBarcodePrintDialogState
    extends State<MultiProductBarcodePrintDialog> {
  final _searchController = TextEditingController();
  final Map<int, _BulkSelection> _selected = {};
  final Map<int, _GroupLoadState> _groups = {};
  final Map<int, String> _simpleBarcodeOverrides = {};
  Timer? _debounce;

  List<ManagementItem> _catalog = const [];
  bool _loading = true;
  bool _generating = false;
  int _catalogRequestSerial = 0;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  String _type = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    for (final row in _selected.values) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog({bool resetPage = false}) async {
    if (resetPage) _page = 1;
    final requestSerial = ++_catalogRequestSerial;
    setState(() => _loading = true);
    try {
      final data = await widget.groupService.managementCatalog(
        page: _page,
        perPage: 20,
        search: _search.isEmpty ? null : _search,
        type: _type == 'all' ? null : _type,
      );
      final raw = (data['data'] as List?) ?? const [];
      final items = raw
          .whereType<Map>()
          .map((e) => ManagementItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted || requestSerial != _catalogRequestSerial) return;
      setState(() {
        _catalog = items;
        _lastPage = _int(data['last_page']).clamp(1, 999999).toInt();
        _total = _int(data['total']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestSerial != _catalogRequestSerial) return;
      setState(() => _loading = false);
      AppFeedback.error(context, 'Could not load products: $e');
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _search = value.trim();
      _loadCatalog(resetPage: true);
    });
  }

  String _simpleBarcode(ManagementItem item) {
    final id = item.id;
    if (id != null && _simpleBarcodeOverrides[id]?.isNotEmpty == true) {
      return _simpleBarcodeOverrides[id]!;
    }
    return item.barcode?.trim() ?? '';
  }

  bool get _needsBarcode => widget.config.effectiveLabelLines.any(
        (line) =>
            line.enabled &&
            (line.field == BarcodeLabelField.barcode ||
                line.field == BarcodeLabelField.barcodeValue),
      );

  Map<String, dynamic> _simpleProductMap(ManagementItem item) => {
        'id': item.id,
        'name': item.name,
        'secondary_name': item.secondaryName,
        'sku': item.sku,
        'barcode': _simpleBarcode(item),
        'price': item.price ?? 0,
        'cost_price': item.costPrice ?? 0,
        'discount': item.discount ?? 0,
        'discount_type': item.discountType ?? 'percentage',
        'stock_qty': item.totalStock,
      };

  void _toggleSimple(ManagementItem item, bool selected) {
    final id = item.id;
    if (id == null) return;
    if (selected) {
      final barcode = _simpleBarcode(item);
      if (_needsBarcode && barcode.isEmpty) return;
      _selected.putIfAbsent(
        id,
        () => _BulkSelection(
          productId: id,
          product: _simpleProductMap(item),
          productName: item.name,
        ),
      );
    } else {
      _removeSelection(id);
    }
    setState(() {});
  }

  void _toggleVariant(
    String groupName,
    Map<String, dynamic> variant,
    bool selected,
  ) {
    final id = _nullableInt(variant['id']);
    if (id == null) return;
    final barcode = (variant['barcode'] ?? '').toString().trim();
    if (selected) {
      if (_needsBarcode && barcode.isEmpty) return;
      _selected.putIfAbsent(
        id,
        () => _BulkSelection(
          productId: id,
          product: Map<String, dynamic>.from(variant),
          productName: groupName,
          variantDetails: _variantDetails(variant),
        ),
      );
    } else {
      _removeSelection(id);
    }
    setState(() {});
  }

  void _removeSelection(int id) {
    final row = _selected.remove(id);
    row?.dispose();
  }

  Future<void> _loadGroup(ManagementItem item) async {
    final groupId = item.groupId;
    if (groupId == null) return;
    final existing = _groups[groupId];
    if (existing != null &&
        (existing.loading || existing.variants.isNotEmpty || existing.error != null)) {
      return;
    }

    final state = _groups.putIfAbsent(
      groupId,
      () => _GroupLoadState(groupName: item.name),
    );
    setState(() {
      state.loading = true;
      state.error = null;
    });
    try {
      final data = await widget.groupService.showGroup(groupId);
      final raw = (data['products'] as List?) ?? const [];
      final variants = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        state.variants = variants;
        state.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        state.loading = false;
        state.error = e.toString();
      });
    }
  }

  int _selectedInGroup(_GroupLoadState? state) {
    if (state == null) return 0;
    return state.variants.where((v) {
      final id = _nullableInt(v['id']);
      return id != null && _selected.containsKey(id);
    }).length;
  }

  void _selectAllLoadedVariants(_GroupLoadState state, bool selected) {
    for (final variant in state.variants) {
      final id = _nullableInt(variant['id']);
      if (id == null) continue;
      final barcode = (variant['barcode'] ?? '').toString().trim();
      if (selected && (!_needsBarcode || barcode.isNotEmpty)) {
        _selected.putIfAbsent(
          id,
          () => _BulkSelection(
            productId: id,
            product: Map<String, dynamic>.from(variant),
            productName: state.groupName,
            variantDetails: _variantDetails(variant),
          ),
        );
      } else if (!selected) {
        _removeSelection(id);
      }
    }
    setState(() {});
  }

  Future<void> _generateSimpleBarcode(ManagementItem item) async {
    final id = item.id;
    if (!widget.canManageProducts || id == null || _generating) return;
    setState(() => _generating = true);
    try {
      final barcode = await widget.productService.generateBarcode();
      await widget.productService.updateProduct(id, {'barcode': barcode});
      if (!mounted) return;
      setState(() => _simpleBarcodeOverrides[id] = barcode);
      AppFeedback.success(context, 'Barcode generated for ${item.name}.');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Barcode generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateVariantBarcode(
    int groupId,
    String groupName,
    Map<String, dynamic> variant,
  ) async {
    if (!widget.canManageProducts || _generating) return;
    final productId = _nullableInt(variant['id']);
    if (productId == null) return;
    setState(() => _generating = true);
    try {
      final barcode = await widget.groupService.generateBarcode();
      await widget.groupService.updateVariant(
        groupId,
        productId,
        {'barcode': barcode},
      );
      if (!mounted) return;
      setState(() => variant['barcode'] = barcode);
      AppFeedback.success(
        context,
        'Barcode generated for $groupName ${_variantDetails(variant)}.',
      );
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Barcode generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  List<BarcodeLabelItem> _buildItems() {
    final items = <BarcodeLabelItem>[];
    for (final row in _selected.values) {
      final copies = int.tryParse(row.quantity.text.trim()) ?? 0;
      if (copies < 1 || copies > BarcodeLabelPrinterService.maxCopies) continue;
      items.add(
        BarcodeLabelItem.fromProduct(
          row.product,
          nameOverride: row.productName,
          variantOverride: row.variantDetails,
          copies: copies,
        ),
      );
    }
    return items;
  }

  Future<void> _continueToPrint() async {
    if (_selected.isEmpty) {
      AppFeedback.warning(context, 'Select at least one product or variant.');
      return;
    }

    for (final row in _selected.values) {
      final copies = int.tryParse(row.quantity.text.trim());
      if (copies == null ||
          copies < 1 ||
          copies > BarcodeLabelPrinterService.maxCopies) {
        AppFeedback.warning(
          context,
          'Each selected SKU must have a label quantity from 1 to ${BarcodeLabelPrinterService.maxCopies}.',
        );
        return;
      }
    }

    final items = _buildItems();
    final total = items.fold<int>(0, (sum, item) => sum + item.copies);
    if (total > BarcodeLabelPrinterService.maxBatchLabels) {
      AppFeedback.warning(
        context,
        'A barcode print job can contain at most ${BarcodeLabelPrinterService.maxBatchLabels} labels.',
      );
      return;
    }

    final printed = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BarcodeBatchPrintDialog(
        items: items,
        config: widget.config,
      ),
    );
    if (printed != null && mounted) {
      Navigator.pop(context, printed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 36).clamp(1060.0, 1480.0).toDouble();
    final height = (screen.height - 36).clamp(650.0, 880.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _header(),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: _catalogPane()),
                  const VerticalDivider(width: 1, color: AppTheme.border),
                  Expanded(flex: 4, child: _selectedPane()),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Print Multiple Product Barcodes',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Select simple products or expand a product group and choose its variants.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _catalogPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search name, SKU, barcode or variant...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchController.clear();
                                  _search = '';
                                  _loadCatalog(resetPage: true);
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'Refresh products',
                    onPressed: _loading ? null : _loadCatalog,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'simple', label: Text('Simple')),
                      ButtonSegment(value: 'variable', label: Text('Groups')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (values) {
                      setState(() => _type = values.first);
                      _loadCatalog(resetPage: true);
                    },
                  ),
                  const Spacer(),
                  Text(
                    '$_total result${_total == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppTheme.border),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _catalog.isEmpty
                  ? const Center(
                      child: Text(
                        'No products matched your search.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _catalog.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppTheme.border),
                      itemBuilder: (context, index) {
                        final item = _catalog[index];
                        return item.isVariable
                            ? _groupRow(item)
                            : _simpleRow(item);
                      },
                    ),
        ),
        const Divider(height: 1, color: AppTheme.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Text(
                'Page $_page of $_lastPage',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 && !_loading
                    ? () {
                        setState(() => _page--);
                        _loadCatalog();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page < _lastPage && !_loading
                    ? () {
                        setState(() => _page++);
                        _loadCatalog();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _simpleRow(ManagementItem item) {
    final id = item.id;
    final barcode = _simpleBarcode(item);
    final hasBarcode = barcode.isNotEmpty;
    final printable = hasBarcode || !_needsBarcode;
    final selected = id != null && _selected.containsKey(id);

    return Container(
      color: selected ? AppTheme.primary.withOpacity(.025) : Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: printable ? (v) => _toggleSimple(item, v == true) : null,
          ),
          const SizedBox(width: 4),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 19,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SKU ${_textOrDash(item.sku)}  •  Stock ${_qty(item.totalStock)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 13,
            child: hasBarcode
                ? Text(
                    barcode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                  )
                : !_needsBarcode
                    ? const Text(
                        'Not required by label design',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10.5,
                        ),
                      )
                    : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Flexible(
                        child: Text(
                          'Barcode missing',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.canManageProducts)
                        IconButton(
                          tooltip: 'Generate barcode',
                          onPressed:
                              _generating ? null : () => _generateSimpleBarcode(item),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 17,
                            color: AppTheme.primary,
                          ),
                        ),
                    ],
                  ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              AppCurrency.format(item.price ?? 0),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupRow(ManagementItem item) {
    final groupId = item.groupId;
    if (groupId == null) return const SizedBox.shrink();
    final state = _groups[groupId];
    final selectedCount = _selectedInGroup(state);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('barcode-group-$groupId'),
        onExpansionChanged: (expanded) {
          if (expanded) _loadGroup(item);
        },
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.purple.withOpacity(.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.account_tree_rounded,
            size: 18,
            color: AppTheme.purple,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
            ),
            if (selectedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$selectedCount selected',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${item.variantCount} variant${item.variantCount == 1 ? '' : 's'}  •  Stock ${_qty(item.totalStock)}  •  ${_priceRange(item)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
        children: [_groupChildren(groupId, item.name, state)],
      ),
    );
  }

  Widget _groupChildren(int groupId, String groupName, _GroupLoadState? state) {
    if (state == null || state.loading) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Could not load variants.',
                style: TextStyle(color: AppTheme.danger),
              ),
            ),
            TextButton(
              onPressed: () {
                _groups.remove(groupId);
                final item = _catalog.firstWhere(
                  (e) => e.groupId == groupId,
                  orElse: () => ManagementItem(
                    type: 'variable',
                    groupId: groupId,
                    name: groupName,
                    isActive: true,
                    variantCount: 0,
                    totalStock: 0,
                  ),
                );
                _loadGroup(item);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (state.variants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'This product group has no variants.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final printable = state.variants
        .where((v) =>
            !_needsBarcode ||
            (v['barcode'] ?? '').toString().trim().isNotEmpty)
        .toList();
    final selectedPrintable = printable.where((v) {
      final id = _nullableInt(v['id']);
      return id != null && _selected.containsKey(id);
    }).length;
    final allSelected = printable.isNotEmpty && selectedPrintable == printable.length;

    return Container(
      color: AppTheme.surfaceSoft.withOpacity(.45),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 4, 14, 4),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  tristate: selectedPrintable > 0 && !allSelected,
                  onChanged: printable.isEmpty
                      ? null
                      : (value) => _selectAllLoadedVariants(state, value == true),
                ),
                Text(
                  _needsBarcode
                      ? 'Select all variants with barcode'
                      : 'Select all variants',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  '$selectedPrintable / ${state.variants.length} selected',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          ...state.variants.map(
            (variant) => _variantRow(groupId, state.groupName, variant),
          ),
        ],
      ),
    );
  }

  Widget _variantRow(
    int groupId,
    String groupName,
    Map<String, dynamic> variant,
  ) {
    final id = _nullableInt(variant['id']);
    final barcode = (variant['barcode'] ?? '').toString().trim();
    final hasBarcode = barcode.isNotEmpty;
    final printable = hasBarcode || !_needsBarcode;
    final selected = id != null && _selected.containsKey(id);

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.fromLTRB(44, 6, 12, 6),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: printable
                ? (v) => _toggleVariant(groupName, variant, v == true)
                : null,
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _variantDetails(variant).isEmpty
                      ? (variant['name'] ?? 'Variant').toString()
                      : _variantDetails(variant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                Text(
                  'SKU ${_textOrDash(variant['sku'])}  •  Stock ${_variantStock(variant)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 14,
            child: hasBarcode
                ? Text(
                    barcode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  )
                : !_needsBarcode
                    ? const Text(
                        'Not required',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10.5,
                        ),
                      )
                    : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Flexible(
                        child: Text(
                          'Barcode missing',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.canManageProducts)
                        IconButton(
                          tooltip: 'Generate barcode',
                          onPressed: _generating
                              ? null
                              : () => _generateVariantBarcode(
                                    groupId,
                                    groupName,
                                    variant,
                                  ),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 17,
                            color: AppTheme.primary,
                          ),
                        ),
                    ],
                  ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              AppCurrency.format(_double(variant['price'])),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedPane() {
    final rows = _selected.values.toList();
    return Container(
      color: const Color(0xFFF8F9FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.playlist_add_check_rounded,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 7),
                const Text(
                  'PRINT JOB',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                    color: AppTheme.navy,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: rows.isEmpty
                      ? null
                      : () {
                          for (final row in _selected.values) {
                            row.dispose();
                          }
                          setState(() => _selected.clear());
                        },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 42,
                            color: AppTheme.textMuted,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No products selected',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.navy,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Select simple products or expand a group and choose variants.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppTheme.border),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.productName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.navy,
                                    ),
                                  ),
                                  if (row.variantDetails.isNotEmpty)
                                    Text(
                                      row.variantDetails,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  Text(
                                    (row.product['barcode'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                controller: row.quantity,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Labels',
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () {
                                _removeSelection(row.productId);
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_needsBarcode && !widget.canManageProducts)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppTheme.warning.withOpacity(.08),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 17, color: AppTheme.warning),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Products without a barcode cannot be selected. A user with Manage Products permission can generate missing barcodes.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final items = _buildItems();
    final labels = items.fold<int>(0, (sum, item) => sum + item.copies);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        children: [
          Text(
            '${_selected.length} SKU${_selected.length == 1 ? '' : 's'} selected',
            style: const TextStyle(color: AppTheme.textMuted),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppTheme.border),
          const SizedBox(width: 14),
          Text(
            'Total labels: $labels',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _continueToPrint,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Review & Print'),
          ),
        ],
      ),
    );
  }

  String _priceRange(ManagementItem item) {
    final min = item.minPrice;
    final max = item.maxPrice;
    if (min == null || max == null) return 'Price —';
    if ((min - max).abs() < .000001) return AppCurrency.format(min);
    return '${AppCurrency.format(min)} – ${AppCurrency.format(max)}';
  }

  static String _variantDetails(Map<String, dynamic> variant) {
    final color = (variant['variant_color'] ?? '').toString().trim();
    final size = (variant['variant_size'] ?? '').toString().trim();
    return [color, size].where((e) => e.isNotEmpty).join(' • ');
  }

  static String _variantStock(Map<String, dynamic> variant) {
    final stocks = variant['stocks'];
    if (stocks is List && stocks.isNotEmpty && stocks.first is Map) {
      return _qty(_double((stocks.first as Map)['quantity']));
    }
    return _qty(_double(variant['stock_qty'] ?? variant['stock']));
  }

  static String _textOrDash(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? '—' : text;
  }

  static String _qty(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    final parsed = _int(value);
    return parsed > 0 ? parsed : null;
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
