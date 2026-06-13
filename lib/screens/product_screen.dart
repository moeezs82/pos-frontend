import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
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
        FilledButton.icon(
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Product'),
        ),
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
                              action: FilledButton.icon(
                                onPressed: () => _openForm(),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add Product'),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final p = _products[index];
                            final name = (p['name'] ?? 'Product').toString();
                            final selectedBranchId = context.watch<BranchProvider>().selectedBranchId;
                            final stocks = (p['stocks'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                            final stockQty = selectedBranchId == null
                                ? stocks.fold<int>(0, (sum, s) => sum + _intVal(s['quantity']))
                                : stocks
                                    .where((s) => _intVal(s['branch_id']) == selectedBranchId)
                                    .fold<int>(0, (sum, s) => sum + _intVal(s['quantity']));
                            final brand = (p['brand']?['name'] ?? '—').toString();
                            final category = (p['category']?['name'] ?? '—').toString();
                            final price = (p['price'] ?? '0').toString();
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
