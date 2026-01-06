import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// local widgets split into small files
import 'package:enterprise_pos/screens/sales/parts/sale_party_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_items_payments.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_totals_card.dart';

class CreateSaleScreen extends StatefulWidget {
  const CreateSaleScreen({super.key});

  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();

  // selections
  String? _selectedBranchId;
  String? _selectedCustomerId;
  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedCustomer;
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;
  Map<String, dynamic>? _selectedUser;
  int? _selectedUserId;

  // cart & payments
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];

  // discount/tax live controllers (now edited inline in totals)
  final discountController = TextEditingController(text: "0");
  final taxController = TextEditingController(text: "0");

  final TextEditingController addressController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  bool _customerLocked = false;

  // barcode (kept intact)
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;

  bool _submitting = false;
  bool _autoCashIfEmpty = true;

  late ProductService _productService;
  late SaleService _saleService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _saleService = SaleService(token: token);

    _barcodeFocusNode.addListener(() {
      setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });

    void _recalc() => setState(() {});
    discountController.addListener(_recalc);
    taxController.addListener(_recalc);
  }

  @override
  void dispose() {
    discountController.dispose();
    taxController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    addressController.dispose();
    customerNameController.dispose();
    customerPhoneController.dispose();
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

  Future<void> _pickCustomer() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final customer = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );
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

  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final vendor = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorPickerSheet(token: token),
    );
    if (!mounted) return;
    setState(() {
      _selectedVendor = vendor;
      _selectedVendorId = vendor?['id'] as int?;
      _items = []; // avoid cross-vendor mix
    });
  }

  Future<void> _pickUser() async {
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final String? effectiveBranchIdStr =
        globalBranchId?.toString() ?? _selectedBranchId;
    final String effectiveBranchId = effectiveBranchIdStr ?? '';

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final user = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          UserPickerSheet(token: token, branchId: effectiveBranchId),
    );
    if (!mounted) return;
    setState(() {
      _selectedUser = user;
      _selectedUserId = user?['id'] as int?;
    });
  }

  // ---------------- Items ----------------
  Future<void> _addItemManual() async {
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

    final size = MediaQuery.of(context).size;

    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height, // ✅ force full height
      ),
      builder: (sheetCtx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: Theme.of(sheetCtx).colorScheme.surface,
          child: ProductPickerGridSheet(
            token: token,
            vendorId: _selectedVendorId,
            multi: true,
            alreadySelectedIds: alreadySelectedIds,
            alreadySelectedQty: alreadySelectedQty,
          ),
        ),
      ),
    );

    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final x in picked) {
        final product = (x["product"] as Map?)?.cast<String, dynamic>();
        final qty = (x["qty"] as num?)?.toDouble() ?? 1.0;
        if (product == null) continue;

        final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
        if (productId == 0) continue;

        final price =
            double.tryParse(product['price']?.toString() ?? '') ?? 0.0;

        // ✅ if already in items -> UPDATE qty to picked qty (or merge as you want)
        final idx = _items.indexWhere(
          (it) => (int.tryParse(it["product_id"].toString()) ?? 0) == productId,
        );

        if (idx != -1) {
          // If your picker returns FINAL qty (set qty), then use this:
          final newQty = qty;

          _items[idx]["quantity"] = newQty;

          final discPct =
              double.tryParse(_items[idx]["discount_pct"]?.toString() ?? '') ??
              0.0;

          final rowPrice =
              double.tryParse(_items[idx]["price"]?.toString() ?? '') ?? price;

          _items[idx]["total"] = _lineTotal(
            price: rowPrice,
            qty: newQty,
            discPct: discPct,
          );
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
                  keyboardType: TextInputType.number,
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
                        int.tryParse(qtyController.text) ?? 1;
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

  // ---------------- Payments ----------------
  Future<void> _addPaymentDialog() async {
    final amountController = TextEditingController();
    String method = "cash";

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(labelText: "Method"),
              items: const [
                DropdownMenuItem(value: "cash", child: Text("Cash")),
                DropdownMenuItem(value: "card", child: Text("Card")),
                DropdownMenuItem(value: "bank", child: Text("Bank")),
                DropdownMenuItem(value: "wallet", child: Text("Wallet")),
              ],
              onChanged: (val) => method = val!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final amt = double.tryParse(amountController.text) ?? 0.0;
              if (amt > 0) {
                setState(
                  () => _payments.add({
                    "amount": amt.toString(),
                    "method": method,
                  }),
                );
                Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Product not found: $code")));
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
    return t.isFinite ? (t < 0 ? 0.0 : t) : 0.0;
  }

  Widget _hiddenBarcodeField() {
    return Opacity(
      opacity: 0,
      child: TextField(
        controller: _barcodeController,
        focusNode: _barcodeFocusNode,
        autofocus: false,
        onSubmitted: _onBarcodeScanned,
      ),
    );
  }

  // ---------------- Submit ----------------
  Future<void> _submitSale() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Add at least 1 item")));
      return;
    }

    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final effectiveBranchId = globalBranchId?.toString() ?? _selectedBranchId;

    // if (effectiveBranchId == null || effectiveBranchId.isEmpty) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text("Please select a branch (on Home)")),
    //   );
    //   return;
    // }
    double _rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final price = _rowNum(i['price']);
      final qty = _rowNum(i['quantity']);
      final disc = _rowNum(i['discount_pct']); // may be null -> 0
      return sum + _lineTotal(price: price, qty: qty, discPct: disc);
    });
    double discount = double.tryParse(discountController.text.trim()) ?? 0.0;
    double tax = double.tryParse(taxController.text.trim()) ?? 0.0;
    double total = (subtotal - discount + tax).clamp(0, double.infinity);

    final List<Map<String, dynamic>> paymentsToSend =
        List<Map<String, dynamic>>.from(_payments);
    if (_autoCashIfEmpty && paymentsToSend.isEmpty) {
      paymentsToSend.add({
        "amount": total.toStringAsFixed(2),
        "method": "cash",
      });
    }

    setState(() => _submitting = true);

    try {
      final meta = <String, dynamic>{
        "customer_snapshot": {
          "name": customerNameController.text.trim(),
          "phone": customerPhoneController.text.trim(),
          "address": addressController.text.trim(),
        },
      };
      final res = await _saleService.createSale(
        branchId: effectiveBranchId,
        customerId: _selectedCustomerId != null
            ? int.tryParse(_selectedCustomerId!)
            : null,
        vendorId: _selectedVendorId,
        userId: _selectedUserId,
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
        return ReceiptItem(
          name: name,
          price: price,
          qty: qty,
          total: lineTotal,
        );
      }).toList();
      final hasPrinter = false;
      if (!kIsWeb && hasPrinter) {
        try {
          const printerIp = "192.168.1.50";
          await ThermalPrinterService.instance.printSaleReceipt(
            printerIp: printerIp,
            shopName: "HT COMPUTERS",
            shopAddress: "HT Computers Clock Tower Sukkur",
            shopPhone: "+92 333 7155125",
            receiptNo: receiptNo,
            dateTime: DateTime.now(),
            items: receiptItems,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            meta: meta,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      } else {
        await ReceiptPreviewService.instance.previewReceipt(
          shopName: "HT COMPUTERS",
          shopAddress: "HT Computers Clock Tower Sukkur",
          shopPhone: "+92 333 7155125",
          receiptNo: receiptNo,
          dateTime: DateTime.now(),
          items: receiptItems,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          meta: meta,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to create sale: $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
              id: (m['id'] ?? m['product_id']) as int,
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

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    double _rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final price = _rowNum(i['price']);
      final qty = _rowNum(i['quantity']);
      final disc = _rowNum(i['discount_pct']); // may be null -> 0
      return sum + _lineTotal(price: price, qty: qty, discPct: disc);
    });
    final discount = _toDouble(discountController);
    final tax = _toDouble(taxController);
    final total = (subtotal - discount + tax).clamp(0, double.infinity);

    final paid = _payments.fold<double>(
      0,
      (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0),
    );
    final balance = total - paid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Sale"),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8.0),
            // child: BranchIndicator(tappable: false),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _hiddenBarcodeField(),

              // Party (customer/salesman/branch/vendor)
              PartySectionCard(
                isAll: isAll,
                selectedCustomer: _selectedCustomer,
                selectedUser: _selectedUser,
                selectedBranch: _selectedBranch,
                selectedVendor: _selectedVendor,
                onPickCustomer: _pickCustomer,
                onPickUser: _pickUser,
                // onPickBranch: _pickBranch,
                onPickVendor: _pickVendor,
                onClearVendor: () => setState(() {
                  _selectedVendor = null;
                  _selectedVendorId = null;
                  _items = [];
                }),
              ),

              const SizedBox(height: 12),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Customer Info",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          if (_selectedCustomerId != null)
                            TextButton.icon(
                              onPressed: _clearCustomerSelection,
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text("Clear"),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: customerNameController,
                        // readOnly: _customerLocked,
                        decoration: InputDecoration(
                          labelText: "Customer Name",
                          hintText: "Walk-in customer name",
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: customerPhoneController,
                        // readOnly: _customerLocked,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: "Phone",
                          hintText: "03xx-xxxxxxx",
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: addressController,
                        // readOnly: _customerLocked,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: "Address",
                          hintText: "Customer address",
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Scanner + Items
              ScannerToggleButton(
                enabled: _scannerEnabled,
                onActivate: () {
                  Future.delayed(const Duration(milliseconds: 50), () {
                    _barcodeFocusNode.requestFocus();
                  });
                },
              ),
              const SizedBox(height: 8),
              // ItemsCard(
              //   items: _items,
              //   onAddItem: _addItemManual,
              //   onEditItem: _editItem,
              //   onRemoveItem: (idx) => setState(() => _items.removeAt(idx)),
              // ),
              // --- FAST TABULAR ITEMS ---
              ItemsTable(
                items: _items,
                onQueryProducts: _queryProducts, // implemented below,
                onAddItem: _addItemManual,
                onItemsChanged: (next) {
                  setState(() => _items = next);
                },
              ),

              const SizedBox(height: 12),

              // Payments
              PaymentsCard(
                payments: _payments,
                autoCashIfEmpty: _autoCashIfEmpty,
                onToggleAutoCash: (v) => setState(() => _autoCashIfEmpty = v),
                onAddPayment: _addPaymentDialog,
                onRemovePayment: (idx) =>
                    setState(() => _payments.removeAt(idx)),
              ),

              const SizedBox(height: 12),

              // Totals (discount & tax editable inline here)
              TotalsCardInline(
                subtotal: _money(subtotal),
                discountController: discountController,
                taxController: taxController,
                total: _money(total),
                paid: _money(paid),
                balance: _money(balance),
                balanceColor: _balanceColor(balance),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submitSale,
                  icon: const Icon(Icons.check),
                  label: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Create Sale"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
