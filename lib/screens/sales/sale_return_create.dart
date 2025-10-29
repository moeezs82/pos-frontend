import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
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

  /// Controllers + cached numbers per line
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, double> _unitPrice = {};
  final Map<int, double> _discountPct = {}; // <- your DB column: discount (percentage)

  final TextEditingController _reasonController = TextEditingController();
  bool _submitting = false;

  // Approve + Refund (kept but can be hidden if not used)
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

  /// qty * price * (1 - discount/100)
  double _lineAmount({
    required int itemId,
    required int qty,
  }) {
    final price = _unitPrice[itemId] ?? 0.0;
    final disc = (_discountPct[itemId] ?? 0.0).clamp(0.0, 100.0);
    final net = price * (1 - disc / 100.0);
    return qty * (net < 0 ? 0 : net);
  }

  double _computeReturnTotal() {
    double total = 0.0;
    for (final it in _saleItems) {
      final id = it['id'] as int;
      final qty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
      if (qty > 0) {
        total += _lineAmount(itemId: id, qty: qty);
      }
    }
    return total;
  }

  void _recalcRefundDefault() {
    _refundAmountCtrl.text = _computeReturnTotal().toStringAsFixed(2);
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

              final uri = Uri.parse("${ApiClient.baseUrl}/sales")
                  .replace(queryParameters: {"search": controller.text});

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
                      _unitPrice.clear();
                      _discountPct.clear();

                      for (var item in _saleItems) {
                        final id = item['id'] as int;

                        // cache unit TP and discount (%) from your columns
                        _unitPrice[id] = _toDouble(item['price']);      // TP
                        _discountPct[id] = _toDouble(item['discount']); // <-- your column name

                        // start at 0 return qty
                        _qtyControllers[id] = TextEditingController(text: "0")
                          ..addListener(() {
                            setState(() {
                              if (_approveNow && _refundNow) _recalcRefundDefault();
                            });
                          });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Please select a sale")));
      return;
    }

    // Build items with >0 return qty
    final items = _saleItems
        .where((i) {
          final id = i['id'] as int;
          final q = int.tryParse(_qtyControllers[id]?.text ?? "0") ?? 0;
          return q > 0;
        })
        .map((i) => {
              "sale_item_id": i['id'],
              "quantity": int.parse(_qtyControllers[i['id']]!.text),
            })
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter at least 1 return quantity")),
      );
      return;
    }

    // Clamp refund if used
    final computedTotal = _computeReturnTotal();
    if (_approveNow && _refundNow) {
      final requested = double.tryParse(_refundAmountCtrl.text.trim()) ?? 0.0;
      if (requested <= 0 || requested > computedTotal + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requested <= 0
                  ? "Enter a valid refund amount"
                  : "Refund cannot exceed return total (${_currency.format(computedTotal)})",
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Failed to create return")));
      return;
    }

    // Parse created return id
    int? returnId;
    try {
      final data = jsonDecode(createRes.body);
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

    // 2) Optional approve (+ refund)
    if (_approveNow) {
      final approveUri =
          Uri.parse("${ApiClient.baseUrl}/sales/returns/$returnId/approve");

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
            "refund[refunded_at]":
                DateFormat("yyyy-MM-dd").format(_refundDate!),
        };
      }

      final approveRes = await http.post(
        approveUri,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
        body: approveBody,
      );

      if (approveRes.statusCode != 200) {
        setState(() => _submitting = false);
        String msg = "Failed to approve return";
        try {
          final d = jsonDecode(approveRes.body);
          if (d is Map && d['message'] != null) msg = d['message'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }

    setState(() => _submitting = false);
    if (mounted) {
      final msg = _approveNow
          ? (_refundNow
              ? "Return created, approved and refunded ${_currency.format(double.tryParse(_refundAmountCtrl.text) ?? _computeReturnTotal())}"
              : "Return created and approved")
          : "Return created";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _computeReturnTotal();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Sale Return"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🔍 Selected sale / pick sale
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

              // 🛒 Items table
              if (_saleItems.isEmpty)
                const Expanded(
                  child: Center(child: Text("No sale items")),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      _ReturnTableHeader(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _saleItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final item = _saleItems[i];
                            final id = item['id'] as int;
                            final name = item['product']?['name'] ?? '—';
                            final soldQty = item['quantity'] ?? 0;
                            final price = _unitPrice[id] ?? 0.0;       // TP
                            final disc = (_discountPct[id] ?? 0.0)
                                .clamp(0.0, 100.0);                    // %

                            // return qty in controller
                            final retQty =
                                int.tryParse(_qtyControllers[id]?.text ?? '0') ??
                                    0;
                            final amount = _lineAmount(
                                itemId: id, qty: retQty); // with discount

                            return SizedBox(
                              height: 44,
                              child: Row(
                                children: [
                                  // Product
                                  Expanded(
                                    flex: 5,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                  // TP
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(_currency.format(price)),
                                    ),
                                  ),
                                  // Discount (%)
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text("${disc.toStringAsFixed(0)}%"),
                                    ),
                                  ),
                                  // Sold
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text("$soldQty"),
                                    ),
                                  ),
                                  // Return (editable)
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _qtyControllers[id],
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 10),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (v) {
                                        final parsed =
                                            int.tryParse(v.trim()) ?? 0;
                                        // clamp 0..soldQty
                                        if (parsed < 0 ||
                                            parsed > (soldQty as int)) {
                                          final clamped = parsed
                                              .clamp(0, soldQty as int);
                                          _qtyControllers[id]!.text =
                                              clamped.toString();
                                          _qtyControllers[id]!.selection =
                                              TextSelection.fromPosition(
                                            TextPosition(
                                              offset: _qtyControllers[id]!
                                                  .text
                                                  .length,
                                            ),
                                          );
                                        } else {
                                          setState(() {
                                            if (_approveNow && _refundNow) {
                                              _recalcRefundDefault();
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  // Amount (qty * price * (1 - disc%))
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        _currency.format(amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // 📝 Reason
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: "Reason",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ✅ Approve / Refund section (kept minimal here)
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
                            if (_approveNow && _refundNow) {
                              _recalcRefundDefault();
                            }
                          });
                        },
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Return Total: ${_currency.format(total)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Submit
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

class _ReturnTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).hintColor,
        );
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const Expanded(flex: 5, child: Text("Product")),
          Expanded(flex: 2, child: Text("T.P", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Discount (%)", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Sold", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Return", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Amount", style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
