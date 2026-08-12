import 'dart:async';

import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/forms/variable_product_form_screen.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/screens/product_group_detail_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/barcode_print_dialog.dart';
import 'package:enterprise_pos/widgets/variant_barcode_print_dialog.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

// ─── Unified management autocomplete search field ─────────────────────────────

class _ProductAutoSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ProductGroupService productGroupService;
  final String typeFilter;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final ValueChanged<ManagementItem> onQuickView;

  const _ProductAutoSearchField({
    required this.controller,
    required this.productGroupService,
    required this.typeFilter,
    required this.onSearch,
    required this.onClear,
    required this.onQuickView,
  });

  @override
  State<_ProductAutoSearchField> createState() => _ProductAutoSearchFieldState();
}

class _ProductAutoSearchFieldState extends State<_ProductAutoSearchField> {
  final _fieldKey = GlobalKey();
  late final FocusNode _focusNode;
  OverlayEntry? _overlayEntry;
  List<ManagementItem> _suggestions = [];
  int _focusedIndex = -1;
  Timer? _debounce;
  bool _fetchingHints = false;
  bool _overlayPointerDown = false;
  Offset _dropdownOffset = Offset.zero;
  double _dropdownWidth = 420;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_suggestions.isEmpty || _overlayEntry == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() =>
          _focusedIndex = (_focusedIndex + 1).clamp(0, _suggestions.length - 1));
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedIndex =
          (_focusedIndex - 1).clamp(-1, _suggestions.length - 1));
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_focusedIndex >= 0) {
        _selectAtIndex(_focusedIndex);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focusNode.hasFocus && !_overlayPointerDown) {
          _removeOverlay();
        }
      });
    }
  }

  void _beginOverlayPointerInteraction() => _overlayPointerDown = true;

  void _endOverlayPointerInteraction() {
    _overlayPointerDown = false;
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted &&
            !_focusNode.hasFocus &&
            !_overlayPointerDown &&
            _overlayEntry != null) {
          _removeOverlay();
        }
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _suggestions = [];
        _focusedIndex = -1;
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      _removeOverlay();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(query),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _fetchingHints = true);
    try {
      final data = await widget.productGroupService.managementCatalog(
        page: 1,
        perPage: 8,
        search: query,
        type: widget.typeFilter == 'all' ? null : widget.typeFilter,
      );
      final raw = (data['data'] as List?) ?? const [];
      final items = raw
          .whereType<Map>()
          .map((e) => ManagementItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      _suggestions = items;
      _focusedIndex = -1;
      if (items.isNotEmpty && _focusNode.hasFocus) {
        _showOrUpdateOverlay();
      } else {
        _removeOverlay();
      }
    } catch (_) {
      if (mounted) _removeOverlay();
    } finally {
      if (mounted) setState(() => _fetchingHints = false);
    }
  }

  void _showOrUpdateOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    final renderBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      _dropdownOffset =
          Offset(globalOffset.dx, globalOffset.dy + renderBox.size.height);
      _dropdownWidth = renderBox.size.width.clamp(320.0, 560.0);
    }
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _selectAtIndex(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final item = _suggestions[index];
    widget.controller.text = item.name;
    _removeOverlay();
    widget.onSearch();
  }

  void _quickViewAtIndex(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final item = _suggestions[index];
    _removeOverlay();
    widget.onQuickView(item);
  }

  String _priceLabel(ManagementItem item) {
    if (!item.isVariable) return AppCurrency.format(item.price ?? 0);
    if (item.minPrice == null || item.maxPrice == null) return '—';
    if (item.minPrice == item.maxPrice) return AppCurrency.format(item.minPrice!);
    return '${AppCurrency.format(item.minPrice!)} – ${AppCurrency.format(item.maxPrice!)}';
  }

  Widget _buildOverlayContent(BuildContext ctx) {
    return Positioned(
      left: _dropdownOffset.dx,
      top: _dropdownOffset.dy,
      width: _dropdownWidth,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _beginOverlayPointerInteraction(),
        onPointerUp: (_) => _endOverlayPointerInteraction(),
        onPointerCancel: (_) => _endOverlayPointerInteraction(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_suggestions.length, (i) {
              final item = _suggestions[i];
              final isFocused = i == _focusedIndex;
              final subtitle = item.isVariable
                  ? '${item.variantCount} variants · ${_stockLabel(item.totalStock)} stock · ${_priceLabel(item)}'
                  : 'SKU: ${item.sku?.isNotEmpty == true ? item.sku : '—'} · ${_priceLabel(item)}';
              return ColoredBox(
                color: isFocused ? AppTheme.primarySoft : Colors.transparent,
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        canRequestFocus: false,
                        onTap: () => _selectAtIndex(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                item.isVariable
                                    ? Icons.account_tree_rounded
                                    : Icons.inventory_2_rounded,
                                size: 16,
                                color: isFocused
                                    ? AppTheme.primary
                                    : AppTheme.primary.withOpacity(0.55),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: isFocused
                                            ? AppTheme.primary
                                            : AppTheme.navy,
                                      ),
                                    ),
                                    if (item.secondaryName?.trim().isNotEmpty == true) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.secondaryName!.trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
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
                              const SizedBox(width: 8),
                              EnterpriseStatusBadge(
                                label: item.isVariable ? 'VARIABLE' : 'SIMPLE',
                                color: item.isVariable
                                    ? AppTheme.purple
                                    : AppTheme.info,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: item.isVariable
                          ? 'Open variants'
                          : 'Quick view / edit',
                      child: InkWell(
                        canRequestFocus: false,
                        onTap: () => _quickViewAtIndex(i),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  static String _stockLabel(double value) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _fieldKey,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        onSubmitted: (_) {
          _removeOverlay();
          widget.onSearch();
        },
        decoration: InputDecoration(
          hintText: 'Search product, group, SKU, barcode...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_fetchingHints)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (widget.controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _removeOverlay();
                    widget.onClear();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              IconButton(
                tooltip: 'Search',
                onPressed: () {
                  _removeOverlay();
                  widget.onSearch();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProductsScreenState extends State<ProductsScreen> {
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  bool _importExportBusy = false;
  bool _showCost = false;
  String _search = '';
  // Presentation-only filter over the unified management endpoint.
  // 'all' keeps simple products and variable families in one paginated list.
  String _typeFilter = 'all';
  final List<ManagementItem> _items = [];
  final _searchController = TextEditingController();

  late ProductService _productService;
  late ProductGroupService _groupService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _groupService = ProductGroupService(token: token);
    _fetchProducts(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) {
      _items.clear();
      _page = 1;
    }

    try {
      final data = await _groupService.managementCatalog(
        page: _page,
        perPage: 20,
        search: _search.isNotEmpty ? _search : null,
        type: _typeFilter == 'all' ? null : _typeFilter,
      );
      final raw = (data['data'] as List?) ?? const [];
      final items = raw
          .whereType<Map>()
          .map((e) => ManagementItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = (data['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (data['last_page'] as num?)?.toInt() ?? _lastPage;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load products: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchType(String type) {
    if (_typeFilter == type) return;
    setState(() => _typeFilter = type);
    _fetchProducts(reset: true);
  }

  Future<void> _openAddVariableProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VariableProductFormScreen()),
    );
    if (result == true && mounted) _fetchProducts(reset: true);
  }

  Future<void> _openGroupDetailItem(ManagementItem item) async {
    final groupId = item.groupId;
    if (groupId == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductGroupDetailScreen(
          groupId: groupId,
          groupName: item.name,
        ),
      ),
    );
    if (changed == true && mounted) _fetchProducts(reset: true);
  }

  Future<Map<String, dynamic>?> _loadSimpleProduct(ManagementItem item) async {
    final id = item.id;
    if (id == null) return null;
    try {
      return await _productService.getProduct(id);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load product: $e');
      return null;
    }
  }

  Future<void> _openManagementItem(ManagementItem item) async {
    if (item.isVariable) {
      await _openGroupDetailItem(item);
      return;
    }
    final product = await _loadSimpleProduct(item);
    if (product != null && mounted) await _openForm(product);
  }

  void _onSearch() {
    setState(() => _search = _searchController.text.trim());
    _fetchProducts(reset: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
    _fetchProducts(reset: true);
  }

  Future<void> _onRefresh() async => _fetchProducts(reset: true);

  Future<void> _deleteProduct(int id) async {
    try {
      await _productService.deleteProduct(id);
      if (!mounted) return;
      AppFeedback.success(context, 'Product deleted successfully');
      _fetchProducts(reset: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to delete product: $e');
    }
  }

  Future<void> _openForm([dynamic product]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (!mounted) return;
    if (result != null) _fetchProducts(reset: true);
  }

  Future<void> _confirmDeleteItem(ManagementItem item) async {
    final id = item.id;
    if (id == null || item.isVariable) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text(
          'Are you sure you want to delete "${item.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) await _deleteProduct(id);
  }

  Future<void> _printBarcodeLabelsItem(ManagementItem item) async {
    if (item.isVariable) {
      await _printVariableBarcodeLabelsItem(item);
      return;
    }
    final product = await _loadSimpleProduct(item);
    if (product != null && mounted) await _printBarcodeLabels(product);
  }

  Future<PrinterConfig?> _loadBarcodePrinterConfig() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('print-barcode-labels')) {
      AppFeedback.error(context, 'You do not have permission to print product labels.');
      return null;
    }
    if (!auth.hasAddon('barcode_labels')) {
      AppFeedback.warning(
        context,
        'Barcode Label Printing is not active for this branch.',
      );
      return null;
    }

    final printerConfig = context.read<PrinterConfigProvider>();
    try {
      final token = auth.token;
      if (token == null) {
        throw Exception('Your session has expired. Please sign in again.');
      }
      // Refresh here so a recent branch switch cannot print with another
      // branch's cached label size or printer destination.
      await printerConfig.refresh(token);
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Could not load barcode printer settings: $e');
      }
      return null;
    }
    if (!mounted) return null;

    final config = printerConfig.config.copyWith(
      barcodeCurrency: context.read<BranchProvider>().currency,
    );
    if (!config.isBarcodeConfigured) {
      AppFeedback.warning(
        context,
        config.barcodeAddonActive
            ? 'Ask a Master Admin to configure Barcode Label Printing for this branch.'
            : 'Barcode Label Printing is not active for this branch.',
      );
      return null;
    }
    return config;
  }

  Future<void> _printVariableBarcodeLabelsItem(ManagementItem item) async {
    final groupId = item.groupId;
    if (groupId == null) return;
    final config = await _loadBarcodePrinterConfig();
    if (config == null || !mounted) return;

    try {
      final data = await _groupService.showGroup(groupId);
      if (!mounted) return;
      final raw = data['products'] as List? ?? const [];
      final variants = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (variants.isEmpty) {
        AppFeedback.warning(context, 'This product family does not have any variants to print.');
        return;
      }
      final copies = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VariantBarcodePrintDialog(
          groupId: groupId,
          groupName: item.name,
          variants: variants,
          config: config,
          service: _groupService,
        ),
      );
      if (copies != null && mounted) {
        AppFeedback.success(
          context,
          '$copies barcode label${copies == 1 ? '' : 's'} sent to print.',
        );
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not load product variants: $e');
    }
  }

  Future<void> _printBarcodeLabels(dynamic product) async {
    final barcode = (product['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) {
      AppFeedback.warning(context, 'Add a barcode to this product before printing labels.');
      return;
    }

    final config = await _loadBarcodePrinterConfig();
    if (config == null || !mounted) return;

    final copies = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BarcodePrintDialog(
        product: Map<String, dynamic>.from(product as Map),
        config: config,
      ),
    );
    if (mounted && copies != null) {
      AppFeedback.success(context, '$copies barcode label${copies == 1 ? '' : 's'} sent to print.');
    }
  }

  Future<void> _exportProducts(String format) async {
    setState(() => _importExportBusy = true);
    try {
      final file = await _productService.exportProducts(
        format: format,
        search: _search.isEmpty ? null : _search,
      );
      final path = await saveReportFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.contentType,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Products exported and opened: $path');
    } on ReportSaveCancelledException {
      // User dismissed the save dialog — nothing to report.
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _importExportBusy = false);
    }
  }

  Future<void> _downloadImportTemplate(String format) async {
    setState(() => _importExportBusy = true);
    try {
      final file = await _productService.downloadImportTemplate(format: format);
      final path = await saveReportFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.contentType,
      );
      if (!mounted) return;
      AppFeedback.success(context, 'Template saved and opened: $path');
    } on ReportSaveCancelledException {
      // User dismissed the save dialog — nothing to report.
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to download template: $e');
    } finally {
      if (mounted) setState(() => _importExportBusy = false);
    }
  }

  Future<void> _pickAndImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      if (mounted) AppFeedback.error(context, 'Could not read the selected file.');
      return;
    }

    setState(() => _importExportBusy = true);
    try {
      final report = await _productService.importProducts(filePath: path, filename: picked.name);
      if (!mounted) return;
      _fetchProducts(reset: true);
      await _showImportResultDialog(report);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importExportBusy = false);
    }
  }

  Future<void> _showImportResultDialog(ProductImportReport report) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Result'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rows processed: ${report.totalRows}'),
              const SizedBox(height: 4),
              Text('Created: ${report.created}', style: const TextStyle(color: AppTheme.success)),
              Text('Updated: ${report.updated}', style: const TextStyle(color: AppTheme.info)),
              Text('Failed: ${report.failed}', style: const TextStyle(color: AppTheme.danger)),
              if (report.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Errors', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: report.errors.length,
                    itemBuilder: (context, i) {
                      final e = report.errors[i];
                      final skuLabel = (e.sku != null && e.sku!.isNotEmpty) ? ' (SKU ${e.sku})' : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Row ${e.row}$skuLabel: ${e.message}'),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showImportExportMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export products (Excel)'),
              onTap: () {
                Navigator.pop(ctx);
                _exportProducts('xlsx');
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export products (CSV)'),
              onTap: () {
                Navigator.pop(ctx);
                _exportProducts('csv');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Import products…'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndImportFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Download import template'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadImportTemplate('xlsx');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManageProducts = auth.hasPermission('manage-products');
    final canPrintBarcodes = auth.hasPermission('print-barcode-labels') &&
        auth.hasAddon('barcode_labels');

    return EnterprisePage(
      title: 'Products',
      subtitle: 'Manage simple products and variable product families in one catalog.',
      icon: Icons.inventory_2_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: [
        if (canManageProducts) ...[
          OutlinedButton.icon(
            onPressed: _importExportBusy ? null : _showImportExportMenu,
            icon: _importExportBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.import_export_rounded),
            label: const Text('Import/Export'),
          ),
          const SizedBox(width: 8),
          _AddProductMenuButton(
            onSimple: () => _openForm(),
            onVariable: _openAddVariableProduct,
          ),
        ],
      ],
      bottomNavigationBar: _items.isNotEmpty
          ? EnterprisePaginationBar(
              page: _page,
              lastPage: _lastPage,
              loading: _loading,
              onPrevious: _page > 1
                  ? () {
                      setState(() => _page--);
                      _fetchProducts();
                    }
                  : null,
              onNext: _page < _lastPage
                  ? () {
                      setState(() => _page++);
                      _fetchProducts();
                    }
                  : null,
            )
          : null,
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              _TypeFilterButtons(
                current: _typeFilter,
                onChanged: _switchType,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: MediaQuery.of(context).size.width >= 720
                    ? 420
                    : double.infinity,
                child: _ProductAutoSearchField(
                  controller: _searchController,
                  productGroupService: _groupService,
                  typeFilter: _typeFilter,
                  onSearch: _onSearch,
                  onClear: _clearSearch,
                  onQuickView: _openManagementItem,
                ),
              ),
              Tooltip(
                message: _showCost ? 'Hide cost price' : 'Show cost price',
                child: IconButton(
                  icon: Icon(_showCost
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showCost = !_showCost),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            EnterpriseEmptyState(
                              icon: _typeFilter == 'variable'
                                  ? Icons.account_tree_rounded
                                  : Icons.inventory_2_outlined,
                              title: _emptyTitle(),
                              subtitle: _emptySubtitle(),
                              action: canManageProducts
                                  ? _AddProductMenuButton(
                                      onSimple: () => _openForm(),
                                      onVariable: _openAddVariableProduct,
                                    )
                                  : null,
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _buildManagementCard(
                            _items[index],
                            canManageProducts: canManageProducts,
                            canPrintBarcodes: canPrintBarcodes,
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  String _emptyTitle() {
    if (_search.isNotEmpty) return 'No products found';
    switch (_typeFilter) {
      case 'simple':
        return 'No simple products';
      case 'variable':
        return 'No variable products';
      default:
        return 'No products yet';
    }
  }

  String _emptySubtitle() {
    if (_search.isNotEmpty) {
      return 'No product or product family matched your search. Try a name, SKU or barcode.';
    }
    switch (_typeFilter) {
      case 'simple':
        return 'Add a simple product to start selling and tracking stock.';
      case 'variable':
        return 'Add a variable product to manage size and color variants.';
      default:
        return 'Add a simple or variable product to build your catalog.';
    }
  }

  Widget _buildManagementCard(
    ManagementItem item, {
    required bool canManageProducts,
    required bool canPrintBarcodes,
  }) {
    if (item.isVariable) {
      return _buildVariableCard(item);
    }
    return _buildSimpleCard(
      item,
      canManageProducts: canManageProducts,
      canPrintBarcodes: canPrintBarcodes,
    );
  }

  Widget _buildSimpleCard(
    ManagementItem item, {
    required bool canManageProducts,
    required bool canPrintBarcodes,
  }) {
    final stock = _stockLabel(item.totalStock);
    final stockColor = item.totalStock <= 0
        ? AppTheme.danger
        : item.totalStock <= 5
            ? AppTheme.warning
            : AppTheme.success;
    final sku = item.sku?.trim().isNotEmpty == true ? item.sku!.trim() : '—';
    final brand = item.brandName?.trim().isNotEmpty == true
        ? item.brandName!.trim()
        : '—';
    final category = item.categoryName?.trim().isNotEmpty == true
        ? item.categoryName!.trim()
        : '—';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canManageProducts ? () => _openManagementItem(item) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primarySoft,
                foregroundColor: AppTheme.primary,
                child: Text(
                  item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        EnterpriseStatusBadge(
                          label: 'SIMPLE',
                          color: AppTheme.info,
                        ),
                        const SizedBox(width: 6),
                        EnterpriseStatusBadge(
                          label: item.isActive ? 'ACTIVE' : 'INACTIVE',
                          color: item.isActive
                              ? AppTheme.success
                              : AppTheme.textMuted,
                        ),
                      ],
                    ),
                    if (item.secondaryName?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.secondaryName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        EnterpriseMetricChip(
                          label: 'SKU',
                          value: sku,
                          color: AppTheme.info,
                          icon: Icons.qr_code_rounded,
                        ),
                        EnterpriseMetricChip(
                          label: 'Stock',
                          value: stock,
                          color: stockColor,
                          icon: Icons.inventory_rounded,
                        ),
                        EnterpriseMetricChip(
                          label: 'Price',
                          value: AppCurrency.format(item.price ?? 0),
                          color: AppTheme.primary,
                          icon: Icons.sell_rounded,
                        ),
                        if (_showCost)
                          EnterpriseMetricChip(
                            label: 'Cost',
                            value: AppCurrency.format(item.costPrice ?? 0),
                            color: AppTheme.warning,
                            icon: Icons.price_change_rounded,
                          ),
                        EnterpriseMetricChip(
                          label: 'Brand',
                          value: brand,
                          color: AppTheme.purple,
                        ),
                        EnterpriseMetricChip(
                          label: 'Category',
                          value: category,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Wrap(
                spacing: 2,
                children: [
                  if (canPrintBarcodes)
                    IconButton(
                      tooltip: item.isVariable ? 'Print variant barcodes' : 'Print barcode labels',
                      onPressed: () => _printBarcodeLabelsItem(item),
                      icon: const Icon(
                        Icons.qr_code_2_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                  if (canManageProducts) ...[
                    IconButton(
                      tooltip: 'Edit product',
                      onPressed: () => _openManagementItem(item),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton(
                      tooltip: 'Delete product',
                      onPressed: () => _confirmDeleteItem(item),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariableCard(ManagementItem item) {
    final stock = _stockLabel(item.totalStock);
    final priceRange = _priceRange(item);
    final brand = item.brandName?.trim().isNotEmpty == true
        ? item.brandName!.trim()
        : '—';
    final category = item.categoryName?.trim().isNotEmpty == true
        ? item.categoryName!.trim()
        : '—';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openGroupDetailItem(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.purple.withOpacity(0.10),
                foregroundColor: AppTheme.purple,
                child: const Icon(Icons.account_tree_rounded, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        EnterpriseStatusBadge(
                          label: 'VARIABLE',
                          color: AppTheme.purple,
                        ),
                        const SizedBox(width: 6),
                        EnterpriseStatusBadge(
                          label: item.isActive ? 'ACTIVE' : 'INACTIVE',
                          color: item.isActive
                              ? AppTheme.success
                              : AppTheme.textMuted,
                        ),
                      ],
                    ),
                    if (item.secondaryName?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.secondaryName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        EnterpriseMetricChip(
                          label: 'Variants',
                          value: item.variantCount.toString(),
                          color: AppTheme.purple,
                          icon: Icons.tune_rounded,
                        ),
                        EnterpriseMetricChip(
                          label: 'Total Stock',
                          value: stock,
                          color: item.totalStock <= 0
                              ? AppTheme.danger
                              : AppTheme.success,
                          icon: Icons.inventory_rounded,
                        ),
                        EnterpriseMetricChip(
                          label: 'Price',
                          value: priceRange,
                          color: AppTheme.primary,
                          icon: Icons.sell_rounded,
                        ),
                        EnterpriseMetricChip(
                          label: 'Brand',
                          value: brand,
                          color: AppTheme.purple,
                        ),
                        EnterpriseMetricChip(
                          label: 'Category',
                          value: category,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  String _stockLabel(double value) {
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  String _priceRange(ManagementItem item) {
    if (item.minPrice == null || item.maxPrice == null) return '—';
    if (item.minPrice == item.maxPrice) {
      return AppCurrency.format(item.minPrice!);
    }
    return '${AppCurrency.format(item.minPrice!)} – ${AppCurrency.format(item.maxPrice!)}';
  }
}

class _AddProductMenuButton extends StatelessWidget {
  final VoidCallback onSimple;
  final VoidCallback onVariable;

  const _AddProductMenuButton({
    required this.onSimple,
    required this.onVariable,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add product',
      offset: const Offset(0, 42),
      onSelected: (value) {
        if (value == 'variable') {
          onVariable();
        } else {
          onSimple();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'simple',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Simple Product'),
            subtitle: Text('Single SKU and stock item'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'variable',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.account_tree_rounded),
            title: Text('Variable Product'),
            subtitle: Text('Size/color variants with separate stock'),
          ),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 18),
            SizedBox(width: 7),
            Text(
              'Add Product',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 5),
            Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Type filter toggle buttons ────────────────────────────────────────────────

class _TypeFilterButtons extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _TypeFilterButtons({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab('all', 'All', Icons.apps_rounded),
          _tab('simple', 'Simple', Icons.inventory_2_outlined),
          _tab('variable', 'Variable', Icons.account_tree_rounded),
        ],
      ),
    );
  }

  Widget _tab(String value, String label, IconData icon) {
    final selected = current == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
