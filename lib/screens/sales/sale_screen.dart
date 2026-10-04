import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_select_range_dialog.dart';
import 'package:enterprise_pos/screens/sales/picking_list_screen.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/services/batch_print_job_service.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/services/app_navigator.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // Data
  // Bounded virtual paging: keep only a small working set in memory.
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

  // Filters
  int? _selectedCustomerId;
  String? _selectedCustomerLabel;
  String _sortBy = "date"; // 'date' | 'total'
  String _searchQuery = "";
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _paymentStatusFilter;
  String? _saleTypeFilter;
  int? _saleSourceId;
  int? _areaId;
  int? _salesmanId;
  int? _deliveryBoyId;
  int? _createdById;
  List<Map<String, dynamic>> _saleSources = const [];
  List<Map<String, dynamic>> _areas = const [];
  List<Map<String, dynamic>> _salesmen = const [];
  List<Map<String, dynamic>> _deliveryBoys = const [];
  List<Map<String, dynamic>> _creators = const [];
  List<String> _saleTypes = const [];

  // UI
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _currency = const AppMoneyFormatter();
  Timer? _searchDebounce;

  // ── Batch print ──────────────────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<int> _selectedSaleIds = {};

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

  // ── Batch print helpers ───────────────────────────────────────────────────

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedSaleIds.clear();
    });
  }

  void _toggleSaleSelection(int saleId) {
    setState(() {
      if (_selectedSaleIds.contains(saleId)) {
        _selectedSaleIds.remove(saleId);
      } else {
        _selectedSaleIds.add(saleId);
      }
    });
  }

  /// Collect all sale IDs in the given row range from cached pages.
  /// Pages not yet loaded are fetched on-demand (sequentially so we don't
  /// hammer the API). Returns null if cancelled mid-fetch.
  Future<List<int>?> _collectSaleIdsForRange(BatchRangeSelection range) async {
    final ids = <int>[];

    if (range.mode == BatchRangeMode.rows) {
      final from = (range.fromRow ?? 1) - 1; // 0-indexed
      final to = (range.toRow ?? _total) - 1;
      for (int i = from; i <= math.min(to, _total - 1); i++) {
        if (!mounted) return null;
        var sale = _saleAt(i);
        // If the page isn't cached yet, wait for it.
        if (sale == null) {
          final page = (i ~/ _pageSize) + 1;
          await _loadSalesPage(page: page);
          sale = _saleAt(i);
        }
        if (sale == null) continue;
        final id = _toInt(sale['id']);
        if (id != null) ids.add(id);
      }
    } else {
      // Invoice-number range: iterate all cached + yet-to-load pages
      final from = range.fromInvoice ?? '';
      final to = range.toInvoice ?? '';
      for (int i = 0; i < _total; i++) {
        if (!mounted) return null;
        var sale = _saleAt(i);
        if (sale == null) {
          final page = (i ~/ _pageSize) + 1;
          await _loadSalesPage(page: page);
          sale = _saleAt(i);
        }
        if (sale == null) continue;
        final inv = (sale['invoice_no'] ?? '').toString();
        if (inv.compareTo(from) >= 0 && inv.compareTo(to) <= 0) {
          final id = _toInt(sale['id']);
          if (id != null) ids.add(id);
        }
      }
    }
    return ids;
  }

  Future<void> _startBatchPrint(List<int> saleIds) async {
    if (saleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invoices selected for printing.')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final printerCfg = context.read<PrinterConfigProvider>();
    final token = auth.token ?? '';

    // Confirm secondary printer if configured
    bool printSecondary = false;
    if (printerCfg.secondaryPrintEnabled && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Secondary Printer'),
          content: Text(
            'A secondary printer (${printerCfg.secondaryLocalPrinterName ?? printerCfg.secondaryNetworkIp ?? 'configured'}) '
            'is set up. Also print on secondary for each invoice?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Main only'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Both printers'),
            ),
          ],
        ),
      );
      printSecondary = confirmed ?? false;
    }

    final config = BatchPrintConfig(
      activeConnection: printerCfg.activeConnection,
      networkIp: printerCfg.networkIp,
      networkPort: printerCfg.networkPort,
      localPrinterName: printerCfg.localPrinterName,
      secondaryEnabled: printerCfg.secondaryPrintEnabled,
      secondaryNetworkIp: printerCfg.secondaryNetworkIp,
      secondaryNetworkPort: printerCfg.secondaryNetworkPort,
      secondaryLocalPrinterName: printerCfg.secondaryLocalPrinterName,
      shopName: printerCfg.shopName,
      shopAddress: printerCfg.shopAddress,
      shopPhone: printerCfg.shopPhone,
      mainTemplate: printerCfg.mainInvoiceTemplate,
      secondaryTemplate: printerCfg.secondaryInvoiceTemplate,
      secondaryHeader: printerCfg.secondaryReceiptHeader,
      mainPaperCode: printerCfg.mainPaperCode,
      footerLines: printerCfg.footerLines,
      footerLineStyles: printerCfg.footerLineStyles,
      invoiceHeading: printerCfg.invoiceHeading,
      printLogo: printerCfg.printLogoEnabled,
      logoData: printerCfg.printLogoData,
      printQr: printerCfg.qrCodeEnabled,
      qrUrl: printerCfg.qrCodeUrl,
      qrCaption: printerCfg.qrCodeCaption,
      itemDiscountDisplay: printerCfg.itemDiscountDisplay,
      devCreditEnabled: printerCfg.devCreditEnabled,
      devCreditText: printerCfg.devCreditText,
      printSecondary: printSecondary,
    );

    BatchPrintJobService.instance.startJob(
      saleIds: saleIds,
      token: token,
      config: config,
    );

    setState(() {
      _selectionMode = false;
      _selectedSaleIds.clear();
    });
  }

  Future<void> _onBatchPrintFromRange() async {
    final result = await showBatchRangeDialog(
      context,
      totalRows: _total,
      confirmLabel: 'Print Invoices',
    );
    if (result == null || !mounted) return;

    // Show a loading dialog while we collect IDs
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Collecting invoices…'),
        ]),
      ),
    );
    final ids = await _collectSaleIdsForRange(result);
    if (mounted) Navigator.pop(context); // close loading dialog
    if (ids == null || !mounted) return;
    await _startBatchPrint(ids);
  }

  Future<void> _onSelectRangeForSelection() async {
    final result = await showBatchRangeDialog(
      context,
      totalRows: _total,
      confirmLabel: 'Select Invoices',
    );
    if (result == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Selecting invoices…'),
        ]),
      ),
    );
    final ids = await _collectSaleIdsForRange(result);
    if (mounted) Navigator.pop(context); // close loading dialog
    if (ids == null || !mounted) return;
    setState(() {
      _selectedSaleIds.addAll(ids);
    });
  }

  void _selectAllLoaded() {
    final ids = <int>{};
    for (final list in _pageCache.values) {
      for (final s in list) {
        final id = _toInt(s['id']);
        if (id != null) ids.add(id);
      }
    }
    setState(() => _selectedSaleIds.addAll(ids));
  }

  Future<void> _onBatchPrintSelected() async {
    final ids = _selectedSaleIds.toList();
    await _startBatchPrint(ids);
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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
    await Future.wait([
      _fetchFilterOptions(),
      _loadSalesPage(page: 1),
    ]);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _loadSalesPage({required int page}) async {
    if (page < 1 || _loadingPages.contains(page)) return;
    final generation = _requestGeneration;
    if (_pageCache.containsKey(page)) {
      _touchPage(page);
      return;
    }
    if (mounted) setState(() => _loadingPages.add(page));
    try {
      final params = <String, String>{
        'page': page.toString(),
        'sort_by': _sortBy == 'total' ? 'total' : 'date',
        if (_selectedCustomerId != null) 'customer_id': _selectedCustomerId!.toString(),
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        if (_fromDate != null) 'date_from': _fmtDate(_fromDate!),
        if (_toDate != null) 'date_to': _fmtDate(_toDate!),
        if (_paymentStatusFilter != null) 'payment_status': _paymentStatusFilter!,
        if (_saleTypeFilter != null) 'sale_type': _saleTypeFilter!,
        if (_saleSourceId != null) 'sale_source_id': _saleSourceId.toString(),
        if (_areaId != null) 'area_id': _areaId.toString(),
        if (_salesmanId != null) 'salesman_id': _salesmanId.toString(),
        if (_deliveryBoyId != null) 'delivery_boy_id': _deliveryBoyId.toString(),
        if (_createdById != null) 'created_by': _createdById.toString(),
      };
      final uri = Uri.parse('${ApiClient.baseUrl}/sales').replace(queryParameters: params);
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'});
      if (generation != _requestGeneration) return;
      if (res.statusCode != 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load sales')));
        return;
      }
      final decoded = jsonDecode(res.body);
      final data = decoded['data'];
      final list = List<dynamic>.from(data['data'] ?? const []);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _pageCache[page] = list;
        _lastPage = _toInt(data['last_page']) ?? 1;
        _total = _toInt(data['total']) ?? ((_lastPage - 1) * _pageSize + list.length);
        _touchPage(page);
        _evictOldPages(keepPage: page);
      });
    } finally {
      if (mounted) setState(() => _loadingPages.remove(page));
    }
  }

  void _touchPage(int page) => _pageAccessOrder[page] = ++_cacheAccessTick;

  int _estimatedVisiblePage() {
    if (!_scrollController.hasClients) return 1;
    final firstIndex = (_scrollController.offset / _rowExtent).floor();
    return (firstIndex ~/ _pageSize) + 1;
  }

  void _evictOldPages({required int keepPage}) {
    if (_pageCache.length <= _maxCachedPages) return;
    final visible = _estimatedVisiblePage();
    final protected = <int>{keepPage, visible, visible - 1, visible + 1}
      ..removeWhere((p) => p < 1 || p > _lastPage);
    while (_pageCache.length > _maxCachedPages) {
      int? victim;
      int? oldest;
      for (final page in _pageCache.keys) {
        if (protected.contains(page)) continue;
        final tick = _pageAccessOrder[page] ?? 0;
        if (oldest == null || tick < oldest) { oldest = tick; victim = page; }
      }
      if (victim == null) break;
      _pageCache.remove(victim);
      _pageAccessOrder.remove(victim);
    }
  }

  dynamic _saleAt(int index) {
    final page = (index ~/ _pageSize) + 1;
    final offset = index % _pageSize;
    final cached = _pageCache[page];
    if (cached == null) {
      if (!_loadingPages.contains(page)) Future.microtask(() => _loadSalesPage(page: page));
      return null;
    }
    _touchPage(page);
    return offset < cached.length ? cached[offset] : null;
  }

  Future<void> _fetchFilterOptions() async {
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final res = await http.get(
        Uri.parse("${ApiClient.baseUrl}/sales/filter-options"),
        headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      );
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map ? decoded['data'] : null;
      if (raw is! Map) return;
      List<Map<String, dynamic>> refs(String key) {
        final list = raw[key];
        if (list is! List) return const [];
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      final types = raw['sale_types'];
      setState(() {
        _saleSources = refs('sale_sources');
        _areas = refs('areas');
        _salesmen = refs('salesmen');
        _deliveryBoys = refs('delivery_boys');
        _creators = refs('creators');
        _saleTypes = types is List ? types.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const [];
      });
    } catch (_) {
      // Filters are convenience only; sales remain usable if references fail.
    }
  }

  int get _advancedFilterCount => [
        _paymentStatusFilter,
        _saleTypeFilter,
        _saleSourceId,
        _areaId,
        _salesmanId,
        _deliveryBoyId,
        _createdById,
      ].where((e) => e != null).length;

  String _refName(List<Map<String, dynamic>> rows, int? id) {
    if (id == null) return '';
    for (final row in rows) {
      if (_toInt(row['id']) == id) return (row['name'] ?? '#$id').toString();
    }
    return '#$id';
  }

  Future<void> _openAdvancedFilters() async {
    var payment = _paymentStatusFilter;
    var saleType = _saleTypeFilter;
    var sourceId = _saleSourceId;
    var areaId = _areaId;
    var salesmanId = _salesmanId;
    var deliveryBoyId = _deliveryBoyId;
    var createdById = _createdById;

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          DropdownMenuItem<int?> allItem(String label) => DropdownMenuItem<int?>(value: null, child: Text(label));
          List<DropdownMenuItem<int?>> refItems(List<Map<String, dynamic>> rows, String allLabel) => [
                allItem(allLabel),
                ...rows.map((r) => DropdownMenuItem<int?>(
                      value: _toInt(r['id']),
                      child: Text((r['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                    )),
              ];
          return AlertDialog(
            title: const Text('Sale Filters'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<String?>(
                        value: payment,
                        decoration: const InputDecoration(labelText: 'Payment Status', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('All Statuses')),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(value: 'partial', child: Text('Partial')),
                          DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                        ],
                        onChanged: (v) => setLocalState(() => payment = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<String?>(
                        value: saleType,
                        decoration: const InputDecoration(labelText: 'Sale Type', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Types')),
                          ..._saleTypes.map((v) => DropdownMenuItem<String?>(value: v, child: Text(_prettyLabel(v)))),
                        ],
                        onChanged: (v) => setLocalState(() => saleType = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: sourceId,
                        decoration: const InputDecoration(labelText: 'Sale From', border: OutlineInputBorder()),
                        items: refItems(_saleSources, 'All Sources'),
                        onChanged: (v) => setLocalState(() => sourceId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: areaId,
                        decoration: const InputDecoration(labelText: 'Town / Area', border: OutlineInputBorder()),
                        items: refItems(_areas, 'All Areas'),
                        onChanged: (v) => setLocalState(() => areaId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: salesmanId,
                        decoration: const InputDecoration(labelText: 'Salesman', border: OutlineInputBorder()),
                        items: refItems(_salesmen, 'All Salesmen'),
                        onChanged: (v) => setLocalState(() => salesmanId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: deliveryBoyId,
                        decoration: const InputDecoration(labelText: 'Delivery Boy', border: OutlineInputBorder()),
                        items: refItems(_deliveryBoys, 'All Delivery Boys'),
                        onChanged: (v) => setLocalState(() => deliveryBoyId = v),
                      ),
                    ),
                    SizedBox(
                      width: 285,
                      child: DropdownButtonFormField<int?>(
                        value: createdById,
                        decoration: const InputDecoration(labelText: 'Created By / Cashier', border: OutlineInputBorder()),
                        items: refItems(_creators, 'All Users'),
                        onChanged: (v) => setLocalState(() => createdById = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setLocalState(() {
                    payment = null;
                    saleType = null;
                    sourceId = null;
                    areaId = null;
                    salesmanId = null;
                    deliveryBoyId = null;
                    createdById = null;
                  });
                },
                child: const Text('Clear'),
              ),
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Apply')),
            ],
          );
        },
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _paymentStatusFilter = payment;
      _saleTypeFilter = saleType;
      _saleSourceId = sourceId;
      _areaId = areaId;
      _salesmanId = salesmanId;
      _deliveryBoyId = deliveryBoyId;
      _createdById = createdById;
    });
    await _fetchInitial();
  }

  String _prettyLabel(String value) {
    if (value.trim().isEmpty) return value;
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  Future<void> _clearAdvancedFilter(String key) async {
    setState(() {
      switch (key) {
        case 'payment': _paymentStatusFilter = null; break;
        case 'type': _saleTypeFilter = null; break;
        case 'source': _saleSourceId = null; break;
        case 'area': _areaId = null; break;
        case 'salesman': _salesmanId = null; break;
        case 'delivery': _deliveryBoyId = null; break;
        case 'creator': _createdById = null; break;
      }
    });
    await _fetchInitial();
  }

  Future<void> _onRefresh() async {
    if (mounted) setState(() => _refreshing = true);
    try { await _fetchInitial(); } finally { if (mounted) setState(() => _refreshing = false); }
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searchQuery = val.trim());
      await _fetchInitial();
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  ({String label, Color color}) _paymentStatus(dynamic sale) {
    final raw = (sale['payment_status'] ?? '').toString().toLowerCase();
    if (raw == 'paid') return (label: "PAID", color: Colors.green);
    if (raw == 'partial') return (label: "PARTIAL", color: Colors.orange);
    if (raw == 'unpaid' || raw == 'pending') return (label: "UNPAID", color: Colors.red);
    final total = _toDouble(sale['total']);
    final paid = _toDouble(sale['paid_amount']);
    if (total <= 0.004 || paid >= total - 0.004) return (label: "PAID", color: Colors.green);
    if (paid <= 0.004) return (label: "UNPAID", color: Colors.red);
    return (label: "PARTIAL", color: Colors.orange);
  }

  Future<void> _openCustomerPicker() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CustomerPickerSheet(token: token),
      ),
    );

    setState(() {
      if (picked == null) {
        _selectedCustomerId = null;
        _selectedCustomerLabel = null;
      } else {
        _selectedCustomerId = _toInt(picked['id']);
        _selectedCustomerLabel = CustomerDisplayUtils.nameWithArea(
          picked,
          fallback: 'Customer #${picked['id']}',
        );
      }
    });

    await _fetchInitial();
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      await _fetchInitial();
    }
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? _fromDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      await _fetchInitial();
    }
  }

  void _clearDates() async {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    await _fetchInitial();
  }


  Future<void> _openPickingList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickingListScreen(
          initialFromDate: _fromDate,
          initialToDate: _toDate,
          initialCustomerId: _selectedCustomerId,
          initialCustomerLabel: _selectedCustomerLabel,
          initialSearch: _searchQuery,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.hasPermission('create-sales');
    return CounterIQDesktopShell(
      activeRouteId: PosRouteIds.sales,
      onOpenProducts: () {},
      child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _buildWorkspaceHeader(canCreate),
              const SizedBox(height: 12),
              _buildFilterBar(),
              if (_activeFilterCount > 0) ...[const SizedBox(height: 8), _buildActiveFilters()],
              if (_selectionMode) ...[const SizedBox(height: 8), _buildSelectionToolbar()],
              const SizedBox(height: 10),
              if (_refreshing) const LinearProgressIndicator(minHeight: 2),
              if (_refreshing) const SizedBox(height: 8),
              Expanded(child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _total == 0
                      ? ListView(children: const [SizedBox(height: 70), EnterpriseEmptyState(icon: Icons.receipt_long_outlined, title: 'No sales found', subtitle: 'Try changing the search or filters.')])
                      : _buildSalesTable()),
              if (_total > 0) ...[const SizedBox(height: 8), _buildStatusBar()],
            ]),
          ),
    );
  }

  int get _activeFilterCount => _advancedFilterCount + (_selectedCustomerId != null ? 1 : 0) + (_fromDate != null ? 1 : 0) + (_toDate != null ? 1 : 0);

  Widget _buildWorkspaceHeader(bool canCreate) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Sales History', style: TextStyle(color: AppTheme.navy, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.45)),
      SizedBox(height: 4),
      Text('Review invoices, customers, payment status and sale activity.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
    ])),
    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(onPressed: _openPickingList, icon: const Icon(Icons.inventory_2_outlined, size: 18), label: const Text('Picking List')),
      // Toggle selection mode
      if (_total > 0)
        _selectionMode
            ? OutlinedButton.icon(
                onPressed: _toggleSelectionMode,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel Selection'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger)),
              )
            : OutlinedButton.icon(
                onPressed: _toggleSelectionMode,
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('Select'),
              ),
      // Batch print by range (always available when there are sales)
      if (_total > 0 && !_selectionMode)
        OutlinedButton.icon(
          onPressed: _onBatchPrintFromRange,
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Batch Print'),
        ),
      IconButton(tooltip: 'Refresh sales', onPressed: _onRefresh, icon: const Icon(Icons.refresh_rounded)),
      if (canCreate) FilledButton.icon(onPressed: () async { final created = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleScreen())); if (created == true && mounted) _fetchInitial(); }, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New Sale')),
    ])
  ]);

  Widget _buildSelectionToolbar() {
    final count = _selectedSaleIds.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_box_rounded, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            count == 0 ? 'Tap rows to select invoices' : '$count invoice${count == 1 ? '' : 's'} selected',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.navy),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _onSelectRangeForSelection,
            icon: const Icon(Icons.date_range_outlined, size: 16),
            label: const Text('Select Range'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _selectAllLoaded,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text('Select Loaded'),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _selectedSaleIds.clear()),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _onBatchPrintSelected,
              icon: const Icon(Icons.print_rounded, size: 17),
              label: Text('Print $count'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
    child: LayoutBuilder(builder: (context, constraints) => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(width: math.min(360.0, math.max(260.0, constraints.maxWidth * .28)).toDouble(), height: 42, child: TextField(controller: _searchController, onChanged: _onSearchChanged, decoration: InputDecoration(hintText: 'Invoice, customer, product, SKU or barcode', prefixIcon: const Icon(Icons.search_rounded, size: 19), suffixIcon: _searchController.text.isNotEmpty ? IconButton(onPressed: () { _searchController.clear(); _onSearchChanged(''); }, icon: const Icon(Icons.close_rounded, size: 18)) : null, isDense: true, border: const OutlineInputBorder()))),
      _filterButton(Icons.person_outline_rounded, _selectedCustomerLabel ?? 'All customers', _openCustomerPicker),
      _filterButton(Icons.date_range_outlined, _fromDate == null ? 'From date' : DateFormat('dd MMM yyyy').format(_fromDate!), _pickFromDate),
      _filterButton(Icons.event_available_outlined, _toDate == null ? 'To date' : DateFormat('dd MMM yyyy').format(_toDate!), _pickToDate),
      PopupMenuButton<String>(tooltip: 'Sort sales', onSelected: (v) async { setState(() => _sortBy = v); await _fetchInitial(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'date', child: Text('Newest date')), PopupMenuItem(value: 'total', child: Text('Amount'))], child: _filterSurface(Icons.swap_vert_rounded, _sortBy == 'total' ? 'Amount' : 'Date')),
      OutlinedButton.icon(onPressed: _openAdvancedFilters, icon: const Icon(Icons.tune_rounded, size: 18), label: Text(_advancedFilterCount == 0 ? 'More filters' : 'More filters ($_advancedFilterCount)')),
      if (_activeFilterCount > 0) TextButton.icon(onPressed: _clearAllFilters, icon: const Icon(Icons.filter_alt_off_rounded, size: 17), label: const Text('Clear')),
    ])),
  );

  Widget _filterButton(IconData icon, String label, VoidCallback onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: _filterSurface(icon, label));
  Widget _filterSurface(IconData icon, String label) => Container(height: 42, constraints: const BoxConstraints(maxWidth: 190), padding: const EdgeInsets.symmetric(horizontal: 11), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.borderStrong), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17, color: AppTheme.textMuted), const SizedBox(width: 7), Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontSize: 12, fontWeight: FontWeight.w700)))]));

  Future<void> _clearAllFilters() async {
    setState(() { _selectedCustomerId = null; _selectedCustomerLabel = null; _fromDate = null; _toDate = null; _paymentStatusFilter = null; _saleTypeFilter = null; _saleSourceId = null; _areaId = null; _salesmanId = null; _deliveryBoyId = null; _createdById = null; });
    await _fetchInitial();
  }

  Widget _buildActiveFilters() => Wrap(spacing: 6, runSpacing: 6, children: [
    if (_selectedCustomerId != null) InputChip(label: Text(_selectedCustomerLabel ?? 'Customer'), onDeleted: () async { setState(() { _selectedCustomerId = null; _selectedCustomerLabel = null; }); await _fetchInitial(); }),
    if (_fromDate != null) InputChip(label: Text('From ${DateFormat('dd MMM yyyy').format(_fromDate!)}'), onDeleted: () async { setState(() => _fromDate = null); await _fetchInitial(); }),
    if (_toDate != null) InputChip(label: Text('To ${DateFormat('dd MMM yyyy').format(_toDate!)}'), onDeleted: () async { setState(() => _toDate = null); await _fetchInitial(); }),
    if (_paymentStatusFilter != null) InputChip(label: Text('Payment: ${_prettyLabel(_paymentStatusFilter!)}'), onDeleted: () => _clearAdvancedFilter('payment')),
    if (_saleTypeFilter != null) InputChip(label: Text('Type: ${_prettyLabel(_saleTypeFilter!)}'), onDeleted: () => _clearAdvancedFilter('type')),
    if (_salesmanId != null) InputChip(label: Text('Salesman: ${_refName(_salesmen, _salesmanId)}'), onDeleted: () => _clearAdvancedFilter('salesman')),
    if (_areaId != null) InputChip(label: Text('Area: ${_refName(_areas, _areaId)}'), onDeleted: () => _clearAdvancedFilter('area')),
    if (_saleSourceId != null) InputChip(label: Text('Source: ${_refName(_saleSources, _saleSourceId)}'), onDeleted: () => _clearAdvancedFilter('source')),
    if (_deliveryBoyId != null) InputChip(label: Text('Rider: ${_refName(_deliveryBoys, _deliveryBoyId)}'), onDeleted: () => _clearAdvancedFilter('delivery')),
    if (_createdById != null) InputChip(label: Text('Created by: ${_refName(_creators, _createdById)}'), onDeleted: () => _clearAdvancedFilter('creator')),
  ]);

  Widget _buildSalesTable() {
    // In selection mode we add an extra 42 px checkbox column at the start.
    final widths = _selectionMode
        ? const <double>[42, 170, 132, 230, 150, 130, 125, 125, 105, 70]
        : const <double>[170, 132, 230, 150, 130, 125, 125, 105, 70];
    final minWidth = widths.fold<double>(0, (a, b) => a + b) + 24;

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

          final headerCells = _selectionMode
              ? const ['', 'Invoice', 'Date', 'Customer', 'Source', 'Total', 'Paid', 'Balance', 'Status', '']
              : const ['Invoice', 'Date', 'Customer', 'Source', 'Total', 'Paid', 'Balance', 'Status', ''];

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableRow(headerCells, header: true),
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
                            final sale = _saleAt(index);
                            return sale == null
                                ? _loadingRow(index)
                                : _saleRow(sale);
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

  Widget _tableRow(List<String> cells, {bool header = false, int? saleId}) {
    final widths = _selectionMode
        ? const <double>[42, 170, 132, 230, 150, 130, 125, 125, 105, 70]
        : const <double>[170, 132, 230, 150, 130, 125, 125, 105, 70];
    // In selection mode the first column is the checkbox; offset the numeric-align indices.
    final numericOffset = _selectionMode ? 1 : 0;
    final isSelected = saleId != null && _selectedSaleIds.contains(saleId);
    return Container(
      height: header ? 42 : _rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: header
            ? AppTheme.surfaceSoft
            : isSelected
                ? AppTheme.primarySoft
                : Colors.white,
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: List.generate(cells.length, (i) {
          // First cell in selection mode: checkbox
          if (_selectionMode && i == 0) {
            if (header) return const SizedBox(width: 42);
            return SizedBox(
              width: 42,
              child: Checkbox(
                value: isSelected,
                onChanged: saleId == null ? null : (_) => _toggleSaleSelection(saleId),
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }
          final dataIndex = i;
          final isNumeric = dataIndex >= (4 + numericOffset) && dataIndex <= (6 + numericOffset);
          return SizedBox(
            width: widths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                cells[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isNumeric ? TextAlign.right : TextAlign.left,
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

  Widget _saleRow(dynamic s) {
    final saleId = _toInt(s['id']) ?? 0;
    final total = _toDouble(s['total']); final paid = _toDouble(s['paid_amount']); final balance = s['balance_amount'] != null ? _toDouble(s['balance_amount']) : math.max(0, total - paid).toDouble(); final st = _paymentStatus(s);
    final dt = _tryParseDate(s['created_at'] ?? s['date']); final customer = (s['customer']?['first_name'] ?? 'Walk-in').toString();
    final invoiceNo = (s['invoice_no'] ?? '').toString();
    // In selection mode the checkbox column is prepended via _tableRow.
    final dataCells = [invoiceNo, dt == null ? (s['invoice_date'] ?? '').toString() : DateFormat('dd MMM yyyy • HH:mm').format(dt), customer, (s['sale_source_name'] ?? 'Counter').toString(), _currency.format(total), _currency.format(paid), _currency.format(balance), st.label, ''];
    final cells = _selectionMode ? ['', ...dataCells] : dataCells;
    return InkWell(
      onTap: _selectionMode
          ? () => _toggleSaleSelection(saleId)
          : () async {
              final changed = await Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: saleId)));
              if (changed == true && mounted) _fetchInitial();
            },
      child: Stack(children: [
        _tableRow(cells, saleId: saleId),
        if (!_selectionMode)
          Positioned(right: 15, top: 10, child: IconButton(tooltip: 'Copy invoice', icon: const Icon(Icons.copy_rounded, size: 17), onPressed: () async { await Clipboard.setData(ClipboardData(text: invoiceNo)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $invoiceNo'))); })),
      ]),
    );
  }

  Widget _loadingRow(int index) => Container(height: _rowExtent, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))), child: Row(children: [Container(width: 130, height: 10, decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(5))), const Spacer(), if (_loadingPages.contains((index ~/ _pageSize) + 1)) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8))]));

  Widget _buildStatusBar() => Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(10)), child: Row(children: [Text('$_total sale${_total == 1 ? '' : 's'}', style: const TextStyle(color: AppTheme.navy, fontSize: 12, fontWeight: FontWeight.w900)), const SizedBox(width: 8), Container(width: 1, height: 16, color: AppTheme.border), const SizedBox(width: 8), const Expanded(child: Text('Optimized server-backed loading • bounded memory while scrolling', overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))), if (_loadingPages.isNotEmpty && !_initialLoading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8))]));

}

DateTime? _tryParseDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

Widget _miniPill(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    margin: const EdgeInsets.only(right: 6),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      "$label: $value",
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

// Pick readable fg on any bg
(Color fg, Color bg) _chipPalette(BuildContext ctx, Color base) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final bg = isDark ? base.withOpacity(.25) : base.withOpacity(.12);
  final fg = isDark ? base.withOpacity(.95) : base.withOpacity(.90);
  return (fg, bg);
}

Widget _amountChip(
  BuildContext ctx,
  String label,
  String value,
  Color base, {
  IconData? icon,
}) {
  final (fg, bg) = _chipPalette(ctx, base);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    margin: const EdgeInsets.only(right: 6, top: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: base.withOpacity(.35), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800, // 🔥 emphasize the number
            color: fg,
          ),
        ),
      ],
    ),
  );
}
