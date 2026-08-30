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
  String? _customerType;
  List<Map<String, dynamic>> _saleSources = const [];
  List<Map<String, dynamic>> _customerAreas = const [];
  final Map<String, Set<String>> _hiddenColumnsByReport = <String, Set<String>>{};
  int? _observedBranchId;
  bool _branchRefreshScheduled = false;
  int _page = 1;
  int _perPage = 50;

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

  bool get _supportsSaleSource => _saleSourceReportKeys.contains(_selectedReport.key);
  bool get _supportsArea => _areaReportKeys.contains(_selectedReport.key);
  bool get _supportsCustomerType => _selectedReport.key == 'area-customer-potential';
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _service = ReportsService(token: token);
      _saleSourceService = SaleSourceService(token: token);
      _customerAreaService = CustomerAreaService(token: token);
      _loadSaleSources();
      _loadCustomerAreas();
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
    _saleSources = const [];
    _customerAreas = const [];
    if (_ready && !_branchRefreshScheduled) {
      _branchRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _branchRefreshScheduled = false;
        if (!mounted) return;
        await Future.wait([_loadSaleSources(), _loadCustomerAreas()]);
        if (mounted) {
          _page = 1;
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

  Map<String, dynamic> _filters({bool export = false}) {
    return {
      if (_from != null) 'from': _dateTimeFmt.format(_from!),
      if (_to != null) 'to': _dateTimeFmt.format(_to!),
      if ((_searchCtrl.text).trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
      if (_status != null && _status!.isNotEmpty) 'status': _status,
      if (_method != null && _method!.isNotEmpty) 'method': _method,
      if (_supportsSaleSource && _saleSourceId != null) 'sale_source_id': _saleSourceId,
      if (_supportsArea && _areaId != null) 'area_id': _areaId,
      if (_supportsCustomerType && _customerType != null && _customerType!.isNotEmpty) 'customer_type': _customerType,
      if (export && _hiddenColumns.isNotEmpty) 'hidden_columns': _hiddenColumns.join(','),
      'page': export ? 1 : _page,
      'per_page': export ? 1000 : (_searchCtrl.text.trim().isNotEmpty ? 250 : _perPage),
      'direction': 'desc',
    };
  }

  void _onSearchChanged() {
    setState(() => _page = 1);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _ready && !_loading) _fetch();
    });
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _service.runEnterpriseReport(
        reportKey: _selectedReport.key,
        filters: _filters(),
      );
      if (!mounted) return;
      setState(() => _result = _EnterpriseReportResponse.fromJson(data));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      final file = await _service.exportEnterpriseReport(
        reportKey: _selectedReport.key,
        format: format,
        filters: _filters(export: true),
        orientation: 'landscape',
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
      _page = 1;
    });
    _fetch();
  }

  void _selectReport(_EnterpriseReportMeta report) {
    if (_selectedReport.key == report.key) return;
    setState(() {
      _selectedReport = report;
      _page = 1;
      _result = null;
      _error = null;
      _status = null;
      _method = null;
      _customerType = null;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;

    final deliveryEnabled = context.watch<BranchFeatureProvider>().deliveryEnabled;
    final reports = _effectiveReports(deliveryEnabled);

    // If delivery was just disabled and the active report is delivery-only,
    // switch to the first available report (post-frame to avoid setState-in-build).
    if (!deliveryEnabled && _selectedReport.key == 'delivery-boy-cash') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectReport(reports.first);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enterprise Reports'),
        centerTitle: false,
        actions: [
          const Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false)),
          IconButton(
            tooltip: 'Refresh',
            onPressed: (!_ready || _loading) ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isWide) _buildSideCatalog(reports),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  _buildHero(isWide: isWide, reports: reports),
                  _buildFilterPanel(isWide: isWide),
                  if (_loading)
                    const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    SliverFillRemaining(hasScrollBody: false, child: _ErrorState(message: _error!, onRetry: _fetch))
                  else ...[
                    _buildAreaInsights(),
                    _buildTotals(),
                    _buildTable(),
                    _buildPagination(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
                    Text(_selectedReport.description, style: const TextStyle(color: Colors.white70)),
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
            setState(() => _page = 1);
            _fetch();
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search invoices, parties, products...',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _page = 1);
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
                  _page = 1;
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
                  _page = 1;
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
                  _page = 1;
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
      DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _perPage,
          borderRadius: BorderRadius.circular(14),
          items: const [25, 50, 100, 250].map((v) => DropdownMenuItem(value: v, child: Text('$v rows'))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _perPage = v;
              _page = 1;
            });
            _fetch();
          },
        ),
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
    final visible = totals.entries.where((e) => !_hiddenColumns.contains(e.key)).take(8).toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: visible.map((e) => _TotalCard(label: _labelize(e.key), value: _formatValue(e.value, e.key))).toList(),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTable() {
    final result = _result;
    if (result == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final visibleRows = _visibleRows(result);
    final visibleColumns = result.columns.where((c) => !_hiddenColumns.contains(c.key)).toList(growable: false);
    if (visibleRows.isEmpty) {
      final searching = _searchCtrl.text.trim().isNotEmpty;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(searching ? 'No rows match your search on this report' : 'No data found for selected filters', style: Theme.of(context).textTheme.titleMedium)),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.7))),
          clipBehavior: Clip.antiAlias,
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width >= 980 ? MediaQuery.of(context).size.width - 360 : MediaQuery.of(context).size.width - 32),
                child: DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 64,
                  columns: visibleColumns.map((c) => DataColumn(label: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w800)))).toList(),
                  rows: visibleRows.map((row) {
                    return DataRow(
                      cells: visibleColumns.map((c) => DataCell(Text(_formatValue(row[c.key], c.key), overflow: TextOverflow.ellipsis))).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildPagination() {
    final p = _result?.pagination;
    if (p == null) return const SliverToBoxAdapter(child: SizedBox(height: 24));
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Row(
          children: [
            Text(_searchCtrl.text.trim().isEmpty ? 'Page ${p.currentPage} of ${p.lastPage} • ${p.total} records' : '${_visibleRows(_result!).length} matching rows • server page ${p.currentPage}/${p.lastPage}'),
            const Spacer(),
            IconButton(
              onPressed: p.currentPage <= 1 || _loading ? null : () { setState(() => _page = p.currentPage - 1); _fetch(); },
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: p.currentPage >= p.lastPage || _loading ? null : () { setState(() => _page = p.currentPage + 1); _fetch(); },
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
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

    return k.contains('total') || k.contains('amount') || k.contains('balance') || k.contains('paid') || k.contains('tax') || k.contains('discount') || k.contains('profit') || k.contains('revenue') || k.contains('cost') || k.contains('debit') || k.contains('credit') || k.contains('cash') || k.contains('valuation') || k.contains('sales') || k.contains('purchase');
  }

  String _labelize(String key) => key.replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}

class _EnterpriseReportResponse {
  final String title;
  final List<_ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;
  final _ReportPagination? pagination;

  _EnterpriseReportResponse({required this.title, required this.columns, required this.rows, required this.totals, this.pagination});

  factory _EnterpriseReportResponse.fromJson(Map<String, dynamic> json) {
    return _EnterpriseReportResponse(
      title: (json['title'] ?? '').toString(),
      columns: (json['columns'] as List? ?? []).map((e) => _ReportColumn.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      rows: (json['rows'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      totals: Map<String, dynamic>.from((json['totals'] as Map?) ?? const {}),
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
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
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
  _EnterpriseReportMeta(key: 'customer-receivables', title: 'Customer Receivables', group: 'Accounting', description: 'All customer balances and AR base.', icon: Icons.person_search_rounded),
  _EnterpriseReportMeta(key: 'vendor-payables', title: 'Vendor Payables', group: 'Accounting', description: 'All vendor balances and AP base.', icon: Icons.group_work_rounded),
  _EnterpriseReportMeta(key: 'trial-balance', title: 'Trial Balance', group: 'Accounting', description: 'Debit, credit and balance by account.', icon: Icons.balance_rounded),
  _EnterpriseReportMeta(key: 'ledger-detail', title: 'Ledger Detail', group: 'Accounting', description: 'Journal posting detail with party filters.', icon: Icons.list_alt_rounded),
];
