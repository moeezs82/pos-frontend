import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/cashbook/widgets/cb_pagination.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DayBookDayDetailsScreen extends StatefulWidget {
  /// The date to show details for (YYYY-MM-DD).
  final String date;

  const DayBookDayDetailsScreen({super.key, required this.date});

  @override
  State<DayBookDayDetailsScreen> createState() => _DayBookDayDetailsScreenState();
}

class _DayBookDayDetailsScreenState extends State<DayBookDayDetailsScreen> {
  late CashBookService _cashService;

  // Data
  List<Map<String, dynamic>> _rows = [];

  // Totals / balances
  String _opening = "0.00";
  String _closing = "0.00";
  String _totIn = "0.00";
  String _totOut = "0.00";
  String _totNet = "0.00";

  // UI state
  bool _loading = true;
  bool _includeLines = true;

  // Pagination
  int _currentPage = 1;
  int _lastPage = 1;
  final int _perPage = 50;

  // Sorting / filtering
  String _sort = "created_at"; // created_at | in | out | net | reference_type
  String _order = "asc";       // asc | desc
  String? _referenceType;      // e.g., "App\\Models\\Sale"
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _cashService = CashBookService(token: token);
    _fetch(page: 1);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() => _loading = true);
    final branchId = context.read<BranchProvider>().selectedBranchId;

    try {
      // FIX: use the correct service method name
      final res = await _cashService.getDayBookDayDetails(
        date: widget.date,
        branchId: branchId?.toString(),
        page: page,
        perPage: _perPage,
        sort: _sort,
        order: _order,
        referenceType: _referenceType,
        search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
        includeLines: _includeLines,
      );

      final totals = Map<String, dynamic>.from(res['totals'] ?? {});
      final rows = List<Map<String, dynamic>>.from(res['rows'] ?? const []);
      final p = Map<String, dynamic>.from(res['pagination'] ?? {});

      setState(() {
        _opening = (res['opening'] ?? 0).toString();
        _closing = (res['closing'] ?? 0).toString();
        _totIn = (totals['in'] ?? 0).toString();
        _totOut = (totals['out'] ?? 0).toString();
        _totNet = (totals['net'] ?? 0).toString();

        _rows = rows;
        _currentPage = (p['current_page'] ?? 1) as int;
        _lastPage = (p['last_page'] ?? 1) as int;

        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load day details: $e")),
        );
      }
    }
  }

  String _fmtMoney(dynamic v) {
    if (v == null) return "0.00";
    final d = (v is String) ? double.tryParse(v) : (v is num ? v.toDouble() : 0.0);
    return (d ?? 0.0).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final isAllBranch = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: Text("Day Details — ${widget.date}"),
        actions: [
          const BranchIndicator(tappable: false),
          IconButton(
            tooltip: "Refresh",
            onPressed: () => _fetch(page: _currentPage),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Summary / balances
          _SummaryBar(
            opening: _opening,
            inAmt: _totIn,
            outAmt: _totOut,
            net: _totNet,
            closing: _closing,
          ),

          // Filters row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                // Search
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: "Search (memo / reference id)",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetch(page: 1),
                  ),
                ),
                const SizedBox(width: 8),

                // Reference type quick picker
                SizedBox(
                  width: 220,
                  child: _ReferenceTypeField(
                    value: _referenceType,
                    onChanged: (v) {
                      setState(() => _referenceType = v);
                      _fetch(page: 1);
                    },
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                // SORT — FIX: use DropdownButtonFormField instead of InputDecorator
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _sort,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Sort by",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'created_at', child: Text('Created time')),
                      DropdownMenuItem(value: 'in', child: Text('In amount')),
                      DropdownMenuItem(value: 'out', child: Text('Out amount')),
                      DropdownMenuItem(value: 'net', child: Text('Net (In-Out)')),
                      DropdownMenuItem(value: 'reference_type', child: Text('Reference type')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sort = v);
                      _fetch(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // ORDER — FIX: use DropdownButtonFormField instead of InputDecorator
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _order,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Order",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'asc', child: Text('Ascending')),
                      DropdownMenuItem(value: 'desc', child: Text('Descending')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _order = v);
                      _fetch(page: 1);
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Include lines
                Row(
                  children: [
                    const Text("Include lines"),
                    Switch(
                      value: _includeLines,
                      onChanged: (val) {
                        setState(() => _includeLines = val);
                        _fetch(page: _currentPage);
                      },
                    ),
                  ],
                ),

                const Spacer(),

                if (isAllBranch)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Text(
                      "All branches",
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text("No entries found for this date."))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _EntryCard(
                          row: _rows[i],
                          includeLines: _includeLines,
                        ),
                      ),
          ),

          // Pagination
          CBPagination(
            currentPage: _currentPage,
            lastPage: _lastPage,
            onPrev: _currentPage > 1 ? () => _fetch(page: _currentPage - 1) : null,
            onNext: _currentPage < _lastPage ? () => _fetch(page: _currentPage + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Simple summary bar for balances & totals
class _SummaryBar extends StatelessWidget {
  final String opening;
  final String inAmt;
  final String outAmt;
  final String net;
  final String closing;

  const _SummaryBar({
    required this.opening,
    required this.inAmt,
    required this.outAmt,
    required this.net,
    required this.closing,
  });

  String _fmt(String v) {
    final d = double.tryParse(v) ?? 0.0;
    return d.toStringAsFixed(2);
  }

  Widget _pill(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: (color ?? Colors.blueGrey.shade50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_fmt(value), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _pill("Opening", opening),
            _pill("In", inAmt, color: Colors.green.withOpacity(0.15)),
            _pill("Out", outAmt, color: Colors.red.withOpacity(0.15)),
            _pill("Net", net, color: Colors.blue.withOpacity(0.15)),
            _pill("Closing", closing),
          ],
        ),
      ),
    );
  }
}

/// Reference type input with a few quick options + free text
class _ReferenceTypeField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ReferenceTypeField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const suggestions = <String>[
      'App\\Models\\Sale',
      'App\\Models\\Receipt',
      'App\\Models\\Purchase',
      'App\\Models\\VendorPayment',
      'App\\Models\\SaleReturn',
      'App\\Models\\PurchaseClaim',
    ];

    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      decoration: const InputDecoration(
        labelText: "Reference type (optional)",
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text("All types")),
        ...suggestions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
      ],
      onChanged: onChanged,
    );
  }
}

