import 'dart:convert';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SaleReturnDetailScreen extends StatefulWidget {
  final int returnId;
  const SaleReturnDetailScreen({super.key, required this.returnId});

  @override
  State<SaleReturnDetailScreen> createState() => _SaleReturnDetailScreenState();
}

class _SaleReturnDetailScreenState extends State<SaleReturnDetailScreen> {
  Map<String, dynamic>? _return;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri =
        Uri.parse("${ApiService.baseUrl}/sales/returns/${widget.returnId}");

    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _return = data['data'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _approveReturn() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
        "${ApiService.baseUrl}/sales/returns/${widget.returnId}/approve");

    final res = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (res.statusCode == 200) {
      await _fetchDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Return approved successfully")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to approve return")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_return == null) {
      return const Scaffold(
        body: Center(child: Text("Failed to load return details")),
      );
    }

    final items = _return!['items'] as List;
    final status = _return!['status'];
    final sale = _return!['sale'];
    final currency =
        NumberFormat.simpleCurrency(decimalDigits: 2, name: ""); // money format

    Color statusColor;
    switch (status) {
      case "approved":
        statusColor = Colors.green;
        break;
      case "pending":
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.red;
    }

    return Scaffold(
      appBar: AppBar(title: Text("Return #${_return!['return_no']}")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔖 Status + Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(
                    status.toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: statusColor,
                ),
                Text(
                  DateFormat.yMMMd().add_jm().format(
                        DateTime.parse(_return!['created_at']),
                      ),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 📄 Return + Sale Info
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Invoice: ${sale['invoice_no']}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      "Customer: ${sale['customer'] != null ? "${sale['customer']['first_name']} ${sale['customer']['last_name']}" : "Walk-In"}",
                    ),
                    Text("Branch: ${sale['branch']['name']}"),
                    if (_return!['reason'] != null &&
                        _return!['reason'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text("Reason: ${_return!['reason']}"),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SaleDetailScreen(
                                saleId: sale['id'],
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long),
                        label: const Text("View Sale Details"),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🛒 Items Section
            const Text("Returned Items",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),
            ...items.map((item) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(item['product']['name']),
                  subtitle: Text("SKU: ${item['product']['sku']}"),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Text(
                      item['quantity'].toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Price: ${currency.format(double.parse(item['price']))}",
                      ),
                      Text(
                        "Total: ${currency.format(double.parse(item['total']))}",
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            // 💰 Summary Section
            Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "Subtotal: ${currency.format(double.parse(_return!['subtotal']))}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    "Tax: ${currency.format(double.parse(_return!['tax']))}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Divider(),
                  Text(
                    "Total: ${currency.format(double.parse(_return!['total']))}",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ],
              ),
            ),

            if (status == "pending") ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _approveReturn,
                  icon: const Icon(Icons.check),
                  label: const Text("Approve Return"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
