import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/api/cashbook_service.dart';

class CashbookDayDetailsScreen extends StatefulWidget {
  final String date; // "YYYY-MM-DD"
  final String? accountId;
  final String? branchId;
  const CashbookDayDetailsScreen({
    super.key,
    required this.date,
    this.accountId,
    this.branchId,
  });

  @override
  State<CashbookDayDetailsScreen> createState() =>
      _CashbookDayDetailsScreenState();
}

class _CashbookDayDetailsScreenState extends State<CashbookDayDetailsScreen> {
  late final CashBookService _service;

  // latest response (header/totals)
  Map<String, dynamic>? _data;

  // list across pages
  final List<Map<String, dynamic>> _rows = [];

  // loading/error
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;

  // filters
  String? _type; // receipt|payment|expense|transfer_in|transfer_out
  String? _method; // cash|card|bank|wallet
  String? _partyKind; // customer|vendor|none
  String? _search;

  // pagination
  int _page = 1;
  int _lastPage = 1;
  final _perPage = 100;
  int _total = 0;

  // branch tracking
  int? _lastBranchId;

  // scroll
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? "";
    _service = CashBookService(token: token);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.watch<BranchProvider>().selectedBranchId;
    if (_lastBranchId != current || current == null) {
      _lastBranchId = current;
      _refresh();
    }
  }

  void _onScroll() {
    if (_loadingMore || _initialLoading) return;
    if (_page >= _lastPage) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _initialLoading = true;
      _error = null;
      _page = 1;
      _rows.clear();
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getCashBookDayDetails(
        date: widget.date,
        accountId: widget.accountId,
        branchId: branchId?.toString(),
        type: _type,
        method: _method,
        partyKind: _partyKind,
        search: _search,
        page: 1,
        perPage: _perPage,
        sort: "created_at",
        order: "asc",
      );

      final pagination = Map<String, dynamic>.from(res["pagination"] ?? {});
      _page = (pagination["current_page"] ?? 1) as int;
      _lastPage = (pagination["last_page"] ?? 1) as int;
      _total = (pagination["total"] ?? 0) as int;

      setState(() {
        _data = res;
        _rows.addAll(List<Map<String, dynamic>>.from(res["rows"] ?? const []));
        _initialLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final next = _page + 1;
      final res = await _service.getCashBookDayDetails(
        date: widget.date,
        accountId: widget.accountId,
        branchId: branchId?.toString(),
        type: _type,
        method: _method,
        partyKind: _partyKind,
        search: _search,
        page: next,
        perPage: _perPage,
        sort: "created_at",
        order: "asc",
      );

      final pagination = Map<String, dynamic>.from(res["pagination"] ?? {});
      _page = (pagination["current_page"] ?? next) as int;
      _lastPage = (pagination["last_page"] ?? _lastPage) as int;
      _total = (pagination["total"] ?? _total) as int;

      final newRows = List<Map<String, dynamic>>.from(res["rows"] ?? const []);
      setState(() {
        _rows.addAll(newRows);
        _data = {...?_data, ...res};
        _loadingMore = false;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load more: $e')));
      }
    }
  }

  void _applyFilters({
    String? type,
    String? method,
    String? party,
    String? searchTxt,
  }) {
    _type = type;
    _method = method;
    _partyKind = party;
    _search = searchTxt ?? _search;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Cashbook • ${widget.date}"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _refresh)
          : _data == null
          ? const Center(child: Text("No data"))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Small counts line
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    "Loaded ${_rows.length} / $_total (page $_page of $_lastPage)",
                    style: t.textTheme.labelSmall,
                  ),
                ),
                _SummaryBar(data: _data!),
                _FilterBar(
                  type: _type,
                  method: _method,
                  partyKind: _partyKind,
                  onChanged: (t1, m1, p1) =>
                      _applyFilters(type: t1, method: m1, party: p1),
                  onSearch: (txt) => _applyFilters(searchTxt: txt),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      itemCount: _rows.length + 1, // footer
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i == _rows.length) {
                          if (_page < _lastPage) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _loadingMore
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(),
                                      )
                                    : TextButton(
                                        onPressed: _loadNextPage,
                                        child: const Text('Load more'),
                                      ),
                              ),
                            );
                          }
                          return const SizedBox(height: 12);
                        }
                        return _TxnRow(row: _rows[i]);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummaryBar({required this.data});

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final totals = Map<String, dynamic>.from(data["totals"] ?? {});
    final opening = _s(data["opening"]);
    final closing = _s(data["closing"]);

    // simple inline labels with a tiny color accent on numbers
    TextStyle numStyle(Color c) =>
        t.textTheme.bodySmall!.copyWith(color: c, fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Opening: ", style: t.textTheme.bodySmall),
              Text(opening, style: numStyle(t.colorScheme.primary)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("In: ", style: t.textTheme.bodySmall),
              Text(_s(totals["in"]), style: numStyle(Colors.green)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Out: ", style: t.textTheme.bodySmall),
              Text(_s(totals["out"]), style: numStyle(Colors.red)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Expense: ", style: t.textTheme.bodySmall),
              Text(_s(totals["expense"]), style: numStyle(Colors.red)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Net: ", style: t.textTheme.bodySmall),
              Text(
                _s(totals["net"]),
                style: numStyle(
                  (double.tryParse(_s(totals["net"])) ?? 0) >= 0
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Closing: ", style: t.textTheme.bodySmall),
              Text(closing, style: numStyle(t.colorScheme.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  final String? type;
  final String? method;
  final String? partyKind;
  final void Function(String? type, String? method, String? partyKind)
  onChanged;
  final ValueChanged<String>? onSearch;
  const _FilterBar({
    required this.type,
    required this.method,
    required this.partyKind,
    required this.onChanged,
    this.onSearch,
  });

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  late String? _type = widget.type;
  late String? _method = widget.method;
  late String? _partyKind = widget.partyKind;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _apply() => widget.onChanged(_type, _method, _partyKind);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Dropdown<String?>(
            label: "Type",
            value: _type,
            items: const [
              null,
              "receipt",
              "payment",
              "expense",
              "transfer_in",
              "transfer_out",
            ],
            display: (v) => v ?? "Any",
            onChanged: (v) {
              setState(() => _type = v);
              _apply();
            },
          ),
          _Dropdown<String?>(
            label: "Method",
            value: _method,
            items: const [null, "cash", "card", "bank", "wallet"],
            display: (v) => v ?? "Any",
            onChanged: (v) {
              setState(() => _method = v);
              _apply();
            },
          ),
          _Dropdown<String?>(
            label: "Party",
            value: _partyKind,
            items: const [null, "customer", "vendor", "none"],
            display: (v) => v ?? "Any",
            onChanged: (v) {
              setState(() => _partyKind = v);
              _apply();
            },
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => widget.onSearch?.call(v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: "Search ref/voucher/note/name…",
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) display;
  final ValueChanged<T> onChanged;
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ).copyWith(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isDense: true,
            value: value,
            items: items
                .map(
                  (e) => DropdownMenuItem<T>(value: e, child: Text(display(e))),
                )
                .toList(),
            onChanged: (v) {
              if (v != null || items.contains(null)) onChanged(v as T);
            },
          ),
        ),
      ),
    );
  }
}

/// Compact row: 2 lines, tiny padding, colored left stripe by direction.
class _TxnRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _TxnRow({required this.row});

  @override
  Widget build(BuildContext context) {
    String _s(dynamic v) => (v ?? '').toString();

    final dir = _s(row['direction']); // in | out
    final type = _s(row['type']);
    final method = _s(row['method']);
    final amountStr = _s(row['amount_signed']);
    final amount = double.tryParse(amountStr.replaceAll(',', '')) ?? 0.0;

    final branchName = _s(row['branch']?['name']);
    final accountName = _s(row['account']?['name']);
    final ref = _s(row['reference']);
    final cpKind = _s(row['counterparty']?['kind']);
    final cpName = _s(row['counterparty']?['name']);
    final vendorMap = (row['vendor'] as Map?)?.cast<String, dynamic>();
    final vendorName = _s(vendorMap?['name']);
    final saleInvoice = _s((row['sale'] as Map?)?['invoice_no']);
    final created = _s(row['created_at']);
    final otherAcc = _s(row['transfer']?['other_account']);

    final t = Theme.of(context);
    final stripe = dir == 'in' ? Colors.green : Colors.red;

    // Build a compact meta line
    final List<String> meta = [];
    // if (branchName.isNotEmpty) meta.add(branchName);
    if (accountName.isNotEmpty) meta.add(accountName);
    if (method.isNotEmpty) meta.add(method);
    if (ref.isNotEmpty) meta.add("Ref $ref");
    if (cpKind != 'none' && cpName.isNotEmpty) meta.add("$cpKind: $cpName");
    if (vendorName.isNotEmpty) meta.add("vendor: $vendorName");
    if (saleInvoice.isNotEmpty) meta.add("Inv $saleInvoice");
    if (otherAcc.isNotEmpty) meta.add("XFER $otherAcc");
    if (created.isNotEmpty) meta.add(created);

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: stripe, width: 3)),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        minLeadingWidth: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        title: Text(
          "${type.toUpperCase()} • ${dir.toUpperCase()}"
          "${branchName.isNotEmpty ? ' • $branchName' : ''}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          // meta.join(" • "),
          meta.join(" -- "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (t.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w600, // semi-bold
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        trailing: Text(
          amountStr.isEmpty ? '0.00' : amountStr,
          style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: amount >= 0 ? Colors.green : Colors.red,
          ),
          textAlign: TextAlign.right,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 28),
            const SizedBox(height: 8),
            Text("Failed to load", style: t.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}
