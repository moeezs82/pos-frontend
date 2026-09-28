import 'dart:async' show Timer;
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/api/customer_area_service.dart';
import 'package:enterprise_pos/api/sale_source_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_feature_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/counteriq_desktop_shell.dart';
import 'package:enterprise_pos/widgets/report_pdf_export_dialog.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class EnterpriseReportsWorkspaceScreen extends StatefulWidget {
  final String? initialReportKey;

  const EnterpriseReportsWorkspaceScreen({super.key, this.initialReportKey});

  @override
  State<EnterpriseReportsWorkspaceScreen> createState() => _EnterpriseReportsWorkspaceScreenState();
}

class _EnterpriseReportsWorkspaceScreenState extends State<EnterpriseReportsWorkspaceScreen> {
  final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  final _currencyFmt = const AppMoneyFormatter();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  late ReportsService _service;
  late SaleSourceService _saleSourceService;
  late CustomerAreaService _customerAreaService;
  late _EnterpriseReportMeta _selectedReport;

  DateTime? _from;
  DateTime? _to;
  String? _status;
  String? _method;
  int? _saleSourceId;
  int? _areaId;
  int? _productVendorId;
  int? _stockCategoryId;
  int? _stockBrandId;
  int? _stockVendorId;
  int? _expenseAccountId;
  int? _expenseCreatedById;
  String? _customerType;
  List<Map<String, dynamic>> _saleSources = const [];
  List<Map<String, dynamic>> _customerAreas = const [];
  List<Map<String, dynamic>> _productVendors = const [];
  List<Map<String, dynamic>> _stockCategories = const [];
  List<Map<String, dynamic>> _stockBrands = const [];
  List<Map<String, dynamic>> _expenseAccounts = const [];
  List<Map<String, dynamic>> _expensePaymentMethods = const [];
  List<Map<String, dynamic>> _expenseCreators = const [];
  final Map<String, Set<String>> _hiddenColumnsByReport = <String, Set<String>>{};
  int? _observedBranchId;
  bool _branchRefreshScheduled = false;
  static const int _perPage = 50;
  static const int _maxCachedPages = 6;
  static const double _reportRowExtent = 40;
  final ScrollController _reportScrollController = ScrollController();
  final ScrollController _reportHorizontalController = ScrollController();
  final Map<int, _EnterpriseReportResponse> _reportPages = {};
  final Set<int> _loadingReportPages = {};
  int _lastPage = 1;
  int _totalRows = 0;
  int _requestGeneration = 0;

  bool _ready = false;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  _EnterpriseReportResponse? _result;

  List<_EnterpriseReportMeta> get _allReports => _enterpriseReports;

  static const _saleSourceReportKeys = <String>{
    'sales-summary',
    'sales-detail',
    'sales-by-product',
    'sales-by-vendor',
    'sales-by-category',
    'sales-by-brand',
    'sales-by-customer',
    'sales-by-salesman',
    'sales-by-hour',
    'sales-by-payment-method',
    'sales-by-source',
    'sales-by-area',
    'area-customer-potential',
    'sale-return-summary',
    'sale-return-detail',
    'discount-report',
    'tax-report',
  };

  static const _areaReportKeys = <String>{
    'sales-summary',
    'sales-detail',
    'sales-by-product',
    'sales-by-vendor',
    'sales-by-category',
    'sales-by-brand',
    'sales-by-customer',
    'sales-by-salesman',
    'sales-by-hour',
    'sales-by-payment-method',
    'sales-by-source',
    'sales-by-area',
    'area-customer-potential',
    'sale-return-summary',
    'sale-return-detail',
    'discount-report',
    'tax-report',
  };

  static const _productVendorReportKeys = <String>{
    'sales-summary',
    'sales-by-product',
    'sales-by-area',
    'sales-by-vendor',
  };

  static const _stockDimensionReportKeys = <String>{
    'current-stock',
    'low-stock',
    'stock-valuation',
  };

  bool get _supportsSaleSource => _saleSourceReportKeys.contains(_selectedReport.key);
  bool get _supportsArea => _areaReportKeys.contains(_selectedReport.key);
  bool get _supportsProductVendor => _productVendorReportKeys.contains(_selectedReport.key);
  bool get _supportsStockDimensions => _stockDimensionReportKeys.contains(_selectedReport.key);
  bool get _supportsCustomerType => _selectedReport.key == 'area-customer-potential';
  bool get _supportsExpenseFilters => _selectedReport.key == 'expense-report';
  Set<String> get _hiddenColumns => _hiddenColumnsByReport.putIfAbsent(_selectedReport.key, () => <String>{});

