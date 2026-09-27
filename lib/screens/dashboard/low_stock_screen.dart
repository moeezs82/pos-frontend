import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  static const int _perPage = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 56;

  final _numberFmt = NumberFormat.decimalPattern();
  final _scrollController = ScrollController();
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};

  late ReportsService _service;
  int _lastPage = 1;
  int _total = 0;
  String? _error;

  bool get _initialLoading => _loadingPages.contains(1) && _pages.isEmpty;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = ReportsService(token: token);
    _scrollController.addListener(_onScroll);
    _resetAndLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetAndLoad() async {
    if (!mounted) return;
    setState(() {
      _pages.clear();
      _loadingPages.clear();
      _lastPage = 1;
      _total = 0;
      _error = null;
    });
    await _loadPage(1, force: true);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _loadPage(int page, {bool force = false}) async {
    if (page < 1 || (_pages.isNotEmpty && page > _lastPage)) return;
    if (!force && (_pages.containsKey(page) || _loadingPages.contains(page))) return;
    if (mounted) setState(() => _loadingPages.add(page));

    try {
      final data = await _service.runEnterpriseReport(
        reportKey: 'low-stock',
        filters: {
          'page': page,
          'per_page': _perPage,
          'sort_by': 'quantity',
          'direction': 'asc',
        },
      );
      final rows = ((data['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      final pagination = Map<String, dynamic>.from((data['pagination'] as Map?) ?? const {});
      final current = (pagination['current_page'] as num?)?.toInt() ?? page;
      final last = (pagination['last_page'] as num?)?.toInt() ?? 1;
      final total = (pagination['total'] as num?)?.toInt() ??
          (last <= 1 ? rows.length : (last - 1) * _perPage + rows.length);

      if (!mounted) return;
      setState(() {
        _pages[current] = rows;
        _lastPage = last < 1 ? 1 : last;
        _total = total < rows.length ? rows.length : total;
        _loadingPages.remove(page);
        _error = null;
        _evictFarPages(_visiblePageEstimate());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages.remove(page);
        _error = e.toString();
      });
      AppFeedback.error(context, 'Failed to load low stock: $e');
    }
  }

  int _visiblePageEstimate() {
    if (!_scrollController.hasClients || _total == 0) return 1;
    final index = (_scrollController.offset / _rowExtent).floor().clamp(0, _total - 1);
    return (index ~/ _perPage) + 1;
  }

  void _evictFarPages(int anchor) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()
      ..sort((a, b) => (b - anchor).abs().compareTo((a - anchor).abs()));
    for (final key in keys) {
      if (_pages.length <= _maxCachedPages) break;
      if ((key - anchor).abs() <= 1) continue;
      _pages.remove(key);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _total == 0) return;
    final first = (_scrollController.offset / _rowExtent).floor().clamp(0, _total - 1);
    final count = (_scrollController.position.viewportDimension / _rowExtent).ceil() + 8;
    final lastIndex = (first + count).clamp(0, _total - 1);
    final firstPage = (first ~/ _perPage) + 1;
    final lastPage = (lastIndex ~/ _perPage) + 1;
    for (var page = firstPage; page <= lastPage; page++) {
      _loadPage(page);
    }
    if (lastPage < _lastPage) _loadPage(lastPage + 1);
    if (firstPage > 1) _loadPage(firstPage - 1);
    if (_pages.length > _maxCachedPages && mounted) {
      setState(() => _evictFarPages(firstPage));
    }
  }

  Map<String, dynamic>? _rowAt(int index) {
    final page = (index ~/ _perPage) + 1;
    final local = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(page));
      return null;
    }
    return local < rows.length ? rows[local] : null;
  }

  num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return EnterprisePage(
      title: 'Low Stock',
      subtitle: 'Products at or below their reorder level, loaded with bounded server-backed scrolling.',
      icon: Icons.warning_amber_rounded,
      actions: [
        OutlinedButton.icon(
          onPressed: _resetAndLoad,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _initialLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null && _pages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 34),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _resetAndLoad, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                      ],
                    ),
                  )
                : _total == 0
                    ? const EnterpriseEmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'All stocked up',
                        subtitle: 'No products are currently at or below their reorder level.',
                      )
                    : Column(
                        children: [
                          _header(),
                          Expanded(
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _scrollController,
                                itemExtent: _rowExtent,
                                cacheExtent: _rowExtent * 12,
                                itemCount: _total,
                                itemBuilder: (_, index) {
                                  final row = _rowAt(index);
                                  return row == null ? _loadingRow() : _dataRow(row);
                                },
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            color: AppTheme.surfaceSoft,
                            child: Text(
                              '$_total low-stock item${_total == 1 ? '' : 's'} • ${_pages.length} cached page${_pages.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _header() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppTheme.surfaceSoft,
        child: const Row(
          children: [
            Expanded(flex: 32, child: Text('PRODUCT', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 150, child: Text('SKU', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 18, child: Text('CATEGORY', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 130, child: Text('STOCK', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 130, child: Text('REORDER AT', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 18, child: Text('BRANCH', style: _headerStyle)),
          ],
        ),
      );

  Widget _dataRow(Map<String, dynamic> row) {
    final name = (row['product'] ?? 'Product').toString();
    final sku = (row['sku'] ?? '—').toString();
    final qty = _num(row['quantity']);
    final reorderLevel = _num(row['reorder_level']);
    final branch = (row['branch'] ?? '—').toString();
    final category = (row['category'] ?? '—').toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          Expanded(flex: 32, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(width: 16),
          SizedBox(width: 150, child: Text(sku, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 16),
          Expanded(flex: 18, child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 16),
          SizedBox(width: 130, child: Text(_numberFmt.format(qty), style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w900))),
          const SizedBox(width: 16),
          SizedBox(width: 130, child: Text(_numberFmt.format(reorderLevel), style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 16),
          Expanded(flex: 18, child: Text(branch, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _loadingRow() => const DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  static const TextStyle _headerStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: .25,
  );
}
