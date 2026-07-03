import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/widgets/party_autocomplete_field.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';

// local widgets split into small files
import 'package:enterprise_pos/screens/sales/parts/sale_party_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_items_payments.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_totals_card.dart';

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

  // Named focus nodes for keyboard-shortcut field-jumping (Part C).
  // Each controller is cleared before focus is requested so the field opens
  // with a blank search query rather than leftover text.
  final _customerFocusNode = FocusNode();
  final _salesmanFocusNode = FocusNode();
  final _deliveryBoyFocusNode = FocusNode();
  final _productSearchFocusNode = FocusNode();
  final _customerController = TextEditingController();
  final _salesmanController = TextEditingController();
  final _deliveryBoyController = TextEditingController();
  final _productSearchController = TextEditingController();

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
    await _addItemManual();
  }

  @override
  void dispose() {
    discountController.dispose();
    taxController.dispose();
    cashReceivedController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _pageFocusNode.dispose();
    addressController.dispose();
    customerNameController.dispose();
    customerPhoneController.dispose();
    _customerFocusNode.dispose();
    _salesmanFocusNode.dispose();
    _deliveryBoyFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _customerController.dispose();
    _salesmanController.dispose();
    _deliveryBoyController.dispose();
    _productSearchController.dispose();
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
  }

  Future<void> _pickDeliveryBoy() async {
    final user = await _openDeliveryBoySheet();
    _applyDeliveryBoySelection(user);
  }

  // ---------------- Items ----------------

  /// Adds or updates a single product in [_items].
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

    final product = await _productService.getProductByBarcode(
      code,
      vendorId: _selectedVendorId,
    );
    if (product != null) {
      final price = double.tryParse(product['price']?.toString() ?? '') ?? 0.0;
      setState(() {
        _items.add({
          "product_id": product['id'],
          "name": product['name'],
          "cost_price": product['cost_price'],
          "wholesale_price": product['wholesale_price'],
          "quantity": 1.0,
          "price": price,
          "discount_pct": 0.0,
          "total": _lineTotal(price: price, qty: 1.0, discPct: 0.0),
        });
      });
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

    final List<Map<String, dynamic>> paymentsToSend = [];
    if (_autoCashIfEmpty && total > 0) {
      paymentsToSend.add({
        "amount": total.toStringAsFixed(2),
        "method": "cash",
      });
    }

    final paid = paymentsToSend.fold<double>(
      0.0,
      (sum, payment) => sum + _metaNum(payment['amount']),
    );
    final balance = total - paid;

    final enteredCashReceived = _toDouble(cashReceivedController);
    final cashReceived = enteredCashReceived > 0
        ? enteredCashReceived
        : (_autoCashIfEmpty && total > 0 ? total : 0.0);
    final changeAmount = (cashReceived - total)
        .clamp(0.0, double.infinity)
        .toDouble();

    setState(() => _submitting = true);

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
      final res = await _saleService.createSale(
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
        discount: discount,
        tax: tax,
        meta: meta,
      );
      final receiptNo =
          (res['data']?['sale']?['invoice_no'] ?? res['data']?['id'] ?? 'N/A')
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
      AppFeedback.success(context, "Sale $receiptNo created successfully. Ready for next sale.");
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _items.isEmpty) _addItemManual();
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

      return list
          .map<ProductRef>((raw) {
            final m = raw as Map<String, dynamic>;
            return ProductRef(
              id: _metaInt(m['id'] ?? m['product_id']) ?? 0,
              name: (m['name'] ?? m['title'] ?? 'Unnamed').toString(),
              tp: _tp(m),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <ProductRef>[];
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

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 1080;
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

    final paid = _autoCashIfEmpty && total > 0 ? total : 0.0;
    final balance = total - paid;
    final enteredCashReceived = _toDouble(cashReceivedController);
    final effectiveCashReceived = enteredCashReceived > 0
        ? enteredCashReceived
        : (_autoCashIfEmpty && total > 0 ? total : 0.0);
    final changeAmount = (effectiveCashReceived - total)
        .clamp(0.0, double.infinity)
        .toDouble();

    final customerLabel = customerNameController.text.trim().isEmpty
        ? (_selectedCustomer == null ? 'Walk-in customer' : 'Selected customer')
        : customerNameController.text.trim();

    final partyPanel = Column(
      children: [
        PartySectionCard(
          isAll: isAll,
          selectedCustomer: _selectedCustomer,
          selectedUser: _selectedUser,
          selectedDeliveryBoy: _selectedDeliveryBoy,
          selectedBranch: _selectedBranch,
          selectedVendor: _selectedVendor,
          branchId: _effectiveBranchIdStr(),
          token: Provider.of<AuthProvider>(context, listen: false).token!,
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
          customerController: _customerController,
          salesmanController: _salesmanController,
          deliveryBoyController: _deliveryBoyController,
        ),
        const SizedBox(height: 14),
        _CustomerInfoPanel(
          customerNameController: customerNameController,
          customerPhoneController: customerPhoneController,
          addressController: addressController,
          selectedCustomerId: _selectedCustomerId,
          onClearCustomer: _clearCustomerSelection,
        ),
      ],
    );

    final itemsPanel = Column(
      children: [
        _ScannerPanel(
          scannerEnabled: _scannerEnabled,
          onActivateScanner: _focusBarcodeScanner,
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
          subtitleOf: (p) =>
              (p['sku'] ?? p['barcode'] ?? '').toString(),
          idOf: (p) => (p['id'] ?? '').toString(),
          onSelected: (p) => setState(() => _applyPickedProduct(p)),
          onBrowseAll: () async {
            final alreadySelectedIds = _items
                .map((e) => int.tryParse(e["product_id"].toString()) ?? 0)
                .where((id) => id > 0)
                .toList();
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
          onQueryProducts: _queryProducts,
          onAddItem: _addItemManual,
          onItemsChanged: (next) {
            setState(() => _items = next);
          },
        ),
      ],
    );

    final paymentAndTotalsPanel = Column(
      children: [
        PaymentsCard(
          autoCashIfEmpty: _autoCashIfEmpty,
          onToggleAutoCash: (v) => setState(() => _autoCashIfEmpty = v),
          cashReceivedController: cashReceivedController,
          changeAmount: _money(changeAmount),
        ),
        const SizedBox(height: 14),
        TotalsCardInline(
          subtotal: _money(subtotal),
          discountController: discountController,
          taxController: taxController,
          total: _money(total),
          paid: _money(paid),
          balance: _money(balance),
          balanceColor: _balanceColor(balance),
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
            _ctrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, includeSaleCreate: true),
            _cmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, includeSaleCreate: true),
            // Field-focus shortcuts — jump cursor directly into the field so
            // the user can start typing a search immediately. These are ADDITIVE;
            // the existing F3/F4/Ctrl+Shift+C/D modal-picker shortcuts above are
            // unchanged. Ctrl+Shift+U (cUstomer), S (Salesman), B (delivery
            // Boy), P (Product) were chosen because C/D are already taken.
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
              _productSearchController.clear();
              _productSearchFocusNode.requestFocus();
            },
          },
          child: Scaffold(
      appBar: AppBar(
        title: const Text('Create Sale'),
        actions: [
          IconButton(
            tooltip: 'Sale shortcuts',
            onPressed: () => showAppShortcutGuide(context, includeSaleCreate: true),
            icon: const Icon(Icons.keyboard_rounded),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: BranchIndicator(tappable: false),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _addItemManual,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Items (F2)'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _SaleWorkspaceHeader(
                  customerLabel: customerLabel,
                  itemCount: _items.length,
                  total: _money(total),
                  balance: _money(balance),
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
                                    partyPanel,
                                    const SizedBox(height: 14),
                                    itemsPanel,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 390,
                                child: paymentAndTotalsPanel,
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              partyPanel,
                              const SizedBox(height: 14),
                              itemsPanel,
                              const SizedBox(height: 14),
                              paymentAndTotalsPanel,
                            ],
                          ),
                  ),
                ),
              ),
              _CreateSaleBottomBar(
                itemCount: _items.length,
                total: _money(total),
                paid: _money(paid),
                balance: _money(balance),
                submitting: _submitting,
                onSubmit: _submitSale,
              ),
            ],
          ),
          Positioned(left: 0, top: 0, child: _hiddenBarcodeField()),
        ],
      ),
        ),
      ),
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

