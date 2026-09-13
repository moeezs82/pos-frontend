import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/delivery_boy_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_feature_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/customers/customers_edit_screen.dart';
import 'package:enterprise_pos/screens/vendors/vendor_edit_screen.dart';
import 'package:enterprise_pos/forms/user_form_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/payment_method_dropdown.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum PartyPaymentKind { customer, vendor, deliveryBoy }
enum PartyBalanceFilter { all, advanceCredit, outstanding }
enum PaymentAllocationMode { auto, manual, unallocated }

class PartyPaymentsScreen extends StatefulWidget {
  const PartyPaymentsScreen({super.key});

  @override
  State<PartyPaymentsScreen> createState() => _PartyPaymentsScreenState();
}

class _PartyPaymentsScreenState extends State<PartyPaymentsScreen> {
  late CustomerService _customerService;
  late VendorService _vendorService;
  late DeliveryBoyService _deliveryBoyService;
  VoidCallback? _branchListener;

  PartyPaymentKind _kind = PartyPaymentKind.customer;
  PartyBalanceFilter _balanceFilter = PartyBalanceFilter.all;
  bool _loadingParties = false;
  bool _loadingDetail = false;
  bool _posting = false;
  int? _reversingPaymentId;
  // Monotonic token: a detail/ledger response is applied only if its party
  // selection is still the current one (discards stale responses when the user
  // switches party while a request is in flight).
  int _detailGen = 0;
  int _partyLoadGen = 0;
  int _partyPage = 1;
  int _partyLastPage = 1;
  int _partyTotal = 0;
  static const int _partyPageSize = 50;

  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _partyScrollController = ScrollController();

  String _search = '';
  String _method = 'cash';
  String? _detailError;

  final List<Map<String, dynamic>> _parties = [];
  final List<Map<String, dynamic>> _ledger = [];
  final List<Map<String, dynamic>> _openDocuments = [];
  final Map<int, double> _manualAllocations = {};
  PaymentAllocationMode _allocationMode = PaymentAllocationMode.auto;
  Map<String, dynamic>? _selectedParty;
  Map<String, dynamic>? _detail;
  double _opening = 0;
  double _unallocatedCredit = 0;
  int _ledgerTotal = 0;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _customerService = CustomerService(token: token);
    _vendorService = VendorService(token: token);
    _deliveryBoyService = DeliveryBoyService(token: token);

