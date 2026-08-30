import 'dart:async';

import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/picking_list_print_service.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PickingListScreen extends StatefulWidget {
  final DateTime? initialFromDate;
  final DateTime? initialToDate;
  final int? initialCustomerId;
  final String? initialCustomerLabel;
  final String initialSearch;

  const PickingListScreen({
    super.key,
    this.initialFromDate,
    this.initialToDate,
    this.initialCustomerId,
    this.initialCustomerLabel,
    this.initialSearch = '',
  });

  @override
  State<PickingListScreen> createState() => _PickingListScreenState();
}

class _PickingListScreenState extends State<PickingListScreen> {
  late SaleService _service;
  final _printer = const PickingListPrintService();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  late DateTime _fromDate;
  late DateTime _toDate;
  int? _customerId;
  String? _customerLabel;

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _fromDate = _dateOnly(widget.initialFromDate ?? today);
    _toDate = _dateOnly(widget.initialToDate ?? widget.initialFromDate ?? today);
    if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
    _customerId = widget.initialCustomerId;
    _customerLabel = widget.initialCustomerLabel;
    _searchController.text = widget.initialSearch;
    final token = context.read<AuthProvider>().token!;
    _service = SaleService(token: token);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getPickingList(
        dateFrom: _apiDate(_fromDate),
        dateTo: _apiDate(_toDate),
        customerId: _customerId,
        search: _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _fromDate : _toDate,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _fromDate = _dateOnly(picked);
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = _dateOnly(picked);
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
    await _load();
  }

  Future<void> _setQuickRange(String key) async {
    final today = _dateOnly(DateTime.now());
    setState(() {
      switch (key) {
        case 'yesterday':
          _fromDate = today.subtract(const Duration(days: 1));
          _toDate = _fromDate;
          break;
        case '7days':
          _fromDate = today.subtract(const Duration(days: 6));
          _toDate = today;
          break;
        default:
          _fromDate = today;
          _toDate = today;
      }
    });
    await _load();
  }

