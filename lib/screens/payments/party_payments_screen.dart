import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/customers/customers_edit_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendor_edit_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum PartyPaymentKind { customer, vendor }

class PartyPaymentsScreen extends StatefulWidget {
  const PartyPaymentsScreen({super.key});

  @override
  State<PartyPaymentsScreen> createState() => _PartyPaymentsScreenState();
}

class _PartyPaymentsScreenState extends State<PartyPaymentsScreen> {
  late CustomerService _customerService;
  late VendorService _vendorService;
  VoidCallback? _branchListener;

  PartyPaymentKind _kind = PartyPaymentKind.customer;
  bool _loadingParties = false;
  bool _loadingDetail = false;
  bool _posting = false;

  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _search = '';
  String _method = 'cash';
  String? _detailError;

  final List<Map<String, dynamic>> _parties = [];
  final List<Map<String, dynamic>> _ledger = [];
  Map<String, dynamic>? _selectedParty;
  Map<String, dynamic>? _detail;
  double _opening = 0;
  int _ledgerTotal = 0;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _customerService = CustomerService(token: token);
    _vendorService = VendorService(token: token);

    final branchProvider = context.read<BranchProvider>();
    _branchListener = () => _reloadAll(keepSelection: true);
    branchProvider.addListener(_branchListener!);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParties(resetSelection: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    final branchProvider = context.read<BranchProvider>();
    if (_branchListener != null) branchProvider.removeListener(_branchListener!);
    super.dispose();
  }

  Future<void> _reloadAll({bool keepSelection = false}) async {
    await _loadParties(resetSelection: !keepSelection);
    if (keepSelection && _selectedParty != null) {
      final selectedId = _idOf(_selectedParty!);
      final refreshed = _parties.where((p) => _idOf(p) == selectedId).toList();
      if (refreshed.isNotEmpty) {
        await _selectParty(refreshed.first);
      } else if (mounted) {
        setState(() {
          _selectedParty = null;
          _detail = null;
          _ledger.clear();
        });
      }
    }
  }

  Future<void> _loadParties({bool resetSelection = false}) async {
    if (_loadingParties) return;
    setState(() {
      _loadingParties = true;
      if (resetSelection) {
        _selectedParty = null;
        _detail = null;
        _ledger.clear();
        _detailError = null;
      }
    });

    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomers(
              page: 1,
              search: _search,
              includeBalance: true,
              branchId: branchId,
            )
          : await _vendorService.getVendors(
              page: 1,
              search: _search,
              includeBalance: true,
              branchId: branchId,
            );

      final loaded = _extractParties(res);
      if (!mounted) return;
      setState(() {
        _parties
          ..clear()
          ..addAll(loaded);
      });

      if (resetSelection && loaded.isNotEmpty) {
        await _selectParty(loaded.first);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load ${_kindLabelPlural.toLowerCase()}: $e');
    } finally {
      if (mounted) setState(() => _loadingParties = false);
    }
  }

  List<Map<String, dynamic>> _extractParties(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final list = map[_kind == PartyPaymentKind.customer ? 'customers' : 'vendors'] ??
          map['items'] ??
          map['data'] ??
          const [];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return const [];
  }

