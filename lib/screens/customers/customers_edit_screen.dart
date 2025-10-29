import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomerEditScreen extends StatefulWidget {
  final int customerId;
  const CustomerEditScreen({super.key, required this.customerId});

  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen>
    with SingleTickerProviderStateMixin {
  late CustomerService _service;
  late TabController _tab;

  bool _postingReceipt = false; // NEW
  final _amountController = TextEditingController(); // NEW
  final _referenceController = TextEditingController(); // NEW
  String methodPay = "cash";

  bool _loadingHeader = true;
  String? _errorHeader;

  Map<String, dynamic>? customer; // includes total_sales/total_receipts/balance

  // Sales state
  final int _pageSize = 10;
  bool _loadingSales = false;
  bool _loadedSalesOnce = false;
  String? _errorSales;
  int _salesPage = 1, _salesLastPage = 1, _salesTotal = 0;
  final List<Map<String, dynamic>> _sales = [];

  // Ledger state (replaces receipts)
  bool _loadingLedger = false;
  bool _loadedLedgerOnce = false;
  String? _errorLedger;
  int _ldgPage = 1, _ldgLastPage = 1, _ldgTotal = 0;
  double _opening = 0.0, _openingForPage = 0.0;
  final List<Map<String, dynamic>> _ledger = [];

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CustomerService(token: token);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHeader();
      // Preload Sales
      _loadSales(page: 1);
    });
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tab.indexIsChanging) {
      if (_tab.index == 0 && !_loadedSalesOnce) _loadSales(page: 1);
      if (_tab.index == 1 && !_loadedLedgerOnce) _loadLedger(page: 1);
    }
  }

  Future<void> _loadHeader() async {
    setState(() {
      _loadingHeader = true;
      _errorHeader = null;
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getCustomerDetail(
        id: widget.customerId,
        branchId: branchId,
      );
      setState(() {
        customer = (res['data'] as Map).cast<String, dynamic>();
      });
    } catch (e) {
      setState(() => _errorHeader = "Failed to load customer: $e");
    } finally {
      setState(() => _loadingHeader = false);
    }
  }

  Future<void> _openReceiveModal() async {
    if (customer == null || _postingReceipt) return;
    _amountController.text = "";
    _referenceController.text = "";
    

    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // force explicit action
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              title: Row(
                children: [
                  const Icon(Icons.payments_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "Record Receipt",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close),
                    onPressed: _postingReceipt
                        ? null
                        : () => Navigator.pop(dlgCtx),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 320,
                    maxWidth: 420,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _amountController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Amount",
                            hintText: "0.00",
                            prefixIcon: Icon(Icons.currency_exchange_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final t = (v ?? "").trim();
                            if (t.isEmpty) return "Amount is required";
                            final parsed = double.tryParse(t);
                            if (parsed == null) return "Enter a valid number";
                            return null;
                          },
                          onFieldSubmitted: (_) async {
                            if (_postingReceipt) return;
                            if (!(formKey.currentState?.validate() ?? false))
                              return;
                            await _submitReceipt(dlgCtx);
                            setLocal(() {}); // refresh local UI if still open
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _referenceController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Reference",
                            hintText: "Reference Note",
                            prefixIcon: Icon(Icons.file_present),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: methodPay,
                          decoration: const InputDecoration(
                            labelText: "Method",
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "cash",
                              child: Text("Cash"),
                            ),
                            DropdownMenuItem(
                              value: "bank",
                              child: Text("Bank"),
                            ),
                          ],
                          onChanged: (val) => methodPay = val!,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                OutlinedButton(
                  onPressed: _postingReceipt
                      ? null
                      : () => Navigator.pop(dlgCtx),
                  child: const Text("Cancel"),
                ),
                FilledButton.icon(
                  onPressed: _postingReceipt
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false))
                            return;
                          await _submitReceipt(dlgCtx);
                          setLocal(() {}); // keep dialog reactive if needed
                        },
                  icon: _postingReceipt
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitReceipt(BuildContext sheetCtx) async {
    setState(() => _postingReceipt = true);
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final amount = double.parse(_amountController.text.trim());
      final reference = _referenceController.text.trim();
      final method = methodPay;

      await _service.createReceipt(
        customerId: widget.customerId,
        amount: amount,
        branchId: branchId,
        method: method,
        reference: reference,
      );

      if (mounted) {
        Navigator.pop(sheetCtx); // close modal
        // Refresh header + whichever tab is visible
        await _loadHeader();
        if (_tab.index == 0 && _loadedSalesOnce) {
          await _loadSales(page: _salesPage);
        } else if (_tab.index == 1 && _loadedLedgerOnce) {
          await _loadLedger(page: _ldgPage);
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Receipt recorded")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to save receipt: $e")));
      }
    } finally {
      if (mounted) setState(() => _postingReceipt = false);
    }
  }

  Future<void> _loadSales({required int page}) async {
    if (_loadingSales) return;
    setState(() {
      _loadingSales = true;
      _errorSales = null;
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getCustomerSales(
        id: widget.customerId,
        page: page,
        perPage: _pageSize,
        branchId: branchId,
      );
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      setState(() {
        _sales
          ..clear()
          ..addAll(items);
        _salesPage = (wrap['current_page'] as num?)?.toInt() ?? page;
        _salesLastPage = (wrap['last_page'] as num?)?.toInt() ?? _salesLastPage;
        _salesTotal = (wrap['total'] as num?)?.toInt() ?? _salesTotal;
        _loadedSalesOnce = true;
      });
    } catch (e) {
      setState(() => _errorSales = "Failed to load sales: $e");
    } finally {
      setState(() => _loadingSales = false);
    }
  }

  Future<void> _refreshAll() async {
    // Avoid overlapping requests
    if (_loadingHeader || _loadingSales || _loadingLedger) return;

    await _loadHeader();

    if (_tab.index == 0) {
      await _loadSales(page: _salesPage); // keep current page
    } else {
      await _loadLedger(page: _ldgPage); // keep current page
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refreshed')));
  }

  Future<void> _loadLedger({required int page}) async {
    if (_loadingLedger) return;
    setState(() {
      _loadingLedger = true;
      _errorLedger = null;
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getCustomerLedger(
        id: widget.customerId,
        page: page,
        perPage: _pageSize,
        branchId: branchId,
        // Optionally pass from/to if you wire date pickers later
        // from: '2025-10-01',
        // to: '2025-10-24',
      );
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

      setState(() {
        _ledger
          ..clear()
          ..addAll(items);
        _opening = ((wrap['opening'] as num?) ?? 0).toDouble();
        _openingForPage = ((wrap['opening_for_page'] as num?) ?? 0).toDouble();
        _ldgPage = (wrap['current_page'] as num?)?.toInt() ?? page;
        _ldgLastPage = (wrap['last_page'] as num?)?.toInt() ?? _ldgLastPage;
        _ldgTotal = (wrap['total'] as num?)?.toInt() ?? _ldgTotal;
        _loadedLedgerOnce = true;
      });
    } catch (e) {
      setState(() => _errorLedger = "Failed to load ledger: $e");
    } finally {
      setState(() => _loadingLedger = false);
    }
  }

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  Future<void> _openEdit() async {
    if (customer == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: customer)),
    );
    if (result == true) {
      await _loadHeader();
      if (_tab.index == 0 && _loadedSalesOnce) _loadSales(page: _salesPage);
      if (_tab.index == 1 && _loadedLedgerOnce) _loadLedger(page: _ldgPage);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Customer updated")));
    }
  }

  Widget _segmentedTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final border = theme.dividerColor.withOpacity(0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: TabBar(
          controller: _tab,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: theme.colorScheme.primary.withOpacity(0.08),
            border: Border.all(color: theme.colorScheme.primary, width: 0.8),
          ),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.textTheme.bodyMedium?.color,
          tabs: const [
            Tab(text: "Sales"),
            Tab(text: "Ledger"),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer"),
        actions: [
          IconButton(
            tooltip: 'Receive',
            icon: const Icon(Icons.payments_rounded),
            onPressed:
                (_loadingHeader ||
                    _loadingSales ||
                    _loadingLedger ||
                    _postingReceipt)
                ? null
                : _openReceiveModal, // NEW
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loadingHeader || _loadingSales || _loadingLedger)
                ? null
                : _refreshAll,
          ),
        ],
      ),
      body: _loadingHeader
          ? const Center(child: CircularProgressIndicator())
          : _errorHeader != null
          ? _ErrorView(message: _errorHeader!, onRetry: _loadHeader)
          : Column(
              children: [
                // Overview
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderBlock(customer: customer!, onEdit: _openEdit),
                        const SizedBox(height: 8),
                        _TotalsRow(customer: customer!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: (_loadingHeader || _postingReceipt)
                          ? null
                          : _openReceiveModal,
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text("Receive"),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),

                // Tabs
                _segmentedTabBar(context),

                // Tab contents
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _SalesTab(
                        items: _sales,
                        isLoading: _loadingSales,
                        error: _errorSales,
                        page: _salesPage,
                        lastPage: _salesLastPage,
                        total: _salesTotal,
                        onRetry: () => _loadSales(page: _salesPage),
                        onPrev: () => _loadSales(page: _salesPage - 1),
                        onNext: () => _loadSales(page: _salesPage + 1),
                        onRefresh: () async => _loadSales(page: 1),
                      ),
                      _LedgerTab(
                        items: _ledger,
                        opening: _opening,
                        openingForPage: _openingForPage,
                        isLoading: _loadingLedger,
                        error: _errorLedger,
                        page: _ldgPage,
                        lastPage: _ldgLastPage,
                        total: _ldgTotal,
                        onRetry: () => _loadLedger(page: _ldgPage),
                        onPrev: () => _loadLedger(page: _ldgPage - 1),
                        onNext: () => _loadLedger(page: _ldgPage + 1),
                        onRefresh: () async => _loadLedger(page: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/* ============================ Tabs ============================ */

class _SalesTab extends StatelessWidget {
  const _SalesTab({
    required this.items,
    required this.isLoading,
    required this.error,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onRetry,
    required this.onPrev,
    required this.onNext,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final String? error;
  final int page, lastPage, total;
  final VoidCallback onRetry, onPrev, onNext;
  final Future<void> Function() onRefresh;

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _ErrorView(message: error!, onRetry: onRetry);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        children: [
          _SectionCard(
            child: items.isEmpty
                ? const _EmptyMini(text: "No sales to show")
                : Column(
                    children: [
                      for (final s in items) ...[
                        ListTile(
                          dense: true,
                          minVerticalPadding: 6,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 0,
                          ),
                          leading: const Icon(Icons.receipt_long, size: 18),
                          title: Text(
                            s['invoice_no']?.toString() ?? 'Invoice',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            "Date: ${s['invoice_date']}  •  Due: ${s['due_date'] ?? '—'}  •  Open: ${_m(s['open_amount'] as num?)}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color?.withOpacity(0.75),
                            ),
                          ),
                          trailing: Text(
                            _m(s['total'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SaleDetailScreen(saleId: s['id'] as int),
                              ),
                            );
                          },
                        ),
                        if (s != items.last)
                          Divider(
                            height: 10,
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.5),
                          ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _Pager(
            page: page,
            lastPage: lastPage,
            total: total,
            onPrev: onPrev,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({
    required this.items,
    required this.opening,
    required this.openingForPage,
    required this.isLoading,
    required this.error,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onRetry,
    required this.onPrev,
    required this.onNext,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> items;
  final double opening;
  final double openingForPage;
  final bool isLoading;
  final String? error;
  final int page, lastPage, total;
  final VoidCallback onRetry, onPrev, onNext;
  final Future<void> Function() onRefresh;

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _ErrorView(message: error!, onRetry: onRetry);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        children: [
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LedgerHeaderRow(
                  label: "Opening (before range)",
                  value: _m(opening),
                ),
                const SizedBox(height: 6),
                _LedgerHeaderRow(
                  label: "Balance at page start",
                  value: _m(openingForPage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SectionCard(
            child: items.isEmpty
                ? const _EmptyMini(text: "No ledger entries to show")
                : Column(
                    children: [
                      for (final r in items) ...[
                        _LedgerRow(item: r),
                        if (r != items.last)
                          Divider(
                            height: 10,
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.5),
                          ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _Pager(
            page: page,
            lastPage: lastPage,
            total: total,
            onPrev: onPrev,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

class _LedgerHeaderRow extends StatelessWidget {
  const _LedgerHeaderRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(
      context,
    ).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: subtle, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final Map<String, dynamic> item;

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(
      context,
    ).textTheme.bodySmall?.color?.withOpacity(0.75);

    final date = (item['date'] ?? '') as String;
    final memo = (item['memo'] ?? '') as String;
    final account = (item['account_name'] ?? '') as String;
    final debit = (item['debit'] as num?) ?? 0;
    final credit = (item['credit'] as num?) ?? 0;
    final balance = (item['balance'] as num?) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          // Left: icon + meta
          SizedBox(
            width: 36,
            child: Icon(
              debit > 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
          // Middle: description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memo.isEmpty ? '(No memo)' : memo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  "${date.isEmpty ? '—' : date}"
                  "${account.isNotEmpty ? " • $account" : ""}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right: amounts (aligned)
          SizedBox(
            width: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _MoneyCol(label: "Dr", value: _m(debit)),
                const SizedBox(width: 12),
                _MoneyCol(label: "Cr", value: _m(credit)),
                const SizedBox(width: 12),
                _MoneyCol(label: "Bal", value: _m(balance), bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyCol extends StatelessWidget {
  const _MoneyCol({
    required this.label,
    required this.value,
    this.bold = false,
  });
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(
      context,
    ).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: subtle, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/* ============================ Shared widgets ============================ */

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.35),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.customer, required this.onEdit});
  final Map<String, dynamic> customer;
  final VoidCallback onEdit;

  String _initials(String? f, String? l) {
    final a = (f ?? '').trim();
    final b = (l ?? '').trim();
    final s = ((a.isNotEmpty ? a[0] : '') + (b.isNotEmpty ? b[0] : ''))
        .toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.color?.withOpacity(0.75);
    final first = (customer['first_name'] ?? '') as String;
    final last = (customer['last_name'] ?? '') as String;
    final email = customer['email'] ?? '—';
    final phone = customer['phone'] ?? '—';
    final status = (customer['status'] ?? 'active').toString();
    final address = (customer['address'] ?? '') as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 6),
        Tooltip(
          message: "Record receipt",
          child: InkWell(
            onTap:
                onEdit
                    is VoidCallback // keep original param signature
                ? null
                : null, // placeholder (ignore) – we'll wire from parent container
            borderRadius: BorderRadius.circular(8),
            child: const SizedBox.shrink(),
          ),
        ),
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            _initials(first, last),
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "$first $last".trim().isEmpty
                          ? "(No name)"
                          : "$first $last".trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StatusDot(status: status),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: "Edit customer",
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.edit_rounded, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                "Phone: $phone  •  Email: $email",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtle, fontSize: 12),
              ),
              if (address.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtle, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.customer});
  final Map<String, dynamic> customer;

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = (customer['balance'] as num?) ?? 0;
    Color balColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    if (balance > 0) {
      balColor = Colors.orange.shade800;
    } else if (balance < 0) {
      balColor = Colors.green.shade800;
    } else {
      balColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    }

    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: "Balance",
            value: _m(balance),
            color: balColor,
            bold: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: "Debit",
            value: _m(customer['total_sales'] as num?),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: "Credit",
            value: _m(customer['total_receipts'] as num?),
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.color?.withOpacity(0.75);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: subtle, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? theme.textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int lastPage;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(
      context,
    ).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Total: $total", style: TextStyle(color: subtle)),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: page > 1 ? onPrev : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text("Prev"),
            ),
            const SizedBox(width: 8),
            Text("Page $page / $lastPage", style: TextStyle(color: subtle)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: page < lastPage ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text("Next"),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: sub),
            const SizedBox(height: 8),
            const Text("Oops", style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: sub),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    if (s == 'active') {
      c = Colors.green;
    } else if (s == 'inactive' || s == 'blocked') {
      c = Colors.red;
    } else {
      c = Colors.grey;
    }
    return Icon(Icons.circle, size: 8, color: c);
  }
}

class _EmptyMini extends StatelessWidget {
  const _EmptyMini({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Center(
        child: Text(text, style: TextStyle(color: sub)),
      ),
    );
  }
}