class _CustomerInfoPanel extends StatelessWidget {
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final TextEditingController addressController;
  final String? selectedCustomerId;
  final VoidCallback onClearCustomer;

  const _CustomerInfoPanel({
    required this.customerNameController,
    required this.customerPhoneController,
    required this.addressController,
    required this.selectedCustomerId,
    required this.onClearCustomer,
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
              const Expanded(child: Text('Walk-in details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              if (selectedCustomerId != null)
                TextButton.icon(
                  onPressed: onClearCustomer,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final name = TextFormField(
                controller: customerNameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Walk-in customer name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              );
              final phone = TextFormField(
                controller: customerPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '03xx-xxxxxxx',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              );
              if (!wide) {
                return Column(
                  children: [
                    name,
                    const SizedBox(height: 10),
                    phone,
                    const SizedBox(height: 10),
                    _addressField(),
                  ],
                );
              }
              return Column(
                children: [
                  Row(children: [Expanded(child: name), const SizedBox(width: 10), Expanded(child: phone)]),
                  const SizedBox(height: 10),
                  _addressField(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _addressField() {
    return TextFormField(
      controller: addressController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Address',
        hintText: 'Customer address',
        prefixIcon: Icon(Icons.location_on_outlined),
      ),
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  final bool scannerEnabled;
  final VoidCallback onActivateScanner;
  final VoidCallback onOpenPicker;

  const _ScannerPanel({
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
              scannerEnabled ? 'Scanner active' : 'Search products or scan barcode',
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