/// One entry row (expandable) with lines table
class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool includeLines;

  const _EntryCard({required this.row, required this.includeLines});

  String _fmt(dynamic v) {
    if (v == null) return "0.00";
    final n = (v is String) ? double.tryParse(v) : (v is num ? v.toDouble() : 0.0);
    return (n ?? 0.0).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final refType = (row['reference_type'] ?? '') as String;
    final refId = row['reference_id']?.toString() ?? '';
    final memo = (row['memo'] ?? '') as String;
    final time = (row['time'] ?? '') as String;
    final inAmt = _fmt(row['in']);
    final outAmt = _fmt(row['out']);
    final netAmt = _fmt(row['net']);

    final lines = (row['lines'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              memo.isNotEmpty ? memo : (refType.split('\\').last + (refId.isNotEmpty ? " #$refId" : "")),
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _AmountChip(label: "In", value: inAmt, color: Colors.green),
          const SizedBox(width: 6),
          _AmountChip(label: "Out", value: outAmt, color: Colors.red),
          const SizedBox(width: 6),
          _AmountChip(label: "Net", value: netAmt, color: Colors.blue),
        ],
      ),
      subtitle: Text(
        "${refType.isNotEmpty ? refType.split('\\').last : 'Entry'} • $time",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        if (includeLines && lines.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Account Code')),
                DataColumn(label: Text('Account Name')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Debit')),
                DataColumn(label: Text('Credit')),
              ],
              rows: lines.map((l) {
                return DataRow(cells: [
                  DataCell(Text((l['account_code'] ?? '').toString())),
                  DataCell(Text((l['account_name'] ?? '').toString())),
                  DataCell(Text((l['account_type'] ?? '').toString())),
                  DataCell(Text(_fmt(l['debit']))),
                  DataCell(Text(_fmt(l['credit']))),
                ]);
              }).toList(),
            ),
          )
        else if (includeLines && lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("No lines available for this entry."),
            ),
          ),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AmountChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: color.withOpacity(0.1),
      shape: StadiumBorder(side: BorderSide(color: color.withOpacity(0.4))),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
