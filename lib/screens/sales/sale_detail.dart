import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

// parts
import 'package:enterprise_pos/screens/sales/parts/sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_payments_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_totals_editable.dart';

class SaleDetailScreen extends StatefulWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Map<String, dynamic>? _sale;
  bool _loading = true;
  bool _updated = false;

  // optional vendor filter for add-item
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;

  // controllers for inline edit (filled from _sale on fetch)
  final discountCtl = TextEditingController();
  final taxCtl = TextEditingController();

  ApiClient get _api =>
      ApiClient(token: Provider.of<AuthProvider>(context, listen: false).token);

  @override
  void initState() {
    super.initState();
    _fetchSale();
  }

  @override
  void dispose() {
    discountCtl.dispose();
    taxCtl.dispose();
    super.dispose();
  }

  /* ====================== Data ====================== */

  Future<void> _fetchSale() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get("/sales/${widget.saleId}");
      if (!mounted) return;
      setState(() {
        _sale = res['data'];
        _selectedVendorId = _sale?['vendor_id'];
        // seed controllers
        discountCtl.text = (_sale?['discount'] ?? 0).toString();
        taxCtl.text = (_sale?['tax'] ?? 0).toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load sale: $e")),
      );
    }
  }

  Future<void> _updateDiscountTax() async {
    // push only discount & tax
    try {
      await _api.put(
        "/sales/${widget.saleId}",
        body: {
          "discount": double.tryParse(discountCtl.text.trim()) ?? 0.0,
          "tax": double.tryParse(taxCtl.text.trim()) ?? 0.0,
        },
      );
      if (!mounted) return;
      _updated = true;
      await _fetchSale();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Updated discount/tax.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Update failed: $e")),
      );
    }
  }

  /* ====================== Payments ====================== */

  Future<void> _addPayment() async {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              try {
                await _api.post(
                  "/sales/${widget.saleId}/payments",
                  body: {"amount": amountController.text, "method": method},
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Add payment failed: $e")),
                );
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _editPayment(Map p) async {
    final amountCtl = TextEditingController(text: p['amount'].toString());
    String method = (p['method'] ?? 'cash').toString();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtl,
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
              onChanged: (v) => method = v!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            child: const Text("Save"),
            onPressed: () async {
              try {
                await _api.put(
                  "/sales/${widget.saleId}/payments/${p['id']}",
                  body: {"amount": amountCtl.text, "method": method},
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Update payment failed: $e")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deletePayment(int paymentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Payment"),
        content: const Text("Are you sure you want to delete this payment?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, delete")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete("/sales/${widget.saleId}/payments/$paymentId");
      if (!mounted) return;
      await _fetchSale();
      _updated = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete payment failed: $e")),
      );
    }
  }

  /* ====================== Items ====================== */

  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final vendor = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: token),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (vendor == null) {
        _selectedVendor = null;
        _selectedVendorId = null;
      } else {
        _selectedVendor = vendor;
        _selectedVendorId = vendor['id'] as int?;
      }
    });
  }

  Future<void> _addItem() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final product = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: ProductPickerSheet(token: token, vendorId: _selectedVendorId),
      ),
    );
    if (product == null) return;

    final qtyCtl = TextEditingController(text: "1");
    final priceCtl = TextEditingController(text: (product['price'] ?? 0).toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Add ${product['name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              try {
                await _api.post(
                  "/sales/${widget.saleId}/items",
                  body: {
                    "product_id": product['id'],
                    "quantity": int.tryParse(qtyCtl.text) ?? 1,
                    "price": double.tryParse(priceCtl.text) ?? 0.0,
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Add item failed: $e")),
                );
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _editItem(Map item) async {
    final qtyCtl = TextEditingController(text: item['quantity'].toString());
    final priceCtl = TextEditingController(text: item['price'].toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Item"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            child: const Text("Save"),
            onPressed: () async {
              try {
                await _api.put(
                  "/sales/${widget.saleId}/items/${item['id']}",
                  body: {
                    "quantity": int.tryParse(qtyCtl.text) ?? item['quantity'],
                    "price": double.tryParse(priceCtl.text) ?? item['price'],
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Update item failed: $e")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(int itemId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Item"),
        content: const Text("Remove this item from the sale? Stock will be adjusted accordingly."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, delete")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete("/sales/${widget.saleId}/items/$itemId");
      if (!mounted) return;
      await _fetchSale();
      _updated = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete item failed: $e")),
      );
    }
  }

  /* ====================== Print ====================== */

  Future<void> _printInvoice() async {
    if (_sale == null) return;

    final payments = (_sale!['payments'] as List);
    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0),
    );
    final total = double.tryParse(_sale!['total'].toString()) ?? 0.0;
    final remaining = total - paid;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Header(
            level: 0,
            child: pw.Text("Invoice", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text("Invoice No: ${_sale!['invoice_no']}"),
          pw.Text("Date: ${_sale!['created_at'].toString().substring(0, 10)}"),
          pw.SizedBox(height: 10),
          pw.Text("Salesman: ${_sale!['salesman']?['name'] ?? "-"}"),
          pw.SizedBox(height: 10),
          pw.Text("Vendor: ${_sale!['vendor']?['first_name'] ?? "No Vendor"} ${_sale!['vendor']?['last_name'] ?? ""}"),
          pw.SizedBox(height: 10),
          pw.Text("Customer:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text("${_sale!['customer']?['first_name'] ?? "Walk-in"} ${_sale!['customer']?['last_name'] ?? ""}"),
          pw.Text("Email: ${_sale!['customer']?['email'] ?? ""}"),
          pw.Text("Phone: ${_sale!['customer']?['phone'] ?? ""}"),
          pw.SizedBox(height: 10),
          pw.Text("Branch:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(_sale!['branch']?['name'] ?? "N/A"),
          pw.SizedBox(height: 20),
          pw.Text("Items", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.Table.fromTextArray(
            headers: ["Product", "Qty", "Price", "Total"],
            data: (_sale!['items'] as List)
                .map((i) => [
                      i['product']['name'],
                      i['quantity'].toString(),
                      "\$${i['price']}",
                      "\$${i['total']}",
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Text("Summary", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.Text("Subtotal: \$${_sale!['subtotal']}"),
          pw.Text("Discount: \$${_sale!['discount']}"),
          pw.Text("Tax: \$${_sale!['tax']}"),
          pw.Text("Total: \$${_sale!['total']}", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text("Paid: \$${paid.toStringAsFixed(2)}"),
          pw.Text(
            "Remaining: \$${remaining.toStringAsFixed(2)}",
            style: pw.TextStyle(
              color: remaining > 0 ? PdfColors.red : remaining < 0 ? PdfColors.orange : PdfColors.green,
              fontSize: 14,
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text("Payments", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          if (payments.isEmpty) pw.Text("No payments yet"),
          ...payments.map((p) => pw.Text("Method: ${p['method']} | Amount: \$${p['amount']}")),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  /* ====================== Build ====================== */

  @override
  Widget build(BuildContext context) {
    final payments = (_sale?['payments'] as List?) ?? [];
    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0),
    );
    final total = double.tryParse(_sale?['total']?.toString() ?? "0") ?? 0.0;
    final remaining = total - paid;

    final balanceColor = remaining > 0
        ? Colors.red
        : remaining < 0
            ? Colors.orange
            : Colors.green;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Sale Detail"),
          actions: const [BranchIndicator(tappable: false)],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sale == null
                ? const Center(child: Text("Sale not found"))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(
                              "Invoice: ${_sale!['invoice_no']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Date: ${_sale!['created_at'].toString().substring(0, 10)}"),
                                Text("Salesman: ${_sale!['salesman']?['name'] ?? "-"}"),
                                Text("Vendor: ${_sale!['vendor']?['first_name'] ?? "No Vendor"} ${_sale!['vendor']?['last_name'] ?? ""}"),
                                Text("Customer: ${_sale!['customer']?['first_name'] ?? "Walk-in"} ${_sale!['customer']?['last_name'] ?? ""}"),
                                Text("Branch: ${_sale!['branch']?['name']}"),
                                Text("Status: ${_sale!['status']}"),
                              ],
                            ),
                            trailing: IconButton(icon: const Icon(Icons.print), onPressed: _printInvoice),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Items section
                        SaleItemsSection(
                          sale: _sale!,
                          onPickVendor: _pickVendor,
                          selectedVendor: _selectedVendor,
                          onAddItem: _addItem,
                          onEditItem: _editItem,
                          onDeleteItem: _deleteItem,
                        ),

                        const SizedBox(height: 12),

                        // Payments section
                        SalePaymentsSection(
                          payments: payments,
                          onAddPayment: _addPayment,
                          onEditPayment: _editPayment,
                          onDeletePayment: _deletePayment,
                        ),

                        const SizedBox(height: 12),

                        // Summary with inline editable discount/tax
                        SaleTotalsEditable(
                          sale: _sale!,
                          discountController: discountCtl,
                          taxController: taxCtl,
                          paid: paid,
                          balanceColor: balanceColor,
                          onSave: _updateDiscountTax,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
