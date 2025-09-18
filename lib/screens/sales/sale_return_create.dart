import 'dart:convert';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class CreateSaleReturnScreen extends StatefulWidget {
  const CreateSaleReturnScreen({super.key});

  @override
  State<CreateSaleReturnScreen> createState() => _CreateSaleReturnScreenState();
}

class _CreateSaleReturnScreenState extends State<CreateSaleReturnScreen> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedSale;
  List<dynamic> _saleItems = [];
  Map<int, TextEditingController> _qtyControllers = {};

  final TextEditingController _reasonController = TextEditingController();
  bool _submitting = false;

  Future<void> _searchSale(BuildContext context) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Search Sale"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter invoice no...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;

              final uri = Uri.parse(
                "${ApiService.baseUrl}/sales",
              ).replace(queryParameters: {"search": controller.text});

              final res = await http.get(
                uri,
                headers: {
                  "Authorization": "Bearer $token",
                  "Accept": "application/json"
                },
              );

              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                final sales = data['data']['data'];
                if (sales.isNotEmpty) {
                  final sale = sales.first;
                  final saleDetailRes = await http.get(
                    Uri.parse("${ApiService.baseUrl}/sales/${sale['id']}"),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json"
                    },
                  );
                  if (saleDetailRes.statusCode == 200) {
                    final detail = jsonDecode(saleDetailRes.body)['data'];
                    setState(() {
                      _selectedSale = detail;
                      _saleItems = detail['items'];
                      _qtyControllers.clear();
                      for (var item in _saleItems) {
                        _qtyControllers[item['id']] =
                            TextEditingController(text: "0");
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

  Future<void> _submitReturn(BuildContext context) async {
    if (_selectedSale == null) return;

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    setState(() => _submitting = true);

    final items = _saleItems
        .where((i) =>
            int.tryParse(_qtyControllers[i['id']]?.text ?? "0") != null &&
            int.parse(_qtyControllers[i['id']]!.text) > 0)
        .map((i) => {
              "sale_item_id": i['id'],
              "quantity": int.parse(_qtyControllers[i['id']]!.text),
            })
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter at least 1 return quantity")),
      );
      setState(() => _submitting = false);
      return;
    }

    final body = jsonEncode({
      "sale_id": _selectedSale!['id'],
      "items": items,
      "reason": _reasonController.text,
    });

    final res = await http.post(
      Uri.parse("${ApiService.baseUrl}/sales/returns"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: body,
    );

    setState(() => _submitting = false);

    if (res.statusCode == 200) {
      Navigator.pop(context, true); // return success
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to create return")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Sale Return")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🔍 Select Sale
              ListTile(
                title: Text(_selectedSale == null
                    ? "No sale selected"
                    : "Invoice: ${_selectedSale!['invoice_no']}"),
                subtitle: Text(_selectedSale == null
                    ? "Tap search to select sale"
                    : "Customer: ${_selectedSale!['customer']?['first_name'] ?? 'Walk-in'}"),
                trailing: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchSale(context),
                ),
              ),
              const Divider(),

              // 🛒 Sale items
              Expanded(
                child: _saleItems.isEmpty
                    ? const Center(child: Text("No sale items"))
                    : ListView.builder(
                        itemCount: _saleItems.length,
                        itemBuilder: (_, i) {
                          final item = _saleItems[i];
                          return Card(
                            child: ListTile(
                              title: Text(item['product']['name']),
                              subtitle: Text("Qty sold: ${item['quantity']}"),
                              trailing: SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: _qtyControllers[item['id']],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: "Return",
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // 📝 Reason
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: "Reason",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Submit button
              ElevatedButton.icon(
                onPressed: _submitting ? null : () => _submitReturn(context),
                icon: const Icon(Icons.save),
                label: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Submit Return"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