  Future<void> _selectParty(Map<String, dynamic> party) async {
    final id = _idOf(party);
    if (id == null) return;

    setState(() {
      _selectedParty = party;
      _detail = null;
      _ledger.clear();
      _opening = 0;
      _ledgerTotal = 0;
      _detailError = null;
      _loadingDetail = true;
      _amountController.clear();
      _referenceController.clear();
    });

    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final detailRes = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomerDetail(id: id, branchId: branchId)
          : await _vendorService.getVendorDetail(id: id, branchId: branchId);
      final ledgerRes = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomerLedger(id: id, page: 1, perPage: 8, branchId: branchId)
          : await _vendorService.getVendorLedger(id: id, page: 1, perPage: 8, branchId: branchId);

      if (!mounted) return;
      setState(() {
        _detail = _extractDetail(detailRes);
        final ledgerWrap = (ledgerRes['data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final rows = (ledgerWrap['items'] as List?) ?? const [];
        _ledger
          ..clear()
          ..addAll(rows.map((e) => Map<String, dynamic>.from(e as Map)));
        _opening = _toDouble(ledgerWrap['opening']);
        _ledgerTotal = _toInt(ledgerWrap['total']) ?? _ledger.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _detailError = 'Failed to load ${_kindLabel.toLowerCase()} balance/ledger: $e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Map<String, dynamic> _extractDetail(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final nestedKey = _kind == PartyPaymentKind.customer ? 'customer' : 'vendor';
      if (map[nestedKey] is Map) {
        return {
          ...map,
          ...Map<String, dynamic>.from(map[nestedKey] as Map),
        };
      }
      return map;
    }
    return const <String, dynamic>{};
  }

  void _switchKind(PartyPaymentKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _search = '';
      _searchController.clear();
      _method = 'cash';
      _amountController.clear();
      _referenceController.clear();
      _selectedParty = null;
      _detail = null;
      _ledger.clear();
      _detailError = null;
    });
    _loadParties(resetSelection: true);
  }

  void _searchNow() {
    setState(() => _search = _searchController.text.trim());
    _loadParties(resetSelection: true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _search = '');
    _loadParties(resetSelection: true);
  }

  Future<void> _submitPayment() async {
    if (_selectedParty == null || _posting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = _idOf(_selectedParty!);
    if (id == null) return;

    setState(() => _posting = true);
    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final amount = _toDouble(_amountController.text);
      final reference = _referenceController.text.trim();

      if (_kind == PartyPaymentKind.customer) {
        await _customerService.createReceipt(
          customerId: id,
          amount: amount,
          branchId: branchId,
          method: _method,
          reference: reference,
        );
      } else {
        await _vendorService.createPayment(
          vendorId: id,
          amount: amount,
          branchId: branchId,
          method: _method,
          reference: reference,
        );
      }

      if (!mounted) return;
      AppFeedback.success(context, _kind == PartyPaymentKind.customer ? 'Customer receipt recorded' : 'Vendor payment recorded');
      _amountController.clear();
      _referenceController.clear();
      await _reloadAll(keepSelection: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save payment: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _openDetails() async {
    final id = _selectedParty == null ? null : _idOf(_selectedParty!);
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _kind == PartyPaymentKind.customer
            ? CustomerEditScreen(customerId: id)
            : VendorEditScreen(vendorId: id),
      ),
    );
    if (mounted) await _reloadAll(keepSelection: true);
  }

  Map<String, dynamic> get _activeParty {
    return <String, dynamic>{
      ...?_selectedParty,
      ...?_detail,
    };
  }

  String get _kindLabel => _kind == PartyPaymentKind.customer ? 'Customer' : 'Vendor';
  String get _kindLabelPlural => _kind == PartyPaymentKind.customer ? 'Customers' : 'Vendors';
  String get _paymentActionLabel => _kind == PartyPaymentKind.customer ? 'Receive Payment' : 'Make Payment';
  String get _amountLabel => _kind == PartyPaymentKind.customer ? 'Received Amount' : 'Paid Amount';

  int? _idOf(Map<String, dynamic> map) => _toInt(map['id']);

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => _toDouble(v).toStringAsFixed(2);

  String _partyName(Map<String, dynamic> p) {
    if (_kind == PartyPaymentKind.customer) {
      final first = (p['first_name'] ?? '').toString().trim();
      final last = (p['last_name'] ?? '').toString().trim();
      final name = [first, last].where((e) => e.isNotEmpty).join(' ');
      return name.isEmpty ? (p['name'] ?? 'Walk-in Customer').toString() : name;
    }
    return (p['name'] ?? p['company_name'] ?? 'Vendor').toString();
  }

  String _partyInitials(Map<String, dynamic> p) {
    final name = _partyName(p).trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return EnterprisePage(
      title: 'Party Payments',
      subtitle: 'Receive customer dues and record vendor payments from one dedicated workspace.',
      icon: Icons.account_balance_wallet_rounded,
      appBarActions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: BranchIndicator(tappable: false),
        ),
      ],
      actions: [
        OutlinedButton.icon(
          onPressed: (_loadingParties || _loadingDetail || _posting) ? null : () => _reloadAll(keepSelection: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        children: [
          EnterpriseToolbar(
            children: [
              SegmentedButton<PartyPaymentKind>(
                segments: const [
                  ButtonSegment(
                    value: PartyPaymentKind.customer,
                    icon: Icon(Icons.people_alt_rounded),
                    label: Text('Customers'),
                  ),
                  ButtonSegment(
                    value: PartyPaymentKind.vendor,
                    icon: Icon(Icons.groups_2_rounded),
                    label: Text('Vendors'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _posting ? null : (value) => _switchKind(value.first),
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width >= 720 ? 420 : double.infinity,
                child: EnterpriseSearchField(
                  controller: _searchController,
                  hintText: 'Search ${_kindLabelPlural.toLowerCase()} by name, phone, email...',
                  onSubmitted: (_) => _searchNow(),
                  onSearch: _searchNow,
                  onClear: _clearSearch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 380, child: _buildPartyList()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildWorkspace()),
                    ],
                  );
                }
                return Column(
                  children: [
                    SizedBox(height: 260, child: _buildPartyList()),
                    const SizedBox(height: 12),
                    Expanded(child: _buildWorkspace()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyList() {
    return EnterprisePanel(
      padding: EdgeInsets.zero,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: EnterpriseSectionHeader(
              title: _kindLabelPlural,
              subtitle: _loadingParties ? 'Loading...' : '${_parties.length} loaded for quick payment',
              icon: _kind == PartyPaymentKind.customer ? Icons.people_alt_rounded : Icons.groups_2_rounded,
              color: _kind == PartyPaymentKind.customer ? AppTheme.primary : AppTheme.purple,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingParties && _parties.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _parties.isEmpty
                    ? EnterpriseEmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No $_kindLabelPlural found',
                        subtitle: _search.isEmpty ? 'Search or add parties before recording payments.' : 'No record matched your search.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: _parties.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final party = _parties[index];
                          final selected = _selectedParty != null && _idOf(_selectedParty!) == _idOf(party);
                          return _PartyCard(
                            name: _partyName(party),
                            initials: _partyInitials(party),
                            subtitle: _partySubtitle(party),
                            balance: _money(party['balance']),
                            balanceColor: _balanceColor(_toDouble(party['balance'])),
                            selected: selected,
                            onTap: () => _selectParty(party),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    if (_selectedParty == null) {
      return EnterpriseEmptyState(
        icon: Icons.account_circle_outlined,
        title: 'Select a $_kindLabel',
        subtitle: 'Choose a ${_kindLabel.toLowerCase()} to view balance, recent ledger records and payment form.',
      );
    }

    if (_loadingDetail && _detail == null && _ledger.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_detailError != null && _detail == null) {
      return EnterprisePanel(
        elevated: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_rounded, color: AppTheme.danger, size: 32),
            const SizedBox(height: 10),
            Text(_detailError!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _selectParty(_selectedParty!),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final party = _activeParty;
    return RefreshIndicator(
      onRefresh: () => _selectParty(_selectedParty!),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SummaryPanel(
            kind: _kind,
            name: _partyName(party),
            initials: _partyInitials(party),
            subtitle: _partySubtitle(party),
            balance: _money(party['balance']),
            balanceColor: _balanceColor(_toDouble(party['balance'])),
            primaryMetricLabel: _kind == PartyPaymentKind.customer ? 'Sales' : 'Purchases',
            primaryMetricValue: _money(_kind == PartyPaymentKind.customer ? party['total_sales'] : party['total_purchases']),
            secondaryMetricLabel: _kind == PartyPaymentKind.customer ? 'Receipts' : 'Payments',
            secondaryMetricValue: _money(_kind == PartyPaymentKind.customer ? party['total_receipts'] : party['total_payments']),
            onDetails: _openDetails,
          ),
          const SizedBox(height: 12),
          _PaymentPanel(
            formKey: _formKey,
            title: _paymentActionLabel,
            subtitle: _kind == PartyPaymentKind.customer
                ? 'Record customer receipt against receivable balance.'
                : 'Record supplier/vendor payment against payable balance.',
            amountController: _amountController,
            referenceController: _referenceController,
            amountLabel: _amountLabel,
            method: _method,
            posting: _posting,
            onMethodChanged: (value) => setState(() => _method = value ?? 'cash'),
            onSubmit: _submitPayment,
          ),
          const SizedBox(height: 12),
          _LedgerPanel(
            title: 'Recent Ledger',
            opening: _opening,
            total: _ledgerTotal,
            rows: _ledger,
            loading: _loadingDetail,
            onDetails: _openDetails,
          ),
        ],
      ),
    );
  }

  String _partySubtitle(Map<String, dynamic> party) {
    final phone = (party['phone'] ?? '').toString().trim();
    final email = (party['email'] ?? '').toString().trim();
    final address = (party['address'] ?? '').toString().trim();
    final parts = [phone, email, address].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? 'No contact info' : parts.take(2).join(' • ');
  }

  Color _balanceColor(double balance) {
    if (balance > 0) return _kind == PartyPaymentKind.customer ? AppTheme.warning : AppTheme.danger;
    if (balance < 0) return AppTheme.success;
    return AppTheme.textMuted;
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.name,
    required this.initials,
    required this.subtitle,
    required this.balance,
    required this.balanceColor,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String initials;
  final String subtitle;
  final String balance;
  final Color balanceColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: selected ? AppTheme.primary.withOpacity(.35) : AppTheme.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: selected ? AppTheme.primary : AppTheme.surfaceSoft,
                foregroundColor: selected ? Colors.white : AppTheme.navy,
                child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Balance', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(balance, style: TextStyle(color: balanceColor, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.kind,
    required this.name,
    required this.initials,
    required this.subtitle,
    required this.balance,
    required this.balanceColor,
    required this.primaryMetricLabel,
    required this.primaryMetricValue,
    required this.secondaryMetricLabel,
    required this.secondaryMetricValue,
    required this.onDetails,
  });

  final PartyPaymentKind kind;
  final String name;
  final String initials;
  final String subtitle;
  final String balance;
  final Color balanceColor;
  final String primaryMetricLabel;
  final String primaryMetricValue;
  final String secondaryMetricLabel;
  final String secondaryMetricValue;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final accent = kind == PartyPaymentKind.customer ? AppTheme.primary : AppTheme.purple;
    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(17)),
                child: Center(child: Text(initials, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 16))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navy)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Details'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              EnterpriseStatPill(label: 'Balance', value: balance, icon: Icons.account_balance_wallet_rounded, color: balanceColor),
              EnterpriseStatPill(label: primaryMetricLabel, value: primaryMetricValue, icon: Icons.receipt_long_rounded, color: AppTheme.info),
              EnterpriseStatPill(label: secondaryMetricLabel, value: secondaryMetricValue, icon: Icons.payments_rounded, color: AppTheme.success),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.formKey,
    required this.title,
    required this.subtitle,
    required this.amountController,
    required this.referenceController,
    required this.amountLabel,
    required this.method,
    required this.posting,
    required this.onMethodChanged,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final String subtitle;
  final TextEditingController amountController;
  final TextEditingController referenceController;
  final String amountLabel;
  final String method;
  final bool posting;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 860;

    Widget amountField() => TextFormField(
          controller: amountController,
          enabled: !posting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: amountLabel,
            hintText: '0.00',
            prefixIcon: const Icon(Icons.currency_exchange_rounded),
          ),
          validator: (value) {
            final amount = double.tryParse((value ?? '').replaceAll(',', '').trim()) ?? 0;
            if (amount <= 0) return 'Enter a valid amount';
            return null;
          },
          onFieldSubmitted: (_) => onSubmit(),
        );

    Widget methodField() => DropdownButtonFormField<String>(
          value: method,
          decoration: const InputDecoration(
            labelText: 'Method',
            prefixIcon: Icon(Icons.account_balance_rounded),
          ),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Cash')),
            DropdownMenuItem(value: 'bank', child: Text('Bank')),
            DropdownMenuItem(value: 'card', child: Text('Card')),
            DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
          ],
          onChanged: posting ? null : onMethodChanged,
        );

    Widget referenceField() => TextFormField(
          controller: referenceController,
          enabled: !posting,
          decoration: const InputDecoration(
            labelText: 'Reference / Note',
            hintText: 'Optional payment note',
            prefixIcon: Icon(Icons.note_alt_rounded),
          ),
          onFieldSubmitted: (_) => onSubmit(),
        );

    Widget saveButton() => SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: posting ? null : onSubmit,
            icon: posting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded),
            label: Text(posting ? 'Saving...' : 'Save'),
          ),
        );

    final fields = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: amountField()),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: methodField()),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: referenceField()),
              const SizedBox(width: 10),
              saveButton(),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              amountField(),
              const SizedBox(height: 10),
              methodField(),
              const SizedBox(height: 10),
              referenceField(),
              const SizedBox(height: 12),
              saveButton(),
            ],
          );

    return EnterprisePanel(
      elevated: true,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EnterpriseSectionHeader(
              title: title,
              subtitle: subtitle,
              icon: Icons.payments_rounded,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 14),
            fields,
          ],
        ),
      ),
    );
  }
}