    final branchProvider = context.read<BranchProvider>();
    _branchListener = () => _reloadAll(keepSelection: true);
    branchProvider.addListener(_branchListener!);
    _partyScrollController.addListener(_onPartyScroll);
    _amountController.addListener(_onPaymentAmountChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParties(resetSelection: true));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.removeListener(_onPaymentAmountChanged);
    _amountController.dispose();
    _referenceController.dispose();
    _partyScrollController
      ..removeListener(_onPartyScroll)
      ..dispose();
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
          _openDocuments.clear();
          _manualAllocations.clear();
          _unallocatedCredit = 0;
        });
      }
    }
  }

  void _onPartyScroll() {
    if (!_partyScrollController.hasClients || _loadingParties || _partyPage >= _partyLastPage) return;
    if (_partyScrollController.position.extentAfter < 180) {
      _loadParties(page: _partyPage + 1, append: true);
    }
  }

  String get _balanceFilterCode => switch (_balanceFilter) {
        PartyBalanceFilter.all => 'all',
        PartyBalanceFilter.advanceCredit => 'advance_credit',
        PartyBalanceFilter.outstanding => 'outstanding',
      };

  Future<void> _loadParties({bool resetSelection = false, int page = 1, bool append = false}) async {
    if (_loadingParties) return;
    final gen = append ? _partyLoadGen : ++_partyLoadGen;
    setState(() {
      _loadingParties = true;
      if (resetSelection) {
        _parties.clear();
        _partyPage = 1;
        _partyLastPage = 1;
        _partyTotal = 0;
        _selectedParty = null;
        _detail = null;
        _ledger.clear();
        _openDocuments.clear();
        _manualAllocations.clear();
        _allocationMode = PaymentAllocationMode.auto;
        _unallocatedCredit = 0;
        _detailError = null;
      }
    });

    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;
      final res = switch (_kind) {
        PartyPaymentKind.customer => await _customerService.getCustomers(
            page: page,
            perPage: _partyPageSize,
            search: _search,
            includeBalance: true,
            balanceFilter: _balanceFilterCode,
            branchId: branchId,
          ),
        PartyPaymentKind.vendor => await _vendorService.getVendors(
            page: page,
            perPage: _partyPageSize,
            search: _search,
            includeBalance: true,
            balanceFilter: _balanceFilterCode,
            branchId: branchId,
          ),
        PartyPaymentKind.deliveryBoy => await _deliveryBoyService.getDeliveryBoys(
            page: page,
            perPage: _partyPageSize,
            search: _search,
            balanceFilter: _balanceFilterCode,
            branchId: branchId,
          ),
      };

      final loaded = _extractParties(res);
      final pagination = _extractPartyPagination(res, fallbackCount: loaded.length, requestedPage: page);
      if (!mounted || gen != _partyLoadGen) return;
      setState(() {
        if (!append) _parties.clear();
        final knownIds = _parties.map(_idOf).whereType<int>().toSet();
        _parties.addAll(loaded.where((party) {
          final id = _idOf(party);
          return id == null || knownIds.add(id);
        }));
        _partyPage = pagination.$1;
        _partyLastPage = pagination.$2;
        _partyTotal = pagination.$3;
      });

      if (resetSelection && !append && loaded.isNotEmpty) {
        await _selectParty(loaded.first);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load ${_kindLabelPlural.toLowerCase()}: $e');
    } finally {
      if (mounted) setState(() => _loadingParties = false);
    }
  }

  (int, int, int) _extractPartyPagination(
    Map<String, dynamic> res, {
    required int fallbackCount,
    required int requestedPage,
  }) {
    final data = res['data'];
    if (data is Map) {
      final current = _toInt(data['current_page']) ?? requestedPage;
      final last = (_toInt(data['last_page']) ?? current).clamp(1, 1 << 30).toInt();
      final total = _toInt(data['total']) ?? fallbackCount;
      return (current, last, total);
    }
    return (requestedPage, requestedPage, fallbackCount);
  }

  List<Map<String, dynamic>> _extractParties(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final list = map[_kind == PartyPaymentKind.customer
              ? 'customers'
              : _kind == PartyPaymentKind.vendor
                  ? 'vendors'
                  : 'delivery_boys'] ??
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

    final gen = ++_detailGen; // invalidate any earlier in-flight load

    setState(() {
      _selectedParty = party;
      _detail = null;
      _ledger.clear();
      _openDocuments.clear();
      _manualAllocations.clear();
      _allocationMode = PaymentAllocationMode.auto;
      _opening = 0;
      _unallocatedCredit = 0;
      _ledgerTotal = 0;
      _detailError = null;
      _loadingDetail = true;
      _amountController.clear();
      _referenceController.clear();
    });

    try {
      final branchId = context.read<BranchProvider>().selectedBranchId;

      if (_kind == PartyPaymentKind.deliveryBoy) {
        // Delivery boys do not use the customer/vendor ledger endpoints.
        // Their workspace must be built from the dedicated delivery routes:
        // GET /delivery-boys/{id}/orders and GET /delivery-boys/{id}/received.
        // The list response already carries delivery_cash_summary/balance, so we
        // reuse it here and avoid an extra summary call before loading records.
        final ordersRes = await _deliveryBoyService.getOrders(id: id, page: 1, perPage: 8, branchId: branchId);
        final receivedRes = await _deliveryBoyService.getReceived(id: id, page: 1, perPage: 8);

        if (!mounted || gen != _detailGen) return;
        setState(() {
          final orders = _extractItems(ordersRes);
          final received = _extractItems(receivedRes);
          _detail = _deliveryDetailFromParty(party, orders: orders, received: received);
          _ledger
            ..clear()
            ..addAll(_deliveryActivityRows(orders: orders, received: received));
          _opening = 0;
          _ledgerTotal = _extractTotal(ordersRes, fallback: orders.length) + _extractTotal(receivedRes, fallback: received.length);
        });
        return;
      }

      final detailRes = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomerDetail(id: id, branchId: branchId)
          : await _vendorService.getVendorDetail(id: id, branchId: branchId);
      // "Recent" ledger = the newest entries, so request the last page.
      final ledgerRes = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomerLedger(id: id, page: 1, perPage: 8, branchId: branchId, latest: true)
          : await _vendorService.getVendorLedger(id: id, page: 1, perPage: 8, branchId: branchId, latest: true);
      final openDocuments = await _fetchAllOpenDocuments(id, branchId: branchId);
      final auth = context.read<AuthProvider>();
      Map<String, dynamic> creditRes = const {
        'data': {'available_credit': 0}
      };
      final canManagePayment = _kind == PartyPaymentKind.customer
          ? auth.hasPermission('manage-receipts')
          : auth.hasPermission('manage-payments');
      if (canManagePayment) {
        creditRes = _kind == PartyPaymentKind.customer
            ? await _customerService.getUnallocatedCredit(customerId: id)
            : await _vendorService.getUnallocatedCredit(vendorId: id);
      }

      if (!mounted || gen != _detailGen) return;
      setState(() {
        _detail = _extractDetail(detailRes);
        _openDocuments
          ..clear()
          ..addAll(openDocuments);
        _unallocatedCredit = _extractAvailableCredit(creditRes);
        final ledgerWrap = (ledgerRes['data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final rows = (ledgerWrap['items'] as List?) ?? const [];
        _ledger
          ..clear()
          ..addAll(rows.map((e) => Map<String, dynamic>.from(e as Map)));
        _opening = _toDouble(ledgerWrap['opening']);
        _ledgerTotal = _toInt(ledgerWrap['total']) ?? _ledger.length;
      });
    } catch (e) {
      if (!mounted || gen != _detailGen) return;
      setState(() => _detailError = 'Failed to load ${_kindLabel.toLowerCase()} records: $e');
    } finally {
      if (mounted && gen == _detailGen) setState(() => _loadingDetail = false);
    }
  }

  Map<String, dynamic> _extractDetail(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final nestedKey = _kind == PartyPaymentKind.customer
          ? 'customer'
          : _kind == PartyPaymentKind.vendor
              ? 'vendor'
              : 'delivery_boy';
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

  Map<String, dynamic> _deliveryDetailFromParty(
    Map<String, dynamic> party, {
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> received,
  }) {
    final summaryRaw = party['delivery_cash_summary'] ?? party['cash_summary'];
    final summary = summaryRaw is Map ? Map<String, dynamic>.from(summaryRaw) : <String, dynamic>{};

    final fallbackOrdersTotal = _sumBy(orders, 'total');
    final fallbackReceivedTotal = _sumBy(received, 'amount');
    final ordersTotal = _toDouble(summary['orders_total'] ?? party['orders_total'] ?? fallbackOrdersTotal);
    final receivedTotal = _toDouble(summary['received_total'] ?? party['received_total'] ?? fallbackReceivedTotal);

    return <String, dynamic>{
      ...party,
      ...summary,
      'orders_count': _toInt(summary['orders_count'] ?? party['orders_count']) ?? orders.length,
      'orders_total': ordersTotal,
      'received_count': _toInt(summary['received_count'] ?? party['received_count']) ?? received.length,
      'received_total': receivedTotal,
      'balance': _toDouble(summary['balance'] ?? party['balance'] ?? (ordersTotal - receivedTotal)),
    };
  }

  double _sumBy(List<Map<String, dynamic>> rows, String key) {
    return rows.fold<double>(0, (sum, row) => sum + _toDouble(row[key]));
  }

  int _extractTotal(Map<String, dynamic> res, {required int fallback}) {
    final data = res['data'];
    if (data is Map) {
      return _toInt(data['total']) ?? fallback;
    }
    return fallback;
  }

  double _extractAvailableCredit(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map) return _toDouble(data['available_credit']);
    return _toDouble(res['available_credit']);
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
      _openDocuments.clear();
      _manualAllocations.clear();
      _allocationMode = PaymentAllocationMode.auto;
      _unallocatedCredit = 0;
      _detailError = null;
      _partyPage = 1;
      _partyLastPage = 1;
      _partyTotal = 0;
    });
    _loadParties(resetSelection: true);
  }

  void _switchBalanceFilter(PartyBalanceFilter filter) {
    if (_balanceFilter == filter || _loadingParties || _posting) return;
    ++_detailGen;
    setState(() {
      _balanceFilter = filter;
      _partyPage = 1;
      _partyLastPage = 1;
      _partyTotal = 0;
      _selectedParty = null;
      _detail = null;
      _ledger.clear();
      _openDocuments.clear();
      _manualAllocations.clear();
      _allocationMode = PaymentAllocationMode.auto;
      _unallocatedCredit = 0;
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

  void _onPaymentAmountChanged() {
    if (!mounted || _kind == PartyPaymentKind.deliveryBoy) return;
    setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetchAllOpenDocuments(
    int partyId, {
    int? branchId,
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    var lastPage = 1;
    do {
      final res = _kind == PartyPaymentKind.customer
          ? await _customerService.getCustomerSales(
              id: partyId,
              page: page,
              perPage: 100,
              branchId: branchId,
              openOnly: true,
            )
          : await _vendorService.getVendorPurchases(
              id: partyId,
              page: page,
              perPage: 100,
              branchId: branchId,
              openOnly: true,
            );
      rows.addAll(_extractItems(res));
      final data = res['data'];
      if (data is Map) {
        lastPage = _toInt(data['last_page']) ?? page;
      } else {
        lastPage = page;
      }
      page++;
    } while (page <= lastPage && page <= 100);
    return rows;
  }

  List<Map<String, dynamic>> _allocationPreview() {
    final amount = _toDouble(_amountController.text);
    if (amount <= 0 || _kind == PartyPaymentKind.deliveryBoy) return const [];
    if (_allocationMode == PaymentAllocationMode.unallocated) return const [];

    if (_allocationMode == PaymentAllocationMode.manual) {
      final docsById = <int, Map<String, dynamic>>{
        for (final d in _openDocuments)
          if (_idOf(d) != null) _idOf(d)!: d,
      };
      final out = <Map<String, dynamic>>[];
      for (final entry in _manualAllocations.entries) {
        final doc = docsById[entry.key];
        if (doc == null || entry.value <= 0) continue;
        out.add({...doc, 'allocation_amount': entry.value});
      }
      return out;
    }

    var remaining = amount;
    final out = <Map<String, dynamic>>[];
    for (final doc in _openDocuments) {
      if (remaining <= 0.004) break;
      final due = _toDouble(doc['open_amount']);
      if (due <= 0.004) continue;
      final applied = due < remaining ? due : remaining;
      out.add({...doc, 'allocation_amount': applied});
      remaining -= applied;
    }
    return out;
  }

  double get _previewAllocated => _allocationPreview().fold<double>(
        0,
        (sum, row) => sum + _toDouble(row['allocation_amount']),
      );

  double get _previewUnallocated {
    final amount = _toDouble(_amountController.text);
    final value = amount - _previewAllocated;
    return value > 0 ? value : 0;
  }

  Future<Map<int, double>?> _selectManualAllocations({
    required double allocationLimit,
    required String sourceLabel,
    Map<int, double> initial = const {},
  }) async {
    if (allocationLimit <= 0) {
      AppFeedback.error(context, 'There is no amount available to allocate.');
      return null;
    }
    if (_openDocuments.isEmpty) {
      AppFeedback.error(context, 'There are no outstanding invoices to allocate.');
      return null;
    }

    final controllers = <int, TextEditingController>{};
    for (final doc in _openDocuments) {
      final id = _idOf(doc);
      if (id == null) continue;
      final value = initial[id];
      controllers[id] = TextEditingController(
        text: value != null && value > 0 ? value.toStringAsFixed(2) : '',
      );
    }

    final result = await showDialog<Map<int, double>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double allocated() => controllers.values.fold<double>(
                0,
                (sum, c) => sum + _toDouble(c.text),
              );
          return AlertDialog(
            title: Text(_kind == PartyPaymentKind.customer
                ? 'Allocate Customer Credit'
                : 'Allocate Vendor Credit'),
            content: SizedBox(
              width: 700,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      EnterpriseStatPill(
                        label: sourceLabel,
                        value: _money(allocationLimit),
                        icon: Icons.payments_rounded,
                        color: AppTheme.primary,
                      ),
                      EnterpriseStatPill(
                        label: 'Allocated',
                        value: _money(allocated()),
                        icon: Icons.call_split_rounded,
                        color: AppTheme.success,
                      ),
                      EnterpriseStatPill(
                        label: 'Remaining',
                        value: _money((allocationLimit - allocated()).clamp(0, double.infinity)),
                        icon: Icons.savings_outlined,
                        color: AppTheme.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose how much of this ${sourceLabel.toLowerCase()} should settle each invoice. Any remainder stays as party credit / advance.',
                    style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _openDocuments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final doc = _openDocuments[index];
                        final id = _idOf(doc)!;
                        final invoice = (doc['invoice_no'] ?? '#$id').toString();
                        final date = (doc['invoice_date'] ?? '').toString();
                        final due = _toDouble(doc['open_amount']);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(invoice, style: const TextStyle(fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${date.isEmpty ? 'Invoice' : date} • Due ${_money(due)}',
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: controllers[id],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  decoration: const InputDecoration(labelText: 'Apply', hintText: '0.00'),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  final alreadyOther = allocated() - _toDouble(controllers[id]!.text);
                                  final remainingSource = (allocationLimit - alreadyOther).clamp(0, double.infinity);
                                  final max = due < remainingSource ? due : remainingSource;
                                  controllers[id]!.text = max <= 0 ? '' : max.toStringAsFixed(2);
                                  setDialogState(() {});
                                },
                                child: const Text('Max'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final values = <int, double>{};
                  var total = 0.0;
                  for (final doc in _openDocuments) {
                    final id = _idOf(doc)!;
                    final value = _toDouble(controllers[id]?.text);
                    if (value <= 0) continue;
                    final due = _toDouble(doc['open_amount']);
                    if (value > due + 0.004) {
                      AppFeedback.error(context, 'Allocation for ${doc['invoice_no']} exceeds due amount ${_money(due)}.');
                      return;
                    }
                    total += value;
                    values[id] = value;
                  }
                  if (total <= 0) {
                    AppFeedback.error(context, 'Allocate an amount to at least one invoice.');
                    return;
                  }
                  if (total > allocationLimit + 0.004) {
                    AppFeedback.error(context, 'Allocated amount cannot exceed ${_money(allocationLimit)}.');
                    return;
                  }
                  Navigator.pop(dialogContext, values);
                },
                child: const Text('Apply Allocation'),
              ),
            ],
          );
        },
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    return result;
  }

  Future<void> _openManualAllocationDialog() async {
    final paymentAmount = _toDouble(_amountController.text);
    if (paymentAmount <= 0) {
      AppFeedback.error(context, 'Enter the payment amount first.');
      return;
    }
    final result = await _selectManualAllocations(
      allocationLimit: paymentAmount,
      sourceLabel: 'Payment',
      initial: _manualAllocations,
    );
    if (result != null && mounted) {
      setState(() {
        _manualAllocations
          ..clear()
          ..addAll(result);
        _allocationMode = PaymentAllocationMode.manual;
      });
    }
  }

  Future<void> _applyExistingCredit() async {
    if (_selectedParty == null || _posting || _unallocatedCredit <= 0.004) return;
    if (_openDocuments.isEmpty) {
      AppFeedback.error(context, 'There are no outstanding invoices to settle.');
      return;
    }
    final partyId = _idOf(_selectedParty!);
    if (partyId == null) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply Existing Credit'),
        content: Text(
          'Available unallocated credit: ${_money(_unallocatedCredit)}\n\n'
          'Auto Allocate settles the oldest invoices first. Manual lets you choose the invoices and amounts.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'manual'),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Manual'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'auto'),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Auto Allocate'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    var allocations = const <Map<String, dynamic>>[];
    if (choice == 'manual') {
      final selected = await _selectManualAllocations(
        allocationLimit: _unallocatedCredit,
        sourceLabel: 'Existing Credit',
      );
      if (selected == null || !mounted) return;
      final key = _kind == PartyPaymentKind.customer ? 'sale_id' : 'purchase_id';
      allocations = selected.entries
          .where((e) => e.value > 0)
          .map((e) => <String, dynamic>{key: e.key, 'amount': e.value})
          .toList(growable: false);
    }

    setState(() => _posting = true);
    try {
      if (_kind == PartyPaymentKind.customer) {
        await _customerService.applyExistingCredit(
          customerId: partyId,
          allocationMode: choice,
          allocations: allocations,
        );
      } else if (_kind == PartyPaymentKind.vendor) {
        await _vendorService.applyExistingCredit(
          vendorId: partyId,
          allocationMode: choice,
          allocations: allocations,
        );
      }
      if (!mounted) return;
      AppFeedback.success(context, 'Existing credit allocated successfully');
      await _reloadAll(keepSelection: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to allocate existing credit: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String get _allocationModeCode => switch (_allocationMode) {
        PaymentAllocationMode.auto => 'auto',
        PaymentAllocationMode.manual => 'manual',
        PaymentAllocationMode.unallocated => 'unallocated',
      };

  List<Map<String, dynamic>> _allocationPayload() {
    if (_allocationMode != PaymentAllocationMode.manual) return const [];
    final key = _kind == PartyPaymentKind.customer ? 'sale_id' : 'purchase_id';
    return _manualAllocations.entries
        .where((e) => e.value > 0)
        .map((e) => <String, dynamic>{key: e.key, 'amount': e.value})
        .toList(growable: false);
  }

  Widget _buildAllocationSection() {
    if (_kind == PartyPaymentKind.deliveryBoy) return const SizedBox.shrink();
    final preview = _allocationPreview();
    final amount = _toDouble(_amountController.text);
    final allocated = preview.fold<double>(0, (sum, row) => sum + _toDouble(row['allocation_amount']));
    final unallocated = (amount - allocated).clamp(0, double.infinity).toDouble();
    final documentLabel = _kind == PartyPaymentKind.customer ? 'sales' : 'purchases';

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 19, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Invoice Allocation', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              Text(
                '${_openDocuments.length} open $documentLabel',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_unallocatedCredit > 0.004 && _openDocuments.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Existing unallocated credit ${_money(_unallocatedCredit)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _posting ? null : _applyExistingCredit,
                    icon: const Icon(Icons.call_split_rounded, size: 17),
                    label: const Text('Apply Existing Credit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          SegmentedButton<PaymentAllocationMode>(
            segments: const [
              ButtonSegment(value: PaymentAllocationMode.auto, icon: Icon(Icons.auto_awesome_rounded), label: Text('Auto · Oldest First')),
              ButtonSegment(value: PaymentAllocationMode.manual, icon: Icon(Icons.tune_rounded), label: Text('Manual')),
              ButtonSegment(value: PaymentAllocationMode.unallocated, icon: Icon(Icons.savings_outlined), label: Text('Leave Unallocated')),
            ],
            selected: {_allocationMode},
            onSelectionChanged: _posting
                ? null
                : (value) async {
                    final mode = value.first;
                    if (mode == PaymentAllocationMode.manual) {
                      await _openManualAllocationDialog();
                    } else {
                      setState(() {
                        _allocationMode = mode;
                        if (mode != PaymentAllocationMode.manual) _manualAllocations.clear();
                      });
                    }
                  },
          ),
          const SizedBox(height: 10),
          if (_openDocuments.isEmpty)
            const Text(
              'No outstanding invoices. This payment will remain as party credit / advance.',
              style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            )
          else if (_allocationMode == PaymentAllocationMode.unallocated)
            const Text(
              'No invoice will be settled. The full payment remains unallocated party credit / advance.',
              style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
            )
          else ...[
            if (_allocationMode == PaymentAllocationMode.manual)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : _openManualAllocationDialog,
                  icon: const Icon(Icons.edit_rounded, size: 17),
                  label: const Text('Adjust Allocation'),
                ),
              ),
            if (preview.isEmpty)
              Text(
                amount <= 0 ? 'Enter an amount to preview invoice allocation.' : 'No allocation selected.',
                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              )
            else
              ...preview.take(4).map((row) => Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (row['invoice_no'] ?? '#${row['id']}').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _money(row['allocation_amount']),
                          style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.success),
                        ),
                      ],
                    ),
                  )),
            if (preview.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+ ${preview.length - 4} more invoices', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text('Allocated ${_money(allocated)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                'Unallocated ${_money(unallocated)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: unallocated > 0.004 ? AppTheme.warning : AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
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

      if (_kind != PartyPaymentKind.deliveryBoy && _allocationMode == PaymentAllocationMode.manual) {
        final allocated = _manualAllocations.values.fold<double>(0, (sum, value) => sum + value);
        if (allocated <= 0.004) {
          AppFeedback.error(context, 'Allocate an amount to at least one invoice, or choose Leave Unallocated.');
          setState(() => _posting = false);
          return;
        }
        if (allocated > amount + 0.004) {
          AppFeedback.error(context, 'Allocated amount cannot exceed the payment amount.');
          setState(() => _posting = false);
          return;
        }
        final dueById = <int, double>{
          for (final doc in _openDocuments)
            if (_idOf(doc) != null) _idOf(doc)!: _toDouble(doc['open_amount']),
        };
        for (final entry in _manualAllocations.entries) {
          final due = dueById[entry.key];
          if (due == null || entry.value > due + 0.004) {
            AppFeedback.error(context, 'One of the selected invoice allocations is no longer valid. Refresh and try again.');
            setState(() => _posting = false);
            return;
          }
        }
      }

      switch (_kind) {
        case PartyPaymentKind.customer:
          await _customerService.createReceipt(
            customerId: id,
            amount: amount,
            branchId: branchId,
            method: _method,
            reference: reference,
            allocationMode: _allocationModeCode,
            allocations: _allocationPayload(),
          );
          break;
        case PartyPaymentKind.vendor:
          await _vendorService.createPayment(
            vendorId: id,
            amount: amount,
            branchId: branchId,
            method: _method,
            reference: reference,
            allocationMode: _allocationModeCode,
            allocations: _allocationPayload(),
          );
          break;
        case PartyPaymentKind.deliveryBoy:
          await _deliveryBoyService.createReceived(
            deliveryBoyId: id,
            amount: amount,
          );
          break;
      }

      if (!mounted) return;
      AppFeedback.success(context, switch (_kind) {
        PartyPaymentKind.customer => 'Customer receipt recorded',
        PartyPaymentKind.vendor => 'Vendor payment recorded',
        PartyPaymentKind.deliveryBoy => 'Delivery boy cash received',
      });
      _amountController.clear();
      _referenceController.clear();
      await _reloadAll(keepSelection: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save payment: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _reverseLedgerPayment(Map<String, dynamic> row) async {
    if (_kind == PartyPaymentKind.deliveryBoy || _selectedParty == null) return;
    final partyId = _idOf(_selectedParty!);
    final paymentId = _toInt(row['payment_id']);
    if (partyId == null || paymentId == null || _reversingPaymentId != null) return;

    final amount = _kind == PartyPaymentKind.customer
        ? _toDouble(row['credit'])
        : _toDouble(row['debit']);
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReversePaymentDialog(
        partyLabel: _partyName(_activeParty),
        paymentLabel: _kind == PartyPaymentKind.customer ? 'customer receipt' : 'vendor payment',
        amount: _money(amount),
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _reversingPaymentId = paymentId);
    try {
      if (_kind == PartyPaymentKind.customer) {
        await _customerService.reverseReceipt(
          customerId: partyId,
          receiptId: paymentId,
          reason: reason,
        );
      } else {
        await _vendorService.reversePayment(
          vendorId: partyId,
          paymentId: paymentId,
          reason: reason,
        );
      }
      if (!mounted) return;
      AppFeedback.success(context, 'Payment reversed. Enter the correct payment as a new transaction.');
      await _reloadAll(keepSelection: true);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to reverse payment: $e');
    } finally {
      if (mounted) setState(() => _reversingPaymentId = null);
    }
  }

  Future<void> _openDetails() async {
    final id = _selectedParty == null ? null : _idOf(_selectedParty!);
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => switch (_kind) {
          PartyPaymentKind.customer => CustomerEditScreen(customerId: id),
          PartyPaymentKind.vendor => VendorEditScreen(vendorId: id),
          PartyPaymentKind.deliveryBoy => UserFormScreen(user: _activeParty),
        },
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

  String get _kindLabel => switch (_kind) {
        PartyPaymentKind.customer => 'Customer',
        PartyPaymentKind.vendor => 'Vendor',
        PartyPaymentKind.deliveryBoy => 'Delivery Boy',
      };

  String get _kindLabelPlural => switch (_kind) {
        PartyPaymentKind.customer => 'Customers',
        PartyPaymentKind.vendor => 'Vendors',
        PartyPaymentKind.deliveryBoy => 'Delivery Boys',
      };

  String get _paymentActionLabel => switch (_kind) {
        PartyPaymentKind.customer => 'Receive Payment',
        PartyPaymentKind.vendor => 'Make Payment',
        PartyPaymentKind.deliveryBoy => 'Receive from Delivery Boy',
      };

  String get _amountLabel => switch (_kind) {
        PartyPaymentKind.vendor => 'Paid Amount',
        _ => 'Received Amount',
      };

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

  String _money(dynamic v) => AppCurrency.format(v);

  String _partyName(Map<String, dynamic> p) {
    if (_kind == PartyPaymentKind.customer) {
      final first = (p['first_name'] ?? '').toString().trim();
      final last = (p['last_name'] ?? '').toString().trim();
      final name = [first, last].where((e) => e.isNotEmpty).join(' ');
      return name.isEmpty ? (p['name'] ?? 'Walk-in Customer').toString() : name;
    }
    if (_kind == PartyPaymentKind.deliveryBoy) {
      return (p['name'] ?? 'Delivery Boy').toString();
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

  IconData get _kindIcon => switch (_kind) {
        PartyPaymentKind.customer => Icons.people_alt_rounded,
        PartyPaymentKind.vendor => Icons.groups_2_rounded,
        PartyPaymentKind.deliveryBoy => Icons.delivery_dining_rounded,
      };

  Color get _kindColor => switch (_kind) {
        PartyPaymentKind.customer => AppTheme.primary,
        PartyPaymentKind.vendor => AppTheme.purple,
        PartyPaymentKind.deliveryBoy => AppTheme.info,
      };

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map && data['items'] is List) {
      return (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _deliveryActivityRows({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> received,
  }) {
    final rows = <Map<String, dynamic>>[
      for (final order in orders)
        {
          'description': 'Order ${order['invoice_no'] ?? order['id'] ?? ''}'.trim(),
          'source': [
            order['customer_name'],
          ].where((v) => (v ?? '').toString().trim().isNotEmpty).join(' • '),
          'date': order['created_at'],
          'debit': order['total'],
          'credit': order['paid_amount'],
          'balance': order['open_amount'],
        },
      for (final row in received)
        {
          'description': 'Cash Received',
          'source': 'Delivery boy collection',
          'date': row['created_at'],
          'debit': 0,
          'credit': row['amount'],
          'balance': 0,
        },
    ];

    rows.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return EnterprisePage(
      title: 'Party Payments',
      subtitle: 'Receive customer dues, record vendor payments, and collect delivery-boy cash from one workspace.',
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
              Builder(builder: (context) {
                final deliveryEnabled =
                    context.watch<BranchFeatureProvider>().deliveryEnabled;

                // If delivery has just been disabled and we're on that tab,
                // switch back to Customers immediately (post-frame to avoid
                // setState-in-build).
                if (!deliveryEnabled && _kind == PartyPaymentKind.deliveryBoy) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _switchKind(PartyPaymentKind.customer);
                  });
                }

                return SegmentedButton<PartyPaymentKind>(
                  segments: [
                    const ButtonSegment(
                      value: PartyPaymentKind.customer,
                      icon: Icon(Icons.people_alt_rounded),
                      label: Text('Customers'),
                    ),
                    const ButtonSegment(
                      value: PartyPaymentKind.vendor,
                      icon: Icon(Icons.groups_2_rounded),
                      label: Text('Vendors'),
                    ),
                    if (deliveryEnabled)
                      const ButtonSegment(
                        value: PartyPaymentKind.deliveryBoy,
                        icon: Icon(Icons.delivery_dining_rounded),
                        label: Text('Delivery Boys'),
                      ),
                  ],
                  selected: {
                    (!deliveryEnabled && _kind == PartyPaymentKind.deliveryBoy)
                        ? PartyPaymentKind.customer
                        : _kind,
                  },
                  onSelectionChanged:
                      _posting ? null : (value) => _switchKind(value.first),
                );
              }),
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
              SegmentedButton<PartyBalanceFilter>(
                segments: const [
                  ButtonSegment(
                    value: PartyBalanceFilter.all,
                    icon: Icon(Icons.people_outline_rounded),
                    label: Text('All'),
                  ),
                  ButtonSegment(
                    value: PartyBalanceFilter.advanceCredit,
                    icon: Icon(Icons.savings_outlined),
                    label: Text('Advance / Credit'),
                  ),
                  ButtonSegment(
                    value: PartyBalanceFilter.outstanding,
                    icon: Icon(Icons.account_balance_wallet_rounded),
                    label: Text('Outstanding'),
                  ),
                ],
                selected: {_balanceFilter},
                onSelectionChanged: (_loadingParties || _posting)
                    ? null
                    : (value) => _switchBalanceFilter(value.first),
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
              subtitle: _loadingParties && _parties.isEmpty
                  ? 'Loading...'
                  : '${_parties.length} of $_partyTotal loaded • ${switch (_balanceFilter) {
                      PartyBalanceFilter.outstanding => 'outstanding',
                      PartyBalanceFilter.all => 'all',
                      PartyBalanceFilter.advanceCredit => 'advance / credit',
                    }}',
              icon: _kindIcon,
              color: _kindColor,
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
                        controller: _partyScrollController,
                        padding: const EdgeInsets.all(10),
                        itemCount: _parties.length + (_partyPage < _partyLastPage ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == _parties.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: _loadingParties
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : OutlinedButton.icon(
                                        onPressed: () => _loadParties(page: _partyPage + 1, append: true),
                                        icon: const Icon(Icons.expand_more_rounded),
                                        label: const Text('Load more'),
                                      ),
                              ),
                            );
                          }
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
            primaryMetricLabel: switch (_kind) {
              PartyPaymentKind.customer => 'Sales',
              PartyPaymentKind.vendor => 'Purchases',
              PartyPaymentKind.deliveryBoy => 'Orders',
            },
            primaryMetricValue: _money(switch (_kind) {
              PartyPaymentKind.customer => party['total_sales'],
              PartyPaymentKind.vendor => party['total_purchases'],
              PartyPaymentKind.deliveryBoy => party['orders_total'],
            }),
            secondaryMetricLabel: switch (_kind) {
              PartyPaymentKind.customer => 'Receipts',
              PartyPaymentKind.vendor => 'Payments',
              PartyPaymentKind.deliveryBoy => 'Received',
            },
            secondaryMetricValue: _money(switch (_kind) {
              PartyPaymentKind.customer => party['total_receipts'],
              PartyPaymentKind.vendor => party['total_payments'],
              PartyPaymentKind.deliveryBoy => party['received_total'],
            }),
            onDetails: _openDetails,
          ),
          if (_kind != PartyPaymentKind.deliveryBoy &&
              (party['loan'] is Map) &&
              (party['loan']['has_activity'] == true)) ...[
            const SizedBox(height: 12),
            _LoanSeparateCard(
              loanBalance: _money(party['loan']['loan_balance']),
              needsReview: _toDouble(party['loan']['loan_balance']) < 0,
              onView: _openDetails,
            ),
          ],
          const SizedBox(height: 12),
          _PaymentPanel(
            formKey: _formKey,
            title: _paymentActionLabel,
            subtitle: switch (_kind) {
              PartyPaymentKind.customer => 'Record customer receipt against receivable balance.',
              PartyPaymentKind.vendor => 'Record supplier/vendor payment against payable balance.',
              PartyPaymentKind.deliveryBoy => 'Record cash received from delivery boy against assigned delivery orders.',
            },
            amountController: _amountController,
            referenceController: _referenceController,
            amountLabel: _amountLabel,
            method: _method,
            posting: _posting,
            onMethodChanged: (value) => setState(() => _method = value ?? 'cash'),
            onSubmit: _submitPayment,
            allocationSection: _kind == PartyPaymentKind.deliveryBoy ? null : _buildAllocationSection(),
          ),
          const SizedBox(height: 12),
          _LedgerPanel(
            title: _kind == PartyPaymentKind.deliveryBoy ? 'Recent Delivery Cash Activity' : 'Recent Ledger',
            detailsLabel: _kind == PartyPaymentKind.deliveryBoy ? 'User Details' : 'Full Ledger',
            opening: _opening,
            total: _ledgerTotal,
            rows: _ledger,
            loading: _loadingDetail,
            onDetails: _openDetails,
            canReversePayments: context.read<AuthProvider>().hasPermission('reverse-party-payments'),
            reversingPaymentId: _reversingPaymentId,
            onReverse: _reverseLedgerPayment,
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
    if (balance > 0) {
      return _kind == PartyPaymentKind.vendor ? AppTheme.danger : AppTheme.warning;
    }
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

/// Read-only, visually separate loan indicator. Loan balances are NEVER
/// merged into the trade Balance/Sales/Receipts (or Purchases/Payments) cards;
/// this card simply links to the party's separate Loan Ledger.
class _LoanSeparateCard extends StatelessWidget {
  const _LoanSeparateCard({
    required this.loanBalance,
    required this.needsReview,
    required this.onView,
  });

  final String loanBalance;
  final bool needsReview;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final tone = needsReview ? AppTheme.danger : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withOpacity(.20)),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: tone.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.request_quote_rounded, color: tone, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsReview ? 'Loan Balance · Credit / Review' : 'Loan Balance (separate)',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loanBalance,
                  style: TextStyle(color: tone, fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Not included in the trade balance above.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Loan Ledger'),
          ),
        ],
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
    final accent = switch (kind) {
      PartyPaymentKind.customer => AppTheme.primary,
      PartyPaymentKind.vendor => AppTheme.purple,
      PartyPaymentKind.deliveryBoy => AppTheme.info,
    };
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
    this.allocationSection,
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
  final Widget? allocationSection;

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

    Widget methodField() => PaymentMethodDropdown(
          value: method,
          enabled: !posting,
          onChanged: onMethodChanged,
          decoration: const InputDecoration(
            labelText: 'Method',
            prefixIcon: Icon(Icons.account_balance_rounded),
            border: OutlineInputBorder(),
          ),
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
            if (allocationSection != null) allocationSection!,
          ],
        ),
      ),
    );
  }
}

class _LedgerPanel extends StatelessWidget {
  const _LedgerPanel({
    required this.title,
    required this.detailsLabel,
    required this.opening,
    required this.total,
    required this.rows,
    required this.loading,
    required this.onDetails,
    required this.canReversePayments,
    required this.reversingPaymentId,
    required this.onReverse,
  });

  final String title;
  final String detailsLabel;
  final double opening;
  final int total;
  final List<Map<String, dynamic>> rows;
  final bool loading;
  final VoidCallback onDetails;
  final bool canReversePayments;
  final int? reversingPaymentId;
  final ValueChanged<Map<String, dynamic>> onReverse;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _money(dynamic v) => AppCurrency.format(v);

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
                label: Text(detailsLabel),
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
                return _LedgerRow(
                  row: row,
                  canReverse: canReversePayments && row['can_reverse'] == true,
                  reversing: reversingPaymentId != null && reversingPaymentId == _toInt(row['payment_id']),
                  onReverse: () => onReverse(row),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row, required this.canReverse, required this.reversing, required this.onReverse});
  final Map<String, dynamic> row;
  final bool canReverse;
  final bool reversing;
  final VoidCallback onReverse;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic v) => AppCurrency.format(v);

  @override
  Widget build(BuildContext context) {
    final title = (row['description'] ?? row['reference'] ?? row['type'] ?? row['source'] ?? 'Ledger Entry').toString();
    final date = (row['date'] ?? row['txn_date'] ?? row['created_at'] ?? '').toString();
    final account = (row['account_name'] ?? row['account'] ?? '').toString();
    final status = (row['payment_status'] ?? '').toString();
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
                if (status == 'reversed' || status == 'reversal') ...[
                  const SizedBox(height: 4),
                  Text(
                    status == 'reversal'
                        ? 'Reversal entry${row['reversal_reason'] == null ? '' : ' • ${row['reversal_reason']}'}'
                        : 'Reversed${row['reversal_reason'] == null ? '' : ' • ${row['reversal_reason']}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _AmountColumn(label: 'Dr', value: _money(row['debit']), color: AppTheme.warning),
          const SizedBox(width: 14),
          _AmountColumn(label: 'Cr', value: _money(row['credit']), color: AppTheme.success),
          const SizedBox(width: 14),
          _AmountColumn(label: 'Bal', value: _money(row['balance']), color: AppTheme.navy, bold: true),
          if (canReverse) ...[
            const SizedBox(width: 8),
            reversing
                ? const SizedBox(width: 30, height: 30, child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    tooltip: 'Reverse mistaken payment',
                    onPressed: onReverse,
                    icon: const Icon(Icons.undo_rounded, color: AppTheme.danger),
                  ),
          ],
        ],
      ),
    );
  }
}

class _ReversePaymentDialog extends StatefulWidget {
  const _ReversePaymentDialog({required this.partyLabel, required this.paymentLabel, required this.amount});

  final String partyLabel;
  final String paymentLabel;
  final String amount;

  @override
  State<_ReversePaymentDialog> createState() => _ReversePaymentDialogState();
}

class _ReversePaymentDialogState extends State<_ReversePaymentDialog> {
  final _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Enter a clear reason (at least 3 characters).');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reverse Payment'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will reverse the complete ${widget.paymentLabel} of ${widget.amount} for ${widget.partyLabel}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'The original entry remains in the ledger and an opposite accounting entry is created. Enter the correct payment separately afterward.',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Reversal reason',
                hintText: 'Example: Entered 7,500 instead of 750',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _confirm,
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Reverse Payment'),
        ),
      ],
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
