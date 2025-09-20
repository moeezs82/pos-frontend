import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';

// pickers
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/branch_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CreatePurchaseScreen extends StatefulWidget {
  const CreatePurchaseScreen({super.key});

  @override
  State<CreatePurchaseScreen> createState() => _CreatePurchaseScreenState();
}

class _CreatePurchaseScreenState extends State<CreatePurchaseScreen> {
  final _formKey = GlobalKey<FormState>();

  // selections
  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedVendor;

  String? _selectedBranchId;
  int? _selectedVendorId;

  // cart & payments
  final List<Map<String, dynamic>> _items = [];
  final List<Map<String, dynamic>> _payments = [];

  // pricing
  final discountController = TextEditingController();
  final taxController = TextEditingController();

  // barcode
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;

  // receive now
  bool _receiveNow = true; // default ON for convenience

  // services
  late ProductService _productService;
  late PurchaseService _purchaseService;
  late String _token;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: _token);
    _purchaseService = PurchaseService(token: _token);

    _barcodeFocusNode.addListener(() {
      setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });
  }

  /* ----------------- pickers ----------------- */

  Future<void> _pickBranch() async {
    final branch = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => BranchPickerSheet(token: _token),
    );
    if (branch != null) {
      setState(() {
        _selectedBranch = branch;
        _selectedBranchId = branch['id'].toString();
      });
    }
  }

  Future<void> _pickVendor() async {
    final vendor = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: _token),
      ),
    );

    if (vendor == null) {
      setState(() {
        _selectedVendor = null;
        _selectedVendorId = null;
      });
    } else {
      setState(() {
        _selectedVendor = vendor;
        _selectedVendorId = vendor['id'] as int?;
      });
    }
  }

  /* ----------------- products ----------------- */

  Future<void> _addItemManual() async {
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(token: _token),
    );
    if (product == null) return;

    final price = double.tryParse(product['price'].toString()) ?? 0.0;

    setState(() {
      _items.add({
        "product_id": product['id'],
        "name": product['name'],
        "cost_price": product['cost_price'],
        "wholesale_price": product['wholesale_price'],
        "quantity": 1,
        "price": price,
        // for receiving
        "received_qty": 1, // if receiveNow on, this will be used
      });
    });
  }

  void _editItem(int index) {
    final item = _items[index];

    final qtyCtl = TextEditingController(text: item['quantity'].toString());
    final priceCtl = TextEditingController(text: item['cost_price'].toString());
    final rcvCtl = TextEditingController(
      text: (item['received_qty'] ?? item['quantity']).toString(),
    );

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
                  controller: qtyCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Quantity (ordered)",
                  ),
                  onChanged: (_) {
                    if (_receiveNow) {
                      // keep received in range
                      final q = int.tryParse(qtyCtl.text) ?? 1;
                      if ((int.tryParse(rcvCtl.text) ?? 0) > q) {
                        rcvCtl.text = q.toString();
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Purchase Price",
                  ),
                ),
                if (_receiveNow) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: rcvCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Receive Now (qty)",
                    ),
                  ),
                ],
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
                          "Cost Price: \$${(item['cost_price'] ?? 0).toString()}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          "Wholesale: \$${(item['wholesale_price'] ?? 0).toString()}",
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
                  final q = int.tryParse(qtyCtl.text) ?? 1;
                  final p = double.tryParse(priceCtl.text) ?? 0.0;
                  final r = int.tryParse(rcvCtl.text) ?? 0;
                  setState(() {
                    _items[index]['quantity'] = q;
                    _items[index]['price'] = p;
                    if (_receiveNow) {
                      _items[index]['received_qty'] = r.clamp(0, q);
                    } else {
                      _items[index]['received_qty'] = 0;
                    }
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

  /* ----------------- payments ----------------- */

  Future<void> _addPaymentDialog() async {
    final amountCtl = TextEditingController();
    String method = "cash";

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtl,
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
              final amt = double.tryParse(amountCtl.text) ?? 0.0;
              if (amt > 0) {
                setState(() {
                  _payments.add({"amount": amt, "method": method});
                });
                Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  /* ----------------- barcode ----------------- */

  Future<void> _onBarcodeScanned(String code) async {
    if (code.isEmpty) return;
    final product = await _productService.getProductByBarcode(code);

    if (product != null) {
      final price = double.tryParse(product['price'].toString()) ?? 0.0;
      setState(() {
        _items.add({
          "product_id": product['id'],
          "name": product['name'],
          "cost_price": product['cost_price'],
          "wholesale_price": product['wholesale_price'],
          "quantity": 1,
          "price": price,
          "received_qty": _receiveNow ? 1 : 0,
        });
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Product not found: $code")));
    }

    _barcodeController.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  Widget _hiddenBarcodeInput() {
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

  /* ----------------- submit ----------------- */

  Future<void> _submitPurchase() async {
    if (_selectedBranchId == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Branch & at least 1 item required")),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // build items array as expected by backend
      final itemsPayload = _items.map((i) {
        final map = {
          "product_id": i['product_id'],
          "quantity": i['quantity'],
          "price": i['price'],
        };
        if (_receiveNow) {
          // only send if >0; controller clamps later too
          final r = (i['received_qty'] ?? 0) as int;
          if (r > 0) map["received_qty"] = r;
        }
        return map;
      }).toList();

      double toAmount(TextEditingController c) =>
          double.tryParse(c.text.trim()) ?? 0.0;

      final payload = <String, dynamic>{
        "branch_id": int.parse(_selectedBranchId!),
        if (_selectedVendorId != null) "vendor_id": _selectedVendorId,
        "discount": toAmount(discountController),
        "tax": toAmount(taxController),
        "receive_now": _receiveNow,
        "items": itemsPayload,
        if (_payments.isNotEmpty) "payments": _payments,
      };

      await _purchaseService.createPurchase(payload);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /* ----------------- totals ----------------- */

  double get _subtotal =>
      _items.fold<double>(0, (sum, i) => sum + (i['quantity'] * i['price']));
  double get _discount => double.tryParse(discountController.text).absOrZero();
  double get _tax => double.tryParse(taxController.text).absOrZero();
  double get _total => _subtotal - _discount + _tax;
  double get _paid => _payments.fold<double>(
    0,
    (sum, p) => sum + (p['amount'] as num).toDouble(),
  );
  double get _balance => _total - _paid;

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    discountController.dispose();
    taxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final paid = _paid;
    final balance = _balance;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Purchase")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _hiddenBarcodeInput(),

              // Vendor & Branch
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _pickVendor,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Vendor",
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedVendor == null
                                ? "Select Vendor"
                                : "${_selectedVendor?['first_name'] ?? ''} ${_selectedVendor?['last_name'] ?? ''}"
                                      .trim(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickBranch,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Branch",
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedBranch?['name'] ?? "Select Branch",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Discount & Tax + Receive Now
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: discountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Discount",
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: taxController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Tax",
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Receive Now"),
                        subtitle: const Text(
                          "If ON, items can include 'received_qty'",
                        ),
                        value: _receiveNow,
                        onChanged: (v) {
                          setState(() {
                            _receiveNow = v;
                            // normalize received_qtys
                            for (final i in _items) {
                              final q = (i['quantity'] as int?) ?? 0;
                              i['received_qty'] = v
                                  ? (i['received_qty'] ?? q).clamp(0, q)
                                  : 0;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Scanner toggle
              ElevatedButton.icon(
                onPressed: () {
                  Future.delayed(const Duration(milliseconds: 50), () {
                    _barcodeFocusNode.requestFocus();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scannerEnabled ? Colors.green : null,
                ),
                icon: Icon(
                  _scannerEnabled ? Icons.check_circle : Icons.qr_code_scanner,
                ),
                label: Text(
                  _scannerEnabled ? "Scanning Active" : "Start Scanning",
                ),
              ),

              const SizedBox(height: 12),

              // Items
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Items",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      if (_items.isEmpty) const Text("No items added"),
                      ..._items.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final i = entry.value;
                        final q = i['quantity'];
                        final price = i['price'];
                        final cost = i['cost_price'];
                        final rcv = i['received_qty'] ?? 0;

                        final subtitle = _receiveNow
                            ? "Qty: $q | Price: \$$cost | Receive: $rcv"
                            : "Qty: $q | Price: \$$price";

                        return ListTile(
                          title: Text(
                            i['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(subtitle),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => _items.removeAt(idx)),
                          ),
                          onTap: () => _editItem(idx),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _addItemManual,
                          icon: const Icon(Icons.add),
                          label: const Text("Add Product"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Payments
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Payments",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      if (_payments.isEmpty) const Text("No payments yet"),
                      ..._payments.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final p = entry.value;
                        return ListTile(
                          title: Text("\$${p['amount']}"),
                          subtitle: Text("Method: ${p['method']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => _payments.removeAt(idx)),
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _addPaymentDialog,
                          icon: const Icon(Icons.add),
                          label: const Text("Add Payment"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Totals
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text("Subtotal"),
                      trailing: Text("\$${_subtotal.toStringAsFixed(2)}"),
                    ),
                    ListTile(
                      title: const Text("Discount"),
                      trailing: Text("- \$${_discount.toStringAsFixed(2)}"),
                    ),
                    ListTile(
                      title: const Text("Tax"),
                      trailing: Text("+ \$${_tax.toStringAsFixed(2)}"),
                    ),
                    const Divider(height: 0),
                    ListTile(
                      title: const Text("Total"),
                      trailing: Text("\$${total.toStringAsFixed(2)}"),
                    ),
                    ListTile(
                      title: const Text("Paid"),
                      trailing: Text("\$${paid.toStringAsFixed(2)}"),
                    ),
                    ListTile(
                      title: const Text(
                        "Balance",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Text(
                        "\$${balance.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: balance > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submitPurchase,
                  icon: const Icon(Icons.check),
                  label: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Create Purchase"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ----------------- small helpers ----------------- */

extension _NumX on double? {
  double absOrZero() {
    final v = this ?? 0;
    return v.isFinite ? (v < 0 ? -v : v) : 0;
  }
}
