import 'dart:async' show Timer;
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PartyBalancesScreen extends StatefulWidget {
  final String partyType; // customer | vendor

  const PartyBalancesScreen({super.key, required this.partyType});

  @override
  State<PartyBalancesScreen> createState() => _PartyBalancesScreenState();
}

class _PartyBalancesScreenState extends State<PartyBalancesScreen> {
  final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  final _currencyFmt = NumberFormat.simpleCurrency(name: '', decimalDigits: 2);
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  late ReportsService _reports;
  late CustomerService _customers;
  late VendorService _vendors;
  late String _partyType;

  DateTime? _from;
  DateTime? _to;
  int _page = 1;
  int _perPage = 50;

  bool _ready = false;
  bool _loadingBalances = false;
  bool _loadingLedger = false;
  bool _exporting = false;
  String? _error;

  _ReportData? _balances;
  _ReportData? _ledger;
  Map<String, dynamic>? _selectedParty;

  bool get _isCustomer => _partyType == 'customer';
  String get _balanceReportKey => _isCustomer ? 'customer-receivables' : 'vendor-payables';
  String get _partyIdKey => _isCustomer ? 'customer_id' : 'vendor_id';
  String get _partyNameKey => _isCustomer ? 'customer' : 'vendor';
  String get _title => _isCustomer ? 'Customer Balances' : 'Vendor Balances';

  @override
  void initState() {
    super.initState();
    _partyType = widget.partyType == 'vendor' ? 'vendor' : 'customer';
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);

    _searchCtrl.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token!;
      _reports = ReportsService(token: token);
      _customers = CustomerService(token: token);
      _vendors = VendorService(token: token);
      // Branch scoping is resolved by backend from the logged-in user's active branch.
      _ready = true;
      _fetchBalances();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _baseFilters({bool export = false}) => {
        if (_from != null) 'from': _dateTimeFmt.format(_from!),
        if (_to != null) 'to': _dateTimeFmt.format(_to!),
        if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
        'page': export ? 1 : _page,
        'per_page': export ? 1000 : (_searchCtrl.text.trim().isNotEmpty ? 250 : _perPage),
        'direction': 'desc',
      };

