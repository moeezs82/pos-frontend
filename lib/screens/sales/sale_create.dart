import 'dart:async' show Timer;
import 'dart:ui' show FontFeature;

import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/services/offline_invoice_seq_service.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/utils/network_failure.dart';
import 'package:uuid/uuid.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_product_panel.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/sale_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';

// local widgets split into small files
import 'package:enterprise_pos/screens/sales/parts/sale_party_section.dart';

class CreateSaleScreen extends StatefulWidget {
  final Map<String, dynamic>? initialCustomer;

  const CreateSaleScreen({super.key, this.initialCustomer});

  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageFocusNode = FocusNode();

  // selections
  String? _selectedBranchId;
  String? _selectedCustomerId;
  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;
  Map<String, dynamic>? _selectedUser;
  int? _selectedUserId;
  Map<String, dynamic>? _selectedDeliveryBoy;
  int? _selectedDeliveryBoyId;

  // cart & payments
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];

  // Selected tender for the quick single-payment flow. Null falls back to the
  // branch's default drawer method resolved from PaymentMethodProvider.
  String? _saleMethod;
  final saleReferenceController = TextEditingController();

  // discount/tax live controllers (now edited inline in totals)
  final discountController = TextEditingController(text: "0");
  final taxController = TextEditingController(text: "0");
  final cashReceivedController = TextEditingController();

  final TextEditingController addressController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  bool _customerLocked = false;

  // barcode (kept intact)
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;

  // Named focus nodes for keyboard-shortcut field-jumping.
  // Party autocomplete fields (controllers cleared before focus so the field
  // opens with a blank query rather than leftover text).
  final _customerFocusNode = FocusNode();
  final _salesmanFocusNode = FocusNode();
  final _deliveryBoyFocusNode = FocusNode();
  final _vendorFocusNode = FocusNode();
  final _productSearchFocusNode = FocusNode();
  final _customerController = TextEditingController();
  final _salesmanController = TextEditingController();
  final _deliveryBoyController = TextEditingController();
  final _vendorController = TextEditingController();
  final _productSearchController = TextEditingController();
  // Walk-in inline fields
  final _walkInNameFocusNode = FocusNode();
  final _walkInPhoneFocusNode = FocusNode();
  final _walkInAddressFocusNode = FocusNode();
  // Summary / bottom-bar numeric fields (select-all on focus)
  final _discountFocusNode = FocusNode();
  final _taxFocusNode = FocusNode();
  final _cashReceivedFocusNode = FocusNode();

  bool _submitting = false;
  bool _autoCashIfEmpty = true;
  bool _didAutoOpenPicker = false;

  late ProductService _productService;
  late SaleService _saleService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _saleService = SaleService(token: token);

    // Warm customer/salesman/delivery-boy/product caches immediately, in
    // the background, before the user taps any "Select…" button. By the
    // time they actually open a picker a second or two later, it shows
    // cached data instantly instead of a blank spinner.
    final branchId = context.read<BranchProvider>().selectedBranchId?.toString();
    PartyPrefetch.warmForSale(token, branchId: branchId);

    // Offline composition (handover doc G1). Mirror the server catalog
    // (products + price/tax + customers) into local SQLite so a sale can be
    // built with no connectivity and after an app restart — the gap the
    // in-memory-only warm caches above leave open. Then seed the instant
    // pickers from that local cache. All fire-and-forget: if the refresh
    // can't reach the server, the pickers simply read whatever was cached
    // on the last successful sync.
    final branchIdInt = int.tryParse(branchId ?? '');
    _hydrateOfflinePickers(branchIdInt); // immediate, in case we're offline now
    CatalogCacheService.instance
        .refresh(token: token, branchId: branchIdInt)
        .then((_) => _hydrateOfflinePickers(branchIdInt));

    _barcodeFocusNode.addListener(() {
      setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });

    if (widget.initialCustomer != null) {
      final customer = widget.initialCustomer!;
      _selectedCustomer = customer;
      _selectedCustomerId = customer['id']?.toString();
      customerNameController.text = (customer['first_name'] ?? customer['name'] ?? '').toString();
      customerPhoneController.text = (customer['phone'] ?? '').toString();
      addressController.text = (customer['address'] ?? '').toString();
      _customerLocked = _selectedCustomerId != null;
    }

    void _recalc() => setState(() {});
    discountController.addListener(_recalc);
    taxController.addListener(_recalc);
    cashReceivedController.addListener(_recalc);

    // In the 3-panel layout the product grid is always visible — no need to
    // auto-open the picker modal. Focus the center panel search field so
    // the cashier can start typing immediately after navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _productSearchFocusNode.requestFocus();
    });
  }


  /// Seeds the product/customer instant-suggestion buckets from the local
  /// catalog cache so the pickers show data even offline / after a restart.
  void _hydrateOfflinePickers(int? branchIdInt) {
    ProductPickCache.hydrateFromCatalog(vendorId: _selectedVendorId, branchId: branchIdInt);
    CustomerPickCache.hydrateFromCatalog(branchId: branchIdInt);
  }

  Future<void> _openItemPickerOnFirstLoad() async {
    if (_didAutoOpenPicker || !mounted) return;
    _didAutoOpenPicker = true;
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted || _items.isNotEmpty) return;
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) return;
    await _addItemManual();
  }

  @override
  void dispose() {
    discountController.dispose();
    taxController.dispose();
    cashReceivedController.dispose();
    saleReferenceController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _pageFocusNode.dispose();
    addressController.dispose();
    customerNameController.dispose();
    customerPhoneController.dispose();
    _customerFocusNode.dispose();
    _salesmanFocusNode.dispose();
    _deliveryBoyFocusNode.dispose();
    _vendorFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _customerController.dispose();
    _salesmanController.dispose();
    _deliveryBoyController.dispose();
    _vendorController.dispose();
    _productSearchController.dispose();
    _walkInNameFocusNode.dispose();
    _walkInPhoneFocusNode.dispose();
    _walkInAddressFocusNode.dispose();
    _discountFocusNode.dispose();
    _taxFocusNode.dispose();
    _cashReceivedFocusNode.dispose();
    super.dispose();
  }

  // ---------------- Pickers ----------------
  // Future<void> _pickBranch() async {
  //   final token = Provider.of<AuthProvider>(context, listen: false).token!;
  //   final branch = await showModalBottomSheet<Map<String, dynamic>>(
  //     context: context,
  //     builder: (_) => BranchPickerSheet(token: token),
  //   );
  //   if (!mounted) return;
  //   if (branch != null) {
  //     setState(() {
  //       _selectedBranch = branch;
  //       _selectedBranchId = branch['id'].toString();
  //     });
  //   }
  // }

  /// Opens the full customer browse sheet and returns whatever was picked
  /// (null means "cleared / walk-in"). Used both as the manual "Select
  /// Customer" action and as the autocomplete field's "Browse all" fallback.
  Future<Map<String, dynamic>?> _openCustomerSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );
  }

  void _applyCustomerSelection(Map<String, dynamic>? customer) {
    if (!mounted) return;
    if (customer == null) {
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _customerLocked = false;

        // Option A: clear on unselect
        customerNameController.text = "";
        customerPhoneController.text = "";
        addressController.text = "";
      });
    } else {
      final address = (customer['address'] ?? "").toString();
      final name = (customer['first_name'] ?? "").toString();
      final phone = (customer['phone'] ?? "").toString();
      setState(() {
        _selectedCustomer = customer;
        _selectedCustomerId = customer['id'].toString();
        customerNameController.text = name;
        customerPhoneController.text = phone;
        addressController.text = address;

        _customerLocked = true; // lock editing when customer picked
      });
    }
    _restoreSaleScreenFocus();
  }

  Future<void> _pickCustomer() async {
    final customer = await _openCustomerSheet();
    _applyCustomerSelection(customer);
  }

  void _clearCustomerSelection() {
    setState(() {
      _selectedCustomer = null;
      _selectedCustomerId = null;
      _customerLocked = false;
      customerNameController.text = "";
      customerPhoneController.text = "";
      addressController.text = "";
    });
  }

  Future<Map<String, dynamic>?> _openVendorSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorPickerSheet(token: token),
    );
  }

  void _applyVendorSelection(Map<String, dynamic>? vendor) {
    if (!mounted) return;
    setState(() {
      _selectedVendor = vendor;
      _selectedVendorId = _metaInt(vendor?['id']);
      _items = []; // avoid cross-vendor mix
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickVendor() async {
    final vendor = await _openVendorSheet();
    _applyVendorSelection(vendor);
  }

  String _effectiveBranchIdStr() {
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    return globalBranchId?.toString() ?? _selectedBranchId ?? '';
  }

  Future<Map<String, dynamic>?> _openUserSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(token: token, branchId: _effectiveBranchIdStr()),
    );
  }

  void _applyUserSelection(Map<String, dynamic>? user) {
    if (!mounted) return;
    setState(() {
      _selectedUser = user;
      _selectedUserId = _metaInt(user?['id']);
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickUser() async {
    final user = await _openUserSheet();
    _applyUserSelection(user);
  }

  Future<Map<String, dynamic>?> _openDeliveryBoySheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(
        token: token,
        branchId: _effectiveBranchIdStr(),
        role: 'delivery',
        title: 'Select Delivery Boy',
        searchHint: 'Search delivery boy by name, email, phone…',
        allowQuickAdd: false,
      ),
    );
  }

  void _applyDeliveryBoySelection(Map<String, dynamic>? user) {
    if (!mounted) return;
    setState(() {
      _selectedDeliveryBoy = user;
      _selectedDeliveryBoyId = _metaInt(user?['id']);
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickDeliveryBoy() async {
    final user = await _openDeliveryBoySheet();
    _applyDeliveryBoySelection(user);
  }

  // ---------------- Items ----------------

  /// Centralized single-product add for barcode, autocomplete, and product
  /// panel taps. If a compatible positive-qty row already exists it is
  /// incremented by 1; otherwise a new row is appended.
  ///
  /// "Compatible" means same [product_id] AND non-negative quantity so that
  /// deliberate inline-return rows (negative qty) are never merged into a
  /// normal sale line.
  ///
  /// Call inside setState — does NOT call setState itself.
  void _addOrIncrementProduct(Map<String, dynamic> product) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;

    final price = double.tryParse(product['price']?.toString() ?? '') ?? 0.0;

    final idx = _items.indexWhere((it) {
      final existingId =
          int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
      if (existingId != productId) return false;
      // Do not merge into inline-return (negative-qty) rows.
      final existingQty =
          double.tryParse(it['quantity']?.toString() ?? '') ?? 0.0;
      return existingQty >= 0;
    });

    if (idx != -1) {
      // Increment quantity while preserving edited price and discount.
      final existingQty =
          double.tryParse(_items[idx]['quantity']?.toString() ?? '') ?? 0.0;
      final newQty = existingQty + 1.0;
      final discPct =
          double.tryParse(_items[idx]['discount_pct']?.toString() ?? '') ?? 0.0;
      final rowPrice =
          double.tryParse(_items[idx]['price']?.toString() ?? '') ?? price;
      _items[idx]['quantity'] = newQty;
      _items[idx]['total'] =
          _lineTotal(price: rowPrice, qty: newQty, discPct: discPct);
    } else {
      _items.add({
        'product_id': productId,
        'name': product['name'],
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        'quantity': 1.0,
        'price': price,
        'discount_pct': 0.0,
        'total': _lineTotal(price: price, qty: 1.0, discPct: 0.0),
      });
    }
  }

  /// Sets a product's cart quantity to an explicit [qty] value (used only by
  /// the F2 multi-select picker where the user has intentionally specified the
  /// quantity). Preserves the existing row's price and discount when updating.
  ///
  /// For all single-product entry points (barcode, autocomplete, product-panel
  /// tap) use [_addOrIncrementProduct] instead.
  ///
  /// Call inside setState — does NOT call setState itself.
  void _applyPickedProduct(Map<String, dynamic> product, {double qty = 1.0}) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;

    final price = double.tryParse(product['price']?.toString() ?? '') ?? 0.0;

    final idx = _items.indexWhere(
      (it) => (int.tryParse(it["product_id"].toString()) ?? 0) == productId,
    );

    if (idx != -1) {
      _items[idx]["quantity"] = qty;
      final discPct =
          double.tryParse(_items[idx]["discount_pct"]?.toString() ?? '') ?? 0.0;
      final rowPrice =
          double.tryParse(_items[idx]["price"]?.toString() ?? '') ?? price;
      _items[idx]["total"] = _lineTotal(price: rowPrice, qty: qty, discPct: discPct);
    } else {
      _items.add({
        "product_id": productId,
        "name": product['name'],
        "cost_price": product['cost_price'],
        "wholesale_price": product['wholesale_price'],
        "quantity": qty,
        "price": price,
        "discount_pct": 0.0,
        "total": _lineTotal(price: price, qty: qty, discPct: 0.0),
      });
    }
  }

  Future<void> _addItemManual() async {
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before selecting items.');
      return;
    }
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    // ✅ Already selected products in cart/items (for preselect)
    final alreadySelectedIds = _items
        .map((e) => int.tryParse(e["product_id"].toString()) ?? 0)
        .where((id) => id > 0)
        .toList();

    // ✅ Already selected qty map (id -> qty)
    final alreadySelectedQty = <int, double>{
      for (final it in _items)
        (int.tryParse(it["product_id"].toString()) ?? 0):
            (double.tryParse(it["quantity"].toString()) ?? 1.0),
    }..removeWhere((k, _) => k == 0);

    final picked = await ProductPickerGridSheet.openMulti(
      context,
      token: token,
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

    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final x in picked) {
        final product = (x["product"] as Map?)?.cast<String, dynamic>();
        final qty = (x["qty"] as num?)?.toDouble() ?? 1.0;
        if (product == null) continue;
        _applyPickedProduct(product, qty: qty);
      }
    });
  }

  void _editItem(int index) {
    final item = _items[index];
    final qtyController = TextEditingController(
      text: item['quantity'].toString(),
    );
    final priceController = TextEditingController(
      text: item['price'].toString(),
    );

    final costPrice = item['cost_price'] ?? 0.0;
    final wholesalePrice = item['wholesale_price'] ?? 0.0;

    bool showHidden = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text("Edit ${item['name']}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: "Quantity"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Sale Price"),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: Icon(
                    showHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(
                    showHidden ? "Hide Cost/Wholesale" : "Show Cost/Wholesale",
                  ),
                  onPressed: () => setLocal(() => showHidden = !showHidden),
                ),
                if (showHidden) ...[
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Cost Price: \$${costPrice.toString()}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          "Wholesale Price: \$${wholesalePrice.toString()}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _items[index]['quantity'] =
                        double.tryParse(qtyController.text.trim()) ?? 1.0;
                    _items[index]['price'] =
                        double.tryParse(priceController.text) ?? 0.0;
                  });
                  Navigator.pop(context);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Barcode ----------------
  Future<void> _onBarcodeScanned(String code) async {
    if (code.isEmpty) return;

    // Try the live lookup first; if the server is unreachable, fall back to
    // the local catalog cache so scanning still works offline (handover doc
    // G1). getProductByBarcode returns null for "not found" and throws for a
    // network error — both fall through to the cache.
    Map<String, dynamic>? product;
    try {
      product = await _productService.getProductByBarcode(
        code,
        vendorId: _selectedVendorId,
      );
    } catch (_) {
      product = null;
    }
    product ??= await CatalogCacheService.instance.productByBarcode(
      code,
      branchId: int.tryParse(_effectiveBranchIdStr()),
      vendorId: _selectedVendorId,
    );
    if (product != null) {
      // Capture into a final local so Dart flow analysis narrows the type
      // inside the setState closure (local variable reassigned via ??= above
      // prevents automatic narrowing inside lambdas).
      final p = product;
      // Use the centralized merge method so repeated scans of the same
      // barcode increment the existing cart row instead of creating duplicates.
      setState(() => _addOrIncrementProduct(p));
    } else {
      if (!mounted) return;
      AppFeedback.warning(context, "Product not found: $code");
    }
    _barcodeController.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  double _lineTotal({
    required double price,
    required double qty,
    required double discPct,
  }) {
    final d = (discPct / 100.0).clamp(0.0, 100.0);
    final t = qty * price * (1.0 - d);
    return t.isFinite ? t : 0.0;
  }

  Widget _hiddenBarcodeField() {
    return SizedBox(
      width: 1,
      height: 1,
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


  double _metaNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _metaText(dynamic value) => (value ?? '').toString().trim();

  Map<String, dynamic>? _partySnapshot(
    Map<String, dynamic>? source, {
    dynamic id,
    String fallbackName = '',
  }) {
    if (source == null && id == null && fallbackName.trim().isEmpty) return null;

    dynamic read(String key) => source == null ? null : source[key];

    final firstName = _metaText(read('first_name'));
    final lastName = _metaText(read('last_name'));
    final directName = _metaText(read('name'));
    final fallback = fallbackName.trim();
    final combinedName = directName.isNotEmpty
        ? directName
        : [firstName, lastName].where((v) => v.isNotEmpty).join(' ').trim();

    final snapshot = <String, dynamic>{};
    final resolvedId = id ?? read('id');
    if (resolvedId != null) snapshot['id'] = resolvedId;

    final resolvedName = combinedName.isNotEmpty ? combinedName : fallback;
    if (resolvedName.isNotEmpty) snapshot['name'] = resolvedName;

    for (final key in const ['first_name', 'last_name', 'phone', 'mobile', 'email', 'address']) {
      final value = _metaText(read(key));
      if (value.isNotEmpty) snapshot[key] = value;
    }

    return snapshot.isEmpty ? null : snapshot;
  }

  Map<String, dynamic> _buildSaleMeta({
    required String? effectiveBranchId,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paid,
    required double balance,
    required double cashReceived,
    required double changeAmount,
    required List<Map<String, dynamic>> paymentsToSend,
  }) {
    final typedPayments = paymentsToSend.map((payment) {
      return <String, dynamic>{
        'method': _metaText(payment['method']).isEmpty
            ? 'cash'
            : _metaText(payment['method']),
        'amount': _metaNum(payment['amount']),
      };
    }).toList(growable: false);

    final customerSnapshot = <String, dynamic>{
      if (_selectedCustomerId != null) 'id': _selectedCustomerId,
      'name': customerNameController.text.trim().isEmpty
          ? (_metaText(_selectedCustomer?['first_name']).isEmpty
              ? 'Walk-in customer'
              : [
                  _metaText(_selectedCustomer?['first_name']),
                  _metaText(_selectedCustomer?['last_name']),
                ].where((v) => v.isNotEmpty).join(' ').trim())
          : customerNameController.text.trim(),
      'phone': customerPhoneController.text.trim(),
      'address': addressController.text.trim(),
    };

    final meta = <String, dynamic>{
      'customer_snapshot': customerSnapshot,
      'branch_snapshot': {
        if (effectiveBranchId != null && effectiveBranchId.isNotEmpty)
          'id': effectiveBranchId,
        if (_selectedBranch != null) ...{
          if (_selectedBranch!['name'] != null) 'name': _selectedBranch!['name'],
          if (_selectedBranch!['location'] != null) 'location': _selectedBranch!['location'],
        },
      },
      'salesman_snapshot': _partySnapshot(
        _selectedUser,
        id: _selectedUserId,
        fallbackName: _metaText(_selectedUser?['name']),
      ),
      'delivery_boy_snapshot': _partySnapshot(
        _selectedDeliveryBoy,
        id: _selectedDeliveryBoyId,
        fallbackName: _metaText(_selectedDeliveryBoy?['name']),
      ),
      'vendor_snapshot': _partySnapshot(
        _selectedVendor,
        id: _selectedVendorId,
      ),
      'totals_snapshot': {
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'delivery': 0.0,
        'total': total,
        'paid': paid,
        'balance': balance,
      },
      'payments_snapshot': typedPayments,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
      'delivery': 0.0,
      'sale_type': _selectedDeliveryBoyId != null ? 'delivery' : 'counter',
    };

    meta.removeWhere((_, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty));
    return meta;
  }

  // ---------------- Submit ----------------
  Future<void> _submitSale() async {
    if (_items.isEmpty) {
      AppFeedback.warning(context, "Add at least 1 item before creating sale.");
      return;
    }

    final auth = context.read<AuthProvider>();
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final effectiveBranchId = globalBranchId?.toString() ?? _selectedBranchId;

    if (auth.isMasterAdmin && globalBranchId == null) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before creating sale.');
      return;
    }
    double _rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final price = _rowNum(i['price']);
      final qty = _rowNum(i['quantity']);
      final disc = _rowNum(i['discount_pct']); // may be null -> 0
      return sum + _lineTotal(price: price, qty: qty, discPct: disc);
    });
    double discount = double.tryParse(discountController.text.trim()) ?? 0.0;
    double tax = double.tryParse(taxController.text.trim()) ?? 0.0;
    double total = subtotal - discount + tax;

    // Resolve the selected tender (falls back to the branch default drawer
    // method). Reference only applies to non-drawer methods (KNET/card/bank…).
    final pmProvider = context.read<PaymentMethodProvider>();
    final effectiveMethod =
        _saleMethod ?? pmProvider.defaultMethod?.method ?? 'cash';
    final isDrawerMethod =
        pmProvider.byCode(effectiveMethod)?.affectsCashDrawer ??
            (effectiveMethod == 'cash');
    final saleReference = saleReferenceController.text.trim();

    final List<Map<String, dynamic>> paymentsToSend = [];
    if (_autoCashIfEmpty && total > 0) {
      paymentsToSend.add({
        "amount": total.toStringAsFixed(2),
        "method": effectiveMethod,
        if (!isDrawerMethod && saleReference.isNotEmpty)
          "reference": saleReference,
      });
    }
    final Map<String, dynamic>? refundToSend =
        _autoCashIfEmpty && total < 0
        ? {
            'amount': total.abs().toStringAsFixed(2),
            'method': effectiveMethod,
            if (!isDrawerMethod && saleReference.isNotEmpty)
              'reference': saleReference,
          }
        : null;

    final paid = paymentsToSend.fold<double>(
      0.0,
      (sum, payment) => sum + _metaNum(payment['amount']),
    );
    final balance = total - paid;

    final enteredCashReceived = _toDouble(cashReceivedController);
    final cashReceived = enteredCashReceived > 0
        ? enteredCashReceived
        : (_autoCashIfEmpty && total > 0 ? total : 0.0);
    final changeAmount = total > 0
        ? (cashReceived - total).clamp(0.0, double.infinity).toDouble()
        : 0.0;

    setState(() => _submitting = true);

    // Every sale gets a client_ref, online or offline (handover doc §2.2) —
    // this is the idempotency key the backend uses to guarantee a synced
    // offline sale (or a retried/double-tapped submit) never creates a
    // duplicate row. occurred_at is the on-device timestamp captured right
    // now, at the moment "Save Sale" was pressed, so the sale still posts
    // and reports as having happened today even if it ends up queued and
    // synced later (§1.3).
    final clientRef = const Uuid().v4();
    final occurredAt = DateTime.now();

    // Generate a customer-friendly offline invoice reference.  This is
    // generated up-front for EVERY sale (online or offline) so:
    //   • The same reference is printed on the receipt and stored on the
    //     server record, enabling "find this receipt" searches later.
    //   • The UUID client_ref remains internal (idempotency only).
    //   • Online sales that succeed immediately also carry offline_invoice_no
    //     so that receipts and server records are always cross-searchable.
    final shiftProvider = context.read<RegisterShiftProvider>();
    final registerCode =
        shiftProvider.shift?['register']?['code']?.toString() ?? 'REG';
    final branchIdForSeq =
        (globalBranchId ?? int.tryParse(_selectedBranchId ?? '0') ?? 0);

    String? offlineInvoiceNo;
    try {
      offlineInvoiceNo = await OfflineInvoiceSeqService.instance.next(
        branchId: branchIdForSeq,
        registerCode: registerCode,
        occurredAt: occurredAt,
      );
    } catch (e, s) {
      // Non-fatal: fall back to null — the sale can still proceed without it.
      debugPrint('offline_invoice_seq error: $e');
      debugPrintStack(stackTrace: s);
    }

    Map<String, dynamic>? res;
    var queuedOffline = false;

    try {
      final meta = _buildSaleMeta(
        effectiveBranchId: effectiveBranchId,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        total: total,
        paid: paid,
        balance: balance,
        cashReceived: cashReceived,
        changeAmount: changeAmount,
        paymentsToSend: paymentsToSend,
      );
      if (refundToSend != null) {
        meta['refund_snapshot'] = {
          'amount': total.abs(),
          'method': effectiveMethod,
        };
      }
      final payload = _saleService.buildSalePayload(
        branchId: effectiveBranchId,
        customerId: _selectedCustomerId != null
            ? int.tryParse(_selectedCustomerId!)
            : null,
        vendorId: _selectedVendorId,
        userId: _selectedUserId,
        deliveryBoyId: _selectedDeliveryBoyId,
        saleType: _selectedDeliveryBoyId != null ? 'delivery' : null,
        items: _items,
        payments: paymentsToSend,
        refund: refundToSend,
        discount: discount,
        tax: tax,
        meta: meta,
        clientRef: clientRef,
        occurredAt: occurredAt,
        offlineInvoiceNo: offlineInvoiceNo,
      );

      String? queueReason;

      try {
        res = await _saleService
            .createSaleFromPayload(payload)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // Queue on ANY failed submit — not just a network-unreachable one —
        // so the cashier can always keep working instead of getting stuck.
        // The reason is stored alongside the queued sale purely for
        // visibility on the sync screen; it doesn't change what happens
        // next. The actual Sync Now attempt (OfflineSyncService) still
        // correctly tells apart "still offline, keep retrying" from "real
        // error, needs a human" — a genuinely broken item (e.g. a deleted
        // product) will surface as failed on its first sync attempt rather
        // than looping forever, so widening the net here is safe.
        queueReason = isNetworkFailure(e)
            ? 'Offline: could not reach the server ($e).'
            : 'Server responded with an error, queued for review on sync: $e';

        await OfflineSalesQueueService.instance.enqueue(
          clientRef: clientRef,
          payload: payload,
          occurredAt: occurredAt,
          offlineInvoiceNo: offlineInvoiceNo,
          initialError: queueReason,
        );
        queuedOffline = true;
        if (mounted) {
          // ignore: use_build_context_synchronously
          context.read<OfflineQueueProvider>().refresh();
        }
      }

      // receiptNo: prefer the server-confirmed invoice number for online
      // sales; use the customer-friendly offline reference for queued sales.
      // Never expose the UUID client_ref on a customer-facing receipt.
      final receiptNo = queuedOffline
          ? (offlineInvoiceNo ?? 'OFF-PENDING')
          : (res?['data']?['invoice_no'] ??
                  res?['data']?['sale']?['invoice_no'] ??
                  res?['data']?['id'] ??
                  'N/A')
              .toString();

      final receiptItems = _items.map((i) {
        final name = (i['name'] ?? '').toString();
        final price = double.tryParse(i['price']?.toString() ?? '') ?? 0.0;
        final qty = double.tryParse(i['quantity']?.toString() ?? '') ?? 0.0;
        final lineTotal =
            double.tryParse(i['total']?.toString() ?? '') ?? (price * qty);
        return SaleReceiptItem(
          name: name,
          price: price,
          qty: qty,
          total: lineTotal,
        );
      }).toList();
      final printerConfig = context.read<PrinterConfigProvider>();

      if (!printerConfig.isConfigured) {
        try {
          final token = context.read<AuthProvider>().token;
          if (token != null) await printerConfig.refresh(token);
        } catch (e, s) {
          debugPrint('Printer config refresh failed: $e');
          debugPrintStack(stackTrace: s);
        }
      }

      final effectiveShopName = printerConfig.shopName.isNotEmpty ? printerConfig.shopName : 'My Shop';
      final effectiveShopAddress = printerConfig.shopAddress.isNotEmpty ? printerConfig.shopAddress : null;
      final effectiveShopPhone = printerConfig.shopPhone.isNotEmpty ? printerConfig.shopPhone : null;
      final mainTemplate = printerConfig.mainInvoiceTemplate;
      final kitchenTemplate = printerConfig.kitchenInvoiceTemplate;
      final footerLines = printerConfig.footerLines;

      debugPrint('Active printer connection: ${printerConfig.activeConnection}, template: ${mainTemplate.value}');

      var printedToHardware = false;
      if (printerConfig.isNetworkPrinter && (printerConfig.networkIp ?? '').trim().isNotEmpty) {
        try {
          await ThermalPrinterService.instance.printSaleReceiptNetwork(
            printerIp: printerConfig.networkIp!.trim(),
            port: printerConfig.networkPort,
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: DateTime.now(),
            items: receiptItems,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: meta,
            sections: mainTemplate.sections,
            paperWidth: mainTemplate.paperWidthCode,
            footerLines: footerLines,
          );
          printedToHardware = true;

          if (printerConfig.kitchenPrintEnabled && (printerConfig.kitchenNetworkIp ?? '').trim().isNotEmpty) {
            await ThermalPrinterService.instance.printSaleReceiptNetwork(
              printerIp: printerConfig.kitchenNetworkIp!.trim(),
              port: printerConfig.kitchenNetworkPort,
              shopName: '$effectiveShopName - KITCHEN COPY',
              shopAddress: 'KITCHEN COPY',
              shopPhone: effectiveShopPhone,
              receiptNo: receiptNo,
              dateTime: DateTime.now(),
              items: receiptItems,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              grandTotal: total,
              cashReceived: cashReceived,
              changeAmount: changeAmount,
              meta: meta,
              sections: kitchenTemplate.sections,
              paperWidth: kitchenTemplate.paperWidthCode,
              footerLines: footerLines,
            );
          }
        } catch (e, s) {
          debugPrint('PRINT ERROR (network): $e');
          debugPrintStack(stackTrace: s);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      } else if (printerConfig.isLocalPrinter && (printerConfig.localPrinterName ?? '').trim().isNotEmpty) {
        try {
          await ThermalPrinterService.instance.printSaleReceiptWindows(
            printerName: printerConfig.localPrinterName!.trim(),
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: DateTime.now(),
            items: receiptItems,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: meta,
            sections: mainTemplate.sections,
            paperWidth: mainTemplate.paperWidthCode,
            footerLines: footerLines,
          );
          printedToHardware = true;
        } catch (e, s) {
          debugPrint('PRINT ERROR (local): $e');
          debugPrintStack(stackTrace: s);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      }

      if (!printedToHardware) {
        await ReceiptPreviewService.instance.previewReceipt(
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: DateTime.now(),
          items: receiptItems,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          meta: meta,
          sections: mainTemplate.sections,
          paperWidth: mainTemplate.paperWidthCode,
          footerLines: footerLines,
        );
      }

      if (!mounted) return;
      _resetForNextSale(keepInitialCustomer: widget.initialCustomer != null);
      if (queuedOffline) {
        AppFeedback.warning(
          context,
          "Offline — Pending Sync. Receipt: $receiptNo. ${queueReason ?? ''} Official invoice number will be assigned when synced.",
        );
      } else {
        AppFeedback.success(context, "Sale $receiptNo created successfully. Ready for next sale.");
      }
      // Return focus to the product search panel so the cashier can start
      // the next sale immediately without touching the mouse.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _productSearchFocusNode.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, "Failed to create sale: $e");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForNextSale({bool keepInitialCustomer = false}) {
    setState(() {
      _items = [];
      _payments = [];
      discountController.text = '0';
      taxController.text = '0';
      cashReceivedController.clear();
      saleReferenceController.clear();
      _saleMethod = null;
      _selectedVendor = null;
      _selectedVendorId = null;
      _selectedUser = null;
      _selectedUserId = null;
      _selectedDeliveryBoy = null;
      _selectedDeliveryBoyId = null;
      _autoCashIfEmpty = true;

      if (!keepInitialCustomer) {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _customerLocked = false;
        customerNameController.clear();
        customerPhoneController.clear();
        addressController.clear();
      }
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

      double _tp(Map m) {
        for (final k in [
          'tp',
          'sell_price',
          'price',
          'unit_price',
          'default_price',
        ]) {
          final v = m[k];
          if (v != null) {
            final n = double.tryParse(v.toString());
            if (n != null) return n;
          }
        }
        return 0.0;
      }

      double? _stock(Map m) {
        final raw = m['branch_stock'] ?? m['stock'] ?? m['quantity_in_stock'];
        if (raw == null) return null;
        if (raw is Map) {
          final qty = raw['quantity'] ?? raw['qty'] ?? raw['in_stock'];
          return double.tryParse(qty?.toString() ?? '');
        }
        return double.tryParse(raw.toString());
      }

      return list
          .map<ProductRef>((raw) {
            final m = raw as Map<String, dynamic>;
            return ProductRef(
              id: _metaInt(m['id'] ?? m['product_id']) ?? 0,
              name: (m['name'] ?? m['title'] ?? 'Unnamed').toString(),
              tp: _tp(m),
              sku: (m['sku'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['sku'].toString().trim(),
              barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['barcode'].toString().trim(),
              stock: _stock(m),
              raw: m,
            );
          })
          .toList(growable: false);
    } catch (_) {
      // Offline / server-unreachable fallback: search the local SQLite catalog
      // so the product autocomplete keeps working with no connectivity.
      // Uses the same CatalogCacheService that the barcode scanner already falls
      // back to, giving the cashier a consistent offline experience.
      try {
        final branchIdInt = int.tryParse(_effectiveBranchIdStr());
        final offlineRows = await CatalogCacheService.instance.searchProducts(
          q,
          branchId: branchIdInt,
          vendorId: _selectedVendorId,
          limit: 50,
        );
        return offlineRows.map<ProductRef>((m) {
          double tp = 0;
          for (final k in const ['price', 'tp', 'sell_price', 'unit_price']) {
            final v = m[k];
            if (v != null) {
              final n = double.tryParse(v.toString());
              if (n != null) {
                tp = n;
                break;
              }
            }
          }
          return ProductRef(
            id: _metaInt(m['id']) ?? 0,
            name: (m['name'] ?? 'Unnamed').toString(),
            tp: tp,
            sku: (m['sku'] ?? '').toString().trim().isEmpty
                ? null
                : m['sku'].toString().trim(),
            barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                ? null
                : m['barcode'].toString().trim(),
            stock: null, // branch_stock not stored in the SQLite cache shape
            raw: m,
          );
        }).toList(growable: false);
      } catch (_) {
        return const <ProductRef>[];
      }
    }
  }

  // helpers
  double _toDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0.0;
  String _money(num v) => v.toStringAsFixed(2);
  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.orange;
    return Colors.green;
  }


  static SingleActivator _ctrl(LogicalKeyboardKey key) => SingleActivator(key, control: true);
  static SingleActivator _cmd(LogicalKeyboardKey key) => SingleActivator(key, meta: true);
  static SingleActivator _ctrlShift(LogicalKeyboardKey key) => SingleActivator(key, control: true, shift: true);
  static SingleActivator _cmdShift(LogicalKeyboardKey key) => SingleActivator(key, meta: true, shift: true);

  void _focusBarcodeScanner() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  /// Focus [node] and select all text in [ctrl] so typing replaces the current
  /// value. Used for numeric fields (discount, tax, cash received).
  void _focusAndSelectAll(FocusNode node, TextEditingController ctrl) {
    node.requestFocus();
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
  }

  /// After an autocomplete dropdown closes (selection or clear), focus drifts
  /// out of the Create Sale shortcut scope.  Schedule a post-frame callback to
  /// return focus to the page node so local shortcuts (F2, Ctrl+Enter, etc.)
  /// work again immediately without requiring a manual click.
  void _restoreSaleScreenFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      _pageFocusNode.requestFocus();
    });
  }

  // ── Derived cart ID set for the product panel in-cart badges ────────────
  Set<int> get _cartProductIds {
    return _items
        .map((i) => int.tryParse(i['product_id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    double rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final price = rowNum(i['price']);
      final qty = rowNum(i['quantity']);
      final disc = rowNum(i['discount_pct']);
      return sum + _lineTotal(price: price, qty: qty, discPct: disc);
    });
    final discount = _toDouble(discountController);
    final tax = _toDouble(taxController);
    final total = subtotal - discount + tax;

    final enteredCashReceived = _toDouble(cashReceivedController);
    final effectiveCashReceived = enteredCashReceived > 0
        ? enteredCashReceived
        : (_autoCashIfEmpty && total > 0 ? total : 0.0);
    final changeAmount = total > 0
        ? (effectiveCashReceived - total)
              .clamp(0.0, double.infinity)
              .toDouble()
        : 0.0;

    // ── Focus + shortcut scope ──────────────────────────────────────────────
    // CallbackShortcuts must be an ANCESTOR of Focus(_pageFocusNode) so that
    // the local bindings fire when _pageFocusNode holds focus (e.g. after
    // clicking blank space). In the old layout _pageFocusNode was the parent
    // of CallbackShortcuts — making it invisible to the local handler, so
    // key events fell through to the global AppKeyboardShortcuts (where F2
    // opens a new Create Sale screen instead of the product picker here).
    //
    // onTap instead of onTapDown: by the time onTap fires, any inner widget
    // that was tapped (TextField, button) has already called requestFocus().
    // We only take focus when no text-editing widget currently holds it, so
    // TextFields stay interactive and shortcuts are never swallowed.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final pf = FocusManager.instance.primaryFocus;
        final ctx = pf?.context;
        final isEditingText = ctx != null &&
            ctx.findAncestorWidgetOfExactType<EditableText>() != null;
        if (!isEditingText) {
          _pageFocusNode.requestFocus();
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f2): () => _addItemManual(),
            _ctrl(LogicalKeyboardKey.keyI): () => _addItemManual(),
            _cmd(LogicalKeyboardKey.keyI): () => _addItemManual(),
            const SingleActivator(LogicalKeyboardKey.f3): () => _pickCustomer(),
            _ctrlShift(LogicalKeyboardKey.keyC): () => _pickCustomer(),
            _cmdShift(LogicalKeyboardKey.keyC): () => _pickCustomer(),
            const SingleActivator(LogicalKeyboardKey.f4): () => _pickDeliveryBoy(),
            _ctrlShift(LogicalKeyboardKey.keyD): () => _pickDeliveryBoy(),
            _cmdShift(LogicalKeyboardKey.keyD): () => _pickDeliveryBoy(),
            const SingleActivator(LogicalKeyboardKey.f9): _focusBarcodeScanner,
            _ctrl(LogicalKeyboardKey.enter): () => _submitSale(),
            _cmd(LogicalKeyboardKey.enter): () => _submitSale(),
            _ctrl(LogicalKeyboardKey.numpadEnter): () => _submitSale(),
            _cmd(LogicalKeyboardKey.numpadEnter): () => _submitSale(),
            _ctrl(LogicalKeyboardKey.slash): () =>
                showAppShortcutGuide(context, includeSaleCreate: true),
            _cmd(LogicalKeyboardKey.slash): () =>
                showAppShortcutGuide(context, includeSaleCreate: true),
            _ctrlShift(LogicalKeyboardKey.keyU): () {
              _customerController.clear();
              _customerFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyS): () {
              _salesmanController.clear();
              _salesmanFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyB): () {
              _deliveryBoyController.clear();
              _deliveryBoyFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyP): () {
              _productSearchFocusNode.requestFocus();
            },
            // ── New focus shortcuts ──────────────────────────────────────────
            _ctrlShift(LogicalKeyboardKey.keyV): () {
              _vendorController.clear();
              _vendorFocusNode.requestFocus();
            },
            _cmdShift(LogicalKeyboardKey.keyV): () {
              _vendorController.clear();
              _vendorFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyN): () {
              _walkInNameFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyH): () {
              _walkInPhoneFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyA): () {
              _walkInAddressFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyR): () {
              _focusAndSelectAll(_cashReceivedFocusNode, cashReceivedController);
            },
            _cmdShift(LogicalKeyboardKey.keyR): () {
              _focusAndSelectAll(_cashReceivedFocusNode, cashReceivedController);
            },
            _ctrlShift(LogicalKeyboardKey.keyG): () {
              _focusAndSelectAll(_discountFocusNode, discountController);
            },
            _ctrlShift(LogicalKeyboardKey.keyT): () {
              _focusAndSelectAll(_taxFocusNode, taxController);
            },
          },
          child: Focus(
            focusNode: _pageFocusNode,
            autofocus: true,
            skipTraversal: true,
            child: Scaffold(
              backgroundColor: AppTheme.bg,
              body: Form(
              key: _formKey,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Light status bar (30 px) ──────────────────────
                      const SaleStatusBar(light: true),

                      // ── 2-panel workspace ─────────────────────────────
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LEFT 57% – cart workspace
                            Expanded(
                              flex: 57,
                              child: _buildCartWorkspace(
                                token: token,
                                isAll: isAll,
                                subtotal: subtotal,
                              ),
                            ),

                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppTheme.border,
                            ),

                            // RIGHT 43% – product browser with own search bar
                            Expanded(
                              flex: 43,
                              child: SaleProductPanel(
                                key: ValueKey(_selectedVendorId),
                                token: token,
                                vendorId: _selectedVendorId,
                                branchId: int.tryParse(_effectiveBranchIdStr()),
                                cartProductIds: _cartProductIds,
                                onProductTapped: (p) =>
                                    setState(() => _addOrIncrementProduct(p)),
                                onOpenModal: _addItemManual,
                                showSearchBar: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Fixed bottom action bar ───────────────────────
                      _buildBottomBar(
                        total: total,
                        changeAmount: changeAmount,
                      ),
                    ],
                  ),

                  // Hidden 1×1 barcode TextField — offset matches light bar (30 px)
                  Positioned(
                    left: 0,
                    top: 30,
                    child: _hiddenBarcodeField(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Cart workspace (left 57%) ────────────────────────────────────────────
  Widget _buildCartWorkspace({
    required String token,
    required bool isAll,
    required double subtotal,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. FIXED — party selectors (Customer, Salesman, Delivery Boy, Vendor)
          PartySectionCard(
            isAll: isAll,
            selectedCustomer: _selectedCustomer,
            selectedUser: _selectedUser,
            selectedDeliveryBoy: _selectedDeliveryBoy,
            selectedBranch: _selectedBranch,
            selectedVendor: _selectedVendor,
            branchId: _effectiveBranchIdStr(),
            token: token,
            onPickCustomer: _pickCustomer,
            onPickUser: _pickUser,
            onPickDeliveryBoy: _pickDeliveryBoy,
            onPickVendor: _pickVendor,
            onClearVendor: () => setState(() {
              _selectedVendor = null;
              _selectedVendorId = null;
              _items = [];
            }),
            onBrowseCustomerSheet: _openCustomerSheet,
            onApplyCustomer: _applyCustomerSelection,
            onBrowseUserSheet: _openUserSheet,
            onApplyUser: _applyUserSelection,
            onBrowseDeliveryBoySheet: _openDeliveryBoySheet,
            onApplyDeliveryBoy: _applyDeliveryBoySelection,
            onBrowseVendorSheet: _openVendorSheet,
            onApplyVendor: _applyVendorSelection,
            customerFocusNode: _customerFocusNode,
            salesmanFocusNode: _salesmanFocusNode,
            deliveryBoyFocusNode: _deliveryBoyFocusNode,
            vendorFocusNode: _vendorFocusNode,
            customerController: _customerController,
            salesmanController: _salesmanController,
            deliveryBoyController: _deliveryBoyController,
            vendorController: _vendorController,
          ),

          // 2. FIXED — walk-in customer details (compact single-row layout)
          _buildWalkInCompact(),

          const Divider(height: 1, thickness: 1, color: AppTheme.border),

          // 3. FIXED — product autocomplete + scanner + F2
          _buildInputRow(),

          // 4. FIXED — cart table column headers
          _buildCartTableHeader(),

          // 5. INDEPENDENTLY SCROLLABLE — cart item rows
          Expanded(
            child: ItemsTable(
              compact: true,
              items: _items,
              onQueryProducts: _queryProducts,
              onAddItem: _addItemManual,
              onItemsChanged: (next) => setState(() => _items = next),
            ),
          ),

          // 6. FIXED — subtotal + editable discount/tax
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          _buildSummaryRow(subtotal: subtotal),
        ],
      ),
    );
  }

  // ── Fixed cart table column header row ─────────────────────────────────
  Widget _buildCartTableHeader() {
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
            child: Text('T.P', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Disc (%)', style: style, textAlign: TextAlign.right),
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

  // ── Compact walk-in section (two rows: name+phone | address) ────────────
  Widget _buildWalkInCompact() {
    final inputDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: label + name + phone + clear
          Row(
            children: [
              const Text(
                'Walk-in',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Focus: Ctrl+Shift+N',
                  child: SizedBox(
                    height: 40,
                    child: TextFormField(
                      controller: customerNameController,
                      focusNode: _walkInNameFocusNode,
                      decoration: inputDecoration.copyWith(
                        hintText: 'Customer name',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Focus: Ctrl+Shift+H',
                child: SizedBox(
                  width: 120,
                  height: 40,
                  child: TextFormField(
                    controller: customerPhoneController,
                    focusNode: _walkInPhoneFocusNode,
                    keyboardType: TextInputType.phone,
                    decoration: inputDecoration.copyWith(hintText: 'Phone'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_selectedCustomerId != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: _clearCustomerSelection,
                  borderRadius: BorderRadius.circular(4),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          // Row 2: address
          Tooltip(
            message: 'Focus: Ctrl+Shift+A',
            child: SizedBox(
              height: 40,
              child: TextFormField(
                controller: addressController,
                focusNode: _walkInAddressFocusNode,
                decoration: inputDecoration.copyWith(
                  hintText: 'Address (optional)',
                  prefixIcon: const Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input row: product autocomplete + scanner + F2 ─────────────────────
  Widget _buildInputRow() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          // Product autocomplete — adds to cart on selection
          Expanded(
            child: _CartProductSearch(
              focusNode: _productSearchFocusNode,
              controller: _productSearchController,
              onQuery: _queryProducts,
              onSelected: (ref) {
                // Route through the centralized merge/increment method for
                // both raw-data-available and raw-data-missing cases so that
                // selecting the same product twice always increments the
                // existing row rather than appending a new one.
                final productMap = ref.raw ??
                    <String, dynamic>{
                      'id': ref.id,
                      'name': ref.name,
                      'price': ref.tp,
                    };
                setState(() => _addOrIncrementProduct(productMap));
              },
            ),
          ),
          const SizedBox(width: 6),

          // Scanner toggle (F9)
          Tooltip(
            message: 'Focus barcode scanner  (F9)',
            child: InkWell(
              onTap: _focusBarcodeScanner,
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
                  color:
                      _scannerEnabled ? AppTheme.success : AppTheme.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // F2 / Add Items (opens full modal picker for multi-select)
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

  // ── Summary row: item count + subtotal + editable discount/tax ─────────
  Widget _buildSummaryRow({required double subtotal}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Item count + subtotal (read-only)
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
            'Sub: ${subtotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),

          // Order Discount (editable inline)
          const Text(
            'Disc(-):',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Focus: Ctrl+Shift+G',
            child: SizedBox(
              width: 70,
              height: 36,
              child: TextField(
                controller: discountController,
                focusNode: _discountFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Order Tax (editable inline)
          const Text(
            'Tax(+):',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Focus: Ctrl+Shift+T',
            child: SizedBox(
              width: 70,
              height: 36,
              child: TextField(
                controller: taxController,
                focusNode: _taxFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fixed bottom action bar ──────────────────────────────────────────────
  Widget _buildBottomBar({
    required double total,
    required double changeAmount,
  }) {
    final pm = context.watch<PaymentMethodProvider>();
    final methods = pm.activeMethods;
    final currentMethod = _saleMethod ?? pm.defaultMethod?.method;
    final showCashFields =
        pm.byCode(currentMethod ?? '')?.affectsCashDrawer ??
            (currentMethod == null || currentMethod == 'cash');
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Auto Cash toggle
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
            scale: 0.8,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _autoCashIfEmpty,
              onChanged: (v) => setState(() => _autoCashIfEmpty = v),
            ),
          ),
          const SizedBox(width: 8),

          // Payment method selector (dynamic, branch-configured)
          if (methods.isNotEmpty)
            SizedBox(
              width: 128,
              height: 44,
              child: DropdownButtonFormField<String>(
                value: currentMethod,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
                items: methods
                    .map((m) => DropdownMenuItem(
                          value: m.method,
                          child: Text(m.displayName, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _saleMethod = v),
              ),
            ),
          const SizedBox(width: 8),

          // Cash Received + Change apply only to physical drawer cash.
          if (showCashFields) ...[
            Tooltip(
              message: 'Focus: Ctrl+Shift+R',
              child: SizedBox(
                width: 110,
                height: 44,
                child: TextField(
                  controller: cashReceivedController,
                  focusNode: _cashReceivedFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'Cash Recv.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  changeAmount.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: changeAmount > 0 ? AppTheme.success : AppTheme.navy,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ] else
            // Non-drawer tender (KNET/card/bank/cheque): optional reference.
            SizedBox(
              width: 150,
              height: 44,
              child: TextField(
                controller: saleReferenceController,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  hintText: 'Txn / approval',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const Spacer(),

          // Total payable
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Total Payable',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                total.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Clear cart
          OutlinedButton(
            onPressed: () => _resetForNextSale(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppTheme.danger),
              foregroundColor: AppTheme.danger,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),

          // Save Sale (Ctrl+↵)
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submitSale,
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 16),
              label: Text(
                _submitting ? 'Saving…' : 'Save Sale  Ctrl+↵',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _SaleWorkspaceHeader extends StatelessWidget {
  final String customerLabel;
  final int itemCount;
  final String total;
  final String balance;
  final VoidCallback onAddItems;

  const _SaleWorkspaceHeader({
    required this.customerLabel,
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
                child: const Icon(Icons.point_of_sale_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Sale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      customerLabel,
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
              children: [
                title,
                const SizedBox(height: 12),
                stats,
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              stats,
              const SizedBox(width: 12),
              button,
            ],
          );
        },
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


// ── Cart product autocomplete (Point 1) ────────────────────────────────────
// Overlay-based dropdown; adds product to cart on selection.
class _CartProductSearch extends StatefulWidget {
  final FocusNode focusNode;
  final TextEditingController controller;
  final Future<List<ProductRef>> Function(String q) onQuery;
  final void Function(ProductRef ref) onSelected;

  const _CartProductSearch({
    required this.focusNode,
    required this.controller,
    required this.onQuery,
    required this.onSelected,
  });

  @override
  State<_CartProductSearch> createState() => _CartProductSearchState();
}

class _CartProductSearchState extends State<_CartProductSearch> {
  final LayerLink _layerLink = LayerLink();
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  List<ProductRef> _suggestions = [];
  int _highlightIndex = -1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    final q = widget.controller.text.trim();
    if (q.isEmpty) {
      _debounce?.cancel();
      _removeOverlay();
      if (mounted) {
        setState(() {
          _suggestions = [];
          _highlightIndex = -1;
          _loading = false;
        });
      }
      return;
    }
    // Show loading immediately, debounce the actual fetch.
    if (mounted) setState(() => _loading = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final results = await widget.onQuery(q);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _highlightIndex = results.isNotEmpty ? 0 : -1;
      _loading = false;
    });
    if (results.isEmpty) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _buildDropdown());
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectIndex(int i) {
    if (i < 0 || i >= _suggestions.length) return;
    final ref = _suggestions[i];
    widget.controller.clear();
    _removeOverlay();
    setState(() {
      _suggestions = [];
      _highlightIndex = -1;
    });
    widget.onSelected(ref);
  }

  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _highlightIndex =
          (_highlightIndex + delta).clamp(0, _suggestions.length - 1);
    });
    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildDropdown() {
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: const Offset(0, 38),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 420,
          child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) {
                final ref = _suggestions[i];
                final highlighted = i == _highlightIndex;
                final sub = [
                  if (ref.sku != null && ref.sku!.isNotEmpty)
                    'SKU: ${ref.sku}',
                  if (ref.barcode != null && ref.barcode!.isNotEmpty)
                    ref.barcode!,
                ].join('  ');
                return GestureDetector(
                  onTap: () => _selectIndex(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: highlighted
                          ? AppTheme.primarySoft
                          : Colors.transparent,
                      border: const Border(
                        bottom: BorderSide(color: AppTheme.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ref.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: highlighted
                                      ? AppTheme.primary
                                      : AppTheme.navy,
                                ),
                              ),
                              if (sub.isNotEmpty)
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              ref.tp.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                            if (ref.stock != null)
                              Text(
                                'Stock: ${ref.stock!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      // Focus wraps the TextField so onKeyEvent fires while the TextField has focus.
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveHighlight(1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveHighlight(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (_highlightIndex >= 0) {
              _selectIndex(_highlightIndex);
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _removeOverlay();
            setState(() {
              _suggestions = [];
              _highlightIndex = -1;
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            decoration: InputDecoration(
              hintText: 'Search product… (name / SKU / barcode)',
              prefixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    )
                  : const Icon(Icons.search, size: 16),
              suffixIcon: widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        widget.controller.clear();
                        _removeOverlay();
                        setState(() {
                          _suggestions = [];
                          _highlightIndex = -1;
                        });
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: AppTheme.surfaceSoft,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _CreateSaleBottomBar extends StatelessWidget {
  final int itemCount;
  final String total;
  final String paid;
  final String balance;
  final bool submitting;
  final VoidCallback onSubmit;

  const _CreateSaleBottomBar({
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
          BoxShadow(
            color: AppTheme.navy.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
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
              label: Text(submitting ? 'Saving...' : 'Save Sale  Ctrl+Enter'),
            ),
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}
