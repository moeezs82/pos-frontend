import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_totals_card.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/widgets/party_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
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
  bool _didAutoOpenPicker = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openItemPickerOnFirstLoad();
    });
  }

  Future<void> _openItemPickerOnFirstLoad() async {
    if (_didAutoOpenPicker || !mounted) return;
    _didAutoOpenPicker = true;
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted || _items.isNotEmpty) return;
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) return;
    // Vendor picker opens first on purchase create — vendor is required before
    // items make sense. Skip straight to product picker if vendor already set.
    if (_selectedVendorId == null) {
      await _pickVendor();
    } else {
      await _addItemManual();
    }
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

    final idx = _items.indexWhere(
      (item) => item['product_id']?.toString() == productId.toString(),
    );

    if (idx != -1) {
      final price = _toNum(_items[idx]['price']);
      final discPct = _toNum(_items[idx]['discount_pct'] ?? 0);
      _items[idx]['quantity'] = qty;
      _items[idx]['received_qty'] = _receiveNow ? qty : 0.0;
      _items[idx]['total'] = _lineTotal(price: price, qty: qty, discPct: discPct);
    } else {
      final unitCost = _purchaseUnitCost(product);
      _items.add({
        'product_id': productId,
        'name': product['name'] ?? product['title'] ?? 'Unnamed product',
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        'quantity': qty,
        'price': unitCost,
        'discount_pct': 0.0,
        'received_qty': _receiveNow ? qty : 0.0,
        'total': _lineTotal(price: unitCost, qty: qty, discPct: 0.0),
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

  Future<void> _submitPurchase() async {
    if (_items.isEmpty) {
      AppFeedback.warning(context, 'Add at least 1 purchase item.');
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

      final res = await _purchaseService.createPurchase(payload);
      if (!mounted) return;

      final purchaseNo = (res['purchase_no'] ?? res['invoice_no'] ?? res['id'] ?? 'purchase').toString();
      _resetForNextPurchase(keepInitialVendor: widget.initialVendor != null);
      AppFeedback.success(context, 'Purchase $purchaseNo created. Ready for next purchase.');

      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _items.isEmpty) _addItemManual();
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branchProvider = context.watch<BranchProvider>();
    final isBranchMissing = auth.isMasterAdmin && !branchProvider.hasActiveBranch;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 1080;

    final vendorLabel = _selectedVendor == null
        ? 'No vendor selected'
        : ([
              _selectedVendor?['company_name'],
              _selectedVendor?['name'],
              '${_selectedVendor?['first_name'] ?? ''} ${_selectedVendor?['last_name'] ?? ''}'.trim(),
            ].where((value) => value != null && value.toString().trim().isNotEmpty).firstOrNull
                ?.toString() ??
            'Selected vendor');

    final purchaseSetupPanel = Column(
      children: [
        _PurchasePartyPanel(
          isAll: isBranchMissing,
          vendorLabel: vendorLabel,
          branchLabel: branchProvider.label,
          hasVendor: _selectedVendor != null,
          onPickVendor: _pickVendor,
          onClearVendor: _clearVendorSelection,
          onPickBranch: _showBranchControlNotice,
          token: _token,
          selectedVendor: _selectedVendor,
          onBrowseVendorSheet: _openVendorSheet,
          onApplyVendor: _applyVendorSelection,
          vendorFocusNode: _vendorFocusNode,
          vendorController: _vendorController,
        ),
        const SizedBox(height: 14),
        _PurchaseOptionsPanel(
          receiveNow: _receiveNow,
          onReceiveNowChanged: (value) {
            setState(() {
              _receiveNow = value;
              for (final item in _items) {
                final qty = _toNum(item['quantity']);
                item['received_qty'] = value ? qty : 0.0;
              }
            });
          },
        ),
      ],
    );

    final itemsPanel = Column(
      children: [
        _PurchaseScannerPanel(
          scannerEnabled: _scannerEnabled,
          onActivateScanner: () {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) _barcodeFocusNode.requestFocus();
            });
          },
          onOpenPicker: _addItemManual,
        ),
        const SizedBox(height: 10),
        PartyAutocompleteField<Map<String, dynamic>>(
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
          labelOf: (p) => (p['name'] ?? '').toString(),
          subtitleOf: (p) => (p['sku'] ?? p['barcode'] ?? '').toString(),
          idOf: (p) => (p['id'] ?? '').toString(),
          onSelected: (p) => setState(() => _applyPickedProduct(p)),
          onBrowseAll: () async {
            final alreadySelectedIds = _items
                .map((e) => int.tryParse(e['product_id'].toString()) ?? 0)
                .where((id) => id > 0)
                .toList();
            final alreadySelectedQty = <int, double>{
              for (final it in _items)
                (int.tryParse(it['product_id'].toString()) ?? 0):
                    (double.tryParse(it['quantity'].toString()) ?? 1.0),
            }..removeWhere((k, _) => k == 0);
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
            if (picked != null) {
              setState(() {
                for (final x in picked) {
                  final product =
                      (x['product'] as Map?)?.cast<String, dynamic>();
                  final qty = (x['qty'] as num?)?.toDouble() ?? 1.0;
                  if (product != null) _applyPickedProduct(product, qty: qty);
                }
              });
            }
            return null; // adding already happened above
          },
          // selectedLabel intentionally omitted — keeps field open after each add
        ),
        const SizedBox(height: 14),
        ItemsTable(
          items: _items,
          onAddItem: _addItemManual,
          onQueryProducts: _queryProducts,
          onItemsChanged: (next) {
            setState(() {
              _items = next.map((item) {
                final copy = Map<String, dynamic>.from(item);
                if (_receiveNow) copy['received_qty'] = _toNum(copy['quantity']);
                return copy;
              }).toList();
            });
          },
        ),
      ],
    );

    final paymentAndTotalsPanel = Column(
      children: [
        _PurchasePaymentsCard(
          payments: _payments,
          autoCashIfEmpty: _autoCashIfEmpty,
          onToggleAutoCash: (value) => setState(() => _autoCashIfEmpty = value),
          onAddPayment: _addPaymentDialog,
          onRemovePayment: (index) => setState(() => _payments.removeAt(index)),
        ),
        const SizedBox(height: 14),
        TotalsCardInline(
          subtotal: _money(_subtotal),
          discountController: discountController,
          taxController: taxController,
          total: _money(_total),
          paid: _money(_paid),
          balance: _money(_balance),
          balanceColor: _balanceColor(_balance),
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
            const SingleActivator(LogicalKeyboardKey.f2): () => _addItemManual(),
            posCtrl(LogicalKeyboardKey.keyI): () => _addItemManual(),
            posCmd(LogicalKeyboardKey.keyI): () => _addItemManual(),
            const SingleActivator(LogicalKeyboardKey.f3): () => _pickVendor(),
            posCtrlShift(LogicalKeyboardKey.keyV): () => _pickVendor(),
            posCmdShift(LogicalKeyboardKey.keyV): () => _pickVendor(),
            const SingleActivator(LogicalKeyboardKey.f9): () {
              if (mounted) _barcodeFocusNode.requestFocus();
            },
            posCtrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseCreate),
            posCmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseCreate),
            // Field-focus shortcuts — jump directly into autocomplete fields.
            // Ctrl+Shift+V already opens the vendor picker sheet, so vendor
            // field-focus uses Ctrl+Shift+F (Find vendor). Ctrl+Shift+P for
            // product search. Both are ADDITIVE and do not replace any
            // existing binding.
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
      appBar: AppBar(
        title: const Text('Create Purchase'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _addItemManual,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Select items'),
            ),
          ),
          IconButton(
            tooltip: 'Keyboard shortcuts',
            onPressed: () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseCreate),
            icon: const Icon(Icons.keyboard_rounded),
          ),
          const BranchIndicator(tappable: false),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _PurchaseWorkspaceHeader(
                  vendorLabel: vendorLabel,
                  itemCount: _items.length,
                  total: _money(_total),
                  balance: _money(_balance),
                  onAddItems: _addItemManual,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: Column(
                                  children: [
                                    purchaseSetupPanel,
                                    const SizedBox(height: 14),
                                    itemsPanel,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(width: 390, child: paymentAndTotalsPanel),
                            ],
                          )
                        : Column(
                            children: [
                              purchaseSetupPanel,
                              const SizedBox(height: 14),
                              itemsPanel,
                              const SizedBox(height: 14),
                              paymentAndTotalsPanel,
                            ],
                          ),
                  ),
                ),
              ),
              _CreatePurchaseBottomBar(
                itemCount: _items.length,
                total: _money(_total),
                paid: _money(_paid),
                balance: _money(_balance),
                submitting: _submitting,
                onSubmit: _submitPurchase,
              ),
            ],
          ),
          Positioned(left: 0, top: 0, child: _hiddenBarcodeInput()),
        ],
      ),
        ),
      ),
    ),
  );
  }
}

