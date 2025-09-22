import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PurchaseClaimDetailScreen extends StatefulWidget {
  final int claimId;
  const PurchaseClaimDetailScreen({super.key, required this.claimId});

  @override
  State<PurchaseClaimDetailScreen> createState() => _PurchaseClaimDetailScreenState();
}

class _PurchaseClaimDetailScreenState extends State<PurchaseClaimDetailScreen> {
  Map<String, dynamic>? _claim;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse("${ApiClient.baseUrl}/purchase-claims/${widget.claimId}");

    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _claim = data['data'];
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to load claim details")),
      );
    }
  }

  Future<void> _approveClaim() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse("${ApiClient.baseUrl}/purchase-claims/${widget.claimId}/approve");

    final res = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      await _fetchDetail();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Claim approved successfully")),
      );
    } else {
      String msg = "Failed to approve claim";
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) msg = body['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _rejectClaim({String? reason}) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse("${ApiClient.baseUrl}/purchase-claims/${widget.claimId}/reject");

    // Your backend reject() didn’t require a payload; we’ll still support an optional reason.
    final res = await http.post(
      uri,
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
        // If you want to send a reason, keep content-type/json + small body:
        if (reason != null && reason.trim().isNotEmpty) "Content-Type": "application/json",
      },
      body: (reason != null && reason.trim().isNotEmpty)
          ? jsonEncode({"reason": reason.trim()})
          : null,
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      await _fetchDetail();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Claim rejected")),
      );
    } else {
      String msg = "Failed to reject claim";
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) msg = body['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmRejectDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reject Claim"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Optional reason...",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _rejectClaim(reason: controller.text);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "approved":
        return Colors.green;
      case "pending":
        return Colors.orange;
      case "rejected":
        return Colors.red;
      case "closed":
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_claim == null) {
      return const Scaffold(
        body: Center(child: Text("Failed to load claim details")),
      );
    }

    final items = (_claim!['items'] as List?) ?? [];
    final status = (_claim!['status'] ?? '').toString();
    final purchase = _claim!['purchase'] ?? {};
    final vendor = purchase['vendor'];
    final branch = _claim!['branch'];
    final currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");

    final createdAt = _claim!['created_at'];
    final created = createdAt != null ? DateTime.tryParse(createdAt) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text("Claim #${_claim!['claim_no']}"),
        actions: const [BranchIndicator(tappable: false)],
      ),
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
                  backgroundColor: _statusColor(status),
                ),
                Text(
                  created != null ? DateFormat.yMMMd().add_jm().format(created) : '',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 📄 Claim + Purchase Info
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Invoice: ${purchase['invoice_no'] ?? 'N/A'}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text("Vendor: ${vendor?['name'] ?? 'N/A'}"),
                    Text("Branch: ${branch?['name'] ?? 'N/A'}"),
                    Text("Type: ${_claim!['type'] ?? 'N/A'}"),
                    if ((_claim!['reason'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text("Reason: ${_claim!['reason']}"),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PurchaseDetailScreen(purchaseId: purchase['id']),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long),
                        label: const Text("View Purchase Details"),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🛒 Items Section
            const Text(
              "Claimed Items",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...items.map((item) {
              final prod = item['product'] ?? {};
              final name = prod['name'] ?? 'Product';
              final sku = prod['sku'] ?? '-';
              final qty = item['quantity'];
              final priceStr = item['price']?.toString() ?? '0';
              final totalStr = item['total']?.toString() ?? '0';
              final price = double.tryParse(priceStr) ?? 0;
              final total = double.tryParse(totalStr) ?? 0;
              final affectsStock = (item['affects_stock'] == true);
              final batch = (item['batch_no'] ?? '').toString();
              final expiry = (item['expiry_date'] ?? '').toString();
              final remarks = (item['remarks'] ?? '').toString();

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("SKU: $sku • Affects stock: ${affectsStock ? 'Yes' : 'No'}"),
                      if (batch.isNotEmpty || expiry.isNotEmpty || remarks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text([
                            if (batch.isNotEmpty) "Batch: $batch",
                            if (expiry.isNotEmpty) "Expiry: $expiry",
                            if (remarks.isNotEmpty) "Remarks: $remarks",
                          ].join(" • ")),
                        ),
                    ],
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade50,
                    child: Text(
                      '$qty',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Price: ${currency.format(price)}"),
                      Text("Total: ${currency.format(total)}"),
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
                    "Subtotal: ${currency.format(double.tryParse('${_claim!['subtotal']}') ?? 0)}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    "Tax: ${currency.format(double.tryParse('${_claim!['tax']}') ?? 0)}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Divider(),
                  Text(
                    "Total: ${currency.format(double.tryParse('${_claim!['total']}') ?? 0)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
            ),

            if (status == "pending") ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _approveClaim,
                      icon: const Icon(Icons.check),
                      label: const Text("Approve"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _confirmRejectDialog,
                      icon: const Icon(Icons.cancel),
                      label: const Text("Reject"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