  Future<void> _openCustomerPicker() async {
    final token = context.read<AuthProvider>().token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * .85,
        child: CustomerPickerSheet(token: token),
      ),
    );
    if (!mounted || picked == null) return;
    final id = _toInt(picked['id']);
    if (id == null) return;
    setState(() {
      _customerId = id;
      _customerLabel = CustomerDisplayUtils.nameWithArea(
        picked,
        fallback: 'Customer #$id',
      );
    });
    await _load();
  }

  Future<void> _clearCustomer() async {
    setState(() {
      _customerId = null;
      _customerLabel = null;
    });
    await _load();
  }

  Future<void> _print() async {
    final data = _data;
    if (data == null || _printing) return;
    setState(() => _printing = true);
    try {
      await _printer.printOrSave(data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to print picking list: ${_errorText(e)}')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data ?? const <String, dynamic>{};
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    final sales = _toInt(data['sale_count']) ?? 0;
    final products = _toInt(data['product_count']) ?? 0;
    final totalQty = _qty(data['total_quantity']);
    final excludedReturns = _toDouble(data['excluded_return_quantity']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picking List'),
        actions: [
          const BranchIndicator(tappable: false),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _filtersCard(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? _errorState()
                : _loading && _data == null
                    ? const Center(child: CircularProgressIndicator())
                    : _content(
                        items: items,
                        sales: sales,
                        products: products,
                        totalQty: totalQty,
                        excludedReturns: excludedReturns,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filtersCard() {
    final dateLabel = _fromDate == _toDate
        ? DateFormat('dd MMM yyyy').format(_fromDate)
        : '${DateFormat('dd MMM yyyy').format(_fromDate)} — ${DateFormat('dd MMM yyyy').format(_toDate)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Store picking summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Consolidates exact products and variants from sales into quantities to pick for packing.', style: TextStyle(fontSize: 11.5, color: Colors.blueGrey)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _setQuickRange('today'),
                icon: const Icon(Icons.today_outlined, size: 17),
                label: const Text('Today'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: _loading ? null : () => _setQuickRange('yesterday'),
                child: const Text('Yesterday'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: _loading ? null : () => _setQuickRange('7days'),
                child: const Text('Last 7 Days'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 15,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    labelText: 'Invoice / customer',
                    hintText: 'Optional',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _load();
                            },
                            icon: const Icon(Icons.clear_rounded, size: 18),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 12,
                child: InkWell(
                  onTap: _loading ? null : _openCustomerPicker,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Customer',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _customerLabel ?? 'All customers',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_customerId == null)
                          const Icon(Icons.person_search_outlined, size: 18)
                        else
                          GestureDetector(
                            onTap: _clearCustomer,
                            child: const Icon(Icons.clear_rounded, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 154,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickDate(from: true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(DateFormat('dd MMM').format(_fromDate)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Text('to', style: TextStyle(color: Colors.blueGrey)),
              ),
              SizedBox(
                width: 154,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickDate(from: false),
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(DateFormat('dd MMM').format(_toDate)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                label: const Text('Generate'),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Period: $dateLabel',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content({
    required List<Map<String, dynamic>> items,
    required int sales,
    required int products,
    required String totalQty,
    required double excludedReturns,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _metricCard(icon: Icons.receipt_long_outlined, label: 'Sales included', value: '$sales', helper: 'Orders with items to pick')),
              const SizedBox(width: 8),
              Expanded(child: _metricCard(icon: Icons.category_outlined, label: 'Products / variants', value: '$products', helper: 'Exact distinct stock items')),
              const SizedBox(width: 8),
              Expanded(child: _metricCard(icon: Icons.inventory_outlined, label: 'Total quantity', value: totalQty, helper: 'Combined picking quantity')),
              const SizedBox(width: 8),
              SizedBox(
                width: 188,
                child: FilledButton.icon(
                  onPressed: items.isEmpty || _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_outlined),
                  label: Text(_printing ? 'Preparing…' : 'Print / Save PDF'),
                ),
              ),
            ],
          ),
          if (excludedReturns > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(.09),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.amber.withOpacity(.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_return_outlined, size: 17, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_qty(excludedReturns)} return quantity excluded. Picking lists show items that need to be brought for packing, not financial net quantities.',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.5)),
              ),
              child: items.isEmpty ? _emptyState() : _table(items),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(List<Map<String, dynamic>> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth < 1080 ? 1080 : constraints.maxWidth),
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 64,
                  horizontalMargin: 14,
                  columnSpacing: 22,
                  headingTextStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.blueGrey),
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('PRODUCT')),
                    DataColumn(label: Text('VARIANT')),
                    DataColumn(label: Text('SKU / BARCODE')),
                    DataColumn(label: Text('UNIT')),
                    DataColumn(label: Text('SALES'), numeric: true),
                    DataColumn(label: Text('QTY TO PICK'), numeric: true),
                  ],
                  rows: [
                    for (var i = 0; i < items.length; i++) _dataRow(i, items[i]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow _dataRow(int index, Map<String, dynamic> item) {
    final name = _text(item['name'], fallback: 'Product #${item['product_id']}');
    final secondary = _text(item['secondary_name']);
    final size = _text(item['variant_size']);
    final color = _text(item['variant_color']);
    final variant = [size, color].where((e) => e.isNotEmpty).join(' / ');
    final sku = _text(item['sku']);
    final barcode = _text(item['barcode']);
    final unit = _text(item['unit_short_name'], fallback: _text(item['unit_name'], fallback: '—'));
    final orderCount = _toInt(item['sale_count']) ?? 0;
    final qty = _qty(item['quantity']);

    return DataRow(
      cells: [
        DataCell(Text('${index + 1}', style: const TextStyle(color: Colors.blueGrey))),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                if (secondary.isNotEmpty)
                  Text(secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Colors.blueGrey)),
              ],
            ),
          ),
        ),
        DataCell(
          variant.isEmpty
              ? const Text('—', style: TextStyle(color: Colors.grey))
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(.08), borderRadius: BorderRadius.circular(7)),
                  child: Text(variant, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
        ),
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sku.isEmpty ? '—' : sku, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              if (barcode.isNotEmpty) Text(barcode, style: const TextStyle(fontSize: 10.5, color: Colors.blueGrey)),
            ],
          ),
        ),
        DataCell(Text(unit, style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Text('$orderCount', style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(
          Container(
            constraints: const BoxConstraints(minWidth: 74),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.green.withOpacity(.10), borderRadius: BorderRadius.circular(8)),
            child: Text(qty, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.green)),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({required IconData icon, required String label, required String value, required String helper}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(.09), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(helper, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Colors.blueGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 52, color: Colors.blueGrey),
            SizedBox(height: 12),
            Text('No items to pick', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            SizedBox(height: 4),
            Text('No positive sale quantities match the selected period and filters.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey)),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 10),
            const Text('Unable to generate picking list', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 5),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try Again')),
          ],
        ),
      ),
    );
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty || s == 'null' ? fallback : s;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _qty(dynamic value) {
    final n = _toDouble(value);
    if ((n - n.roundToDouble()).abs() < .0000001) return n.toStringAsFixed(0);
    return n.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _errorText(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }
}