class _PurchaseWorkspaceHeader extends StatelessWidget {
  final String vendorLabel;
  final int itemCount;
  final String total;
  final String balance;
  final VoidCallback onAddItems;

  const _PurchaseWorkspaceHeader({
    required this.vendorLabel,
    required this.itemCount,
    required this.total,
    required this.balance,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final title = Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.shopping_cart_checkout_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Purchase', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      vendorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          );
          final stats = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlainStat(label: 'Items', value: itemCount.toString()),
              _PlainStat(label: 'Total', value: '\$$total'),
              _PlainStat(label: 'Balance', value: '\$$balance'),
            ],
          );
          final button = FilledButton.icon(
            onPressed: onAddItems,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Items'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 12), stats, const SizedBox(height: 12), button],
            );
          }
          return Row(children: [Expanded(child: title), const SizedBox(width: 16), stats, const SizedBox(width: 12), button]);
        },
      ),
    );
  }
}

class _PurchasePartyPanel extends StatelessWidget {
  final bool isAll;
  final String vendorLabel;
  final String branchLabel;
  final bool hasVendor;
  final VoidCallback onPickVendor;
  final VoidCallback onClearVendor;
  final VoidCallback onPickBranch;

  /// Needed to call the live, full-database vendor search as the user
  /// types past whatever's in the local warm cache.
  final String? token;