  void _onSearchChanged() {
    setState(() => _page = 1);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _ready && !_loadingBalances) _fetchBalances();
    });
  }

  Future<void> _fetchBalances() async {
    setState(() {
      _loadingBalances = true;
      _error = null;
    });

    try {
      final data = await _reports.runEnterpriseReport(
        reportKey: _balanceReportKey,
        filters: _baseFilters(),
      );
      final report = _ReportData.fromJson(data);
      if (!mounted) return;
      setState(() {
        _balances = report;
        if (_selectedParty != null) {
          final id = _partyId(_selectedParty!);
          Map<String, dynamic>? updated;
          for (final row in report.rows) {
            if (_partyId(row) == id) {
              updated = row;
              break;
            }
          }
          _selectedParty = updated ?? _selectedParty;
        }
      });
      if (_selectedParty != null) {
        await _fetchLedger(_selectedParty!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingBalances = false);
    }
  }

  Future<void> _fetchLedger(Map<String, dynamic> party) async {
    final id = _partyId(party);
    if (id == null) return;
    setState(() {
      _selectedParty = party;
      _loadingLedger = true;
      _ledger = null;
    });

    try {
      final data = await _reports.runEnterpriseReport(
        reportKey: 'ledger-detail',
        filters: {
          if (_from != null) 'from': _dateTimeFmt.format(_from!),
          if (_to != null) 'to': _dateTimeFmt.format(_to!),
            'party_type': _partyType,
          'party_id': id,
          'page': 1,
          'per_page': 100,
          'direction': 'asc',
        },
      );
      if (!mounted) return;
      setState(() => _ledger = _ReportData.fromJson(data));
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Ledger failed: $e');
    } finally {
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      final file = await _reports.exportEnterpriseReport(
        reportKey: _balanceReportKey,
        format: format,
        filters: _baseFilters(export: true),
      );
      final path = await saveReportFile(bytes: file.bytes, filename: file.filename, mimeType: file.contentType);
      if (!mounted) return;
      AppFeedback.success(context, 'Saved and opened: $path');
    } on ReportSaveCancelledException {
      // User dismissed the save dialog — nothing to report.
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickDateTime({required bool isFrom}) async {
    final current = isFrom ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final date = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(date.year, date.month, date.day, time.hour, time.minute, isFrom ? 0 : 59);
      if (isFrom) {
        _from = value;
      } else {
        _to = value;
      }
      _page = 1;
    });
    _fetchBalances();
  }

  Future<void> _quickPayment() async {
    final party = _selectedParty;
    final id = party == null ? null : _partyId(party);
    if (party == null || id == null) return;

    final amountCtrl = TextEditingController(text: _num(party['balance']).abs().toStringAsFixed(2));
    final refCtrl = TextEditingController();
    String method = 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_isCustomer ? 'Receive customer payment' : 'Pay vendor'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_partyName(party), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
                  items: const ['cash', 'card', 'bank', 'wallet'].map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase()))).toList(),
                  onChanged: (v) => setLocal(() => method = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Reference / Note', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;

    try {
      if (_isCustomer) {
        await _customers.createReceipt(customerId: id, amount: amount, method: method, reference: refCtrl.text.trim(), branchId: null);
      } else {
        await _vendors.createPayment(vendorId: id, amount: amount, method: method, reference: refCtrl.text.trim(), branchId: null);
      }
      if (!mounted) return;
      AppFeedback.success(context, 'Payment saved successfully');
      await _fetchBalances();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Payment failed: $e');
    }
  }

  Future<void> _editParty() async {
    final party = _selectedParty;
    if (party == null) return;
    final payload = _partyFormPayload(party);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isCustomer ? CustomerFormScreen(customer: payload) : VendorFormScreen(vendor: payload),
      ),
    );
    if (result != null) _fetchBalances();
  }

  void _openTransaction() {
    final party = _selectedParty;
    if (party == null) return;
    final payload = _partyFormPayload(party);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isCustomer ? CreateSaleScreen(initialCustomer: payload) : CreatePurchaseScreen(initialVendor: payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1050;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        centerTitle: false,
        actions: [
          const Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false)),
          IconButton(tooltip: 'Refresh', onPressed: (!_ready || _loadingBalances) ? null : _fetchBalances, icon: const Icon(Icons.refresh_rounded)),
          OutlinedButton.icon(onPressed: (!_ready || _exporting) ? null : () => _export('xlsx'), icon: const Icon(Icons.table_chart_rounded), label: const Text('Excel')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: (!_ready || _exporting) ? null : () => _export('pdf'), icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(),
            _buildFilters(isWide),
            if (_loadingBalances)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(hasScrollBody: false, child: _ErrorState(message: _error!, onRetry: _fetchBalances))
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: isWide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: _buildBalancesCard()), const SizedBox(width: 12), Expanded(flex: 4, child: _buildLedgerCard())]) : Column(children: [_buildBalancesCard(), const SizedBox(height: 12), _buildLedgerCard()]),
                ),
              ),
            _buildPagination(),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildHeader() {
    final totals = _balances?.totals ?? const <String, dynamic>{};
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withOpacity(.76)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(16)),
                child: Icon(_isCustomer ? Icons.people_alt_rounded : Icons.groups_2_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(_isCustomer ? 'All receivables with instant ledger, receipt and sale actions.' : 'All payables with instant ledger, payment and purchase actions.', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              _HeroMetric(label: 'Balance', value: _money(totals['balance'])),
              const SizedBox(width: 8),
              _HeroMetric(label: 'Invoices', value: _plain(totals['invoices'])),
            ],
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildFilters(bool isWide) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.65))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterChipButton(icon: Icons.schedule_rounded, label: _from == null ? 'From: Any' : 'From: ${_dateTimeFmt.format(_from!)}', onTap: () => _pickDateTime(isFrom: true)),
                _FilterChipButton(icon: Icons.schedule_outlined, label: _to == null ? 'To: Any' : 'To: ${_dateTimeFmt.format(_to!)}', onTap: () => _pickDateTime(isFrom: false)),
                SizedBox(
                  width: isWide ? 320 : double.infinity,
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) { setState(() => _page = 1); _fetchBalances(); },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: _isCustomer ? 'Search customer / phone' : 'Search vendor / phone',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      suffixIcon: _searchCtrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { _searchCtrl.clear(); setState(() => _page = 1); _fetchBalances(); }),
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _perPage,
                    items: const [25, 50, 100, 250].map((v) => DropdownMenuItem(value: v, child: Text('$v rows'))).toList(),
                    onChanged: (v) { if (v == null) return; setState(() { _perPage = v; _page = 1; }); _fetchBalances(); },
                  ),
                ),
                FilledButton.icon(onPressed: (!_ready || _loadingBalances) ? null : _fetchBalances, icon: const Icon(Icons.search_rounded), label: const Text('Apply')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalancesCard() {
    final rows = _visibleBalanceRows();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.65))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(title: _isCustomer ? 'Receivable Customers' : 'Payable Vendors', subtitle: 'Tap any row to see detailed ledger and actions'),
          const Divider(height: 1),
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No balances found')))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final row = rows[i];
                final selected = _selectedParty != null && _partyId(_selectedParty!) == _partyId(row);
                return Material(
                  color: selected ? Theme.of(context).colorScheme.primary.withOpacity(.08) : null,
                  child: ListTile(
                    onTap: () => _fetchLedger(row),
                    leading: CircleAvatar(child: Text(_partyName(row).isEmpty ? '?' : _partyName(row)[0].toUpperCase())),
                    title: Text(_partyName(row), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${row['phone'] ?? 'No phone'} • ${_plain(row['invoices'])} invoices'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(row['balance']), style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text(_isCustomer ? 'Receivable' : 'Payable', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLedgerCard() {
    final party = _selectedParty;
    final ledger = _ledger;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.65))),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(title: party == null ? 'Ledger Detail' : _partyName(party), subtitle: party == null ? 'Select a ${_isCustomer ? 'customer' : 'vendor'} from the left' : 'Balance ${_money(party['balance'])}'),
          if (party != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(onPressed: _quickPayment, icon: Icon(_isCustomer ? Icons.call_received_rounded : Icons.call_made_rounded), label: Text(_isCustomer ? 'Receive' : 'Pay')),
                  OutlinedButton.icon(onPressed: _openTransaction, icon: Icon(_isCustomer ? Icons.point_of_sale_rounded : Icons.shopping_cart_checkout_rounded), label: Text(_isCustomer ? 'New Sale' : 'New Purchase')),
                  OutlinedButton.icon(onPressed: _editParty, icon: const Icon(Icons.edit_rounded), label: const Text('Edit')),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          if (party == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No party selected')))
          else if (_loadingLedger)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (ledger == null || ledger.rows.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No ledger entries found')))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 58,
                columns: ledger.columns.take(7).map((c) => DataColumn(label: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w800)))).toList(),
                rows: ledger.rows.take(100).map((row) => DataRow(cells: ledger.columns.take(7).map((c) => DataCell(Text(_cell(row[c.key], c.key), overflow: TextOverflow.ellipsis))).toList())).toList(),
              ),
            ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildPagination() {
    final p = _balances?.pagination;
    if (p == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Row(
          children: [
            Text(_searchCtrl.text.trim().isEmpty ? 'Page ${p.currentPage} of ${p.lastPage} • ${p.total} records' : '${_visibleBalanceRows().length} matching rows • server page ${p.currentPage}/${p.lastPage}'),
            const Spacer(),
            IconButton(onPressed: p.currentPage <= 1 || _loadingBalances ? null : () { setState(() => _page = p.currentPage - 1); _fetchBalances(); }, icon: const Icon(Icons.chevron_left_rounded)),
            IconButton(onPressed: p.currentPage >= p.lastPage || _loadingBalances ? null : () { setState(() => _page = p.currentPage + 1); _fetchBalances(); }, icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _visibleBalanceRows() {
    final rows = _balances?.rows ?? const <Map<String, dynamic>>[];
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return rows;

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return rows;

    return rows.where((row) {
      final haystack = row.values.map((v) => v?.toString().toLowerCase() ?? '').join(' ');
      return tokens.every(haystack.contains);
    }).toList(growable: false);
  }

  Map<String, dynamic> _partyFormPayload(Map<String, dynamic> row) {
    final name = _partyName(row).trim();
    final parts = name.split(RegExp(r'\s+'));
    return {
      'id': _partyId(row),
      'first_name': parts.isEmpty ? name : parts.first,
      'last_name': parts.length <= 1 ? '' : parts.sublist(1).join(' '),
      'email': row['email'] ?? '',
      'phone': row['phone'] ?? '',
      'address': row['address'] ?? '',
      'status': row['status'] ?? 'active',
    };
  }

  int? _partyId(Map<String, dynamic> row) => _toInt(row[_partyIdKey]);
  String _partyName(Map<String, dynamic> row) => (row[_partyNameKey] ?? row['name'] ?? '#${_partyId(row) ?? ''}').toString().trim();
  String _plain(dynamic v) => v == null ? '0' : v.toString();
  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0;
  String _money(dynamic v) => _currencyFmt.format(_num(v));
  String _cell(dynamic v, String key) {
    if (v == null) return '—';
    final lower = key.toLowerCase();
    if (lower.contains('debit') || lower.contains('credit') || lower.contains('balance') || lower.contains('amount') || lower.contains('total')) return _money(v);
    return v.toString().isEmpty ? '—' : v.toString();
  }
}

class _ReportData {
  final List<_ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;
  final _ReportPagination? pagination;

  _ReportData({required this.columns, required this.rows, required this.totals, this.pagination});

  factory _ReportData.fromJson(Map<String, dynamic> json) {
    return _ReportData(
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
        currentPage: _toInt(json['current_page']) ?? 1,
        lastPage: _toInt(json['last_page']) ?? 1,
        total: _toInt(json['total']) ?? 0,
      );
}

class _CardTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _CardTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 122,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
