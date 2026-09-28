import 'dart:convert';
import 'dart:math' as math;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  static const int _pageSize = 20;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  final Map<int, List<dynamic>> _pageCache = {};
  final Map<int, int> _pageAccessOrder = {};
  final Set<int> _loadingPages = {};
  int _requestGeneration = 0;
  int _cacheAccessTick = 0;
  int _lastPage = 1;
  int _total = 0;
  bool _initialLoading = true;
  bool _refreshing = false;

  Map<String, dynamic>? _selectedProduct;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _qty(dynamic value) {
    final number = _toDouble(value);
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _fetchInitial() async {
    if (!mounted) return;
    ++_requestGeneration;
    setState(() {
      _initialLoading = true;
      _pageCache.clear();
      _pageAccessOrder.clear();
      _loadingPages.clear();
      _lastPage = 1;
      _total = 0;
    });
    await _loadPage(1);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _loadPage(int page) async {
    if (page < 1 || _loadingPages.contains(page)) return;
    final generation = _requestGeneration;
    if (_pageCache.containsKey(page)) {
      _touchPage(page);
      return;
    }
    if (mounted) setState(() => _loadingPages.add(page));

    try {
      final query = <String, String>{
        'page': '$page',
        'per_page': '$_pageSize',
        if (_selectedProduct != null)
          'product_id': _selectedProduct!['id'].toString(),
      };
      final token = context.read<AuthProvider>().token!;
      final uri = Uri.parse('${ApiClient.baseUrl}/stocks')
          .replace(queryParameters: query);
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load stock')),
          );
        }
        return;
      }
      final decoded = jsonDecode(res.body);
      final data = decoded['data'];
      final rows = List<dynamic>.from(data['data'] ?? const []);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _pageCache[page] = rows;
        _lastPage = _toInt(data['last_page']) ?? 1;
        _total = _toInt(data['total']) ??
            ((_lastPage - 1) * _pageSize + rows.length);
        _touchPage(page);
        _evictOldPages(keepPage: page);
      });
    } finally {
      if (mounted) setState(() => _loadingPages.remove(page));
    }
  }

  void _touchPage(int page) {
    _pageAccessOrder[page] = ++_cacheAccessTick;
  }

  int _estimatedVisiblePage() {
    if (!_scrollController.hasClients) return 1;
    final firstIndex = (_scrollController.offset / _rowExtent).floor();
    return (firstIndex ~/ _pageSize) + 1;
  }

  void _evictOldPages({required int keepPage}) {
    if (_pageCache.length <= _maxCachedPages) return;
    final visible = _estimatedVisiblePage();
    final protected = <int>{keepPage, visible, visible - 1, visible + 1}
      ..removeWhere((page) => page < 1 || page > _lastPage);
    while (_pageCache.length > _maxCachedPages) {
      int? victim;
      int? oldest;
      for (final page in _pageCache.keys) {
        if (protected.contains(page)) continue;
        final tick = _pageAccessOrder[page] ?? 0;
        if (oldest == null || tick < oldest) {
          oldest = tick;
          victim = page;
        }
      }
      if (victim == null) break;
      _pageCache.remove(victim);
      _pageAccessOrder.remove(victim);
    }
  }

  dynamic _stockAt(int index) {
    final page = (index ~/ _pageSize) + 1;
    final offset = index % _pageSize;
    final cached = _pageCache[page];
    if (cached == null) {
      if (!_loadingPages.contains(page)) {
        Future.microtask(() => _loadPage(page));
      }
      return null;
    }
    _touchPage(page);
    return offset < cached.length ? cached[offset] : null;
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    try {
      await _fetchInitial();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<Map<String, dynamic>?> _pickProduct() async {
    final token = context.read<AuthProvider>().token!;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(token: token),
    );
  }

  Future<void> _selectProductFilter() async {
    final picked = await _pickProduct();
    if (picked == null || !mounted) return;
    setState(() => _selectedProduct = picked);
    await _fetchInitial();
  }

  Future<void> _clearProductFilter() async {
    setState(() => _selectedProduct = null);
    await _fetchInitial();
  }

  Future<void> _adjustStock(dynamic stock) async {
    final qtyController = TextEditingController();
    Map<String, dynamic>? selectedProduct = stock['product'] is Map
        ? Map<String, dynamic>.from(stock['product'])
        : null;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Adjust Stock'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await _pickProduct();
                      if (picked != null) {
                        setDialogState(() => selectedProduct = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Product',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        selectedProduct?['name']?.toString() ?? 'Select product',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Adjustment quantity',
                      helperText: 'Use a positive value to add stock or a negative value to reduce it.',
                      hintText: 'e.g. 10 or -5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final qty = double.tryParse(qtyController.text.trim()) ?? 0;
                  final productId = _toInt(selectedProduct?['id']);
                  if (qty == 0 || productId == null) return;
                  final token = context.read<AuthProvider>().token!;
                  final res = await http.post(
                    Uri.parse('${ApiClient.baseUrl}/stocks/adjust'),
                    headers: {
                      'Authorization': 'Bearer $token',
                      'Accept': 'application/json',
                    },
                    body: {
                      'product_id': '$productId',
                      'quantity': '$qty',
                      'reason': 'manual adjustment',
                    },
                  );
                  if (!mounted) return;
                  if (res.statusCode >= 200 && res.statusCode < 300) {
                    Navigator.pop(dialogContext);
                    await _fetchInitial();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stock adjustment failed')),
                    );
                  }
                },
                child: const Text('Save Adjustment'),
              ),
            ],
          );
        },
      ),
    );
    qtyController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAdjust = context.watch<AuthProvider>().hasPermission('adjust-stock');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.stock,
      onOpenProducts: () => PosNavigation.openSingleton(
        routeId: PosRouteIds.products,
        builder: (_) => const ProductsScreen(),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildFilterBar(),
            if (_selectedProduct != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    'Product: ${_selectedProduct!['name'] ?? '#${_selectedProduct!['id']}'}',
                  ),
                  onDeleted: _clearProductFilter,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            if (_refreshing) const SizedBox(height: 8),
            Expanded(
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _total == 0
                      ? ListView(
                          children: const [
                            SizedBox(height: 70),
                            EnterpriseEmptyState(
                              icon: Icons.warehouse_outlined,
                              title: 'No stock found',
                              subtitle: 'No stock balances match the selected product.',
                            ),
                          ],
                        )
                      : _buildTable(canAdjust),
            ),
            if (_total > 0) ...[
              const SizedBox(height: 8),
              _buildStatusBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Current branch inventory balances with controlled manual adjustments.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh stock',
          onPressed: _onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _selectProductFilter,
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(
              _selectedProduct == null
                  ? 'All products'
                  : (_selectedProduct!['name'] ?? 'Selected product').toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_selectedProduct != null)
            TextButton.icon(
              onPressed: _clearProductFilter,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
              label: const Text('Clear'),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(bool canAdjust) {
    const widths = <double>[300, 170, 180, 180, 150, 90];
    final minWidth = widths.fold<double>(0, (sum, width) => sum + width) + 24;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(minWidth, constraints.maxWidth).toDouble();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableRow(
                    const ['Product', 'SKU', 'Barcode', 'Branch', 'Quantity', ''],
                    header: true,
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemExtent: _rowExtent,
                          itemCount: _total,
                          cacheExtent: _rowExtent * 12,
                          itemBuilder: (_, index) {
                            final stock = _stockAt(index);
                            return stock == null
                                ? _loadingRow(index)
                                : _stockRow(stock, canAdjust);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableRow(List<String> cells, {bool header = false}) {
    const widths = <double>[300, 170, 180, 180, 150, 90];
    return Container(
      height: header ? 42 : _rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header ? AppTheme.surfaceSoft : Colors.white,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: List.generate(cells.length, (index) {
          return SizedBox(
            width: widths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
              cells[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: index == 4 ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: header ? AppTheme.textMuted : AppTheme.navy,
                fontSize: header ? 11 : 12,
                fontWeight: header ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _stockRow(dynamic stock, bool canAdjust) {
    final product = stock['product'];
    final branch = stock['branch'];
    final cells = <String>[
      (product?['name'] ?? 'Unknown product').toString(),
      (product?['sku'] ?? '—').toString(),
      (product?['barcode'] ?? '—').toString(),
      (branch?['name'] ?? 'Current branch').toString(),
      _qty(stock['quantity']),
      '',
    ];
    return Stack(
      children: [
        _tableRow(cells),
        if (canAdjust)
          Positioned(
            right: 15,
            top: 8,
            child: TextButton.icon(
              onPressed: () => _adjustStock(stock),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Adjust'),
            ),
          ),
      ],
    );
  }

  Widget _loadingRow(int index) {
    return Container(
      height: _rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 150,
            height: 10,
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const Spacer(),
          if (_loadingPages.contains((index ~/ _pageSize) + 1))
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            '$_total stock record${_total == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: AppTheme.border),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Branch-scoped inventory • bounded server paging • stock posting remains server-authoritative',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
