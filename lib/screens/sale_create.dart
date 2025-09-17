import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/api_service.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/branch_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];

  final discountController = TextEditingController();
  final taxController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();

  bool _submitting = false;
  bool _scannerEnabled = false;

  @override
  void initState() {
    super.initState();
    _barcodeFocusNode.addListener(() {
      setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });
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

  // 🏷 Customer Picker
  Future<void> _pickCustomer() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final customer = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );

    if (customer == null) {
      // Clear selection (Walk-in / deselect)
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

  // 🏷 Add Product Manually
  Future<void> _addItemManual() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductPickerSheet(token: token),
    );
    if (product == null) return;

    final qtyController = TextEditingController(text: "1");
    final priceController = TextEditingController(
      text: product['price'].toString(),
    );

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Add ${product['name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Quantity",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Price",
                border: OutlineInputBorder(),
              ),
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
              setState(() {
                _items.add({
                  "product_id": product['id'],
                  "name": product['name'],
                  "quantity": int.tryParse(qtyController.text) ?? 1,
                  "price": double.tryParse(priceController.text) ?? 0.0,
                });
              });
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
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
              decoration: const InputDecoration(
                labelText: "Amount",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(
                labelText: "Method",
                border: OutlineInputBorder(),
              ),
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

  // 🏷 Hidden Barcode Field
  Widget _buildHiddenBarcodeInput() {
    return Opacity(
      opacity: 0,
      child: TextField(
        controller: _barcodeController,
        focusNode: _barcodeFocusNode,
        autofocus: false,
        onSubmitted: (code) {
          // TODO: implement barcode scan handling
        },
      ),
    );
  }

  // 🏷 Submit
  Future<void> _submitSale() async {
    if (_selectedBranchId == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Branch & at least 1 item required")),
      );
      return;
    }

    setState(() => _submitting = true);

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final body = {
      "branch_id": _selectedBranchId!,
      if (_selectedCustomerId != null) "customer_id": _selectedCustomerId!,
      "discount": discountController.text.isEmpty
          ? "0"
          : discountController.text,
      "tax": taxController.text.isEmpty ? "0" : taxController.text,
      for (int i = 0; i < _items.length; i++) ...{
        "items[$i][product_id]": _items[i]['product_id'].toString(),
        "items[$i][quantity]": _items[i]['quantity'].toString(),
        "items[$i][price]": _items[i]['price'].toString(),
      },
      for (int j = 0; j < _payments.length; j++) ...{
        "payments[$j][amount]": _payments[j]['amount'].toString(),
        "payments[$j][method]": _payments[j]['method'].toString(),
      },
    };

    final res = await http.post(
      Uri.parse("${ApiService.baseUrl}/sales"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      body: body,
    );

    setState(() => _submitting = false);

    if (res.statusCode == 200) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to create sale")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(
      0,
      (sum, i) => sum + (i['quantity'] * i['price']),
    );
    final paid = _payments.fold<double>(
      0,
      (sum, p) => sum + double.tryParse(p['amount'].toString())!,
    );
    final balance = total - paid;

    return Scaffold(
      appBar: AppBar(title: const Text("Create Sale")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildHiddenBarcodeInput(),

              // Customer & Branch
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
                          child: Text(
                            _selectedCustomer?['first_name'] ??
                                "Select Customer",
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
                          decoration: const InputDecoration(
                            labelText: "Discount",
                          ),
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

              // Scanner Toggle Button
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
                        final index = entry.key;
                        final i = entry.value;
                        return ListTile(
                          title: Text(
                            i['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Qty: ${i['quantity']} | Price: \$${i['price']}",
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () =>
                                setState(() => _items.removeAt(index)),
                          ),
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
