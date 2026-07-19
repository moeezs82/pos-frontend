import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/forms/vendor_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_detail.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/payment_method_dropdown.dart';
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

  bool _postingPayment = false;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String methodPay = 'cash';

  bool _loadingHeader = true;
  String? _errorHeader;
  Map<String, dynamic>? vendor;

  final int _pageSize = 10;
  bool _loadingPurchases = false;
  bool _loadedPurchasesOnce = false;
  String? _errorPurchases;
  int _purPage = 1, _purLastPage = 1, _purTotal = 0;
  final List<Map<String, dynamic>> _purchases = [];

  bool _loadingLedger = false;
  bool _loadedLedgerOnce = false;
  String? _errorLedger;
  int _ldgPage = 1, _ldgLastPage = 1, _ldgTotal = 0;
  double _opening = 0.0, _openingForPage = 0.0;
  final List<Map<String, dynamic>> _ledger = [];

  // Separate Loan Ledger (Loans Receivable only — never mixed with trade AP).
  bool _loadingLoan = false;
  bool _loadedLoanOnce = false;
  String? _errorLoan;
  int _loanPage = 1, _loanLastPage = 1, _loanTotal = 0;
  double _loanOpening = 0.0, _loanOpeningForPage = 0.0;
  final List<Map<String, dynamic>> _loanRows = [];
  Map<String, dynamic> _loanSummary = const {};

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = VendorService(token: token);
    _tab = TabController(length: 3, vsync: this);
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
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tab.indexIsChanging) {
      if (_tab.index == 0 && !_loadedPurchasesOnce) _loadPurchases(page: 1);
      if (_tab.index == 1 && !_loadedLedgerOnce) _loadLedger(page: 1);
      if (_tab.index == 2 && !_loadedLoanOnce) _loadLoanLedger(page: 1);
    }
  }

  Future<void> _loadHeader() async {
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        vendor = (res['data'] as Map).cast<String, dynamic>();
      });
    } catch (e) {
      if (mounted) setState(() => _errorHeader = 'Failed to load vendor: $e');
    } finally {
      if (mounted) setState(() => _loadingHeader = false);
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
      if (!mounted) return;
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
      if (mounted) setState(() => _errorPurchases = 'Failed to load purchases: $e');
    } finally {
      if (mounted) setState(() => _loadingPurchases = false);
    }
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
      );
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

      if (!mounted) return;
      setState(() {
        _ledger
          ..clear()
          ..addAll(items);
        _opening = _toDouble(wrap['opening']);
        _openingForPage = _toDouble(wrap['opening_for_page']);
        _ldgPage = (wrap['current_page'] as num?)?.toInt() ?? page;
        _ldgLastPage = (wrap['last_page'] as num?)?.toInt() ?? _ldgLastPage;
        _ldgTotal = (wrap['total'] as num?)?.toInt() ?? _ldgTotal;
        _loadedLedgerOnce = true;
      });
    } catch (e) {
      if (mounted) setState(() => _errorLedger = 'Failed to load ledger: $e');
    } finally {
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  Future<void> _loadLoanLedger({required int page}) async {
    if (_loadingLoan) return;
    setState(() {
      _loadingLoan = true;
      _errorLoan = null;
    });
    try {
      final res = await _service.getVendorLoanLedger(
        id: widget.vendorId,
        page: page,
        perPage: _pageSize,
      );
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _loanRows
          ..clear()
          ..addAll(items);
        _loanSummary = ((wrap['summary'] as Map?) ?? const {}).cast<String, dynamic>();
        _loanOpening = _toDouble(wrap['opening']);
        _loanOpeningForPage = _toDouble(wrap['opening_for_page']);
        _loanPage = (wrap['current_page'] as num?)?.toInt() ?? page;
        _loanLastPage = (wrap['last_page'] as num?)?.toInt() ?? _loanLastPage;
        _loanTotal = (wrap['total'] as num?)?.toInt() ?? _loanTotal;
        _loadedLoanOnce = true;
      });
    } catch (e) {
      if (mounted) setState(() => _errorLoan = 'Failed to load loan ledger: $e');
    } finally {
      if (mounted) setState(() => _loadingLoan = false);
    }
  }

  Future<void> _refreshAll() async {
    if (_loadingHeader || _loadingPurchases || _loadingLedger || _loadingLoan) return;
    await _loadHeader();
    if (_tab.index == 0) {
      await _loadPurchases(page: _purPage);
    } else if (_tab.index == 1) {
      await _loadLedger(page: _ldgPage);
    } else {
      await _loadLoanLedger(page: _loanPage);
    }
    if (mounted) AppFeedback.info(context, 'Vendor details refreshed');
  }

  Future<void> _openEdit() async {
    if (vendor == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VendorFormScreen(vendor: vendor)),
    );
    if (result == true) {
      await _loadHeader();
      if (_tab.index == 0 && _loadedPurchasesOnce) _loadPurchases(page: _purPage);
      if (_tab.index == 1 && _loadedLedgerOnce) _loadLedger(page: _ldgPage);
      if (_tab.index == 2 && _loadedLoanOnce) _loadLoanLedger(page: _loanPage);
      if (mounted) AppFeedback.success(context, 'Vendor updated');
    }
  }

  Future<void> _openPaymentModal() async {
    if (vendor == null || _postingPayment) return;
    _amountController.clear();
    _referenceController.clear();
    methodPay = 'cash';
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final name = _vendorDisplayName(vendor!);
            return AlertDialog(
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              title: _PaymentDialogHeader(
                icon: Icons.payments_rounded,
                title: 'Record Vendor Payment',
                subtitle: name.isEmpty ? 'Supplier payment entry' : name,
                onClose: saving ? null : () => Navigator.pop(dlgCtx),
              ),
              content: Form(
                key: formKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DialogBalanceStrip(
                          label: 'Current payable balance',
                          value: _money(vendor!['balance']),
                          color: _vendorBalanceColor(_toDouble(vendor!['balance'])),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _amountController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Amount Paid',
                            hintText: '0.00',
                            prefixIcon: Icon(Icons.currency_exchange_rounded),
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'Amount is required';
                            final parsed = double.tryParse(t);
                            if (parsed == null) return 'Enter a valid amount';
                            if (parsed <= 0) return 'Amount must be greater than zero';
                            return null;
                          },
                          onFieldSubmitted: (_) async {
                            if (saving) return;
                            if (!(formKey.currentState?.validate() ?? false)) return;
                            setLocal(() => saving = true);
                            await _submitPayment(dlgCtx);
                            if (dlgCtx.mounted) setLocal(() => saving = false);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _referenceController,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                            labelText: 'Reference / Note',
                            hintText: 'Cash payment, bank ref, remarks...',
                            prefixIcon: Icon(Icons.notes_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        PaymentMethodDropdown(
                          value: methodPay,
                          enabled: !saving,
                          labelText: 'Payment Method',
                          decoration: const InputDecoration(
                            labelText: 'Payment Method',
                            prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) =>
                              setState(() => methodPay = val ?? 'cash'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: saving ? null : () => Navigator.pop(dlgCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          setLocal(() => saving = true);
                          await _submitPayment(dlgCtx);
                          if (dlgCtx.mounted) setLocal(() => saving = false);
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? 'Saving...' : 'Save Payment'),
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

      if (!mounted) return;
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      await _loadHeader();
      if (_tab.index == 0 && _loadedPurchasesOnce) {
        await _loadPurchases(page: _purPage);
      } else if (_tab.index == 1 && _loadedLedgerOnce) {
        await _loadLedger(page: _ldgPage);
      }
      if (mounted) AppFeedback.success(context, 'Payment recorded successfully');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save payment: $e');
    } finally {
      if (mounted) setState(() => _postingPayment = false);
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0.0;
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _money(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _vendorDisplayName(Map<String, dynamic> v) {
    final company = (v['company'] ?? '').toString().trim();
    final first = (v['first_name'] ?? '').toString().trim();
    final last = (v['last_name'] ?? '').toString().trim();
    final contact = [first, last].where((s) => s.isNotEmpty).join(' ');
    return [company, contact].where((s) => s.trim().isNotEmpty).join(' • ');
  }

  String _initials(Map<String, dynamic> v) {
    final company = (v['company'] ?? '').toString().trim();
    final display = company.isNotEmpty ? company : _vendorDisplayName(v);
    if (display.isEmpty) return '?';
    final clean = display.replaceAll('•', ' ').trim();
    final parts = clean.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) {
      final source = parts.first;
      return source.length >= 2 ? source.substring(0, 2).toUpperCase() : source[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _vendorBalanceColor(double balance) {
    if (balance > 0) return AppTheme.warning;
    if (balance < 0) return AppTheme.success;
    return AppTheme.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingHeader || _loadingPurchases || _loadingLedger || _postingPayment;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Detail'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: BranchIndicator(tappable: false),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: busy ? null : _refreshAll,
          ),
        ],
      ),
      body: _loadingHeader
          ? const Center(child: CircularProgressIndicator())
          : _errorHeader != null
              ? _PartyErrorView(message: _errorHeader!, onRetry: _loadHeader)
              : SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHero(busy),
                            const SizedBox(height: 12),
                            _buildMetrics(),
                            const SizedBox(height: 12),
                            _PartySegmentedTabBar(
                              controller: _tab,
                              tabs: const [
                                Tab(text: 'Purchases'),
                                Tab(text: 'Trade Ledger'),
                                Tab(text: 'Loan Ledger'),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                              money: _money,
                              toInt: _toInt,
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
                              money: _money,
                              toDouble: _toDouble,
                            ),
                            _LoanLedgerTab(
                              items: _loanRows,
                              summary: _loanSummary,
                              opening: _loanOpening,
                              openingForPage: _loanOpeningForPage,
                              isLoading: _loadingLoan,
                              error: _errorLoan,
                              page: _loanPage,
                              lastPage: _loanLastPage,
                              total: _loanTotal,
                              onRetry: () => _loadLoanLedger(page: _loanPage),
                              onPrev: () => _loadLoanLedger(page: _loanPage - 1),
                              onNext: () => _loadLoanLedger(page: _loanPage + 1),
                              onRefresh: () async => _loadLoanLedger(page: 1),
                              money: _money,
                              toDouble: _toDouble,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHero(bool busy) {
    final v = vendor!;
    final displayName = _vendorDisplayName(v);
    final phone = (v['phone'] ?? '').toString();
    final email = (v['email'] ?? '').toString();
    final address = (v['address'] ?? '').toString();
    final balance = _toDouble(v['balance']);

    return _PartyHeroCard(
      title: displayName.isEmpty ? 'Vendor Account' : displayName,
      subtitle: address.isEmpty ? 'Supplier account, payable balance and purchase activity' : address,
      initials: _initials(v),
      typeLabel: 'VENDOR',
      typeIcon: Icons.storefront_rounded,
      status: (v['status'] ?? 'active').toString(),
      balanceLabel: balance > 0
          ? 'Payable Balance'
          : balance < 0
              ? 'Advance / Credit'
              : 'Clear Balance',
      balanceValue: _money(balance),
      balanceTone: _vendorBalanceColor(balance),
      primaryActionLabel: 'Pay Vendor',
      primaryActionIcon: Icons.payments_rounded,
      onPrimaryAction: busy ? null : _openPaymentModal,
      onEdit: busy ? null : _openEdit,
      infoPills: [
        _PartyInfoPill(icon: Icons.phone_rounded, label: 'Phone', value: phone),
        _PartyInfoPill(icon: Icons.mail_rounded, label: 'Email', value: email),
      ],
    );
  }

  Widget _buildMetrics() {
    final v = vendor!;
    final balance = _toDouble(v['balance']);
    return _PartyMetricGrid(
      metrics: [
        _PartyMetric(
          label: 'A/P Balance',
          value: _money(balance),
          icon: Icons.account_balance_wallet_rounded,
          color: _vendorBalanceColor(balance),
          helper: balance > 0
              ? 'You owe this vendor'
              : balance < 0
                  ? 'Vendor credit/advance'
                  : 'No payable balance',
        ),
        _PartyMetric(
          label: 'Purchases',
          value: _money(v['total_purchases']),
          icon: Icons.shopping_bag_rounded,
          color: AppTheme.info,
          helper: 'Total purchase value',
        ),
        _PartyMetric(
          label: 'Payments',
          value: _money(v['total_payments']),
          icon: Icons.payments_rounded,
          color: AppTheme.success,
          helper: 'Total payments made',
        ),
      ],
    );
  }
}

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
    required this.money,
    required this.toInt,
  });

  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final String? error;
  final int page, lastPage, total;
  final VoidCallback onRetry, onPrev, onNext;
  final Future<void> Function() onRefresh;
  final String Function(dynamic value) money;
  final int Function(dynamic value) toInt;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _PartyErrorView(message: error!, onRetry: onRetry);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
        children: [
          if (isLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          if (items.isEmpty)
            const _PartyEmptyState(
              icon: Icons.shopping_bag_rounded,
              title: 'No purchases yet',
              subtitle: 'Purchase invoices for this vendor will appear here.',
            )
          else ...[
            for (final p in items) ...[
              _PartyDocumentRow(
                icon: Icons.shopping_bag_rounded,
                accentColor: AppTheme.purple,
                title: (p['invoice_no'] ?? 'Purchase').toString(),
                amount: money(p['total']),
                primaryMeta: "Date ${p['invoice_date'] ?? '—'}",
                secondaryMeta: '',
                openAmount: money(p['open_amount']),
                onTap: () {
                  final id = toInt(p['id']);
                  if (id <= 0) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchaseId: id)),
                  );
                },
              ),
              if (p != items.last) const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 12),
          _PartyPager(
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
    required this.money,
    required this.toDouble,
  });

  final List<Map<String, dynamic>> items;
  final double opening;
  final double openingForPage;
  final bool isLoading;
  final String? error;
  final int page, lastPage, total;
  final VoidCallback onRetry, onPrev, onNext;
  final Future<void> Function() onRefresh;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _PartyErrorView(message: error!, onRetry: onRetry);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
        children: [
          if (isLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          _PartyLedgerSummary(opening: money(opening), pageStart: money(openingForPage)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _PartyEmptyState(
              icon: Icons.account_balance_rounded,
              title: 'No ledger movement',
              subtitle: 'Payments and purchase ledger entries will appear here.',
            )
          else ...[
            for (final r in items) ...[
              _VendorLedgerCard(item: r, money: money, toDouble: toDouble),
              if (r != items.last) const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 12),
          _PartyPager(
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

class _VendorLedgerCard extends StatelessWidget {
  const _VendorLedgerCard({
    required this.item,
    required this.money,
    required this.toDouble,
  });

  final Map<String, dynamic> item;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;

  @override
  Widget build(BuildContext context) {
    final debit = toDouble(item['debit']);
    final credit = toDouble(item['credit']);
    return _PartyLedgerRow(
      date: (item['date'] ?? '').toString(),
      memo: (item['memo'] ?? '').toString(),
      account: (item['account_name'] ?? '').toString(),
      debit: money(debit),
      credit: money(credit),
      balance: money(item['balance']),
      icon: credit > 0 ? Icons.north_east_rounded : Icons.south_west_rounded,
      accentColor: credit > 0 ? AppTheme.warning : AppTheme.success,
    );
  }
}

class _PaymentDialogHeader extends StatelessWidget {
  const _PaymentDialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
      decoration: const BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _DialogBalanceStrip extends StatelessWidget {
  const _DialogBalanceStrip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_rounded, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/* ============================ Local party detail UI widgets ============================ */

class _LoanLedgerTab extends StatelessWidget {
  const _LoanLedgerTab({
    required this.items,
    required this.summary,
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
    required this.money,
    required this.toDouble,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;
  final double opening;
  final double openingForPage;
  final bool isLoading;
  final String? error;
  final int page, lastPage, total;
  final VoidCallback onRetry, onPrev, onNext;
  final Future<void> Function() onRefresh;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _PartyErrorView(message: error!, onRetry: onRetry);
    }

    final given = toDouble(summary['loan_given']);
    final recovered = toDouble(summary['loan_recovered']);
    final balance = toDouble(summary['loan_balance']);
    final needsReview = balance < 0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
        children: [
          if (isLoading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.info.withOpacity(.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.info.withOpacity(.18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.info),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Loans (Loans Receivable) are tracked separately and never affect the vendor payable balance.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PartyMetricGrid(
            metrics: [
              _PartyMetric(
                label: 'Loan Given',
                value: money(given),
                icon: Icons.call_made_rounded,
                color: AppTheme.warning,
                helper: 'Advanced to borrower',
              ),
              _PartyMetric(
                label: 'Loan Recovered',
                value: money(recovered),
                icon: Icons.call_received_rounded,
                color: AppTheme.success,
                helper: 'Received back',
              ),
              _PartyMetric(
                label: needsReview ? 'Net Loan · Review' : 'Net Loan Balance',
                value: money(balance),
                icon: Icons.account_balance_rounded,
                color: needsReview ? AppTheme.danger : AppTheme.navy,
                helper: needsReview
                    ? 'Credit / over-recovered — review required'
                    : (balance > 0 ? 'Borrower still owes' : 'Settled'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _PartyEmptyState(
              icon: Icons.account_balance_wallet_rounded,
              title: 'No loan activity',
              subtitle: 'Loan given and loan recovered entries for this borrower will appear here.',
            )
          else ...[
            for (final r in items) ...[
              _LoanLedgerCard(item: r, money: money, toDouble: toDouble),
              if (r != items.last) const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 12),
          _PartyPager(
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

class _LoanLedgerCard extends StatelessWidget {
  const _LoanLedgerCard({
    required this.item,
    required this.money,
    required this.toDouble,
  });

  final Map<String, dynamic> item;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;

  @override
  Widget build(BuildContext context) {
    final given = toDouble(item['given']);
    final recovered = toDouble(item['recovered']);
    final isGiven = given > 0;
    final method = (item['method'] ?? '').toString();
    final reference = (item['reference'] ?? '').toString();
    final date = (item['date'] ?? '').toString();
    final status = (item['status'] ?? 'posted').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final left = Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: (isGiven ? AppTheme.warning : AppTheme.success).withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isGiven ? Icons.call_made_rounded : Icons.call_received_rounded,
                  color: isGiven ? AppTheme.warning : AppTheme.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reference.trim().isEmpty ? (isGiven ? 'Loan Given' : 'Loan Recovered') : reference.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _MetaChip(icon: Icons.calendar_today_rounded, label: date.trim().isEmpty ? '—' : date),
                        if (method.trim().isNotEmpty)
                          _MetaChip(icon: Icons.account_balance_wallet_rounded, label: method),
                        if (status != 'posted')
                          _MetaChip(icon: Icons.info_outline_rounded, label: status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final amountRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _AmountBadge(label: 'Given', value: money(given), color: AppTheme.warning),
              _AmountBadge(label: 'Recovered', value: money(recovered), color: AppTheme.success),
              _AmountBadge(label: 'Bal', value: money(item['balance']), color: AppTheme.navy, prominent: true),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 12), amountRow],
            );
          }
          return Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              SizedBox(width: 320, child: amountRow),
            ],
          );
        },
      ),
    );
  }
}

class _PartyInfoPill extends StatelessWidget {
  const _PartyInfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim().isEmpty ? '—' : value.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withOpacity(.90)),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(.70),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              cleanValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyHeroCard extends StatelessWidget {
  const _PartyHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initials,
    required this.typeLabel,
    required this.typeIcon,
    required this.status,
    required this.balanceLabel,
    required this.balanceValue,
    required this.balanceTone,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
    required this.onEdit,
    this.infoPills = const [],
  });

  final String title;
  final String subtitle;
  final String initials;
  final String typeLabel;
  final IconData typeIcon;
  final String status;
  final String balanceLabel;
  final String balanceValue;
  final Color balanceTone;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onEdit;
  final List<_PartyInfoPill> infoPills;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.enterpriseGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withOpacity(.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -48,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(.08),
              ),
            ),
          ),
          Positioned(
            right: 56,
            bottom: -64,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.08), width: 22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final content = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 54 : 64,
                      height: compact ? 54 : 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(.22)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 18 : 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _HeroBadge(
                                icon: typeIcon,
                                label: typeLabel,
                                background: Colors.white.withOpacity(.14),
                                foreground: Colors.white,
                              ),
                              _HeroStatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title.trim().isEmpty ? '(No name)' : title.trim(),
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 21 : 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.35,
                              height: 1.05,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.78),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                          if (infoPills.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(spacing: 8, runSpacing: 8, children: infoPills),
                          ],
                        ],
                      ),
                    ),
                  ],
                );

                final actions = _HeroActions(
                  balanceLabel: balanceLabel,
                  balanceValue: balanceValue,
                  balanceTone: balanceTone,
                  primaryActionLabel: primaryActionLabel,
                  primaryActionIcon: primaryActionIcon,
                  onPrimaryAction: onPrimaryAction,
                  onEdit: onEdit,
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      const SizedBox(height: 16),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 18),
                    SizedBox(width: 238, child: actions),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.balanceLabel,
    required this.balanceValue,
    required this.balanceTone,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.onPrimaryAction,
    required this.onEdit,
  });

  final String balanceLabel;
  final String balanceValue;
  final Color balanceTone;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                balanceLabel,
                style: TextStyle(
                  color: Colors.white.withOpacity(.70),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      balanceValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: balanceTone, shape: BoxShape.circle),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryDark,
            disabledBackgroundColor: Colors.white.withOpacity(.55),
            disabledForegroundColor: AppTheme.textMuted,
          ),
          onPressed: onPrimaryAction,
          icon: Icon(primaryActionIcon),
          label: Text(primaryActionLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(.34)),
            backgroundColor: Colors.white.withOpacity(.06),
          ),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit Profile'),
        ),
      ],
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .25,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatusBadge extends StatelessWidget {
  const _HeroStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().isEmpty ? 'active' : status.trim();
    final color = AppTheme.statusColor(normalized);
    return _HeroBadge(
      icon: Icons.circle,
      label: normalized.toUpperCase(),
      background: color.withOpacity(.18),
      foreground: Colors.white,
    );
  }
}

