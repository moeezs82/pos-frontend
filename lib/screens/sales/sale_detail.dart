import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

class SaleDetailScreen extends StatefulWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Map<String, dynamic>? _sale;
  bool _loading = true;
  bool _updated = false; // track if something changed

  @override
  void initState() {
    super.initState();
    _fetchSale();
  }

  Future<void> _fetchSale() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final res = await http.get(
      Uri.parse("${ApiClient.baseUrl}/sales/${widget.saleId}"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _sale = data['data'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final token = Provider.of<AuthProvider>(
                context,
                listen: false,
              ).token!;
              final res = await http.post(
                Uri.parse(
                  "${ApiClient.baseUrl}/sales/${widget.saleId}/payments",
                ),
                headers: {
                  "Authorization": "Bearer $token",
                  "Accept": "application/json",
                },
                body: {"amount": amountController.text, "method": method},
              );
              if (res.statusCode == 200) {
                Navigator.pop(context); // close dialog
                _fetchSale();
                _updated = true; // mark updated
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // 🖨 Generate PDF Invoice
  Future<void> _printInvoice() async {
    if (_sale == null) return;

    final payments = (_sale!['payments'] as List);
    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + double.tryParse(p['amount'].toString())!,
    );
    final total = double.tryParse(_sale!['total'].toString()) ?? 0.0;
    final remaining = total - paid;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              "Invoice",
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text("Invoice No: ${_sale!['invoice_no']}"),
          pw.Text("Date: ${_sale!['created_at'].toString().substring(0, 10)}"),
          pw.SizedBox(height: 10),

          pw.Text(
            "Customer:",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            "${_sale!['customer']?['first_name'] ?? "Walk-in"} ${_sale!['customer']?['last_name'] ?? ""}",
          ),
          pw.Text("Email: ${_sale!['customer']?['email'] ?? ""}"),
          pw.Text("Phone: ${_sale!['customer']?['phone'] ?? ""}"),
          pw.SizedBox(height: 10),

          pw.Text(
            "Branch:",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(_sale!['branch']?['name'] ?? "N/A"),
          pw.SizedBox(height: 20),

          pw.Text(
            "Items",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.Table.fromTextArray(
            headers: ["Product", "Qty", "Price", "Total"],
            data: (_sale!['items'] as List)
                .map(
                  (i) => [
                    i['product']['name'],
                    i['quantity'].toString(),
                    "\$${i['price']}",
                    "\$${i['total']}",
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 20),

          pw.Text(
            "Summary",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.Text("Subtotal: \$${_sale!['subtotal']}"),
          pw.Text("Discount: \$${_sale!['discount']}"),
          pw.Text("Tax: \$${_sale!['tax']}"),
          pw.Text(
            "Total: \$${_sale!['total']}",
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text("Paid: \$${paid.toStringAsFixed(2)}"),
          pw.Text(
            "Remaining: \$${remaining.toStringAsFixed(2)}",
            style: pw.TextStyle(
              color: remaining > 0
                  ? PdfColors.red
                  : remaining < 0
                  ? PdfColors.orange
                  : PdfColors.green,
              fontSize: 14,
            ),
          ),
          pw.SizedBox(height: 20),

          pw.Text(
            "Payments",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          if (payments.isEmpty) pw.Text("No payments yet"),
          ...payments.map(
            (p) => pw.Text("Method: ${p['method']} | Amount: \$${p['amount']}"),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final payments = (_sale?['payments'] as List?) ?? [];
    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + double.tryParse(p['amount'].toString())!,
    );
    final total = double.tryParse(_sale?['total']?.toString() ?? "0") ?? 0.0;
    final remaining = total - paid;

    Color balanceColor;
    if (remaining > 0) {
      balanceColor = Colors.red; // unpaid
    } else if (remaining < 0) {
      balanceColor = Colors.orange; // overpaid
    } else {
      balanceColor = Colors.green; // fully paid
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated); // send back "true" if updated
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Sale Detail")),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sale == null
            ? const Center(child: Text("Sale not found"))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 📌 Invoice Header
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          "Invoice: ${_sale!['invoice_no']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Date: ${_sale!['created_at'].toString().substring(0, 10)}",
                            ),
                            Text(
                              "Customer: ${_sale!['customer']?['first_name'] ?? "Walk-in"} ${_sale!['customer']?['last_name'] ?? ""}",
                            ),
                            Text("Branch: ${_sale!['branch']?['name']}"),
                            Text("Status: ${_sale!['status']}"),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.print),
                          onPressed: _printInvoice,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 📌 Items
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              "Items",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ...(_sale!['items'] as List).map(
                            (i) => ListTile(
                              title: Text(i['product']['name']),
                              subtitle: Text(
                                "Qty: ${i['quantity']} × \$${i['price']}",
                              ),
                              trailing: Text("\$${i['total']}"),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 📌 Payments
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              "Payments",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          if (payments.isEmpty)
                            const ListTile(title: Text("No payments yet")),
                          ...payments.map(
                            (p) => ListTile(
                              title: Text("\$${p['amount']}"),
                              subtitle: Text("Method: ${p['method']}"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: ElevatedButton.icon(
                              onPressed: _addPayment,
                              icon: const Icon(Icons.add),
                              label: const Text("Add Payment"),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 📌 Summary
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text("Subtotal"),
                            trailing: Text("\$${_sale!['subtotal']}"),
                          ),
                          ListTile(
                            title: const Text("Discount"),
                            trailing: Text("-\$${_sale!['discount']}"),
                          ),
                          ListTile(
                            title: const Text("Tax"),
                            trailing: Text("\$${_sale!['tax']}"),
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text(
                              "Total",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Text(
                              "\$${_sale!['total']}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text("Paid"),
                            trailing: Text("\$${paid.toStringAsFixed(2)}"),
                          ),
                          ListTile(
                            title: const Text("Remaining"),
                            trailing: Text(
                              "\$${remaining.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: balanceColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
