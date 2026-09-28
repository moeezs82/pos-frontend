import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/product_screen.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_create.dart';
import 'package:enterprise_pos/screens/purchases/purchase_claim_detail.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PurchaseClaimsScreen extends StatefulWidget {
  const PurchaseClaimsScreen({super.key});

  @override
  State<PurchaseClaimsScreen> createState() => _PurchaseClaimsScreenState();
}

class _PurchaseClaimsScreenState extends State<PurchaseClaimsScreen> {
  static const int _pageSize = 15;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  final Map<int, List<dynamic>> _pageCache = {};
  final Map<int, int> _pageAccessOrder = {};
  final Set<int> _loadingPages = {};
  int _cacheAccessTick = 0;
  int _requestGeneration = 0;
  int _lastPage = 1;
  int _total = 0;
  bool _initialLoading = true;
  bool _refreshing = false;

  int? _selectedVendorId;
  String? _selectedVendorLabel;
  String? _status;
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _currency = const AppMoneyFormatter();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _fetchInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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
      final params = <String, String>{
        'page': '$page',
        if (_selectedVendorId != null) 'vendor_id': '$_selectedVendorId',
        if (_status != null && _status!.isNotEmpty) 'status': _status!,
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        if (_fromDate != null) 'date_from': _fmtDate(_fromDate!),
        if (_toDate != null) 'date_to': _fmtDate(_toDate!),
      };
      final uri = Uri.parse('${ApiClient.baseUrl}/purchase-claims')
          .replace(queryParameters: params);
      final token = context.read<AuthProvider>().token!;
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (generation != _requestGeneration) return;
      if (res.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load purchase claims')),
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

  dynamic _claimAt(int index) {
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searchQuery = value.trim());
      await _fetchInitial();
    });
  }

  Future<void> _openVendorPicker() async {
    final token = context.read<AuthProvider>().token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * .85,
        child: VendorPickerSheet(token: token),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (picked == null) {
        _selectedVendorId = null;
        _selectedVendorLabel = null;
      } else {
        _selectedVendorId = _toInt(picked['id']);
        final first = (picked['first_name'] ?? '').toString().trim();
        final last = (picked['last_name'] ?? '').toString().trim();
        final name = [first, last].where((part) => part.isNotEmpty).join(' ');
        _selectedVendorLabel = name.isEmpty
            ? 'Vendor #${picked['id']}'
            : name;
      }
    });
    await _fetchInitial();
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? (_fromDate ?? now) : (_toDate ?? _fromDate ?? now),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    await _fetchInitial();
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedVendorId = null;
      _selectedVendorLabel = null;
      _status = null;
      _fromDate = null;
      _toDate = null;
    });
    await _fetchInitial();
  }

  int get _activeFilterCount =>
      (_selectedVendorId != null ? 1 : 0) +
      (_status != null ? 1 : 0) +
      (_fromDate != null ? 1 : 0) +
      (_toDate != null ? 1 : 0) +
      (_searchQuery.isNotEmpty ? 1 : 0);

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppTheme.success;
      case 'pending':
        return AppTheme.warning;
      case 'rejected':
        return AppTheme.danger;
      case 'closed':
        return AppTheme.info;
      default:
        return AppTheme.textMuted;
    }
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().hasPermission('manage-purchases');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.purchaseClaims,
      onOpenProducts: () => PosNavigation.openSingleton(
        routeId: PosRouteIds.products,
        builder: (_) => const ProductsScreen(),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(canManage),
            const SizedBox(height: 12),
            _buildFilterBar(),
            if (_activeFilterCount > 0) ...[
              const SizedBox(height: 8),
              _buildActiveFilters(),
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
                              icon: Icons.assignment_return_outlined,
                              title: 'No purchase claims found',
                              subtitle: 'Try changing the search or filters.',
                            ),
                          ],
                        )
                      : _buildTable(),
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

  Widget _buildHeader(bool canManage) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase Claims',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.45,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Track supplier claims, recovery status and outstanding claim value.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            IconButton(
              tooltip: 'Refresh claims',
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final created = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreatePurchaseClaimScreen(),
                    ),
                  );
                  if (created == true && mounted) await _fetchInitial();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Claim'),
              ),
          ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = math.min(
            350.0,
            math.max(250.0, constraints.maxWidth * .28),
          ).toDouble();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Claim or purchase invoice',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              _filterButton(
                Icons.storefront_outlined,
                _selectedVendorLabel ?? 'All vendors',
                _openVendorPicker,
              ),
              PopupMenuButton<String>(
                tooltip: 'Claim status',
                onSelected: (value) async {
                  setState(() => _status = value == 'all' ? null : value);
                  await _fetchInitial();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(value: 'all', child: Text('All statuses')),
                  PopupMenuItem<String>(value: 'pending', child: Text('Pending')),
                  PopupMenuItem<String>(value: 'approved', child: Text('Approved')),
                  PopupMenuItem<String>(value: 'rejected', child: Text('Rejected')),
                  PopupMenuItem<String>(value: 'closed', child: Text('Closed')),
                ],
                child: _filterSurface(
                  Icons.flag_outlined,
                  _status == null
                      ? 'All statuses'
                      : '${_status![0].toUpperCase()}${_status!.substring(1)}',
                ),
              ),
              _filterButton(
                Icons.date_range_outlined,
                _fromDate == null
                    ? 'From date'
                    : DateFormat('dd MMM yyyy').format(_fromDate!),
                () => _pickDate(from: true),
              ),
              _filterButton(
                Icons.event_available_outlined,
                _toDate == null
                    ? 'To date'
                    : DateFormat('dd MMM yyyy').format(_toDate!),
                () => _pickDate(from: false),
              ),
              if (_activeFilterCount > 0)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                  label: const Text('Clear'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: _filterSurface(icon, label),
    );
  }

  Widget _filterSurface(IconData icon, String label) {
    return Container(
      height: 42,
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderStrong),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppTheme.textMuted),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (_selectedVendorId != null)
          InputChip(
            label: Text(_selectedVendorLabel ?? 'Vendor'),
            onDeleted: () async {
              setState(() {
                _selectedVendorId = null;
                _selectedVendorLabel = null;
              });
              await _fetchInitial();
            },
          ),
        if (_status != null)
          InputChip(
            label: Text('Status: $_status'),
            onDeleted: () async {
              setState(() => _status = null);
              await _fetchInitial();
            },
          ),
        if (_fromDate != null)
          InputChip(
            label: Text('From ${DateFormat('dd MMM yyyy').format(_fromDate!)}'),
            onDeleted: () async {
              setState(() => _fromDate = null);
              await _fetchInitial();
            },
          ),
        if (_toDate != null)
          InputChip(
            label: Text('To ${DateFormat('dd MMM yyyy').format(_toDate!)}'),
            onDeleted: () async {
              setState(() => _toDate = null);
              await _fetchInitial();
            },
          ),
      ],
    );
  }

  Widget _buildTable() {
    const widths = <double>[165, 145, 165, 220, 120, 120, 120, 105, 70];
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
                    const [
                      'Claim',
                      'Date',
                      'Purchase',
                      'Vendor',
                      'Total',
                      'Received',
                      'Balance',
                      'Status',
                      '',
                    ],
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
                            final claim = _claimAt(index);
                            return claim == null
                                ? _loadingRow(index)
                                : _claimRow(claim);
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
    const widths = <double>[165, 145, 165, 220, 120, 120, 120, 105, 70];
    return Container(
      height: header ? 42 : _rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header ? AppTheme.surfaceSoft : Colors.white,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: List.generate(cells.length, (index) {
          final numeric = index >= 4 && index <= 6;
          return SizedBox(
            width: widths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
              cells[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: numeric ? TextAlign.right : TextAlign.left,
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

  Widget _claimRow(dynamic claim) {
    final claimNo = (claim['claim_no'] ?? '').toString();
    final purchase = claim['purchase'];
    final invoice = (purchase?['invoice_no'] ?? '—').toString();
    final vendorData = purchase?['vendor'];
    final first = (vendorData?['first_name'] ?? '').toString().trim();
    final last = (vendorData?['last_name'] ?? '').toString().trim();
    final vendor = [first, last].where((part) => part.isNotEmpty).join(' ');
    final total = _toDouble(claim['total']);
    final received = _toDouble(claim['received_total']);
    final balance = math.max(0, total - received).toDouble();
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);
    final date = _tryParseDate(claim['created_at']);
    final cells = <String>[
      claimNo,
      date == null ? '' : DateFormat('dd MMM yyyy • HH:mm').format(date),
      invoice,
      vendor.isEmpty ? 'Vendor #${claim['vendor_id'] ?? '—'}' : vendor,
      _currency.format(total),
      _currency.format(received),
      _currency.format(balance),
      status.isEmpty ? '—' : status.toUpperCase(),
      '',
    ];

    return InkWell(
      onTap: () async {
        final id = _toInt(claim['id']);
        if (id == null) return;
        final changed = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseClaimDetailScreen(claimId: id),
          ),
        );
        if (changed == true && mounted) await _fetchInitial();
      },
      child: Stack(
        children: [
          _tableRow(cells),
          Positioned(
            right: 15,
            top: 10,
            child: IconButton(
              tooltip: 'Copy claim number',
              icon: const Icon(Icons.copy_rounded, size: 17),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: claimNo));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied: $claimNo')),
                );
              },
            ),
          ),
          Positioned(
            right: 87,
            top: 20,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
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
            width: 130,
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
            '$_total claim${_total == 1 ? '' : 's'}',
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
              'Bounded server paging • claim approval/receipt/rejection logic unchanged',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_loadingPages.isNotEmpty && !_initialLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
        ],
      ),
    );
  }
}