  /// Optional fast-path: when provided, the vendor field becomes an instant
  /// type-to-search autocomplete over the shared vendor cache, with
  /// "Browse all" still available via the classic full sheet.
  final Map<String, dynamic>? selectedVendor;
  final Future<Map<String, dynamic>?> Function()? onBrowseVendorSheet;
  final void Function(Map<String, dynamic>?)? onApplyVendor;

  /// Optional external focus node / controller for the vendor autocomplete
  /// field so that keyboard shortcuts can jump focus directly into it.
  final FocusNode? vendorFocusNode;
  final TextEditingController? vendorController;

  const _PurchasePartyPanel({
    required this.isAll,
    required this.vendorLabel,
    required this.branchLabel,
    required this.hasVendor,
    required this.onPickVendor,
    required this.onClearVendor,
    required this.onPickBranch,
    this.token,
    this.selectedVendor,
    this.onBrowseVendorSheet,
    this.onApplyVendor,
    this.vendorFocusNode,
    this.vendorController,
  });

  String _vendorLabelOf(Map<String, dynamic> v) {
    final first = (v['first_name'] ?? v['company_name'] ?? v['name'] ?? '').toString();
    final last = (v['last_name'] ?? '').toString();
    return "$first ${last.isNotEmpty ? last : ''}".trim();
  }

