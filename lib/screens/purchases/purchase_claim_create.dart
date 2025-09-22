import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class CreatePurchaseClaimScreen extends StatefulWidget {
  const CreatePurchaseClaimScreen({super.key});

  @override
  State<CreatePurchaseClaimScreen> createState() => _CreatePurchaseClaimScreenState();
}

class _CreatePurchaseClaimScreenState extends State<CreatePurchaseClaimScreen> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedPurchase;
  List<dynamic> _purchaseItems = [];

  // controllers per purchase_item_id
  final Map<int, TextEditingController> _qtyCtrls = {};
  final Map<int, TextEditingController> _remarksCtrls = {};
  final Map<int, TextEditingController> _batchCtrls = {};
  final Map<int, TextEditingController> _expiryCtrls = {};
  final Map<int, bool> _affectsStock = {};

  final TextEditingController _reasonCtrl = TextEditingController();
  String _type = 'other'; // shortage|damaged|wrong_item|expired|other

  bool _submitting = false;

  Future<void> _searchPurchase(BuildContext context) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final invCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Search Purchase"),
        content: TextField(
          controller: invCtrl,
          decoration: const InputDecoration(hintText: "Enter invoice no..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (invCtrl.text.isEmpty) return;

              // Assumes: GET /purchases?search=INV
              final listUri = Uri.parse("${ApiClient.baseUrl}/purchases")
                  .replace(queryParameters: {"search": invCtrl.text});
              final listRes = await http.get(listUri, headers: {
                "Authorization": "Bearer $token",
                "Accept": "application/json",
              });

              if (listRes.statusCode == 200) {
                final listData = jsonDecode(listRes.body);
                final purchases = listData['data']['data'];
                if (purchases.isNotEmpty) {
                  final purchase = purchases.first;

                  // Assumes: GET /purchases/{id} returns items[]
                  final detailRes = await http.get(
                    Uri.parse("${ApiClient.baseUrl}/purchases/${purchase['id']}"),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                  );

                  if (detailRes.statusCode == 200) {
                    final detail = jsonDecode(detailRes.body)['data'];
                    setState(() {
                      _selectedPurchase = detail;
                      _purchaseItems = detail['items'] ?? [];

                      _qtyCtrls.clear();
                      _remarksCtrls.clear();
                      _batchCtrls.clear();
                      _expiryCtrls.clear();
                      _affectsStock.clear();

                      for (final it in _purchaseItems) {
                        final int pid = it['id']; // purchase_item_id
                        _qtyCtrls[pid] = TextEditingController(text: "0");
                        _remarksCtrls[pid] = TextEditingController();
                        _batchCtrls[pid] = TextEditingController();
                        _expiryCtrls[pid] = TextEditingController();
                        _affectsStock[pid] = _type != 'shortage'; // default by type
                      }
                    });
                  }
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateFor(int purchaseItemId) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      _expiryCtrls[purchaseItemId]?.text = picked.toIso8601String().split('T').first;
      setState(() {});
    }
  }

  void _onTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _type = val;
      // reset affectsStock defaults based on type
      for (final it in _purchaseItems) {
        final int pid = it['id'];
        // keep manual overrides? If you want to force, uncomment next line:
        _affectsStock[pid] = _type != 'shortage';
      }
    });
  }

  Future<void> _submitClaim(BuildContext context) async {
    if (_selectedPurchase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a purchase first.")),
      );
      return;
    }

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    setState(() => _submitting = true);

    final itemsPayload = _purchaseItems
        .where((i) => int.tryParse(_qtyCtrls[i['id']]?.text ?? "0") != null
            && int.parse(_qtyCtrls[i['id']]!.text) > 0)
        .map<Map<String, dynamic>>((i) {
      final pid = i['id'];
      return {
        "purchase_item_id": pid,
        "quantity": int.parse(_qtyCtrls[pid]!.text),
        "affects_stock": _affectsStock[pid] ?? (_type != 'shortage'),
        if (_remarksCtrls[pid]!.text.isNotEmpty) "remarks": _remarksCtrls[pid]!.text,
        if (_batchCtrls[pid]!.text.isNotEmpty) "batch_no": _batchCtrls[pid]!.text,
        if (_expiryCtrls[pid]!.text.isNotEmpty) "expiry_date": _expiryCtrls[pid]!.text,
      };
    }).toList();

    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least 1 claim quantity.")),
      );
      setState(() => _submitting = false);
      return;
    }

    final body = jsonEncode({
      "purchase_id": _selectedPurchase!['id'],
      "type": _type,
      "reason": _reasonCtrl.text,
      "items": itemsPayload,
    });

    final res = await http.post(
      Uri.parse("${ApiClient.baseUrl}/purchase-claims"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: body,
    );

    setState(() => _submitting = false);

    if (res.statusCode == 200 || res.statusCode == 201) {
      Navigator.pop(context, true);
    } else {
      String msg = "Failed to create purchase claim";
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['message'] is String) msg = d['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorName = _selectedPurchase?['vendor']?['name'] ?? 'N/A';
    final invoiceNo = _selectedPurchase?['invoice_no'] ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Purchase Claim"),
        actions: const [BranchIndicator(tappable: false)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🔍 Select Purchase
              ListTile(
                title: Text(_selectedPurchase == null
                    ? "No purchase selected"
                    : "Invoice: $invoiceNo"),
                subtitle: Text(_selectedPurchase == null
                    ? "Tap search to select purchase"
                    : "Vendor: $vendorName"),
                trailing: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchPurchase(context),
                ),
              ),
              const Divider(),

              // 🎛️ Claim Type + Reason
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _type,
                      items: const [
                        DropdownMenuItem(value: 'shortage', child: Text('Shortage')),
                        DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                        DropdownMenuItem(value: 'wrong_item', child: Text('Wrong Item')),
                        DropdownMenuItem(value: 'expired', child: Text('Expired')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: _onTypeChanged,
                      decoration: const InputDecoration(
                        labelText: 'Claim Type',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: "Reason (optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 🧾 Purchase items
              Expanded(
                child: _purchaseItems.isEmpty
                    ? const Center(child: Text("No purchase items"))
                    : ListView.builder(
                        itemCount: _purchaseItems.length,
                        itemBuilder: (_, i) {
                          final item = _purchaseItems[i];
                          final pid = item['id']; // purchase_item_id
                          final productName = item['product']?['name'] ?? 'Product';
                          final qtyReceived = item['quantity'];
                          final sku = item['product']?['sku'];

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text("SKU: ${sku ?? '-'} • Qty received: $qtyReceived"),
                                    trailing: SizedBox(
                                      width: 90,
                                      child: TextFormField(
                                        controller: _qtyCtrls[pid],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(labelText: "Claim"),
                                      ),
                                    ),
                                  ),
                                  // affects_stock toggle
                                  Row(
                                    children: [
                                      Switch(
                                        value: _affectsStock[pid] ?? (_type != 'shortage'),
                                        onChanged: (v) => setState(() => _affectsStock[pid] = v),
                                      ),
                                      const Text('Affects Stock'),
                                    ],
                                  ),
                                  // extra fields: remarks, batch, expiry
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _remarksCtrls[pid],
                                          decoration: const InputDecoration(
                                            labelText: "Remarks",
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _batchCtrls[pid],
                                          decoration: const InputDecoration(
                                            labelText: "Batch No",
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _expiryCtrls[pid],
                                          readOnly: true,
                                          decoration: InputDecoration(
                                            labelText: "Expiry (YYYY-MM-DD)",
                                            border: const OutlineInputBorder(),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.date_range),
                                              onPressed: () => _pickDateFor(pid),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Container()), // spacer
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Submit
              ElevatedButton.icon(
                onPressed: _submitting ? null : () => _submitClaim(context),
                icon: const Icon(Icons.save),
                label: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Submit Claim"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