class _PartyMetric {
  const _PartyMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.helper,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? helper;
}

class _PartyMetricGrid extends StatelessWidget {
  const _PartyMetricGrid({super.key, required this.metrics});
  final List<_PartyMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 820
            ? (width - 24) / 3
            : width >= 560
                ? (width - 12) / 2
                : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map((metric) => SizedBox(
                    width: itemWidth,
                    child: _PartyMetricCard(metric: metric),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _PartyMetricCard extends StatelessWidget {
  const _PartyMetricCard({super.key, required this.metric});
  final _PartyMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: metric.color.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(metric.icon, color: metric.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: metric.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.2,
                  ),
                ),
                if (metric.helper != null && metric.helper!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metric.helper!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartySegmentedTabBar extends StatelessWidget {
  const _PartySegmentedTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<Tab> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        indicator: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withOpacity(.25)),
        ),
        labelColor: AppTheme.primaryDark,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        tabs: tabs,
      ),
    );
  }
}

class _PartySectionCard extends StatelessWidget {
  const _PartySectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
  }
}

class _PartyDocumentRow extends StatelessWidget {
  const _PartyDocumentRow({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.amount,
    required this.primaryMeta,
    required this.secondaryMeta,
    required this.openAmount,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String amount;
  final String primaryMeta;
  final String secondaryMeta;
  final String openAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final leading = Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              );
              final detail = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.trim().isEmpty ? 'Document' : title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _MetaChip(icon: Icons.calendar_today_rounded, label: primaryMeta),
                        if (secondaryMeta.trim().isNotEmpty)
                          _MetaChip(icon: Icons.event_available_rounded, label: secondaryMeta),
                        _MetaChip(icon: Icons.account_balance_wallet_rounded, label: 'Open $openAmount'),
                      ],
                    ),
                  ],
                ),
              );
              final total = Column(
                crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [leading, const SizedBox(width: 12), detail]),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        total,
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  detail,
                  const SizedBox(width: 16),
                  SizedBox(width: 120, child: total),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label.trim().isEmpty ? '—' : label.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyLedgerSummary extends StatelessWidget {
  const _PartyLedgerSummary({
    super.key,
    required this.opening,
    required this.pageStart,
  });

  final String opening;
  final String pageStart;

  @override
  Widget build(BuildContext context) {
    return _PartyMetricGrid(
      metrics: [
        _PartyMetric(
          label: 'Opening Balance',
          value: opening,
          icon: Icons.account_balance_rounded,
          color: AppTheme.info,
          helper: 'Before selected range',
        ),
        _PartyMetric(
          label: 'Page Start Balance',
          value: pageStart,
          icon: Icons.timeline_rounded,
          color: AppTheme.purple,
          helper: 'Before first row on this page',
        ),
      ],
    );
  }
}