class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel({
    required this.title,
    required this.opening,
    required this.total,
    required this.rows,
    required this.loading,
    required this.onDetails,
  });

  final String title;
  final double opening;
  final int total;
  final List<Map<String, dynamic>> rows;
  final bool loading;
  final VoidCallback onDetails;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => _toDouble(v).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      elevated: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: EnterpriseSectionHeader(
              title: title,
              subtitle: 'Opening ${_money(opening)} • $total ledger entries',
              icon: Icons.timeline_rounded,
              color: AppTheme.info,
              trailing: TextButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text('Full Ledger'),
              ),
            ),
          ),
          const Divider(height: 1),
          if (loading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No ledger records found', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(10),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                return _LedgerRow(row: row);
              },
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row});
  final Map<String, dynamic> row;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => _toDouble(v).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final title = (row['description'] ?? row['reference'] ?? row['type'] ?? row['source'] ?? 'Ledger Entry').toString();
    final date = (row['date'] ?? row['txn_date'] ?? row['created_at'] ?? '').toString();
    final account = (row['account_name'] ?? row['account'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.receipt_long_rounded, color: AppTheme.textMuted, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  [date, account].where((e) => e.trim().isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AmountColumn(label: 'Dr', value: _money(row['debit']), color: AppTheme.warning),
          const SizedBox(width: 14),
          _AmountColumn(label: 'Cr', value: _money(row['credit']), color: AppTheme.success),
          const SizedBox(width: 14),
          _AmountColumn(label: 'Bal', value: _money(row['balance']), color: AppTheme.navy, bold: true),
        ],
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.label, required this.value, required this.color, this.bold = false});

  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: bold ? FontWeight.w900 : FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
