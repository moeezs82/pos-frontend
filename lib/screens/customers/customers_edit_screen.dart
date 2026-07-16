import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/forms/customer_form_screen.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/payment_method_dropdown.dart';
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

  bool _postingReceipt = false;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String methodPay = 'cash';

  bool _loadingHeader = true;
  String? _errorHeader;
  Map<String, dynamic>? customer;

  final int _pageSize = 10;
  bool _loadingSales = false;
  bool _loadedSalesOnce = false;
  String? _errorSales;
  int _salesPage = 1, _salesLastPage = 1, _salesTotal = 0;
  final List<Map<String, dynamic>> _sales = [];

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
      _loadSales(page: 1);
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
      if (_tab.index == 0 && !_loadedSalesOnce) _loadSales(page: 1);
      if (_tab.index == 1 && !_loadedLedgerOnce) _loadLedger(page: 1);
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
      final res = await _service.getCustomerDetail(
        id: widget.customerId,
        branchId: branchId,
      );
      if (!mounted) return;
      setState(() {
        customer = (res['data'] as Map).cast<String, dynamic>();
      });
    } catch (e) {
      if (mounted) setState(() => _errorHeader = 'Failed to load customer: $e');
    } finally {
      if (mounted) setState(() => _loadingHeader = false);
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
      if (!mounted) return;
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
      if (mounted) setState(() => _errorSales = 'Failed to load sales: $e');
    } finally {
      if (mounted) setState(() => _loadingSales = false);
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
      final res = await _service.getCustomerLedger(
        id: widget.customerId,
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

  Future<void> _refreshAll() async {
    if (_loadingHeader || _loadingSales || _loadingLedger) return;
    await _loadHeader();
    if (_tab.index == 0) {
      await _loadSales(page: _salesPage);
    } else {
      await _loadLedger(page: _ldgPage);
    }
    if (mounted) AppFeedback.info(context, 'Customer details refreshed');
  }

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
      if (mounted) AppFeedback.success(context, 'Customer updated');
    }
  }

  Future<void> _openReceiveModal() async {
    if (customer == null || _postingReceipt) return;
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
            final name = _customerName(customer!);
            return AlertDialog(
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              title: _PaymentDialogHeader(
                icon: Icons.payments_rounded,
                title: 'Record Receipt',
                subtitle: name.isEmpty ? 'Customer payment collection' : name,
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
                          label: 'Current customer balance',
                          value: _money(customer!['balance']),
                          color: _customerBalanceColor(_toDouble(customer!['balance'])),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _amountController,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Amount Received',
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
                            await _submitReceipt(dlgCtx);
                            if (dlgCtx.mounted) setLocal(() => saving = false);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _referenceController,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                            labelText: 'Reference / Note',
                            hintText: 'Cash receipt, bank ref, remarks...',
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
                          await _submitReceipt(dlgCtx);
                          if (dlgCtx.mounted) setLocal(() => saving = false);
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? 'Saving...' : 'Save Receipt'),
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

      if (!mounted) return;
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      await _loadHeader();
      if (_tab.index == 0 && _loadedSalesOnce) {
        await _loadSales(page: _salesPage);
      } else if (_tab.index == 1 && _loadedLedgerOnce) {
        await _loadLedger(page: _ldgPage);
      }
      if (mounted) AppFeedback.success(context, 'Receipt recorded successfully');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save receipt: $e');
    } finally {
      if (mounted) setState(() => _postingReceipt = false);
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

  String _customerName(Map<String, dynamic> c) {
    final first = (c['first_name'] ?? '').toString().trim();
    final last = (c['last_name'] ?? '').toString().trim();
    return [first, last].where((s) => s.isNotEmpty).join(' ');
  }

  String _initials(Map<String, dynamic> c) {
    final name = _customerName(c);
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _customerBalanceColor(double balance) {
    if (balance > 0) return AppTheme.warning;
    if (balance < 0) return AppTheme.success;
    return AppTheme.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingHeader || _loadingSales || _loadingLedger || _postingReceipt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Detail'),
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
                                Tab(text: 'Sales History'),
                                Tab(text: 'Ledger'),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHero(bool busy) {
    final c = customer!;
    final name = _customerName(c);
    final phone = (c['phone'] ?? '').toString();
    final email = (c['email'] ?? '').toString();
    final address = (c['address'] ?? '').toString();
    final balance = _toDouble(c['balance']);

    return _PartyHeroCard(
      title: name.isEmpty ? 'Walk-in Customer' : name,
      subtitle: address.isEmpty ? 'Customer account and receivable activity' : address,
      initials: _initials(c),
      typeLabel: 'CUSTOMER',
      typeIcon: Icons.person_rounded,
      status: (c['status'] ?? 'active').toString(),
      balanceLabel: balance > 0
          ? 'Receivable Balance'
          : balance < 0
              ? 'Advance Balance'
              : 'Clear Balance',
      balanceValue: _money(balance),
      balanceTone: _customerBalanceColor(balance),
      primaryActionLabel: 'Receive Payment',
      primaryActionIcon: Icons.payments_rounded,
      onPrimaryAction: busy ? null : _openReceiveModal,
      onEdit: busy ? null : _openEdit,
      infoPills: [
        _PartyInfoPill(icon: Icons.phone_rounded, label: 'Phone', value: phone),
        _PartyInfoPill(icon: Icons.mail_rounded, label: 'Email', value: email),
      ],
    );
  }

  Widget _buildMetrics() {
    final c = customer!;
    final balance = _toDouble(c['balance']);
    return _PartyMetricGrid(
      metrics: [
        _PartyMetric(
          label: 'Balance',
          value: _money(balance),
          icon: Icons.account_balance_wallet_rounded,
          color: _customerBalanceColor(balance),
          helper: balance > 0
              ? 'Customer owes you'
              : balance < 0
                  ? 'Customer advance/credit'
                  : 'No outstanding balance',
        ),
        _PartyMetric(
          label: 'Debit / Sales',
          value: _money(c['total_sales']),
          icon: Icons.receipt_long_rounded,
          color: AppTheme.info,
          helper: 'Total sales posted',
        ),
        _PartyMetric(
          label: 'Credit / Receipts',
          value: _money(c['total_receipts']),
          icon: Icons.payments_rounded,
          color: AppTheme.success,
          helper: 'Total payments received',
        ),
      ],
    );
  }
}

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
              icon: Icons.receipt_long_rounded,
              title: 'No sales yet',
              subtitle: 'Sales generated for this customer will appear here.',
            )
          else ...[
            for (final s in items) ...[
              _PartyDocumentRow(
                icon: Icons.receipt_long_rounded,
                accentColor: AppTheme.info,
                title: (s['invoice_no'] ?? 'Invoice').toString(),
                amount: money(s['total']),
                primaryMeta: "Date ${s['invoice_date'] ?? '—'}",
                secondaryMeta: "Due ${s['due_date'] ?? '—'}",
                openAmount: money(s['open_amount']),
                onTap: () {
                  final id = toInt(s['id']);
                  if (id <= 0) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: id)),
                  );
                },
              ),
              if (s != items.last) const SizedBox(height: 10),
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
              subtitle: 'Receipts and sales ledger entries will appear here.',
            )
          else ...[
            for (final r in items) ...[
              _CustomerLedgerCard(item: r, money: money, toDouble: toDouble),
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

class _CustomerLedgerCard extends StatelessWidget {
  const _CustomerLedgerCard({
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
      icon: debit > 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
      accentColor: debit > 0 ? AppTheme.warning : AppTheme.success,
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
