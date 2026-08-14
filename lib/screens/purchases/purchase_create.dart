import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/screens/purchases/parts/purchase_product_panel.dart';
import 'package:enterprise_pos/widgets/purchase_status_bar.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/widgets/party_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class CreatePurchaseScreen extends StatefulWidget {
  final Map<String, dynamic>? initialVendor;

  const CreatePurchaseScreen({super.key, this.initialVendor});

  @override
  State<CreatePurchaseScreen> createState() => _CreatePurchaseScreenState();
}

class _CreatePurchaseScreenState extends State<CreatePurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageFocusNode = FocusNode();

  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedVendor;

  String? _selectedBranchId;
  int? _selectedVendorId;

  List<Map<String, dynamic>> _items = [];
  final List<Map<String, dynamic>> _payments = [];

  final discountController = TextEditingController(text: '0');
  final taxController = TextEditingController(text: '0');

  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;

  // Named focus nodes for keyboard-shortcut field-jumping (Part C).
  final _vendorFocusNode = FocusNode();
  final _productSearchFocusNode = FocusNode();
  final _vendorController = TextEditingController();
  final _productSearchController = TextEditingController();

  bool _receiveNow = false;
  bool _autoCashIfEmpty = true;
  bool _submitting = false;

  late ProductService _productService;
  late PurchaseService _purchaseService;
  late String _token;

  @override
  void initState() {
    super.initState();
    _token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: _token);
    _purchaseService = PurchaseService(token: _token);

    // Warm vendor/product caches in the background immediately, before the
    // user taps "Select Vendor" — by the time they do, the sheet opens with
    // data already sitting there.
    final branchId = context.read<BranchProvider>().selectedBranchId?.toString();
    PartyPrefetch.warmForPurchase(_token, branchId: branchId);

    _barcodeFocusNode.addListener(() {
      if (mounted) setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });

    if (widget.initialVendor != null) {
      final vendor = widget.initialVendor!;
      _selectedVendor = vendor;
      _selectedVendorId = vendor['id'] is int
          ? vendor['id'] as int
          : int.tryParse(vendor['id']?.toString() ?? '');
    }

    void recalc() {
      if (mounted) setState(() {});
    }

    discountController.addListener(recalc);
    taxController.addListener(recalc);

  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _pageFocusNode.dispose();
    discountController.dispose();
    taxController.dispose();
    _vendorFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _vendorController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void _showBranchControlNotice() {
    AppFeedback.warning(
      context,
      'Branch can only be switched from the dedicated Branch Control screen.',
    );
  }

  Future<Map<String, dynamic>?> _openVendorSheet() async {
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: _token),
      ),
    );
  }

  void _applyVendorSelection(Map<String, dynamic>? vendor) {
    if (!mounted) return;
    setState(() {
      _selectedVendor = vendor;
      _selectedVendorId = vendor?['id'] is int
          ? vendor!['id'] as int
          : int.tryParse(vendor?['id']?.toString() ?? '');
      _items = [];
    });
  }

  Future<void> _pickVendor() async {
    final vendor = await _openVendorSheet();
    _applyVendorSelection(vendor);
  }

  void _clearVendorSelection() {
    setState(() {
      _selectedVendor = null;
      _selectedVendorId = null;
      _items = [];
    });
  }

  Future<List<ProductRef>> _queryProducts(String q) async {
    try {
      final res = await _productService.getProducts(
        page: 1,
        search: q,
        vendorId: _selectedVendorId,
      );
      final data = res['data'];
      List list = const [];

      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map && first['products'] is List) {
          list = first['products'] as List;
        }
      }

      double purchasePrice(Map m) {
        for (final key in ['tp', 'purchase_price', 'cost_price', 'unit_price', 'price', 'default_price']) {
          final value = m[key];
          if (value != null) {
            final parsed = double.tryParse(value.toString());
            if (parsed != null) return parsed;
          }
        }
        return 0.0;
      }

      return list.map<ProductRef>((raw) {
        final m = raw as Map<String, dynamic>;
        final id = int.tryParse((m['id'] ?? m['product_id'] ?? 0).toString()) ?? 0;
        return ProductRef(
          id: id,
          name: (m['name'] ?? m['title'] ?? 'Unnamed').toString(),
          tp: purchasePrice(m),
        );
      }).toList(growable: false);
    } catch (_) {
      return const <ProductRef>[];
    }
  }

  Future<void> _addItemManual() async {
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before selecting items.');
      return;
    }
    final alreadySelectedIds = _items
        .map((e) => int.tryParse(e['product_id'].toString()) ?? 0)
        .where((id) => id > 0)
        .toList();

    final alreadySelectedQty = <int, double>{
      for (final item in _items)
        (int.tryParse(item['product_id'].toString()) ?? 0):
            (double.tryParse(item['quantity'].toString()) ?? 1.0),
    }..removeWhere((key, _) => key == 0);

    final picked = await ProductPickerGridSheet.openMulti(
      context,
      token: _token,
      vendorId: _selectedVendorId,
      alreadySelectedIds: alreadySelectedIds,
      alreadySelectedQty: alreadySelectedQty,
      alreadySelectedProducts: _items.map((item) {
        return {
          'id': item['product_id'],
          'name': item['name'],
          'price': item['price'],
          'cost_price': item['cost_price'],
          'wholesale_price': item['wholesale_price'],
        };
      }).toList(),
    );

    if (!mounted || picked == null) return;

    setState(() {
      final next = <Map<String, dynamic>>[];
      for (final selection in picked) {
        final product = (selection['product'] as Map?)?.cast<String, dynamic>();
        if (product == null) continue;

        final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
        if (productId <= 0) continue;

        final qty = (selection['qty'] as num?)?.toDouble() ?? 1.0;
        final unitCost = _purchaseUnitCost(product);
        final existing = _items.where((item) => item['product_id']?.toString() == productId.toString()).firstOrNull;
        final price = existing == null ? unitCost : _toNum(existing['price']);
        final discountPct = existing == null ? 0.0 : _toNum(existing['discount_pct'] ?? existing['discount']);

        next.add({
          'product_id': productId,
          'name': product['name'] ?? product['title'] ?? 'Unnamed product',
          'cost_price': product['cost_price'],
          'wholesale_price': product['wholesale_price'],
          'quantity': qty,
          'price': price,
          'discount_pct': discountPct,
          'received_qty': _receiveNow ? qty : 0.0,
          'total': _lineTotal(price: price, qty: qty, discPct: discountPct),
          // Carry the quantity contract on the line; the picker's product map
          // is not retained.
          ...QuantityRule.fromProduct(product).toRowFields(),
        });
      }
      _items = next;
    });
  }

  /// Adds or updates a single product in [_items] for the purchase flow.
  /// Call inside setState — does NOT call setState itself.
  void _applyPickedProduct(Map<String, dynamic> product, {double qty = 1.0}) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId <= 0) return;
    final pickerAddQty =
        double.tryParse(product['_picker_add_qty']?.toString() ?? '');

    final idx = _items.indexWhere(
      (item) => item['product_id']?.toString() == productId.toString(),
    );

    if (idx != -1) {
      final price = _toNum(_items[idx]['price']);
      final discPct = _toNum(_items[idx]['discount_pct'] ?? 0);
      final targetQty = pickerAddQty != null && pickerAddQty > 0
          ? _toNum(_items[idx]['quantity']) + pickerAddQty
          : qty;
      _items[idx]['quantity'] = targetQty;
      _items[idx]['received_qty'] = _receiveNow ? targetQty : 0.0;
      _items[idx]['total'] =
          _lineTotal(price: price, qty: targetQty, discPct: discPct);
      _items[idx].addAll(QuantityRule.fromProduct(product).toRowFields());
    } else {
      final unitCost = _purchaseUnitCost(product);
      final targetQty = pickerAddQty != null && pickerAddQty > 0
          ? pickerAddQty
          : qty;
      _items.add({
        'product_id': productId,
        'name': product['name'] ?? product['title'] ?? 'Unnamed product',
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        'quantity': targetQty,
        'price': unitCost,
        'discount_pct': 0.0,
        'received_qty': _receiveNow ? targetQty : 0.0,
        'total': _lineTotal(price: unitCost, qty: targetQty, discPct: 0.0),
        ...QuantityRule.fromProduct(product).toRowFields(),
      });
    }
  }

  double _purchaseUnitCost(Map<String, dynamic> product) {
    for (final key in ['purchase_price', 'cost_price', 'tp', 'unit_price', 'price']) {
      final value = product[key];
      if (value != null) {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return 0.0;
  }

  Future<void> _addPaymentDialog() async {
    final amountCtl = TextEditingController(text: _balance > 0 ? _balance.toStringAsFixed(2) : '');
    final referenceCtl = TextEditingController();

    final pmProvider = context.read<PaymentMethodProvider>();
    final methods = pmProvider.activeMethods;

    if (methods.isEmpty) {
      // Fall back to a reload; if still empty, tell the user to configure them.
      await pmProvider.reload();
    }
    final available = pmProvider.activeMethods;
    if (available.isEmpty) {
      if (mounted) {
        AppFeedback.error(context, 'No payment methods configured for this branch.');
      }
      return;
    }

    String method = (pmProvider.defaultMethod ?? available.first).method;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final selected = pmProvider.byCode(method);
          final showReference = selected != null && !selected.affectsCashDrawer;
          return AlertDialog(
            title: const Text('Add Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: available
                      .map((m) => DropdownMenuItem(
                            value: m.method,
                            child: Text(m.displayName),
                          ))
                      .toList(),
                  onChanged: (value) => setLocal(() => method = value ?? method),
                ),
                if (showReference) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenceCtl,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
                      hintText: 'Cheque no, bank ref, approval code…',
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountCtl.text.trim()) ?? 0.0;
                  if (amount <= 0) return;
                  final ref = referenceCtl.text.trim();
                  setState(() => _payments.add({
                        'amount': amount,
                        'method': method,
                        if (ref.isNotEmpty) 'reference': ref,
                      }));
                  Navigator.pop(context);
                },
                child: const Text('Add Payment'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onBarcodeScanned(String code) async {
    final safeCode = code.trim();
    if (safeCode.isEmpty) return;

    final product = await _productService.getProductByBarcode(safeCode, vendorId: _selectedVendorId);
    if (!mounted) return;

    if (product == null) {
      AppFeedback.warning(context, 'Product not found: $safeCode');
      _barcodeController.clear();
      _refocusScanner();
      return;
    }

    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    final unitCost = _purchaseUnitCost(product);

    setState(() {
      final idx = _items.indexWhere((item) => item['product_id']?.toString() == productId.toString());
      if (idx >= 0) {
        final oldQty = _toNum(_items[idx]['quantity']);
        final nextQty = oldQty + 1;
        _items[idx]['quantity'] = nextQty;
        _items[idx]['received_qty'] = _receiveNow ? nextQty : 0.0;
        _items[idx]['total'] = _lineTotal(
          price: _toNum(_items[idx]['price']),
          qty: nextQty,
          discPct: _toNum(_items[idx]['discount_pct'] ?? 0),
        );
      } else {
        _items.add({
          'product_id': productId,
          'name': product['name'] ?? 'Unnamed product',
          'cost_price': product['cost_price'],
          'wholesale_price': product['wholesale_price'],
          'quantity': 1.0,
          'price': unitCost,
          'discount_pct': 0.0,
          'received_qty': _receiveNow ? 1.0 : 0.0,
          'total': _lineTotal(price: unitCost, qty: 1.0, discPct: 0.0),
          ...QuantityRule.fromProduct(product).toRowFields(),
        });
      }
    });

    _barcodeController.clear();
    _refocusScanner();
  }

  void _refocusScanner() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  Widget _hiddenBarcodeInput() {
    return SizedBox(
      height: 1,
      width: 1,
      child: Opacity(
        opacity: 0,
        child: TextField(
          controller: _barcodeController,
          focusNode: _barcodeFocusNode,
          autofocus: false,
          onSubmitted: _onBarcodeScanned,
        ),
      ),
    );
  }

  /// The first line whose quantity (or received quantity) breaks its unit's
  /// rule, or null. Mirrors the backend guard so the purchase is not sent to
  /// be rejected — the backend checks `quantity` and `received_qty`
  /// separately, and so does this.
  String? _firstQuantityViolation() {
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final name = (item['name'] ?? 'item').toString();
      final rule = QuantityRule.fromProduct(item);

      final quantity = _toNum(item['quantity']);
      if (!rule.allows(quantity)) {
        return 'Line ${i + 1} — $name: ${rule.message}';
      }
      if (_receiveNow && item.containsKey('received_qty')) {
        final received = _toNum(item['received_qty']);
        if (!rule.allows(received)) {
          return 'Line ${i + 1} — $name (received): ${rule.message}';
        }
      }
    }
    return null;
  }

  Future<void> _submitPurchase() async {
    if (_items.isEmpty) {
      AppFeedback.warning(context, 'Add at least 1 purchase item.');
      return;
    }

    final quantityViolation = _firstQuantityViolation();
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return;
    }

    final auth = context.read<AuthProvider>();
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;

    if (auth.isMasterAdmin && globalBranchId == null) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before creating purchase.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final itemsPayload = _items.map((item) {
        final quantity = _toNum(item['quantity']);
        final map = <String, dynamic>{
          'product_id': item['product_id'],
          'quantity': quantity,
          'price': _toNum(item['price']),
          'discount': _toNum(item['discount_pct'] ?? item['discount']),
        };
        if (_receiveNow) {
          final received = item.containsKey('received_qty')
              ? _toNum(item['received_qty'])
              : quantity;
          if (received > 0) map['received_qty'] = received > quantity ? quantity : received;
        }
        return map;
      }).toList();

      final uiPayments = List<Map<String, dynamic>>.from(_payments);
      if (_autoCashIfEmpty && uiPayments.isEmpty && _total > 0) {
        // Auto-cash uses the branch's default drawer method, not a literal.
        final defaultCode =
            context.read<PaymentMethodProvider>().defaultMethod?.method ?? 'cash';
        uiPayments.add({'amount': _total, 'method': defaultCode});
      }

      // Send every row as its own payment — never collapse a Cash + Bank split
      // into a single method.
      final paymentsPayload = uiPayments
          .map((p) => <String, dynamic>{
                'amount': _toNum(p['amount']),
                'method': p['method'] ?? 'cash',
                if (p['reference'] != null &&
                    p['reference'].toString().trim().isNotEmpty)
                  'reference': p['reference'],
                if (p['note'] != null && p['note'].toString().trim().isNotEmpty)
                  'note': p['note'],
              })
          .toList();

      final payload = <String, dynamic>{
        if (_selectedVendorId != null) 'vendor_id': _selectedVendorId,
        'discount': _discount,
        'tax': _tax,
        'receive_now': _receiveNow,
        'items': itemsPayload,
        if (paymentsPayload.isNotEmpty) 'payments': paymentsPayload,
      };

      Map<String, dynamic> res;
      try {
        res = await _purchaseService.createPurchase(payload);
      } catch (error) {
        final issue = CreditLimitIssue.fromException(error);
        if (issue == null) rethrow;
        final mayOverride = issue.canOverride &&
            auth.hasPermission('override-party-credit-limit');
        if (!mayOverride) {
          if (!mounted) return;
          AppFeedback.error(context, issue.summary);
          return;
        }
        final reason = await showCreditLimitOverrideDialog(context, issue);
        if (!mounted) return;
        if (reason == null) return;
        payload['credit_limit_override'] = {'reason': reason};
        res = await _purchaseService.createPurchase(payload);
      }
      if (!mounted) return;

      final purchase = res['purchase'];
      final purchaseNo = ((purchase is Map
                  ? purchase['invoice_no'] ?? purchase['id']
                  : null) ??
              res['purchase_no'] ??
              res['invoice_no'] ??
              res['id'] ??
              'purchase')
          .toString();
      final creditLimitNotice =
          CreditLimitIssue.fromWarning(res['credit_limit_warning']);
      _resetForNextPurchase(keepInitialVendor: widget.initialVendor != null);
      if (creditLimitNotice != null) {
        AppFeedback.warning(
          context,
          creditLimitNotice.overrideUsed
              ? 'Purchase $purchaseNo created with an authorized credit-limit override. ${creditLimitNotice.summary}'
              : 'Purchase $purchaseNo created with a credit-limit warning. ${creditLimitNotice.summary}',
        );
      } else {
        AppFeedback.success(
          context,
          'Purchase $purchaseNo created. Ready for next purchase.',
        );
      }

    } catch (e) {
      if (!mounted) return;
      final issue = CreditLimitIssue.fromException(e);
      final message = issue?.summary ??
          (e is ApiException
              ? e.message
              : e.toString().replaceFirst('Exception: ', ''));
      AppFeedback.error(context, message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForNextPurchase({bool keepInitialVendor = false}) {
    setState(() {
      _items = [];
      _payments.clear();
      discountController.text = '0';
      taxController.text = '0';
      _receiveNow = false;
      _autoCashIfEmpty = true;

      if (!keepInitialVendor) {
        _selectedVendor = null;
        _selectedVendorId = null;
      }
    });
  }

  double _toNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  double _lineTotal({required double price, required double qty, required double discPct}) {
    final discount = (discPct / 100.0).clamp(0.0, 1.0);
    final total = qty * price * (1.0 - discount);
    return total.isFinite ? total : 0.0;
  }

  double get _subtotal => _items.fold<double>(0.0, (sum, item) {
        return sum + _lineTotal(
          price: _toNum(item['price']),
          qty: _toNum(item['quantity']),
          discPct: _toNum(item['discount_pct'] ?? item['discount']),
        );
      });

  double get _discount => double.tryParse(discountController.text.trim())?.absOrZero() ?? 0.0;
  double get _tax => double.tryParse(taxController.text.trim())?.absOrZero() ?? 0.0;
  double get _total => _subtotal - _discount + _tax;
  double get _paid => _payments.fold<double>(0.0, (sum, p) => sum + _toNum(p['amount']));
  double get _balance => _total - _paid;

  String _money(num value) => AppCurrency.format(value);

  Color _balanceColor(double balance) {
    if (balance > 0) return AppTheme.danger;
    if (balance < 0) return AppTheme.warning;
    return AppTheme.success;
  }

  Set<int> get _cartProductIds => _items
      .map((item) => int.tryParse(item['product_id']?.toString() ?? ''))
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();

  Map<int, double> get _cartProductQuantities {
    final result = <int, double>{};
    for (final item in _items) {
      final id = int.tryParse(item['product_id']?.toString() ?? '') ?? 0;
      final qty = _toNum(item['quantity']);
      if (id <= 0 || qty <= 0) continue;
      result[id] = (result[id] ?? 0) + qty;
    }
    return result;
  }

  Widget _buildPurchaseVendorStrip({
    required bool branchMissing,
  }) {
    String vendorLabelOf(Map<String, dynamic> vendor) {
      final first = (vendor['first_name'] ??
              vendor['company_name'] ??
              vendor['name'] ??
              '')
          .toString();
      final last = (vendor['last_name'] ?? '').toString();
      return '$first ${last.isNotEmpty ? last : ''}'.trim();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: PartyAutocompleteField<Map<String, dynamic>>(
              label: 'Vendor',
              hintText: 'Type vendor name…',
              focusNode: _vendorFocusNode,
              controller: _vendorController,
              getCachedItems: () =>
                  VendorPickCache.cache.peek(VendorPickCache.keyFor())?.items ??
                  const [],
              onSearchRemote: (query) =>
                  VendorPickCache.searchRemote(VendorService(token: _token), query),
              labelOf: vendorLabelOf,
              idOf: (vendor) => (vendor['id'] ?? '').toString(),
              selectedLabel: _selectedVendor == null
                  ? null
                  : vendorLabelOf(_selectedVendor!),
              selectedSubtitle: _selectedVendor == null
                  ? null
                  : (_selectedVendor!['phone'] ?? '').toString(),
              onSelected: _applyVendorSelection,
              onCleared: _clearVendorSelection,
              onBrowseAll: _openVendorSheet,
            ),
          ),
          if (branchMissing) ...[
            const SizedBox(width: 8),
            Tooltip(
              message:
                  'Select a working branch from Branch Control before creating a purchase.',
              child: InkWell(
                onTap: _showBranchControlNotice,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(.10),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: AppTheme.warning.withOpacity(.30),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppTheme.warning),
                      SizedBox(width: 5),
                      Text(
                        'Branch required',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPurchaseInputRow() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: PartyAutocompleteField<Map<String, dynamic>>(
              label: 'Add product',
              hintText: 'Type product name, SKU or barcode…',
              focusNode: _productSearchFocusNode,
              controller: _productSearchController,
              getCachedItems: () =>
                  ProductPickCache.cache
                      .peek(ProductPickCache.keyFor(vendorId: _selectedVendorId))
                      ?.items ??
                  const [],
              onSearchRemote: (query) => ProductPickCache.searchRemote(
                _productService,
                query,
                vendorId: _selectedVendorId,
              ),
              labelOf: (product) => (product['name'] ?? '').toString(),
              subtitleOf: (product) =>
                  (product['sku'] ?? product['barcode'] ?? '').toString(),
              idOf: (product) => (product['id'] ?? '').toString(),
              onSelected: (product) {
                setState(() => _applyPickedProduct(product));
                _productSearchController.clear();
              },
              onBrowseAll: () async {
                await _addItemManual();
                return null;
              },
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Focus barcode scanner  (F9)',
            child: InkWell(
              onTap: () {
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted) _barcodeFocusNode.requestFocus();
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _scannerEnabled
                      ? AppTheme.success.withOpacity(.10)
                      : AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _scannerEnabled
                        ? AppTheme.success.withOpacity(.40)
                        : AppTheme.border,
                  ),
                ),
                child: Icon(
                  _scannerEnabled
                      ? Icons.check_circle_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 16,
                  color: _scannerEnabled
                      ? AppTheme.success
                      : AppTheme.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Add items  (F2)',
            child: OutlinedButton.icon(
              onPressed: _addItemManual,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('F2', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseTableHeader() {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('Product', style: style)),
          Expanded(
            flex: 2,
            child: Text('Cost', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Disc', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Text('Qty', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildPurchaseSummaryRow() {
    InputDecoration compactDecoration() => InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: AppTheme.surfaceSoft,
      child: Row(
        children: [
          Text(
            '${_items.length} item${_items.length == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Sub: ${_money(_subtotal)}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const Spacer(),
          const Text(
            'Disc(-):',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 72,
            height: 34,
            child: TextField(
              controller: discountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: compactDecoration(),
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Tax(+):',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 72,
            height: 34,
            child: TextField(
              controller: taxController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: compactDecoration(),
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Total ${_money(_total)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseCartWorkspace({required bool branchMissing}) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPurchaseVendorStrip(branchMissing: branchMissing),
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          _buildPurchaseInputRow(),
          _buildPurchaseTableHeader(),
          Expanded(
            child: ItemsTable(
              compact: true,
              items: _items,
              onAddItem: _addItemManual,
              onQueryProducts: _queryProducts,
              onItemsChanged: (next) {
                setState(() {
                  _items = next.map((item) {
                    final copy = Map<String, dynamic>.from(item);
                    if (_receiveNow) {
                      copy['received_qty'] = _toNum(copy['quantity']);
                    }
                    return copy;
                  }).toList();
                });
              },
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          _buildPurchaseSummaryRow(),
        ],
      ),
    );
  }

  Widget _buildPaymentStrip() {
    if (_payments.isEmpty) return const SizedBox.shrink();
    final methods = context.read<PaymentMethodProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded,
              size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _payments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) {
                  final payment = _payments[index];
                  final method = methods
                      .displayNameFor(payment['method']?.toString());
                  final amount = _money(_toNum(payment['amount']));
                  final reference =
                      (payment['reference'] ?? '').toString().trim();
                  return InputChip(
                    label: Text(reference.isEmpty
                        ? '$method  $amount'
                        : '$method  $amount · $reference'),
                    onDeleted: () =>
                        setState(() => _payments.removeAt(index)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Paid ${_money(_paid)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Text(
            'Balance ${_money(_balance)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _balanceColor(_balance),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseBottomBar() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Auto Cash',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: .8,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _autoCashIfEmpty,
              onChanged: (value) =>
                  setState(() => _autoCashIfEmpty = value),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: _addPaymentDialog,
            icon: const Icon(Icons.add_card_rounded, size: 16),
            label: Text(_payments.isEmpty ? 'Add Payment' : 'Split / Add'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const Spacer(),
          _PurchaseBottomMetric(label: 'Paid', value: _money(_paid)),
          const SizedBox(width: 16),
          _PurchaseBottomMetric(
            label: 'Balance',
            value: _money(_balance),
            valueColor: _balanceColor(_balance),
          ),
          const SizedBox(width: 16),
          _PurchaseBottomMetric(
            label: 'Total',
            value: _money(_total),
            emphasized: true,
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submitPurchase,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _submitting ? 'Saving...' : 'Save Purchase  Ctrl+Enter',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branchProvider = context.watch<BranchProvider>();
    final branchMissing = auth.isMasterAdmin && !branchProvider.hasActiveBranch;
    final width = MediaQuery.of(context).size.width;
    final desktopWorkspace = width >= 1080;
    final branchId =
        int.tryParse(branchProvider.selectedBranchId?.toString() ?? '');

    final workspace = desktopWorkspace
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 57,
                child: _buildPurchaseCartWorkspace(
                  branchMissing: branchMissing,
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppTheme.border,
              ),
              Expanded(
                flex: 43,
                child: PurchaseProductPanel(
                  key: ValueKey(_selectedVendorId),
                  token: _token,
                  vendorId: _selectedVendorId,
                  branchId: branchId,
                  cartProductIds: _cartProductIds,
                  cartProductQuantities: _cartProductQuantities,
                  canCreateVariant: auth.hasPermission('manage-products'),
                  onProductTapped: (product) =>
                      setState(() => _applyPickedProduct(product)),
                  onOpenModal: _addItemManual,
                ),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(
                child: _buildPurchaseCartWorkspace(
                  branchMissing: branchMissing,
                ),
              ),
            ],
          );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) {
        final current = FocusManager.instance.primaryFocus;
        if (current == null || current == _pageFocusNode) {
          _pageFocusNode.requestFocus();
        }
      },
      child: Focus(
        focusNode: _pageFocusNode,
        autofocus: true,
        skipTraversal: true,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            ...posSaveShortcuts(() {
              if (!_submitting) _submitPurchase();
            }),
            const SingleActivator(LogicalKeyboardKey.f2): _addItemManual,
            posCtrl(LogicalKeyboardKey.keyI): _addItemManual,
            posCmd(LogicalKeyboardKey.keyI): _addItemManual,
            const SingleActivator(LogicalKeyboardKey.f3): _pickVendor,
            posCtrlShift(LogicalKeyboardKey.keyV): _pickVendor,
            posCmdShift(LogicalKeyboardKey.keyV): _pickVendor,
            const SingleActivator(LogicalKeyboardKey.f9): () {
              if (mounted) _barcodeFocusNode.requestFocus();
            },
            posCtrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(
                  context,
                  extra: PosShortcutCatalog.purchaseCreate,
                ),
            posCmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(
                  context,
                  extra: PosShortcutCatalog.purchaseCreate,
                ),
            posCtrlShift(LogicalKeyboardKey.keyF): () {
              _vendorController.clear();
              _vendorFocusNode.requestFocus();
            },
            posCtrlShift(LogicalKeyboardKey.keyP): () {
              _productSearchController.clear();
              _productSearchFocusNode.requestFocus();
            },
          },
          child: Scaffold(
            backgroundColor: AppTheme.bg,
            body: Form(
              key: _formKey,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PurchaseStatusBar(
                        light: true,
                        showBackButton: true,
                      ),
                      Expanded(child: workspace),
                      if (_payments.isNotEmpty) _buildPaymentStrip(),
                      _buildPurchaseBottomBar(),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    top: 30,
                    child: _hiddenBarcodeInput(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseBottomMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasized;

  const _PurchaseBottomMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 16 : 13,
            color: valueColor ?? AppTheme.navy,
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

extension _NumX on double {
  double absOrZero() => isFinite ? (this < 0 ? -this : this) : 0.0;
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
