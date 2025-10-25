import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, double> _itemPrices = {}; // sale price for computing totals

  final TextEditingController _reasonController = TextEditingController();
  bool _submitting = false;

  // Approve + Refund options
  bool _approveNow = false;
  bool _refundNow = false;
  final _refundAmountCtrl = TextEditingController();
  String _refundMethod = 'cash';
  final _refundRefCtrl = TextEditingController();
  DateTime? _refundDate;

  final _currency = NumberFormat.simpleCurrency(name: "", decimalDigits: 2);

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  void _recalcRefundDefault() {
    // Set default refund = computed total (clamped later by submit)
    final t = _computeReturnTotal();
    _refundAmountCtrl.text = t.toStringAsFixed(2);
  }

  double _computeReturnTotal() {
    double total = 0.0;
    for (final it in _saleItems) {
      final id = it['id'] as int;
      final qty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
      final price = _itemPrices[id] ?? _toDouble(it['price']); // fallback
      if (qty > 0) {
        total += qty * price;
      }
    }
    return total;
  }

  Future<void> _searchSale(BuildContext context) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Search Sale"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter invoice no..."),
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
                "${ApiClient.baseUrl}/sales",
              ).replace(queryParameters: {"search": controller.text});

              final res = await http.get(
                uri,
                headers: {
                  "Authorization": "Bearer $token",
                  "Accept": "application/json",
                },
              );

              if (res.statusCode == 200) {
                final data = jsonDecode(res.body);
                final sales = data['data']['data'];
                if (sales.isNotEmpty) {
                  final sale = sales.first;
                  final saleDetailRes = await http.get(
                    Uri.parse("${ApiClient.baseUrl}/sales/${sale['id']}"),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                  );
                  if (saleDetailRes.statusCode == 200) {
                    final detail = jsonDecode(saleDetailRes.body)['data'];
                    setState(() {
                      _selectedSale = detail;
                      _saleItems = (detail['items'] as List?) ?? [];
                      _qtyControllers.clear();
                      _itemPrices.clear();

                      for (var item in _saleItems) {
                        final id = item['id'] as int;
                        _qtyControllers[id] = TextEditingController(text: "0")
                          ..addListener(() {
                            setState(() {
                              // live total update
                              if (_refundNow) _recalcRefundDefault();
                            });
                          });
                        // Cache price for total calc
                        _itemPrices[id] = _toDouble(item['price']);
                      }
                    });
                  }
                  if (context.mounted) Navigator.pop(context);
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
    if (_selectedSale == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a sale")));
      return;
    }

    // Build items from entered qty
    final items = _saleItems
        .where((i) {
          final id = i['id'] as int;
          final q = int.tryParse(_qtyControllers[id]?.text ?? "0") ?? 0;
          return q > 0;
        })
        .map(
          (i) => {
            "sale_item_id": i['id'],
            "quantity": int.parse(_qtyControllers[i['id']]!.text),
          },
        )
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter at least 1 return quantity"),
        ),
      );
      return;
    }

    // If refund chosen, clamp to computed total
    final computedTotal = _computeReturnTotal();
    if (_approveNow && _refundNow) {
      final requested = double.tryParse(_refundAmountCtrl.text.trim()) ?? 0.0;
      if (requested <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid refund amount")),
        );
        return;
      }
      if (requested > computedTotal + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Refund cannot exceed return total (${_currency.format(computedTotal)})",
            ),
          ),
        );
        return;
      }
    }

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    setState(() => _submitting = true);

    // 1) Create sale return
    final createBody = jsonEncode({
      "sale_id": _selectedSale!['id'],
      "items": items,
      "reason": _reasonController.text,
    });

    final createRes = await http.post(
      Uri.parse("${ApiClient.baseUrl}/sales/returns"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: createBody,
    );

    if (createRes.statusCode != 200) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to create return")));
      return;
    }

    // Parse created return id
    int? returnId;
    try {
      final data = jsonDecode(createRes.body);
      // API example earlier returns { data: { id, ... } } or { data: return }
      final raw = data['data'];
      if (raw is Map && raw['id'] != null) {
        returnId = (raw['id'] as num).toInt();
      } else if (raw is Map && raw['return']?['id'] != null) {
        returnId = (raw['return']['id'] as num).toInt();
      }
    } catch (_) {}
    if (returnId == null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Return created but could not read ID")),
      );
      return;
    }

    // 2) If approveNow (+ optional refund)
    if (_approveNow) {
      final approveUri = Uri.parse(
        "${ApiClient.baseUrl}/sales/returns/$returnId/approve",
      );

      Map<String, String>? approveBody;
      if (_refundNow) {
        approveBody = {
          "refund[amount]":
              (double.tryParse(_refundAmountCtrl.text.trim()) ?? computedTotal)
                  .toStringAsFixed(2),
          "refund[method]": _refundMethod,
          if (_refundRefCtrl.text.trim().isNotEmpty)
            "refund[reference]": _refundRefCtrl.text.trim(),
          if (_refundDate != null)
            "refund[refunded_at]": DateFormat(
              "yyyy-MM-dd",
            ).format(_refundDate!),
        };
      }

      final approveRes = await http.post(
        approveUri,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
        body: approveBody, // null if no refund
      );

      if (approveRes.statusCode != 200) {
        setState(() => _submitting = false);
        String msg = "Failed to approve return";
        try {
          final d = jsonDecode(approveRes.body);
          if (d is Map && d['message'] != null) msg = d['message'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }

    setState(() => _submitting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _approveNow
                ? (_refundNow
                      ? "Return created, approved and refunded ${_currency.format(double.tryParse(_refundAmountCtrl.text) ?? _computeReturnTotal())}"
                      : "Return created and approved")
                : "Return created",
          ),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _computeReturnTotal();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Sale Return"),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            // child: BranchIndicator(tappable: false),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🔍 Select Sale
              ListTile(
                title: Text(
                  _selectedSale == null
                      ? "No sale selected"
                      : "Invoice: ${_selectedSale!['invoice_no']}",
                ),
                subtitle: Text(
                  _selectedSale == null
                      ? "Tap search to select sale"
                      : "Customer: ${_selectedSale!['customer']?['first_name'] ?? 'Walk-in'}",
                ),
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
                          final name = item['product']?['name'] ?? '—';
                          final soldQty = item['quantity'];
                          final id = item['id'] as int;
                          final price =
                              _itemPrices[id] ?? _toDouble(item['price']);

                          return Card(
                            child: ListTile(
                              title: Text(name),
                              subtitle: Text(
                                "Qty sold: $soldQty  |  Price: ${_currency.format(price)}",
                              ),
                              trailing: SizedBox(
                                width: 90,
                                child: TextFormField(
                                  controller: _qtyControllers[id],
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

              // ✅ Approve + 💵 Refund options
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text("Approve immediately"),
                        value: _approveNow,
                        onChanged: (v) {
                          setState(() {
                            _approveNow = v;
                            if (!_approveNow) _refundNow = false;
                            if (_approveNow && _refundNow)
                              _recalcRefundDefault();
                          });
                        },
                      ),
                      // if (_approveNow) ...[
                      //   SwitchListTile(
                      //     title: const Text("Refund now"),
                      //     value: _refundNow,
                      //     onChanged: (v) {
                      //       setState(() {
                      //         _refundNow = v;
                      //         if (_refundNow) _recalcRefundDefault();
                      //       });
                      //     },
                      //   ),
                        // if (_refundNow) ...[
                        //   Row(
                        //     children: [
                        //       Expanded(
                        //         child: TextField(
                        //           controller: _refundAmountCtrl,
                        //           keyboardType:
                        //               const TextInputType.numberWithOptions(
                        //                 decimal: true,
                        //               ),
                        //           decoration: InputDecoration(
                        //             labelText:
                        //                 "Refund Amount (max ${_currency.format(total)})",
                        //             border: const OutlineInputBorder(),
                        //           ),
                        //         ),
                        //       ),
                        //       const SizedBox(width: 8),
                        //       Expanded(
                        //         child: DropdownButtonFormField<String>(
                        //           value: _refundMethod,
                        //           decoration: const InputDecoration(
                        //             labelText: "Method",
                        //             border: OutlineInputBorder(),
                        //           ),
                        //           items: const [
                        //             DropdownMenuItem(
                        //               value: "cash",
                        //               child: Text("Cash"),
                        //             ),
                        //             DropdownMenuItem(
                        //               value: "card",
                        //               child: Text("Card"),
                        //             ),
                        //             DropdownMenuItem(
                        //               value: "bank",
                        //               child: Text("Bank"),
                        //             ),
                        //             DropdownMenuItem(
                        //               value: "wallet",
                        //               child: Text("Wallet"),
                        //             ),
                        //           ],
                        //           onChanged: (v) => setState(
                        //             () => _refundMethod = v ?? 'cash',
                        //           ),
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        //   const SizedBox(height: 8),
                        //   TextField(
                        //     controller: _refundRefCtrl,
                        //     decoration: const InputDecoration(
                        //       labelText: "Reference (optional)",
                        //       border: OutlineInputBorder(),
                        //     ),
                        //   ),
                        //   const SizedBox(height: 8),
                        //   Row(
                        //     children: [
                        //       Expanded(
                        //         child: OutlinedButton.icon(
                        //           icon: const Icon(Icons.calendar_today),
                        //           label: Text(
                        //             _refundDate == null
                        //                 ? "Refund Date (optional)"
                        //                 : DateFormat.yMMMd().format(
                        //                     _refundDate!,
                        //                   ),
                        //           ),
                        //           onPressed: () async {
                        //             final now = DateTime.now();
                        //             final d = await showDatePicker(
                        //               context: context,
                        //               initialDate: _refundDate ?? now,
                        //               firstDate: DateTime(now.year - 5),
                        //               lastDate: DateTime(now.year + 5),
                        //             );
                        //             if (d != null)
                        //               setState(() => _refundDate = d);
                        //           },
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        // ],
                      // ],
                      const Divider(),
                      // 💰 Summary
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Return Total: ${_currency.format(total)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _submitReturn(context),
                  icon: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_submitting ? "Submitting..." : "Submit Return"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