  List<_EnterpriseReportMeta> _effectiveReports(bool deliveryEnabled) {
    if (deliveryEnabled) return _allReports;
    return _allReports.where((r) => r.key != 'delivery-boy-cash').toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _selectedReport = _allReports.firstWhere(
      (r) => r.key == widget.initialReportKey,
      orElse: () => _allReports.first,
    );

    _searchCtrl.addListener(_onSearchChanged);
    _reportScrollController.addListener(_onReportScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _service = ReportsService(token: token);
      _saleSourceService = SaleSourceService(token: token);
      _customerAreaService = CustomerAreaService(token: token);
      _loadSaleSources();
      _loadCustomerAreas();
      _loadProductVendors();
      _loadInventoryReportFilters();
      _loadExpenseReportFilters();
      // Branch scoping is resolved by backend from the logged-in user's active branch.
      _ready = true;
      _fetch();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branchId = context.watch<BranchProvider>().selectedBranchId;
    if (_observedBranchId == branchId) return;
    _observedBranchId = branchId;
    _saleSourceId = null;
    _areaId = null;
    _productVendorId = null;
    _stockCategoryId = null;
    _stockBrandId = null;
    _stockVendorId = null;
    _expenseAccountId = null;
    _expenseCreatedById = null;
    _saleSources = const [];
    _customerAreas = const [];
    _productVendors = const [];
    _stockCategories = const [];
    _stockBrands = const [];
    _expenseAccounts = const [];
    _expensePaymentMethods = const [];
    _expenseCreators = const [];
    if (_ready && !_branchRefreshScheduled) {
      _branchRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _branchRefreshScheduled = false;
        if (!mounted) return;
        await Future.wait([_loadSaleSources(), _loadCustomerAreas(), _loadProductVendors(), _loadInventoryReportFilters(), _loadExpenseReportFilters()]);
        if (mounted) {
          await _fetch();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _reportScrollController.dispose();
    _reportHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadSaleSources() async {
    try {
      final list = await _saleSourceService.getSaleSources();
      if (!mounted) return;
      setState(() => _saleSources = list);
    } catch (_) {
      // Report execution remains available even if reference-data loading fails.
    }
  }

  Future<void> _loadCustomerAreas() async {
    try {
      final list = await _customerAreaService.getAreas(activeOnly: false);
      if (!mounted) return;
      setState(() => _customerAreas = list);
    } catch (_) {
      // Reports remain usable if reference-data loading is temporarily unavailable.
    }
  }

  Future<void> _loadProductVendors() async {
    try {
      final list = await _service.getProductVendorsForReports();
      if (!mounted) return;
      setState(() => _productVendors = list);
    } catch (_) {
      // Reports remain usable if the vendor reference list is unavailable.
    }
  }

  Future<void> _loadInventoryReportFilters() async {
    try {
      final data = await _service.getInventoryReportFilters();
      if (!mounted) return;
      setState(() {
        _stockCategories = (data['categories'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _stockBrands = (data['brands'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      });
    } catch (_) {
      // Inventory reports remain usable if reference-data filters fail.
    }
  }

  Future<void> _loadExpenseReportFilters() async {
    try {
      final data = await _service.getExpenseReportFilters();
      if (!mounted) return;
      setState(() {
        _expenseAccounts = (data['expense_accounts'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _expensePaymentMethods = (data['payment_methods'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _expenseCreators = (data['creators'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      });
    } catch (_) {
      // Expense report remains usable even if reference-data filters fail.
    }
  }

  String get _activeReportDescription {
    if (_supportsProductVendor && _productVendorId != null) {
      Map<String, dynamic>? selected;
      for (final vendor in _productVendors) {
        if (int.tryParse(vendor['id']?.toString() ?? '') == _productVendorId) {
          selected = vendor;
          break;
        }
      }
      final vendor = selected == null ? 'Selected vendor' : _vendorLabel(selected);
      return '$vendor product sales only. Invoice discount is allocated proportionally; tax and delivery are excluded from vendor revenue.';
    }
    return _selectedReport.description;
  }

  String _vendorLabel(Map<String, dynamic> vendor) {
    final name = (vendor['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = vendor['id']?.toString() ?? '';
    return id.isEmpty ? 'Vendor' : 'Vendor #$id';
  }

  Map<String, dynamic> _filters({bool export = false, int page = 1}) {
    return {
      if (_from != null) 'from': _dateTimeFmt.format(_from!),
      if (_to != null) 'to': _dateTimeFmt.format(_to!),
      if ((_searchCtrl.text).trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
      if (_status != null && _status!.isNotEmpty) 'status': _status,
      if (_method != null && _method!.isNotEmpty) 'method': _method,
      if (_supportsSaleSource && _saleSourceId != null) 'sale_source_id': _saleSourceId,
      if (_supportsArea && _areaId != null) 'area_id': _areaId,
      if (_supportsProductVendor && _productVendorId != null) 'product_vendor_id': _productVendorId,
      if (_supportsStockDimensions && _stockCategoryId != null) 'category_id': _stockCategoryId,
      if (_supportsStockDimensions && _stockBrandId != null) 'brand_id': _stockBrandId,
      if (_supportsStockDimensions && _stockVendorId != null) 'vendor_id': _stockVendorId,
      if (_supportsCustomerType && _customerType != null && _customerType!.isNotEmpty) 'customer_type': _customerType,
      if (_supportsExpenseFilters && _expenseAccountId != null) 'account_id': _expenseAccountId,
      if (_supportsExpenseFilters && _expenseCreatedById != null) 'created_by': _expenseCreatedById,
      if (export && _hiddenColumns.isNotEmpty) 'hidden_columns': _hiddenColumns.join(','),
      'page': export ? 1 : page,
      'per_page': export ? (_supportsExpenseFilters ? 5000 : 1000) : _perPage,
      'direction': 'desc',
    };
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _ready && !_loading) _fetch();
    });
  }

  Future<void> _fetch({int page = 1, bool reset = true}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (reset) {
      _reportPages.clear();
      _loadingReportPages.clear();
      _lastPage = 1;
      _totalRows = 0;
      _result = null;
      _error = null;
      if (_reportScrollController.hasClients) _reportScrollController.jumpTo(0);
    }
    if (_loadingReportPages.contains(page) || page < 1 || (!reset && _totalRows > 0 && page > _lastPage)) return;
    _loadingReportPages.add(page);
    if (mounted && _reportPages.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.runEnterpriseReport(reportKey: _selectedReport.key, filters: _filters(page: page));
      if (!mounted || generation != _requestGeneration) return;
      final response = _EnterpriseReportResponse.fromJson(data);
      setState(() {
        _reportPages[page] = response;
        if (page == 1 || _result == null) _result = response;
        final pagination = response.pagination;
        _lastPage = pagination?.lastPage ?? 1;
        _totalRows = pagination?.total ?? response.rows.length;
        _evictReportPages(keepPage: page);
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      if (_reportPages.isEmpty) setState(() => _error = e.toString());
    } finally {
      _loadingReportPages.remove(page);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onReportScroll() {
    if (!_reportScrollController.hasClients || _totalRows <= 0) return;
    final first = (_reportScrollController.offset / _reportRowExtent).floor().clamp(0, _totalRows - 1);
    final last = (first + (_reportScrollController.position.viewportDimension / _reportRowExtent).ceil() + 6).clamp(0, _totalRows - 1);
    final firstPage = first ~/ _perPage + 1;
    final lastPage = last ~/ _perPage + 1;
    for (var page = firstPage; page <= lastPage; page++) {
      if (!_reportPages.containsKey(page)) _fetch(page: page, reset: false);
    }
    if (lastPage < _lastPage && !_reportPages.containsKey(lastPage + 1)) _fetch(page: lastPage + 1, reset: false);
  }

  Map<String, dynamic>? _reportRowAt(int index) {
    final page = index ~/ _perPage + 1;
    final offset = index % _perPage;
    final response = _reportPages[page];
    if (response == null) { _fetch(page: page, reset: false); return null; }
    return offset < response.rows.length ? response.rows[offset] : null;
  }

  void _evictReportPages({required int keepPage}) {
    if (_reportPages.length <= _maxCachedPages) return;
    final keys = _reportPages.keys.toList()..sort((a,b) => (b-keepPage).abs().compareTo((a-keepPage).abs()));
    while (_reportPages.length > _maxCachedPages && keys.isNotEmpty) { _reportPages.remove(keys.removeAt(0)); }
  }

  Future<void> _export(String format) async {
    ReportPdfExportOptions? pdfOptions;
    if (format == 'pdf') {
      pdfOptions = await showReportPdfExportDialog(
        context,
        reportTitle: _selectedReport.title,
      );
      if (pdfOptions == null || !mounted) return;
    }

    setState(() => _exporting = true);
    try {
      final file = await _service.exportEnterpriseReport(
        reportKey: _selectedReport.key,
        format: format,
        filters: _filters(export: true),
        orientation: pdfOptions?.orientation ?? 'auto',
        paperSize: pdfOptions?.paperSize ?? 'a4',
      );
      final path = await saveReportFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.contentType,
      );
      if (!mounted) return;
      AppFeedback.success(context, format == 'pdf' ? 'PDF saved and opened: $path' : 'Excel saved and opened: $path');
    } on ReportSaveCancelledException {
      // User dismissed the save dialog — nothing to report.
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Export failed: $e');
      print('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickDateTime({required bool isFrom}) async {
    final current = isFrom ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final value = DateTime(date.year, date.month, date.day, time.hour, time.minute, isFrom ? 0 : 59);
    setState(() {
      if (isFrom) {
        _from = value;
      } else {
        _to = value;
      }
    });
    _fetch();
  }

  void _selectReport(_EnterpriseReportMeta report) {
    if (_selectedReport.key == report.key) return;
    setState(() {
      _selectedReport = report;
      _result = null;
      _error = null;
      _status = null;
      _method = null;
      _customerType = null;
      _stockCategoryId = null;
      _stockBrandId = null;
      _stockVendorId = null;
      _expenseAccountId = null;
      _expenseCreatedById = null;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;
    final insidePersistentShell =
        CounterIQDesktopShell.isPersistentShellMounted(context);

    final deliveryEnabled = context.watch<BranchFeatureProvider>().deliveryEnabled;
    final reports = _effectiveReports(deliveryEnabled);

    // If delivery was just disabled and the active report is delivery-only,
    // switch to the first available report (post-frame to avoid setState-in-build).
    if (!deliveryEnabled && _selectedReport.key == 'delivery-boy-cash') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectReport(reports.first);
      });
    }

    final body = SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isWide && !insidePersistentShell) _buildSideCatalog(reports),
          Expanded(
            child: CustomScrollView(
              slivers: [
                _buildHero(
                  isWide: isWide || insidePersistentShell,
                  reports: reports,
                ),
                _buildFilterPanel(isWide: isWide),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(message: _error!, onRetry: _fetch),
                  )
                else ...[
                  _buildAreaInsights(),
                  _buildTotals(),
                  _buildExpenseAccountSummary(),
                  _buildTable(),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (insidePersistentShell) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enterprise Reports'),
        centerTitle: false,
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: BranchIndicator(tappable: false),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: (!_ready || _loading) ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  Widget _buildSideCatalog(List<_EnterpriseReportMeta> reports) {
    final grouped = _groupReports(reports);
    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.65))),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Text('Report Center', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('All enterprise reports in one workspace', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(entry.key, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ...entry.value.map((r) => _ReportNavTile(
                  report: r,
                  selected: r.key == _selectedReport.key,
                  onTap: () => _selectReport(r),
                )),
          ],
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildHero({required bool isWide, required List<_EnterpriseReportMeta> reports}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(.78)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(16)),
                child: Icon(_selectedReport.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedReport.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_activeReportDescription, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              if (!isWide) _buildReportDropdown(reports),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportDropdown(List<_EnterpriseReportMeta> reports) {
    return PopupMenuButton<_EnterpriseReportMeta>(
      tooltip: 'Change report',
      onSelected: _selectReport,
      icon: const Icon(Icons.dashboard_customize_rounded, color: Colors.white),
      itemBuilder: (_) => reports.map((r) => PopupMenuItem(value: r, child: Text('${r.group} • ${r.title}'))).toList(),
    );
  }

  SliverToBoxAdapter _buildFilterPanel({required bool isWide}) {
    final children = <Widget>[
      _FilterChipButton(
        icon: Icons.schedule_rounded,
        label: _from == null ? 'From: Any' : 'From: ${_dateTimeFmt.format(_from!)}',
        onTap: () => _pickDateTime(isFrom: true),
      ),
      _FilterChipButton(
        icon: Icons.schedule_outlined,
        label: _to == null ? 'To: Any' : 'To: ${_dateTimeFmt.format(_to!)}',
        onTap: () => _pickDateTime(isFrom: false),
      ),
      SizedBox(
        width: isWide ? 260 : double.infinity,
        child: TextField(
          controller: _searchCtrl,
          onSubmitted: (_) {
            setState(() {});
            _fetch();
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: _supportsExpenseFilters ? 'Search payee, note, account, method, creator...' : 'Search invoices, parties, products...',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                      _fetch();
                    },
                  ),
          ),
        ),
      ),
      if (_supportsSaleSource)
        Container(
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _saleSourceId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.hub_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Sale Sources'),
                  ]),
                ),
                ..._saleSources.map((source) {
                  final id = int.tryParse(source['id']?.toString() ?? '');
                  final active = source['is_active'] == true ||
                      source['is_active'] == 1 ||
                      source['is_active']?.toString().toLowerCase() == 'true';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      '${source['name'] ?? 'Source'}${active ? '' : ' (Inactive)'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _saleSourceId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsArea)
        Container(
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 250),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _areaId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.location_on_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Towns / Areas'),
                  ]),
                ),
                ..._customerAreas.map((area) {
                  final id = int.tryParse(area['id']?.toString() ?? '');
                  final active = area['is_active'] == true || area['is_active'] == 1 || area['is_active']?.toString().toLowerCase() == 'true';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('${area['name'] ?? 'Area'}${active ? '' : ' (Inactive)'}', overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _areaId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsProductVendor)
        Container(
          constraints: const BoxConstraints(minWidth: 205, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _productVendorId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.local_shipping_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Product Vendors'),
                  ]),
                ),
                ..._productVendors.map((vendor) {
                  final id = int.tryParse(vendor['id']?.toString() ?? '');
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      '${_vendorLabel(vendor)}${vendor['is_active'] == false ? ' (Inactive)' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _productVendorId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsStockDimensions)
        Container(
          constraints: const BoxConstraints(minWidth: 185, maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _stockCategoryId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.category_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Categories'),
                  ]),
                ),
                ..._stockCategories.map((category) {
                  final id = int.tryParse(category['id']?.toString() ?? '');
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text((category['name'] ?? 'Category').toString(), overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _stockCategoryId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsStockDimensions)
        Container(
          constraints: const BoxConstraints(minWidth: 175, maxWidth: 230),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _stockBrandId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.sell_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Brands'),
                  ]),
                ),
                ..._stockBrands.map((brand) {
                  final id = int.tryParse(brand['id']?.toString() ?? '');
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text((brand['name'] ?? 'Brand').toString(), overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _stockBrandId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsStockDimensions)
        Container(
          constraints: const BoxConstraints(minWidth: 195, maxWidth: 270),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _stockVendorId ?? 0,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Row(children: [
                    Icon(Icons.local_shipping_outlined, size: 16),
                    SizedBox(width: 7),
                    Text('All Vendors'),
                  ]),
                ),
                ..._productVendors.map((vendor) {
                  final id = int.tryParse(vendor['id']?.toString() ?? '');
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      '${_vendorLabel(vendor)}${vendor['is_active'] == false ? ' (Inactive)' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _stockVendorId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsCustomerType)
        Container(
          constraints: const BoxConstraints(minWidth: 175, maxWidth: 210),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _customerType ?? '',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: '', child: Text('All Customer Types')),
                DropdownMenuItem(value: 'retail', child: Text('Retail')),
                DropdownMenuItem(value: 'wholesale', child: Text('Wholesale')),
                DropdownMenuItem(value: 'reseller', child: Text('Reseller')),
              ],
              onChanged: (value) {
                setState(() {
                  _customerType = value == null || value.isEmpty ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsExpenseFilters)
        Container(
          constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _expenseAccountId ?? 0,
              isExpanded: true,
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem(value: 0, child: Text('All Expense Accounts')),
                ..._expenseAccounts.map((account) {
                  final id = int.tryParse(account['id']?.toString() ?? '');
                  final code = (account['code'] ?? '').toString().trim();
                  final name = (account['name'] ?? 'Expense').toString().trim();
                  final active = account['is_active'] == true || account['is_active'] == 1 || account['is_active']?.toString() == '1';
                  final label = code.isEmpty ? name : '$code · $name';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('$label${active ? '' : ' (Inactive)'}', overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _expenseAccountId = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsExpenseFilters)
        Container(
          constraints: const BoxConstraints(minWidth: 175, maxWidth: 230),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _method ?? '',
              isExpanded: true,
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '', child: Text('All Payment Methods')),
                ..._expensePaymentMethods.map((method) {
                  final code = (method['method'] ?? '').toString();
                  final label = (method['display_name'] ?? code).toString();
                  final active = method['is_active'] == true || method['is_active'] == 1 || method['is_active']?.toString() == '1';
                  return DropdownMenuItem<String>(
                    value: code,
                    child: Text('$label${active ? '' : ' (Inactive)'}', overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _method = value == null || value.isEmpty ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsExpenseFilters)
        Container(
          constraints: const BoxConstraints(minWidth: 175, maxWidth: 230),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _expenseCreatedById ?? 0,
              isExpanded: true,
              items: <DropdownMenuItem<int>>[
                const DropdownMenuItem(value: 0, child: Text('All Creators')),
                ..._expenseCreators.map((user) {
                  final id = int.tryParse(user['id']?.toString() ?? '');
                  final name = (user['name'] ?? 'User').toString();
                  final active = user['is_active'] == true || user['is_active'] == 1 || user['is_active']?.toString() == '1';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text('$name${active ? '' : ' (Inactive)'}', overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _expenseCreatedById = value == 0 ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      if (_supportsExpenseFilters)
        Container(
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 185),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _status ?? '',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: '', child: Text('All Statuses')),
                DropdownMenuItem(value: 'posted', child: Text('Posted')),
                DropdownMenuItem(value: 'void', child: Text('Voided')),
              ],
              onChanged: (value) {
                setState(() {
                  _status = value == null || value.isEmpty ? null : value;
                            });
                _fetch();
              },
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _result == null ? null : _showColumnPicker,
        icon: const Icon(Icons.view_column_outlined),
        label: Text(_hiddenColumns.isEmpty ? 'Columns' : 'Columns (${_hiddenColumns.length} hidden)'),
      ),
      FilledButton.icon(
        onPressed: (!_ready || _loading) ? null : _fetch,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Run'),
      ),
      OutlinedButton.icon(
        onPressed: (!_ready || _exporting) ? null : () => _export('xlsx'),
        icon: const Icon(Icons.table_chart_rounded),
        label: const Text('Excel'),
      ),
      OutlinedButton.icon(
        onPressed: (!_ready || _exporting) ? null : () => _export('pdf'),
        icon: const Icon(Icons.picture_as_pdf_rounded),
        label: const Text('PDF'),
      ),
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.7))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children),
          ),
        ),
      ),
    );
  }

  bool _isProfitSensitiveColumn(String key) {
    final k = key.toLowerCase();
    return k == 'cogs' || k.contains('profit') || k.contains('margin');
  }

  Future<void> _showColumnPicker() async {
    final result = _result;
    if (result == null || result.columns.isEmpty) return;
    final working = Set<String>.from(_hiddenColumns);
    final applied = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hiddenProfit = result.columns.where((c) => _isProfitSensitiveColumn(c.key)).every((c) => working.contains(c.key));
          final visibleCount = result.columns.where((c) => !working.contains(c.key)).length;
          return AlertDialog(
            title: const Text('Visible report columns'),
            content: SizedBox(
              width: 430,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose what staff can see on screen and in the next Excel/PDF export.', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setDialogState(working.clear),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Show all'),
                      ),
                      if (result.columns.any((c) => _isProfitSensitiveColumn(c.key)))
                        OutlinedButton.icon(
                          onPressed: () => setDialogState(() {
                            for (final c in result.columns.where((c) => _isProfitSensitiveColumn(c.key))) {
                              working.add(c.key);
                            }
                          }),
                          icon: Icon(hiddenProfit ? Icons.visibility_off : Icons.lock_outline, size: 18),
                          label: const Text('Hide profit fields'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: result.columns.map((column) {
                          final visible = !working.contains(column.key);
                          final sensitive = _isProfitSensitiveColumn(column.key);
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: visible,
                            title: Text(column.label),
                            subtitle: sensitive ? const Text('Profit-sensitive') : null,
                            secondary: sensitive ? const Icon(Icons.lock_outline_rounded, size: 19) : null,
                            onChanged: (value) => setDialogState(() {
                              if (value == true) {
                                working.remove(column.key);
                              } else if (visibleCount > 1) {
                                working.add(column.key);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: visibleCount < 1 ? null : () => Navigator.pop(dialogContext, working), child: const Text('Apply')),
            ],
          );
        },
      ),
    );
    if (applied == null || !mounted) return;
    setState(() => _hiddenColumnsByReport[_selectedReport.key] = applied);
  }

  SliverToBoxAdapter _buildAreaInsights() {
    final result = _result;
    if (result == null || result.rows.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    if (_selectedReport.key != 'sales-by-area' && _selectedReport.key != 'area-customer-potential') {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    Map<String, dynamic>? maxBy(String key) {
      Map<String, dynamic>? best;
      num? bestValue;
      for (final row in result.rows) {
        final value = row[key];
        final n = value is num ? value : num.tryParse(value?.toString() ?? '');
        if (n == null) continue;
        if (best == null || n > bestValue!) {
          best = row;
          bestValue = n;
        }
      }
      return best;
    }

    final cards = <_InsightData>[];
    if (_selectedReport.key == 'sales-by-area') {
      final revenue = maxBy('net_sales');
      final invoices = maxBy('invoices');
      final avg = maxBy('avg_invoice');
      if (revenue != null) cards.add(_InsightData('Highest Net Sales', '${revenue['area']} • ${_formatValue(revenue['net_sales'], 'net_sales')}'));
      if (invoices != null) cards.add(_InsightData('Most Orders', '${invoices['area']} • ${_formatValue(invoices['invoices'], 'invoices')} invoices'));
      if (avg != null) cards.add(_InsightData('Highest Avg Invoice', '${avg['area']} • ${_formatValue(avg['avg_invoice'], 'avg_invoice')}'));
    } else {
      final base = maxBy('customers');
      final opportunity = maxBy('no_purchase');
      final repeat = maxBy('repeat_rate');
      final revenue = maxBy('net_sales');
      if (base != null) cards.add(_InsightData('Largest Customer Base', '${base['area']} • ${_formatValue(base['customers'], 'customers')}'));
      if (opportunity != null) cards.add(_InsightData('Largest Reactivation Opportunity', '${opportunity['area']} • ${_formatValue(opportunity['no_purchase'], 'no_purchase')} customers'));
      if (repeat != null) cards.add(_InsightData('Highest Repeat Rate', '${repeat['area']} • ${_formatValue(repeat['repeat_rate'], 'repeat_rate')}%'));
      if (revenue != null) cards.add(_InsightData('Highest Net Sales', '${revenue['area']} • ${_formatValue(revenue['net_sales'], 'net_sales')}'));
    }
    if (cards.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(spacing: 10, runSpacing: 10, children: cards.map((c) => _InsightCard(data: c)).toList()),
      ),
    );
  }

  SliverToBoxAdapter _buildTotals() {
    final totals = _result?.totals ?? const <String, dynamic>{};
    if (totals.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final entries = totals.entries.where((e) => !_hiddenColumns.contains(e.key)).toList();
    final visible = _supportsExpenseFilters
        ? <String>['total_expenses', 'reversed_amount', 'net_expenses', 'entry_count', 'posted_entries', 'voided_entries']
            .where(totals.containsKey)
            .map((key) => MapEntry(key, totals[key]))
            .toList()
        : entries.take(8).toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: visible.map((e) => _TotalCard(label: _labelize(e.key), value: _formatValue(e.value, e.key))).toList(),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildExpenseAccountSummary() {
    if (!_supportsExpenseFilters) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final rows = _result?.breakdowns['by_account'] ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('Expense Account Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 40,
                  columns: const [
                    DataColumn(label: Text('Account')),
                    DataColumn(label: Text('Entries'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Reversed'), numeric: true),
                    DataColumn(label: Text('Net'), numeric: true),
                  ],
                  rows: rows.map((row) {
                    final code = (row['account_code'] ?? '').toString();
                    final name = (row['expense_account'] ?? '').toString();
                    final label = code.isEmpty ? name : '$code · $name';
                    return DataRow(cells: [
                      DataCell(Text(label)),
                      DataCell(Text(_formatValue(row['entries'], 'entries'))),
                      DataCell(Text(_formatValue(row['total_expenses'], 'total_expenses'))),
                      DataCell(Text(_formatValue(row['reversed_amount'], 'reversed_amount'))),
                      DataCell(Text(_formatValue(row['net_expenses'], 'net_expenses'))),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _reportBaseColumnWidth(_ReportColumn column, int columnCount) {
    final key = column.key.toLowerCase();
    final label = column.label.toLowerCase();
    if (key.contains('date') || key.contains('time')) return 138;
    if (key.contains('description') || key.contains('notes') || key.contains('product_name') || key.contains('party_name')) return 220;
    if (key.contains('name') || key.contains('vendor') || key.contains('customer') || key.contains('account')) return 180;
    if (key.contains('invoice') || key.contains('reference') || key.contains('code')) return 150;
    if (key.contains('status') || key.contains('type') || key.contains('source') || key.contains('method')) return 132;
    if (key.contains('qty') || key.contains('count') || key.contains('units') || key.contains('invoices')) return 105;
    if (key.contains('amount') || key.contains('sales') || key.contains('profit') || key.contains('cogs') || key.contains('balance') || key.contains('total') || key.contains('tax') || key.contains('discount') || key.contains('cost') || key.contains('price')) return 132;
    if (label.length > 18) return 165;
    return columnCount <= 5 ? 170 : 138;
  }

  SliverToBoxAdapter _buildTable() {
    final result = _result;
    if (result == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final visibleColumns = result.columns.where((c) => !_hiddenColumns.contains(c.key)).toList(growable: false);
    if (_totalRows == 0) {
      return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No data found for selected filters', style: Theme.of(context).textTheme.titleMedium))));
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final baseWidths = visibleColumns.map((c) => _reportBaseColumnWidth(c, visibleColumns.length)).toList(growable: false);
            final baseTotal = baseWidths.fold<double>(0, (sum, width) => sum + width);
            final usableWidth = constraints.maxWidth > 24 ? constraints.maxWidth - 24 : 0.0;
            final extraPerColumn = visibleColumns.isEmpty || baseTotal >= usableWidth ? 0.0 : (usableWidth - baseTotal) / visibleColumns.length;
            final widths = baseWidths.map((width) => width + extraPerColumn).toList(growable: false);
            final contentWidth = 24 + widths.fold<double>(0, (sum, width) => sum + width);
            final tableWidth = contentWidth < constraints.maxWidth ? constraints.maxWidth : contentWidth;
            return Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.7))),
              child: SizedBox(
                height: 500,
                child: Scrollbar(
                  controller: _reportHorizontalController,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _reportHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(children: [
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: AppTheme.surfaceSoft,
                          child: Row(
                            children: [
                              for (var i = 0; i < visibleColumns.length; i++)
                                SizedBox(
                                  width: widths[i],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 7),
                                    child: Text(visibleColumns[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMuted, fontSize: 10.5)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _reportScrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _reportScrollController,
                              itemExtent: _reportRowExtent,
                              cacheExtent: _reportRowExtent * 14,
                              itemCount: _totalRows,
                              itemBuilder: (_, index) {
                                final row = _reportRowAt(index);
                                if (row == null) return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < visibleColumns.length; i++)
                                        SizedBox(
                                          width: widths[i],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 7),
                                            child: Text(_formatValue(row[visibleColumns[i].key], visibleColumns[i].key), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: AppTheme.surfaceSoft,
                          child: Row(children: [
                            Text('$_totalRows records', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text('Bounded cache: ${_reportPages.length}/$_maxCachedPages pages', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Map<String, List<_EnterpriseReportMeta>> _groupReports(List<_EnterpriseReportMeta> reports) {
    final grouped = <String, List<_EnterpriseReportMeta>>{};
    for (final report in reports) {
      grouped.putIfAbsent(report.group, () => []).add(report);
    }
    return grouped;
  }

  List<Map<String, dynamic>> _visibleRows(_EnterpriseReportResponse result) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return result.rows;

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return result.rows;

    return result.rows.where((row) {
      final haystack = row.values.map((v) => v?.toString().toLowerCase() ?? '').join(' ');
      return tokens.every(haystack.contains);
    }).toList(growable: false);
  }

  String _formatValue(dynamic value, String key) {
    if (value == null) return '—';
    if (value is num && _looksMoney(key)) return _currencyFmt.format(value);
    if (value is num) return NumberFormat.decimalPattern().format(value);
    final text = value.toString();
    if (text.isEmpty) return '—';
    final parsed = num.tryParse(text);
    if (parsed != null && _looksMoney(key)) return _currencyFmt.format(parsed);
    return text;
  }

  bool _looksMoney(String key) {
    final k = key.toLowerCase();

    // `no_purchase` is a customer count in Area Customer Potential, not a
    // monetary purchase value. Keep this guard before the generic
    // `purchase` keyword check so totals, table cells and insight cards all
    // render it as a plain number (for example: `0 customers`).
    if (k == 'no_purchase') return false;

    return k == 'net_expenses' || k.contains('total') || k.contains('amount') || k.contains('balance') || k.contains('paid') || k.contains('tax') || k.contains('discount') || k.contains('profit') || k.contains('revenue') || k.contains('cost') || k.contains('debit') || k.contains('credit') || k.contains('cash') || k.contains('valuation') || k.contains('sales') || k.contains('purchase');
  }

  String _labelize(String key) => key.replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}

class _EnterpriseReportResponse {
  final String title;
  final List<_ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;
  final Map<String, List<Map<String, dynamic>>> breakdowns;
  final _ReportPagination? pagination;

  _EnterpriseReportResponse({required this.title, required this.columns, required this.rows, required this.totals, required this.breakdowns, this.pagination});

  factory _EnterpriseReportResponse.fromJson(Map<String, dynamic> json) {
    return _EnterpriseReportResponse(
      title: (json['title'] ?? '').toString(),
      columns: (json['columns'] as List? ?? []).map((e) => _ReportColumn.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      rows: (json['rows'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      totals: Map<String, dynamic>.from((json['totals'] as Map?) ?? const {}),
      breakdowns: (json['breakdowns'] as Map? ?? const {}).map<String, List<Map<String, dynamic>>>((key, value) {
        final rows = (value as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        return MapEntry(key.toString(), rows);
      }),
      pagination: json['pagination'] is Map ? _ReportPagination.fromJson(Map<String, dynamic>.from(json['pagination'] as Map)) : null,
    );
  }
}

class _ReportColumn {
  final String key;
  final String label;

  _ReportColumn({required this.key, required this.label});

  factory _ReportColumn.fromJson(Map<String, dynamic> json) => _ReportColumn(key: (json['key'] ?? '').toString(), label: (json['label'] ?? json['key'] ?? '').toString());
}

class _ReportPagination {
  final int currentPage;
  final int lastPage;
  final int total;

  _ReportPagination({required this.currentPage, required this.lastPage, required this.total});

  factory _ReportPagination.fromJson(Map<String, dynamic> json) => _ReportPagination(
        currentPage: _toInt(json['current_page'], fallback: 1),
        lastPage: _toInt(json['last_page'], fallback: 1),
        total: _toInt(json['total'], fallback: 0),
      );
}

class _EnterpriseReportMeta {
  final String key;
  final String title;
  final String group;
  final String description;
  final IconData icon;

  const _EnterpriseReportMeta({required this.key, required this.title, required this.group, required this.description, required this.icon});
}

class _ReportNavTile extends StatelessWidget {
  final _EnterpriseReportMeta report;
  final bool selected;
  final VoidCallback onTap;

  const _ReportNavTile({required this.report, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? scheme.primary.withOpacity(.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(report.icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
          title: Text(report.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          subtitle: Text(report.description, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: selected,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _InsightData {
  final String label;
  final String value;
  const _InsightData(this.label, this.value);
}

class _InsightCard extends StatelessWidget {
  final _InsightData data;
  const _InsightCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 7),
          Text(data.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterChipButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final String value;

  const _TotalCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 34),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

int _toInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

const _enterpriseReports = <_EnterpriseReportMeta>[
  _EnterpriseReportMeta(key: 'sales-summary', title: 'Sales Summary', group: 'Sales', description: 'Daily invoices, net sales, returns, COGS and gross profit.', icon: Icons.summarize_rounded),
  _EnterpriseReportMeta(key: 'sales-detail', title: 'Sales Detail', group: 'Sales', description: 'Invoice-level sales detail for audit and export.', icon: Icons.receipt_long_rounded),
  _EnterpriseReportMeta(key: 'sales-by-product', title: 'Sales by Product', group: 'Sales', description: 'Revenue, quantity, COGS and profit by SKU.', icon: Icons.inventory_2_rounded),
  _EnterpriseReportMeta(key: 'sales-by-vendor', title: 'Sales by Vendor', group: 'Sales', description: 'Product-vendor sales performance with proportional invoice discount allocation; tax and delivery excluded.', icon: Icons.local_shipping_rounded),
  _EnterpriseReportMeta(key: 'sales-by-category', title: 'Sales by Category', group: 'Sales', description: 'Category contribution and sales mix.', icon: Icons.category_rounded),
  _EnterpriseReportMeta(key: 'sales-by-brand', title: 'Sales by Brand', group: 'Sales', description: 'Brand performance by revenue and quantity.', icon: Icons.local_offer_rounded),
  _EnterpriseReportMeta(key: 'sales-by-customer', title: 'Sales by Customer', group: 'Sales', description: 'Customer-wise revenue and invoice count.', icon: Icons.people_alt_rounded),
  _EnterpriseReportMeta(key: 'sales-by-salesman', title: 'Sales by Cashier', group: 'Sales', description: 'Cashier or salesman performance.', icon: Icons.badge_rounded),
  _EnterpriseReportMeta(key: 'sales-by-hour', title: 'Hourly Sales', group: 'Sales', description: 'Sales heatmap base by hour.', icon: Icons.schedule_rounded),
  _EnterpriseReportMeta(key: 'sales-by-payment-method', title: 'Payment Collection', group: 'Sales', description: 'Cash, card, bank and wallet collections.', icon: Icons.payments_rounded),
  _EnterpriseReportMeta(key: 'sales-by-source', title: 'Sales by Source', group: 'Sales', description: 'Compare invoice volume, revenue, COGS and profit by Sale From channel.', icon: Icons.hub_outlined),
  _EnterpriseReportMeta(key: 'sales-by-area', title: 'Sales by Town / Area', group: 'Sales', description: 'Historical area performance using the immutable area captured on each sale.', icon: Icons.location_on_rounded),
  _EnterpriseReportMeta(key: 'area-customer-potential', title: 'Area Customer Potential', group: 'Customer Insights', description: 'Current customer-base opportunity, activity, repeat rate and spend by area.', icon: Icons.travel_explore_rounded),
  _EnterpriseReportMeta(key: 'delivery-boy-cash', title: 'Delivery Boy Cash', group: 'Sales', description: 'Delivery boy cash received and pending.', icon: Icons.delivery_dining_rounded),
  _EnterpriseReportMeta(key: 'discount-report', title: 'Discount Report', group: 'Sales', description: 'Discounts by invoice and period.', icon: Icons.percent_rounded),
  _EnterpriseReportMeta(key: 'tax-report', title: 'Tax Report', group: 'Sales', description: 'Tax collected and taxable sales.', icon: Icons.account_balance_rounded),
  _EnterpriseReportMeta(key: 'sale-return-summary', title: 'Sale Return Summary', group: 'Returns', description: 'Return totals by day.', icon: Icons.assignment_return_rounded),
  _EnterpriseReportMeta(key: 'sale-return-detail', title: 'Sale Return Detail', group: 'Returns', description: 'Return invoice detail and impact.', icon: Icons.undo_rounded),
  _EnterpriseReportMeta(key: 'purchase-summary', title: 'Purchase Summary', group: 'Purchases', description: 'Purchase totals by day.', icon: Icons.shopping_cart_checkout_rounded),
  _EnterpriseReportMeta(key: 'purchase-detail', title: 'Purchase Detail', group: 'Purchases', description: 'Bill-level supplier purchase detail.', icon: Icons.article_rounded),
  _EnterpriseReportMeta(key: 'purchase-by-product', title: 'Purchase by Product', group: 'Purchases', description: 'Purchased quantity and cost by SKU.', icon: Icons.add_business_rounded),
  _EnterpriseReportMeta(key: 'purchase-by-vendor', title: 'Purchase by Vendor', group: 'Purchases', description: 'Vendor-wise purchase volume.', icon: Icons.groups_2_rounded),
  _EnterpriseReportMeta(key: 'vendor-payment-summary', title: 'Vendor Payments', group: 'Purchases', description: 'Payments made to vendors.', icon: Icons.outbox_rounded),
  _EnterpriseReportMeta(key: 'purchase-claim-summary', title: 'Purchase Claim Summary', group: 'Purchases', description: 'Damage/shortage claim summary.', icon: Icons.report_problem_rounded),
  _EnterpriseReportMeta(key: 'purchase-claim-detail', title: 'Purchase Claim Detail', group: 'Purchases', description: 'Detailed purchase claim rows.', icon: Icons.assignment_late_rounded),
  _EnterpriseReportMeta(key: 'current-stock', title: 'Current Stock', group: 'Inventory', description: 'On-hand stock by product.', icon: Icons.warehouse_rounded),
  _EnterpriseReportMeta(key: 'low-stock', title: 'Low Stock / Reorder', group: 'Inventory', description: 'Products below reorder level.', icon: Icons.warning_amber_rounded),
  _EnterpriseReportMeta(key: 'stock-valuation', title: 'Stock Valuation', group: 'Inventory', description: 'Inventory quantity and value.', icon: Icons.price_check_rounded),
  _EnterpriseReportMeta(key: 'stock-movement', title: 'Stock Movement Ledger', group: 'Inventory', description: 'In/out movement ledger.', icon: Icons.swap_vert_circle_rounded),
  _EnterpriseReportMeta(key: 'inventory-adjustment', title: 'Inventory Adjustment', group: 'Inventory', description: 'Adjustment-only movement report.', icon: Icons.tune_rounded),
  // _EnterpriseReportMeta(key: 'cashbook', title: 'Cashbook', group: 'Accounting', description: 'Receipts, payments and cash movement.', icon: Icons.account_balance_wallet_rounded),
  // _EnterpriseReportMeta(key: 'daybook', title: 'Daybook', group: 'Accounting', description: 'Full day transaction book.', icon: Icons.calendar_view_day_rounded),
  _EnterpriseReportMeta(key: 'profit-loss', title: 'Profit & Loss', group: 'Accounting', description: 'Income, expenses and net result.', icon: Icons.trending_up_rounded),
  _EnterpriseReportMeta(key: 'expense-report', title: 'Expense Report', group: 'Accounting', description: 'Recorded operating expenses by account, method, creator and status.', icon: Icons.receipt_long_rounded),
  _EnterpriseReportMeta(key: 'customer-receivables', title: 'Customer Receivables', group: 'Accounting', description: 'All customer balances and AR base.', icon: Icons.person_search_rounded),
  _EnterpriseReportMeta(key: 'vendor-payables', title: 'Vendor Payables', group: 'Accounting', description: 'All vendor balances and AP base.', icon: Icons.group_work_rounded),
  _EnterpriseReportMeta(key: 'trial-balance', title: 'Trial Balance', group: 'Accounting', description: 'Debit, credit and balance by account.', icon: Icons.balance_rounded),
  _EnterpriseReportMeta(key: 'ledger-detail', title: 'Ledger Detail', group: 'Accounting', description: 'Journal posting detail with party filters.', icon: Icons.list_alt_rounded),
];
