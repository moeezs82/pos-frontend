import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/sale_service.dart'; // ⬅️ NEW
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/branch_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart'; // ⬅️ NEW
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CreateSaleScreen extends StatefulWidget {
  const CreateSaleScreen({super.key});

  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedBranchId;
  String? _selectedCustomerId;
  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedCustomer;

  // ⬇️ NEW: Optional vendor
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];

  final discountController = TextEditingController();
  final taxController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();

  bool _submitting = false;
  bool _scannerEnabled = false;
  bool _autoCashIfEmpty = true;

  late ProductService _productService;
  late SaleService _saleService; // ⬅️ NEW

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _saleService = SaleService(token: token); // ⬅️ NEW
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
    super.dispose();
  }

  // 🏷 Branch Picker
  Future<void> _pickBranch() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final branch = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => BranchPickerSheet(token: token),
    );
    if (branch != null) {
      setState(() {
        _selectedBranch = branch;
        _selectedBranchId = branch['id'].toString();
      });
    }
  }

  // 🏷 Customer Picker (supports deselect)
  Future<void> _pickCustomer() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final customer = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );

    if (customer == null) {
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerId = null;
      });
    } else {
      setState(() {
        _selectedCustomer = customer;
        _selectedCustomerId = customer['id'].toString();
      });
    }
  }

  // 🏷 Vendor Picker (optional) — NEW
  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final vendor = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorPickerSheet(token: token),
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

  // 🏷 Add Product (manual picker → instant add)
  Future<void> _addItemManual() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    // ⬇️ When vendor is selected, pass it to the picker so its API can filter.
    // Assumes ProductPickerSheet optionally accepts vendorId (int?).
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(
        token: token,
        vendorId: _selectedVendorId,
      ),
    );
    if (product == null) return;

    setState(() {
      _items.add({
        "product_id": product['id'],
        "name": product['name'],
        "cost_price": product['cost_price'],
        "wholesale_price": product['wholesale_price'],
        "quantity": 1,
        "price": double.tryParse(product['price'].toString()) ?? 0.0,
      });
    });
  }

  // 🏷 Edit Product (when tapping item)
  void _editItem(int index) {
    final item = _items[index];
    final qtyController = TextEditingController(text: item['quantity'].toString());
    final priceController = TextEditingController(text: item['price'].toString());

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
                  icon: Icon(showHidden ? Icons.visibility_off : Icons.visibility),
                  label: Text(showHidden ? "Hide Cost/Wholesale" : "Show Cost/Wholesale"),
                  onPressed: () => setLocal(() => showHidden = !showHidden),
                ),
                if (showHidden) ...[
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Cost Price: \$${costPrice.toString()}", style: const TextStyle(color: Colors.grey)),
                        Text("Wholesale Price: \$${wholesalePrice.toString()}", style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _items[index]['quantity'] = int.tryParse(qtyController.text) ?? 1;
                    _items[index]['price'] = double.tryParse(priceController.text) ?? 0.0;
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

  // 🏷 Add Payment
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final amt = double.tryParse(amountController.text) ?? 0.0;
              if (amt > 0) {
                setState(() {
                  _payments.add({"amount": amt.toString(), "method": method});
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

  // 🏷 Barcode Scan — DO NOT TOUCH (left as-is)
  Future<void> _onBarcodeScanned(String code) async {
    if (code.isEmpty) return;
    final product = await _productService.getProductByBarcode(code);

    if (product != null) {
      setState(() {
        _items.add({
          "product_id": product['id'],
          "name": product['name'],
          "cost_price": product['cost_price'],
          "wholesale_price": product['wholesale_price'],
          "quantity": 1,
          "price": double.tryParse(product['price'].toString()) ?? 0.0,
        });
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product not found: $code")));
    }

    _barcodeController.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  Widget _buildHiddenBarcodeInput() {
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

  // 🏷 Submit — now calls SaleService
  Future<void> _submitSale() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add at least 1 item")));
      return;
    }

    // Prefer global branch; fallback to local only when global = All
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final String? effectiveBranchIdStr = globalBranchId?.toString() ?? _selectedBranchId;

    if (effectiveBranchIdStr == null || effectiveBranchIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a branch (on Home)")));
      return;
    }
    final int effectiveBranchId = int.tryParse(effectiveBranchIdStr) ?? 0;
    if (effectiveBranchId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid branch")));
      return;
    }

    // Totals
    double subtotal = _items.fold<double>(0, (sum, i) => sum + ((i['quantity'] as num) * (i['price'] as num))).toDouble();
    double discount = double.tryParse(discountController.text.trim()) ?? 0.0;
    double tax = double.tryParse(taxController.text.trim()) ?? 0.0;
    double total = (subtotal - discount + tax).clamp(0, double.infinity);

    // Payments (auto-cash if empty)
    final List<Map<String, dynamic>> paymentsToSend = List<Map<String, dynamic>>.from(_payments);
    if (_autoCashIfEmpty && paymentsToSend.isEmpty) {
      paymentsToSend.add({"amount": total.toStringAsFixed(2), "method": "cash"});
    }

    setState(() => _submitting = true);

    try {
      final res = await _saleService.createSale(
        branchId: effectiveBranchId,
        customerId: _selectedCustomerId != null ? int.tryParse(_selectedCustomerId!) : null,
        vendorId: _selectedVendorId, // ⬅️ NEW: pass vendor if selected
        items: _items,
        payments: paymentsToSend,
        discount: discount,
        tax: tax,
      );

      // consider both 200 & 201 as OK if your ApiClient exposes status; otherwise rely on success structure
      // If your API wraps success payload, adjust accordingly.
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create sale: $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double toDouble(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;
    String money(num v) => v.toStringAsFixed(2);

    final subtotal = _items.fold<double>(0, (sum, i) => sum + ((i['quantity'] as num) * (i['price'] as num))).toDouble();
    final discount = toDouble(discountController);
    final tax = toDouble(taxController);
    final total = (subtotal - discount + tax).clamp(0, double.infinity);

    final paid = _payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0));
    final balance = total - paid;
    final isAll = context.watch<BranchProvider>().isAll;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Sale"),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: BranchIndicator(tappable: false),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildHiddenBarcodeInput(),

              // Customer, Branch, Vendor (NEW)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _pickCustomer,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Customer",
                            border: OutlineInputBorder(),
                          ),
                          child: Text(_selectedCustomer?['first_name'] ?? "Select Customer"),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isAll)
                        InkWell(
                          onTap: _pickBranch,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Branch",
                              border: OutlineInputBorder(),
                            ),
                            child: Text(_selectedBranch?['name'] ?? "Select Branch"),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // ⬇️ NEW: Vendor (optional)
                      InkWell(
                        onTap: _pickVendor,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Vendor (optional)",
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(_selectedVendor?['name']?.toString() ?? "Select Vendor")),
                              if (_selectedVendorId != null)
                                IconButton(
                                  tooltip: "Clear",
                                  onPressed: () => setState(() {
                                    _selectedVendor = null;
                                    _selectedVendorId = null;
                                  }),
                                  icon: const Icon(Icons.clear),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Discount & Tax
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: discountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Discount"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: taxController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Tax"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Scanner Toggle
              ElevatedButton.icon(
                onPressed: () {
                  Future.delayed(const Duration(milliseconds: 50), () {
                    _barcodeFocusNode.requestFocus();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scannerEnabled ? Colors.green : null,
                ),
                icon: Icon(_scannerEnabled ? Icons.check_circle : Icons.qr_code_scanner),
                label: Text(_scannerEnabled ? "Scanning Active" : "Start Scanning"),
              ),

              const SizedBox(height: 12),

              // Items
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Items", style: TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      if (_items.isEmpty) const Text("No items added"),
                      ..._items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final i = entry.value;
                        return ListTile(
                          title: Text(i['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Qty: ${i['quantity']} | Price: \$${i['price']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => _items.removeAt(index)),
                          ),
                          onTap: () => _editItem(index),
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
                      const Text("Payments", style: TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Auto-cash if no payment"),
                        subtitle: const Text("When ON, sends full invoice total as CASH if you add no payments."),
                        value: _autoCashIfEmpty,
                        onChanged: (v) => setState(() => _autoCashIfEmpty = v),
                      ),
                      if (_payments.isEmpty) const Text("No payments yet"),
                      ..._payments.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final p = entry.value;
                        return ListTile(
                          title: Text("\$${p['amount']}"),
                          subtitle: Text("Method: ${p['method']}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => _payments.removeAt(idx)),
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
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ListTile(dense: true, title: const Text("Subtotal"), trailing: Text("\$${money(subtotal)}", style: const TextStyle(fontWeight: FontWeight.w600))),
                      ListTile(dense: true, title: const Text("Discount"), trailing: Text("-\$${money(discount)}", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red))),
                      ListTile(dense: true, title: const Text("Tax"), trailing: Text("\$${money(tax)}", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                      const Divider(height: 8),
                      ListTile(
                        title: const Text("Total", style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text("\$${money((subtotal - discount + tax).clamp(0, double.infinity))}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                      ),
                      ListTile(dense: true, title: const Text("Paid"), trailing: Text("\$${money(_payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0)))}", style: const TextStyle(fontWeight: FontWeight.w600))),
                      ListTile(
                        dense: true,
                        title: const Text("Balance"),
                        trailing: Text(
                          "\$${money((subtotal - discount + tax).clamp(0, double.infinity) - _payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0)))}",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: balanceColor((subtotal - discount + tax).clamp(0, double.infinity) - _payments.fold<double>(0, (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submitSale,
                  icon: const Icon(Icons.check),
                  label: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Create Sale"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.orange;
    return Colors.green;
  }
}
