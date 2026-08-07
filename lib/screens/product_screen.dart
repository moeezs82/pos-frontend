import 'dart:async';

import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/barcode_print_dialog.dart';
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

// ─── Autocomplete search field ────────────────────────────────────────────────

class _ProductAutoSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ProductService productService;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  const _ProductAutoSearchField({
    required this.controller,
    required this.productService,
    required this.onSearch,
    required this.onClear,
  });

  @override
  State<_ProductAutoSearchField> createState() => _ProductAutoSearchFieldState();
}

class _ProductAutoSearchFieldState extends State<_ProductAutoSearchField> {
  /// Key on the search field container — used to locate it on screen so the
  /// dropdown can be positioned without CompositedTransformFollower.
  final _fieldKey = GlobalKey();

  late final FocusNode _focusNode;
  OverlayEntry? _overlayEntry;
  List<Map<String, dynamic>> _suggestions = [];
  int _focusedIndex = -1;
  Timer? _debounce;
  bool _fetchingHints = false;

  /// Cached absolute position for the dropdown (recomputed each open).
  Offset _dropdownOffset = Offset.zero;
  double _dropdownWidth = 420;

  @override
  void initState() {
    super.initState();
    // Key events are intercepted at the FocusNode level so they run before
    // TextField's own handlers (e.g. preventing cursor-move on ArrowDown).
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

  // ── Key navigation ────────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Only act on down-events (and repeats for held arrow keys).
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // No dropdown → pass every key through to TextField as normal.
    if (_suggestions.isEmpty || _overlayEntry == null) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusedIndex = (_focusedIndex + 1).clamp(0, _suggestions.length - 1));
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedIndex = (_focusedIndex - 1).clamp(-1, _suggestions.length - 1));
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_focusedIndex >= 0) {
        _selectAtIndex(_focusedIndex);
        return KeyEventResult.handled;
      }
      // No item highlighted → let TextField fire onSubmitted normally.
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Consume Escape so the global "go back" shortcut doesn't also fire.
      _removeOverlay();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Overlay lifecycle ─────────────────────────────────────────────────────

  void _onControllerChanged() => setState(() {});

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Small delay so a tap inside the overlay can register before it closes.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() { _suggestions = []; _focusedIndex = -1; });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) { _removeOverlay(); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => _fetchingHints = true);
    try {
      final data = await widget.productService.getProducts(page: 1, search: query);
      final wrapper = (data['data'] as List).first;
      final items = (wrapper['products'] as List<dynamic>)
          .take(8)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      _suggestions = items;
      _focusedIndex = -1; // reset keyboard selection on each new result set
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
    // Compute absolute screen position once, when the overlay is first created.
    // This avoids CompositedTransformFollower / RenderFollowerLayer entirely.
    final renderBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      _dropdownOffset = Offset(globalOffset.dx, globalOffset.dy + renderBox.size.height);
      _dropdownWidth = renderBox.size.width.clamp(320.0, 520.0);
    }
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _selectAtIndex(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final p = _suggestions[index];
    widget.controller.text = (p['name'] ?? '').toString();
    _removeOverlay();
    widget.onSearch();
  }

  Future<void> _quickViewAtIndex(int index) async {
    if (index < 0 || index >= _suggestions.length) return;
    // Capture before clearing.
    final p = Map<String, dynamic>.from(_suggestions[index]);
    // Tear down the overlay silently — no setState to avoid any mid-frame rebuild.
    _overlayEntry?.remove();
    _overlayEntry = null;
    _suggestions = [];
    _focusedIndex = -1;
    // Navigate directly, exactly like the Edit button on the list does.
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)),
    );
    if (!mounted) return;
    // If the form saved a change, refresh the search results.
    if (result != null) widget.onSearch();
  }

  // ── Overlay UI ────────────────────────────────────────────────────────────

  Widget _buildOverlayContent(BuildContext ctx) {
    // Plain Positioned at the precomputed absolute screen offset.
    // No CompositedTransformFollower — avoids all RenderFollowerLayer errors.
    return Positioned(
      left: _dropdownOffset.dx,
      top: _dropdownOffset.dy,
      width: _dropdownWidth,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_suggestions.length, (i) {
                  final p = _suggestions[i];
                  final isFocused = i == _focusedIndex;
                  final name = (p['name'] ?? '').toString();
                  final sku = (p['sku'] ?? '—').toString();
                  final price = AppCurrency.format(p['price']);
                  // The row tap (select/search) and the quick-view icon are in
                  // separate, non-overlapping widgets so their gestures never
                  // compete. Using nested InkWells previously caused both onTap
                  // callbacks to fire on a single tap.
                  return ColoredBox(
                    color: isFocused ? AppTheme.primarySoft : Colors.transparent,
                    child: Row(
                      children: [
                        // ── Tappable left area (select & search) ──────────
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectAtIndex(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2_rounded,
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
                                          name,
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
                                        const SizedBox(height: 2),
                                        Text(
                                          'SKU: $sku · $price',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── Quick-view icon (separate tap area) ───────────
                        Tooltip(
                          message: 'Quick view / edit',
                          child: InkWell(
                            onTap: () => _quickViewAtIndex(i),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: isFocused
                                    ? AppTheme.primary
                                    : AppTheme.textMuted,
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
    );
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
          hintText: 'Search product, SKU, barcode...',
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
  final List<dynamic> _products = [];
  final _searchController = TextEditingController();

  late ProductService _productService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
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
      _products.clear();
      _page = 1;
    }

    try {
      final data = await _productService.getProducts(
        page: _page,
        search: _search,
      );

      final wrapper = (data['data'] as List).first;
      final items = wrapper['products'] as List<dynamic>;

      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(items);
        _page = (wrapper['current_page'] as num?)?.toInt() ?? _page;
        _lastPage = (wrapper['last_page'] as num?)?.toInt() ?? _lastPage;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load products: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  int _intVal(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
  double _doubleVal(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Future<void> _openForm([dynamic product]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (!mounted) return;
    if (result != null) _fetchProducts(reset: true);
  }

  Future<void> _confirmDelete(dynamic product) async {
    final name = (product['name'] ?? 'this product').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "$name"? This action cannot be undone.'),
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

    if (confirm == true) await _deleteProduct(product['id']);
  }

  Future<void> _printBarcodeLabels(dynamic product) async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('print-barcode-labels')) {
      AppFeedback.error(context, 'You do not have permission to print product labels.');
      return;
    }
    if (!auth.hasAddon('barcode_labels')) {
      AppFeedback.warning(
        context,
        'Barcode Label Printing is not active for this branch.',
      );
      return;
    }

    final barcode = (product['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) {
      AppFeedback.warning(context, 'Add a barcode to this product before printing labels.');
      return;
    }

    final printerConfig = context.read<PrinterConfigProvider>();
    try {
      final token = auth.token;
      if (token == null) throw Exception('Your session has expired. Please sign in again.');
      // Refresh here so a recent branch switch cannot print with another
      // branch's cached label size or printer destination.
      await printerConfig.refresh(token);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not load barcode printer settings: $e');
      return;
    }
    if (!mounted) return;

    final config = printerConfig.config.copyWith(
      barcodeCurrency: context.read<BranchProvider>().currency,
    );
    if (!config.isBarcodeConfigured) {
      AppFeedback.warning(
        context,
        config.barcodeAddonActive
            ? 'Ask a Master Admin to configure the Barcode Printer for this branch.'
            : 'Barcode Label Printing is not active for this branch.',
      );
      return;
    }

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
    final canPrintBarcodes = auth.hasPermission('print-barcode-labels')
        && auth.hasAddon('barcode_labels');
    return EnterprisePage(
      title: 'Products',
      subtitle: 'Manage SKU, pricing, brands, categories and available stock.',
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
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Product'),
          ),
        ],
      ],
      bottomNavigationBar: _products.isNotEmpty
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
              SizedBox(
                width: MediaQuery.of(context).size.width >= 720 ? 420 : double.infinity,
                child: _ProductAutoSearchField(
                  controller: _searchController,
                  productService: _productService,
                  onSearch: _onSearch,
                  onClear: _clearSearch,
                ),
              ),
              Tooltip(
                message: _showCost ? 'Hide cost price' : 'Show cost price',
                child: IconButton(
                  icon: Icon(_showCost ? Icons.visibility_off_rounded : Icons.visibility_rounded),
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
                  : _products.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            EnterpriseEmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: 'No products found',
                              subtitle: _search.isEmpty
                                  ? 'Add your first product to start selling and tracking stock.'
                                  : 'No product matched your search. Try SKU, barcode, product name or category.',
                              action: canManageProducts
                                  ? FilledButton.icon(
                                      onPressed: () => _openForm(),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Add Product'),
                                    )
                                  : null,
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            // Here's the corrected code to preserve decimals:
                            final p = _products[index];
                            final name = (p['name'] ?? 'Product').toString();
                            final selectedBranchId = context.watch<BranchProvider>().selectedBranchId;
                            final stocks = (p['stocks'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

                            // FIX: Use fold<double> instead of fold<int>, and _doubleVal instead of _intVal
                            final stockQty = selectedBranchId == null
                                ? stocks.fold<double>(0.0, (sum, s) => sum + _doubleVal(s['quantity']))
                                : stocks
                                    .where((s) => _intVal(s['branch_id']) == selectedBranchId)
                                    .fold<double>(0.0, (sum, s) => sum + _doubleVal(s['quantity']));

                            final brand = (p['brand']?['name'] ?? '—').toString();
                            final category = (p['category']?['name'] ?? '—').toString();
                            final price = AppCurrency.format(p['price']);
                            final sku = (p['sku'] ?? '—').toString();
                            final stockColor = stockQty <= 0 ? AppTheme.danger : stockQty <= 5 ? AppTheme.warning : AppTheme.success;

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primarySoft,
                                  foregroundColor: AppTheme.primary,
                                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    EnterpriseStatusBadge(
                                      label: stockQty <= 0 ? 'OUT' : 'STOCK $stockQty',
                                      color: stockColor,
                                      icon: Icons.inventory_rounded,
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
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
                                        label: 'Price',
                                        value: price,
                                        color: AppTheme.primary,
                                        icon: Icons.sell_rounded,
                                      ),
                                      if (_showCost)
                                        EnterpriseMetricChip(
                                          label: 'Cost',
                                          value: AppCurrency.format(p['cost_price'] ?? 0),
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
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (canPrintBarcodes)
                                      IconButton(
                                        tooltip: 'Print barcode labels',
                                        onPressed: () => _printBarcodeLabels(p),
                                        icon: const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                                      ),
                                    if (canManageProducts) ...[
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => _openForm(p),
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () => _confirmDelete(p),
                                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
