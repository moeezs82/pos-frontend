import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_detail.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VendorEditScreen extends StatefulWidget {
  final int vendorId;
  const VendorEditScreen({super.key, required this.vendorId});

  @override
  State<VendorEditScreen> createState() => _VendorEditScreenState();
}

class _VendorEditScreenState extends State<VendorEditScreen>
    with SingleTickerProviderStateMixin {
  late VendorService _service;
  late TabController _tab;

  bool _postingPayment = false; // NEW
  final _amountController = TextEditingController(); // NEW
  final _referenceController = TextEditingController(); // NEW
  String methodPay = "cash";

  bool _loadingHeader = true;
  String? _errorHeader;

  Map<String, dynamic>?
  vendor; // includes total_purchases/total_payments/balance

  // Purchases state
  final int _pageSize = 10;
  bool _loadingPurchases = false;
  bool _loadedPurchasesOnce = false;
  String? _errorPurchases;
  int _purPage = 1, _purLastPage = 1, _purTotal = 0;
  final List<Map<String, dynamic>> _purchases = [];

  // Ledger state
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
    _service = VendorService(token: token);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHeader();
      _loadPurchases(page: 1);
    });
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tab.indexIsChanging) {
      if (_tab.index == 0 && !_loadedPurchasesOnce) _loadPurchases(page: 1);
      if (_tab.index == 1 && !_loadedLedgerOnce) _loadLedger(page: 1);
    }
  }

  Future<void> _openReceiveModal() async {
    if (vendor == null || _postingPayment) return;
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
                    "Record Payment",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close),
                    onPressed: _postingPayment
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
                            if (_postingPayment) return;
                            if (!(formKey.currentState?.validate() ?? false))
                              return;
                            await _submitPayment(dlgCtx);
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
                  onPressed: _postingPayment
                      ? null
                      : () => Navigator.pop(dlgCtx),
                  child: const Text("Cancel"),
                ),
                FilledButton.icon(
                  onPressed: _postingPayment
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false))
                            return;
                          await _submitPayment(dlgCtx);
                          setLocal(() {}); // keep dialog reactive if needed
                        },
                  icon: _postingPayment
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

  Future<void> _submitPayment(BuildContext sheetCtx) async {
    setState(() => _postingPayment = true);
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final amount = double.parse(_amountController.text.trim());
      final reference = _referenceController.text.trim();
      final method = methodPay;

      await _service.createPayment(
        vendorId: widget.vendorId,
        amount: amount,
        branchId: branchId,
        method: method,
        reference: reference,
      );

      if (mounted) {
        Navigator.pop(sheetCtx); // close modal
        // Refresh header + whichever tab is visible
        await _loadHeader();
        if (_tab.index == 0 && _loadedPurchasesOnce) {
          await _loadPurchases(page: _purPage);
        } else if (_tab.index == 1 && _loadedLedgerOnce) {
          await _loadLedger(page: _ldgPage);
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Payment recorded")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to save payment: $e")));
      }
    } finally {
      if (mounted) setState(() => _postingPayment = false);
    }
  }

  Future<void> _loadHeader() async {
    setState(() {
      _loadingHeader = true;
      _errorHeader = null;
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getVendorDetail(
        id: widget.vendorId,
        branchId: branchId,
      );
      setState(() {
        vendor = (res['data'] as Map).cast<String, dynamic>();
      });
    } catch (e) {
      setState(() => _errorHeader = "Failed to load vendor: $e");
    } finally {
      setState(() => _loadingHeader = false);
    }
  }

  Future<void> _loadPurchases({required int page}) async {
    if (_loadingPurchases) return;
    setState(() {
      _loadingPurchases = true;
      _errorPurchases = null;
    });
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = await _service.getVendorPurchases(
        id: widget.vendorId,
        page: page,
        perPage: _pageSize,
        branchId: branchId,
      );
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      setState(() {
        _purchases
          ..clear()
          ..addAll(items);
        _purPage = (wrap['current_page'] as num?)?.toInt() ?? page;
        _purLastPage = (wrap['last_page'] as num?)?.toInt() ?? _purLastPage;
        _purTotal = (wrap['total'] as num?)?.toInt() ?? _purTotal;
        _loadedPurchasesOnce = true;
      });
    } catch (e) {
      setState(() => _errorPurchases = "Failed to load purchases: $e");
    } finally {
      setState(() => _loadingPurchases = false);
    }
  }

  // ADD THIS inside _VendorEditScreenState
  Future<void> _refreshAll() async {
    // Avoid overlapping requests
    if (_loadingHeader || _loadingPurchases || _loadingLedger) return;

    await _loadHeader();

    if (_tab.index == 0) {
      await _loadPurchases(page: _purPage); // keep current page
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
      final res = await _service.getVendorLedger(
        id: widget.vendorId,
        page: page,
        perPage: _pageSize,
        branchId: branchId,
        // from: 'YYYY-MM-DD', to: 'YYYY-MM-DD',
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
    if (vendor == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorFormScreen(vendor: vendor)),
    );
    if (result == true) {
      await _loadHeader();
      if (_tab.index == 0 && _loadedPurchasesOnce)
        _loadPurchases(page: _purPage);
      if (_tab.index == 1 && _loadedLedgerOnce) _loadLedger(page: _ldgPage);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Vendor updated")));
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
            Tab(text: "Purchases"),
            Tab(text: "Ledger (A/P)"),
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
        title: const Text("Vendor"),
        actions: [
          IconButton(
            tooltip: 'Pay',
            icon: const Icon(Icons.payments_rounded),
            onPressed:
                (_loadingHeader ||
                    _loadingPurchases ||
                    _loadingLedger ||
                    _postingPayment)
                ? null
                : _openReceiveModal, // NEW
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loadingHeader || _loadingPurchases || _loadingLedger)
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VendorHeaderBlock(vendor: vendor!, onEdit: _openEdit),
                        const SizedBox(height: 8),
                        _VendorTotalsRow(vendor: vendor!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: (_loadingHeader || _postingPayment)
                          ? null
                          : _openReceiveModal,
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text("Pay"),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                _segmentedTabBar(context),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _PurchasesTab(
                        items: _purchases,
                        isLoading: _loadingPurchases,
                        error: _errorPurchases,
                        page: _purPage,
                        lastPage: _purLastPage,
                        total: _purTotal,
                        onRetry: () => _loadPurchases(page: _purPage),
                        onPrev: () => _loadPurchases(page: _purPage - 1),
                        onNext: () => _loadPurchases(page: _purPage + 1),
                        onRefresh: () async => _loadPurchases(page: 1),
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

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab({
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
                ? const _EmptyMini(text: "No purchases to show")
                : Column(
                    children: [
                      for (final p in items) ...[
                        ListTile(
                          dense: true,
                          minVerticalPadding: 6,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 0,
                          ),
                          leading: const Icon(
                            Icons.shopping_bag_rounded,
                            size: 18,
                          ),
                          title: Text(
                            p['invoice_no']?.toString() ?? 'Purchase',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            "Date: ${p['invoice_date']}  •  Open: ${_m(p['open_amount'] as num?)}",
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
                            _m(p['total'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PurchaseDetailScreen(
                                  purchaseId: p['id'] as int,
                                ),
                              ),
                            );
                          },
                        ),
                        if (p != items.last)
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
          SizedBox(
            width: 36,
            child: Icon(
              credit > 0 ? Icons.north_east_rounded : Icons.south_west_rounded,
              size: 18,
            ),
          ),
          const SizedBox(width: 4),
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

/* ============================ Shared widgets ============================ */

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

class _VendorHeaderBlock extends StatelessWidget {
  const _VendorHeaderBlock({required this.vendor, required this.onEdit});
  final Map<String, dynamic> vendor;
  final VoidCallback onEdit;

  String _initials(String? f, String? l, [String? company]) {
    final a = (f ?? '').trim();
    final b = (l ?? '').trim();
    final c = (company ?? '').trim();
    final src = (c.isNotEmpty ? c : (a + b)).trim();
    final s = src.isNotEmpty
        ? (src.length >= 2 ? (src[0] + src[1]) : src[0])
        : '?';
    return s.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.color?.withOpacity(0.75);

    final company = (vendor['company'] ?? '') as String;
    final first = (vendor['first_name'] ?? '') as String;
    final last = (vendor['last_name'] ?? '') as String;
    final email = vendor['email'] ?? '—';
    final phone = vendor['phone'] ?? '—';
    final status = (vendor['status'] ?? 'active').toString();
    final address = (vendor['address'] ?? '') as String;

    final displayName = [
      company.trim().isEmpty ? null : company.trim(),
      "$first $last".trim().isEmpty ? null : "$first $last".trim(),
    ].whereType<String>().join(' • ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            _initials(first, last, company),
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
                      displayName.isEmpty ? "(No vendor name)" : displayName,
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
                    message: "Edit vendor",
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

class _VendorTotalsRow extends StatelessWidget {
  const _VendorTotalsRow({required this.vendor});
  final Map<String, dynamic> vendor;

  String _m(num? v) => (v ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = (vendor['balance'] as num?) ?? 0; // +ve => payable
    Color balColor = theme.textTheme.bodyLarge?.color ?? Colors.black;
    if (balance > 0) {
      balColor = Colors.orange.shade800; // you owe vendor
    } else if (balance < 0) {
      balColor = Colors.green.shade800; // advance/credit from vendor
    } else {
      balColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
    }

    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: "A/P Balance",
            value: _m(balance),
            color: balColor,
            bold: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: "Purchases",
            value: _m(vendor['total_purchases'] as num?),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStat(
            label: "Payments",
            value: _m(vendor['total_payments'] as num?),
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