  @override
  Widget build(BuildContext context) {
    final vendorField = (onBrowseVendorSheet != null && token != null)
        ? PartyAutocompleteField<Map<String, dynamic>>(
            label: 'Vendor',
            hintText: 'Type vendor name…',
            focusNode: vendorFocusNode,
            controller: vendorController,
            getCachedItems: () =>
                VendorPickCache.cache.peek(VendorPickCache.keyFor())?.items ?? const [],
            onSearchRemote: (query) =>
                VendorPickCache.searchRemote(VendorService(token: token!), query),
            labelOf: _vendorLabelOf,
            idOf: (v) => (v['id'] ?? '').toString(),
            selectedLabel: selectedVendor != null ? _vendorLabelOf(selectedVendor!) : null,
            selectedSubtitle: selectedVendor != null ? (selectedVendor!['phone'] ?? '').toString() : null,
            onSelected: (v) => onApplyVendor?.call(v),
            onCleared: onClearVendor,
            onBrowseAll: onBrowseVendorSheet!,
          )
        : _SelectField(
            label: 'Vendor',
            valueText: vendorLabel,
            icon: Icons.storefront_outlined,
            onTap: onPickVendor,
            showClear: hasVendor,
            onClear: onClearVendor,
          );

    final fields = <Widget>[
      vendorField,
      if (isAll)
        const _BranchRequiredNotice(),
    ];

    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Purchase setup',
            subtitle: 'Select vendor before adding supplier items.',
            icon: Icons.receipt_long_outlined,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 700 || fields.length == 1) {
                return Column(
                  children: fields
                      .map((field) => Padding(padding: const EdgeInsets.only(bottom: 10), child: field))
                      .toList(),
                );
              }
              return Row(
                children: [
                  for (int i = 0; i < fields.length; i++) ...[
                    if (i != 0) const SizedBox(width: 10),
                    Expanded(child: fields[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}


class _BranchRequiredNotice extends StatelessWidget {
  const _BranchRequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withOpacity(.28)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppTheme.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Select a working branch from Branch Control before creating a purchase.',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navy),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseOptionsPanel extends StatelessWidget {
  final bool receiveNow;
  final ValueChanged<bool> onReceiveNowChanged;

  const _PurchaseOptionsPanel({required this.receiveNow, required this.onReceiveNowChanged});

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(receiveNow ? Icons.inventory_rounded : Icons.pending_actions_rounded,
              color: receiveNow ? AppTheme.success : AppTheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Receiving mode', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text(
                  'Turn on if goods are received immediately with this purchase.',
                  style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Switch(value: receiveNow, onChanged: onReceiveNowChanged),
        ],
      ),
    );
  }
}

class _PurchaseScannerPanel extends StatelessWidget {
  final bool scannerEnabled;
  final VoidCallback onActivateScanner;
  final VoidCallback onOpenPicker;

  const _PurchaseScannerPanel({
    required this.scannerEnabled,
    required this.onActivateScanner,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(scannerEnabled ? Icons.check_circle_rounded : Icons.qr_code_scanner_rounded,
              color: scannerEnabled ? AppTheme.success : AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              scannerEnabled ? 'Scanner active' : 'Search supplier products or scan barcode',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onActivateScanner,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Scan'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onOpenPicker,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Items'),
          ),
        ],
      ),
    );
  }
}


class _PurchasePaymentsCard extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final bool autoCashIfEmpty;
  final ValueChanged<bool> onToggleAutoCash;
  final VoidCallback onAddPayment;
  final void Function(int index) onRemovePayment;

  const _PurchasePaymentsCard({
    required this.payments,
    required this.autoCashIfEmpty,
    required this.onToggleAutoCash,
    required this.onAddPayment,
    required this.onRemovePayment,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Supplier payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: onAddPayment,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Auto cash if no payment is added',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Switch(value: autoCashIfEmpty, onChanged: onToggleAutoCash),
              ],
            ),
          ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...payments.asMap().entries.map((entry) {
              final index = entry.key;
              final payment = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${AppCurrency.format(payment['amount'])} • ${(payment['method'] ?? '').toString().toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove payment',
                      icon: const Icon(Icons.close_rounded, color: AppTheme.danger),
                      onPressed: () => onRemovePayment(index),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _CreatePurchaseBottomBar extends StatelessWidget {
  final int itemCount;
  final String total;
  final String paid;
  final String balance;
  final bool submitting;
  final VoidCallback onSubmit;

  const _CreatePurchaseBottomBar({
    required this.itemCount,
    required this.total,
    required this.paid,
    required this.balance,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(color: AppTheme.navy.withOpacity(.05), blurRadius: 18, offset: const Offset(0, -8)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EnterpriseStatPill(label: 'Items', value: itemCount.toString(), icon: Icons.inventory_2_outlined, color: AppTheme.primary),
              EnterpriseStatPill(label: 'Total', value: '\$$total', icon: Icons.payments_outlined, color: AppTheme.success),
              EnterpriseStatPill(label: 'Balance', value: '\$$balance', icon: Icons.account_balance_wallet_outlined, color: AppTheme.warning),
            ],
          );
          final button = SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded),
              label: Text(submitting ? 'Saving...' : 'Save Purchase  Ctrl+Enter'),
            ),
          );

          if (constraints.maxWidth < 760) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 10), button]);
          }
          return Row(children: [Expanded(child: info), const SizedBox(width: 12), button]);
        },
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final VoidCallback onTap;
  final bool showClear;
  final VoidCallback? onClear;

  const _SelectField({
    required this.label,
    required this.valueText,
    required this.icon,
    required this.onTap,
    this.showClear = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (showClear)
                IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: onClear)
              else
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainStat extends StatelessWidget {
  final String label;
  final String value;

  const _PlainStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
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
