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
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  bool _importExportBusy = false;
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
                child: EnterpriseSearchField(
                  controller: _searchController,
                  hintText: 'Search product, SKU, barcode...',
                  onSubmitted: (_) => _onSearch(),
                  onSearch: _onSearch,
                  onClear: _clearSearch,
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
