import 'dart:async';
import 'dart:convert';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';

class SaleReturnsScreen extends StatefulWidget {
  const SaleReturnsScreen({super.key});

  @override
  State<SaleReturnsScreen> createState() => _SaleReturnsScreenState();
}

class _SaleReturnsScreenState extends State<SaleReturnsScreen> {
  static const int _defaultPerPage = 20;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 58;

  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  List<Map<String, dynamic>> _branches = [];
  int _perPage = _defaultPerPage;
  int _lastPage = 1;
  int _total = 0;
  bool _initialLoading = true;
  String? _loadError;

  // Filters
  String? _selectedBranchId; // used only when global=All
  int? _selectedCustomerId;
  String? _selectedCustomerLabel;
  String _searchQuery = "";
  DateTime? _fromDate;
  DateTime? _toDate;

  // UI
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _currency = const AppMoneyFormatter();
  Timer? _searchDebounce;

  // Services
  late CommonService _commonService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _commonService = CommonService(token: token);
    _attachScrollListener();
    _fetchInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _attachScrollListener() {
    _scrollController.addListener(_onScroll);
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _fetchInitial() async {
    if (!mounted) return;
    setState(() {
      _initialLoading = true;
      _pages.clear();
      _loadingPages.clear();
      _lastPage = 1;
      _total = 0;
      _loadError = null;
    });
    await Future.wait([_fetchBranches(), _fetchReturns(page: 1, force: true)]);
    if (!mounted) return;
    setState(() => _initialLoading = false);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _fetchBranches() async {
    if (!mounted) return;
    setState(() => _branches = []);
  }

  Future<void> _fetchReturns({required int page, bool force = false}) async {
    if (page < 1) return;
    if (_pages.isNotEmpty && page > _lastPage) return;
    if (!force && (_pages.containsKey(page) || _loadingPages.contains(page))) return;

    if (mounted) setState(() => _loadingPages.add(page));
    final branchProv = context.read<BranchProvider>();
    final isAll = branchProv.isAll;
    final globalBranchId = branchProv.selectedBranchId;

    final params = <String, String>{
      'page': page.toString(),
      if (!isAll && globalBranchId != null) 'branch_id': globalBranchId.toString(),
      if (isAll && _selectedBranchId != null) 'branch_id': _selectedBranchId!,
      if (_selectedCustomerId != null) 'customer_id': _selectedCustomerId!.toString(),
      if (_searchQuery.isNotEmpty) 'search': _searchQuery,
      if (_fromDate != null) 'date_from': _fmtDate(_fromDate!),
      if (_toDate != null) 'date_to': _fmtDate(_toDate!),
    };

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/sales/returns').replace(queryParameters: params);
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'});
      if (res.statusCode != 200) throw Exception('Failed to load sale returns');

      final decoded = jsonDecode(res.body);
      final paginator = Map<String, dynamic>.from(decoded['data'] as Map? ?? const {});
      final rows = (paginator['data'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
      final current = (paginator['current_page'] as num?)?.toInt() ?? page;
      final last = (paginator['last_page'] as num?)?.toInt() ?? 1;
      final perPage = (paginator['per_page'] as num?)?.toInt() ?? (rows.isEmpty ? _perPage : rows.length);
      final total = (paginator['total'] as num?)?.toInt() ??
          (last <= 1 ? rows.length : (last - 1) * perPage + rows.length);

      if (!mounted) return;
      setState(() {
        _pages[current] = rows;
        _lastPage = last < 1 ? 1 : last;
        _perPage = perPage <= 0 ? _defaultPerPage : perPage;
        _total = total < rows.length ? rows.length : total;
        _loadingPages.remove(page);
        _loadError = null;
        _evictFarPages(_visiblePageEstimate());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages.remove(page);
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
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
      _fetchReturns(page: page);
    }
    if (lastPage < _lastPage) _fetchReturns(page: lastPage + 1);
    if (firstPage > 1) _fetchReturns(page: firstPage - 1);
    if (_pages.length > _maxCachedPages && mounted) {
      setState(() => _evictFarPages(firstPage));
    }
  }

  Map<String, dynamic>? _returnAt(int index) {
    final page = (index ~/ _perPage) + 1;
    final local = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReturns(page: page));
      return null;
    }
    return local < rows.length ? rows[local] : null;
  }

  Future<void> _onRefresh() => _fetchInitial();

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

  Future<void> _startReturnWorkflow() async {
    final invoiceController = TextEditingController();
    final invoice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Sale Return'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: invoiceController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Original invoice number',
              hintText: 'e.g. INV-20260927-008',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = invoiceController.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    invoiceController.dispose();
    if (!mounted || invoice == null || invoice.trim().isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateSaleScreen(initialReturnInvoice: invoice.trim()),
      ),
    );
    if (mounted) _fetchInitial();
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

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    final canCreate = context.watch<AuthProvider>().hasPermission('create-sales');

    return EnterprisePage(
      title: 'Sale Returns',
      subtitle: 'Review formal and inline sale returns using the same return history definition as Reports.',
      icon: Icons.assignment_return_outlined,
      actions: [
        OutlinedButton.icon(
          onPressed: _initialLoading ? null : _fetchInitial,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
        if (canCreate)
          FilledButton.icon(
            onPressed: _startReturnWorkflow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Return'),
          ),
      ],
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              if (isAll)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedBranchId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All branches')),
                      ..._branches.map((b) => DropdownMenuItem<String?>(value: b['id'].toString(), child: Text(b['name'].toString()))),
                    ],
                    onChanged: (v) { setState(() => _selectedBranchId = v); _fetchInitial(); },
                  ),
                ),
              SizedBox(
                width: 270,
                child: InkWell(
                  onTap: _openCustomerPicker,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Customer'),
                    child: Row(
                      children: [
                        Expanded(child: Text(_selectedCustomerLabel ?? 'All customers', overflow: TextOverflow.ellipsis)),
                        if (_selectedCustomerId == null)
                          const Icon(Icons.person_search_outlined, size: 18)
                        else
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Clear customer',
                            onPressed: () { setState(() { _selectedCustomerId = null; _selectedCustomerLabel = null; }); _fetchInitial(); },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Return # or invoice…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                      onPressed: () { _searchController.clear(); _onSearchChanged(''); },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickFromDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: Text(_fromDate == null ? 'From' : DateFormat('dd MMM').format(_fromDate!)),
              ),
              OutlinedButton.icon(
                onPressed: _pickToDate,
                icon: const Icon(Icons.event_outlined, size: 17),
                label: Text(_toDate == null ? 'To' : DateFormat('dd MMM').format(_toDate!)),
              ),
              if (_fromDate != null || _toDate != null)
                TextButton.icon(onPressed: _clearDates, icon: const Icon(Icons.close_rounded, size: 17), label: const Text('Clear dates')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                child: Text('$_total returns', style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              clipBehavior: Clip.antiAlias,
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _loadError != null && _pages.isEmpty
                      ? _errorState()
                      : _total == 0
                          ? const Center(child: Text('No returns found'))
                          : Column(
                              children: [
                                _tableHeader(),
                                Expanded(
                                  child: Scrollbar(
                                    controller: _scrollController,
                                    thumbVisibility: true,
                                    child: RefreshIndicator(
                                      onRefresh: _onRefresh,
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        itemExtent: _rowExtent,
                                        cacheExtent: _rowExtent * 12,
                                        itemCount: _total,
                                        itemBuilder: (_, index) {
                                          final row = _returnAt(index);
                                          return row == null ? _loadingRow() : _returnRow(row);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppTheme.surfaceSoft,
        child: const Row(
          children: [
            SizedBox(width: 155, child: Text('RETURN', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 155, child: Text('INVOICE', style: _headerStyle)),
            SizedBox(width: 16),
            Expanded(flex: 28, child: Text('CUSTOMER', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 130, child: Text('DATE', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 140, child: Text('AMOUNT', style: _headerStyle)),
            SizedBox(width: 16),
            SizedBox(width: 84, child: Text('ACTIONS', style: _headerStyle)),
          ],
        ),
      );

  Widget _returnRow(Map<String, dynamic> r) {
    final returnNo = (r['return_no'] ?? '').toString();
    final kind = (r['kind'] ?? 'formal').toString();
    final sale = r['sale'] as Map?;
    final invoice = (sale?['invoice_no'] ?? r['invoice_no'] ?? 'N/A').toString();
    final customerMap = sale?['customer'] as Map?;
    final customer = [
      (customerMap?['first_name'] ?? r['customer_first_name'] ?? '').toString(),
      (customerMap?['last_name'] ?? r['customer_last_name'] ?? '').toString(),
    ].where((x) => x.trim().isNotEmpty).join(' ');
    final total = _toDouble(r['total']);
    final dt = _tryParseDate((r['created_at'] ?? '').toString());
    final saleId = _toInt(r['sale_id'] ?? sale?['id']);

    return InkWell(
      onTap: () async {
        if (saleId == null || saleId <= 0) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: saleId)),
        );
        if (mounted) _fetchInitial();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            SizedBox(width: 155, child: Text(returnNo.isEmpty ? '—' : returnNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 16),
            SizedBox(width: 155, child: Text(invoice, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
            Expanded(flex: 28, child: Text(customer.isEmpty ? 'Walk-in / N/A' : customer, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
            SizedBox(width: 130, child: Text(dt == null ? '—' : DateFormat('dd MMM yyyy').format(dt))),
            const SizedBox(width: 16),
            SizedBox(width: 140, child: Text(_currency.format(total), style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 16),
            SizedBox(
              width: 84,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Copy return #',
                    onPressed: returnNo.isEmpty ? null : () async {
                      await Clipboard.setData(ClipboardData(text: returnNo));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $returnNo')));
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                  Icon(
                    kind == 'inline' ? Icons.receipt_long_outlined : Icons.chevron_right_rounded,
                    size: 19,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _loadingRow() => const DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 34),
            const SizedBox(height: 10),
            Text(_loadError ?? 'Failed to load sale returns', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _fetchInitial, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      );

  static const TextStyle _headerStyle = TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .25);
}

DateTime? _tryParseDate(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString());
  } catch (_) {
    return null;
  }
}

(Color fg, Color bg) _chipPalette(BuildContext ctx, Color base) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final bg = isDark ? base.withOpacity(.25) : base.withOpacity(.12);
  final fg = isDark ? base.withOpacity(.95) : base.withOpacity(.90);
  return (fg, bg);
}

Widget _amountChip(BuildContext ctx, String label, String value, Color base, {IconData? icon}) {
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
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
        ),
      ],
    ),
  );
}