class _PartyLedgerRow extends StatelessWidget {
  const _PartyLedgerRow({
    super.key,
    required this.date,
    required this.memo,
    required this.account,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.icon,
    required this.accentColor,
  });

  final String date;
  final String memo;
  final String account;
  final String debit;
  final String credit;
  final String balance;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final left = Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memo.trim().isEmpty ? '(No memo)' : memo.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        _MetaChip(icon: Icons.calendar_today_rounded, label: date.trim().isEmpty ? '—' : date),
                        if (account.trim().isNotEmpty)
                          _MetaChip(icon: Icons.account_tree_rounded, label: account),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final amountRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _AmountBadge(label: 'Dr', value: debit, color: AppTheme.danger),
              _AmountBadge(label: 'Cr', value: credit, color: AppTheme.success),
              _AmountBadge(label: 'Bal', value: balance, color: AppTheme.navy, prominent: true),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 12), amountRow],
            );
          }
          return Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              SizedBox(width: 300, child: amountRow),
            ],
          );
        },
      ),
    );
  }
}

class _AmountBadge extends StatelessWidget {
  const _AmountBadge({
    required this.label,
    required this.value,
    required this.color,
    this.prominent = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(prominent ? .08 : .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(prominent ? .18 : .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(.72),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: prominent ? 13.5 : 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyPager extends StatelessWidget {
  const _PartyPager({
    super.key,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            'Total $total  •  Page $page of $lastPage',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: page > 1 ? onPrev : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: page < lastPage ? onNext : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartyEmptyState extends StatelessWidget {
  const _PartyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _PartySectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: AppTheme.textMuted, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.navy,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartyErrorView extends StatelessWidget {
  const _PartyErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _PartySectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.error_outline_rounded, size: 30, color: AppTheme.danger),
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load details',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
