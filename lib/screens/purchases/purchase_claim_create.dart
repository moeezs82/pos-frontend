import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CreatePurchaseClaimScreen extends StatefulWidget {
  const CreatePurchaseClaimScreen({super.key});

  @override
  State<CreatePurchaseClaimScreen> createState() =>
      _CreatePurchaseClaimScreenState();
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

  // NEW: Approve + Receipt on create
  bool _approveNow = false;
  bool _receiveNow = false;
  final _receiptAmountCtrl = TextEditingController();
  String _receiptMethod = 'cash';
  final _receiptRefCtrl = TextEditingController();
  DateTime? _receiptDate;

  final _currency = NumberFormat.simpleCurrency(name: "", decimalDigits: 2);

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double _computeClaimTotal() {
    double sum = 0.0;
    for (final it in _purchaseItems) {
      final pid = it['id'] as int; // purchase_item_id
      final qty = int.tryParse(_qtyCtrls[pid]?.text ?? '0') ?? 0;
      final price = _toDouble(it['price']); // purchase price from API
      if (qty > 0) sum += qty * price;
    }
    return sum;
  }

  void _syncDefaultReceipt() {
    final t = _computeClaimTotal();
    _receiptAmountCtrl.text = t.toStringAsFixed(2);
  }

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

              final listUri = Uri.parse(
                "${ApiClient.baseUrl}/purchases",
              ).replace(queryParameters: {"search": invCtrl.text});
              final listRes = await http.get(
                listUri,
                headers: {
                  "Authorization": "Bearer $token",
                  "Accept": "application/json",
                },
              );

              if (listRes.statusCode == 200) {
                final listData = jsonDecode(listRes.body);
                final purchases = listData['data']['data'];
                if (purchases.isNotEmpty) {
                  final purchase = purchases.first;

                  final detailRes = await http.get(
                    Uri.parse(
                      "${ApiClient.baseUrl}/purchases/${purchase['id']}",
                    ),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                  );

                  if (!mounted) return;
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
                        _qtyCtrls[pid] = TextEditingController(text: "0")
                          ..addListener(() {
                            if (_receiveNow) setState(_syncDefaultReceipt);
                          });
                        _remarksCtrls[pid] = TextEditingController();
                        _batchCtrls[pid] = TextEditingController();
                        _expiryCtrls[pid] = TextEditingController();
                        _affectsStock[pid] =
                            _type != 'shortage'; // default by type
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
      _expiryCtrls[purchaseItemId]?.text = picked
          .toIso8601String()
          .split('T')
          .first;
      setState(() {});
    }
  }

  void _onTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _type = val;
      for (final it in _purchaseItems) {
        final int pid = it['id'];
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

    final itemsPayload = _purchaseItems
        .where((i) {
          final txt = _qtyCtrls[i['id']]?.text ?? "0";
          final q = int.tryParse(txt) ?? 0;
          return q > 0;
        })
        .map<Map<String, dynamic>>((i) {
          final pid = i['id'] as int;
          return {
            "purchase_item_id": pid,
            "quantity": int.parse(_qtyCtrls[pid]!.text),
            "affects_stock": _affectsStock[pid] ?? (_type != 'shortage'),
            if (_remarksCtrls[pid]!.text.isNotEmpty)
              "remarks": _remarksCtrls[pid]!.text,
            if (_batchCtrls[pid]!.text.isNotEmpty)
              "batch_no": _batchCtrls[pid]!.text,
            if (_expiryCtrls[pid]!.text.isNotEmpty)
              "expiry_date": _expiryCtrls[pid]!.text,
          };
        })
        .toList();

    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least 1 claim quantity.")),
      );
      return;
    }

    // Guard: receipt amount <= total when approve+receive now
    final total = _computeClaimTotal();
    if (_approveNow && _receiveNow) {
      final requested = double.tryParse(_receiptAmountCtrl.text.trim()) ?? 0.0;
      if (requested <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid receipt amount")),
        );
        return;
      }
      if (requested > total + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Receipt cannot exceed claim total (${_currency.format(total)})",
            ),
          ),
        );
        return;
      }
    }

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    setState(() => _submitting = true);

    // Build request body
    final Map<String, dynamic> payload = {
      "purchase_id": _selectedPurchase!['id'],
      "type": _type,
      "reason": _reasonCtrl.text,
      "items": itemsPayload,
      if (_approveNow) "approve_now": true,
      if (_approveNow && _receiveNow)
        "receipt": {
          "amount": double.tryParse(_receiptAmountCtrl.text.trim()) ?? total,
          "method": _receiptMethod,
          if (_receiptRefCtrl.text.trim().isNotEmpty)
            "reference": _receiptRefCtrl.text.trim(),
          if (_receiptDate != null)
            "received_at": DateFormat("yyyy-MM-dd").format(_receiptDate!),
        },
    };

    final res = await http.post(
      Uri.parse("${ApiClient.baseUrl}/purchase-claims"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(payload),
    );

    setState(() => _submitting = false);

    if (!mounted) return;
    if (res.statusCode == 200 || res.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _approveNow
                ? (_receiveNow
                      ? "Claim created, approved and receipt posted ${_currency.format(double.tryParse(_receiptAmountCtrl.text) ?? total)}"
                      : "Claim created and approved")
                : "Claim created",
          ),
        ),
      );
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
    final vendorName =
        _selectedPurchase?['vendor']?['name'] ??
        _selectedPurchase?['vendor']?['first_name'] ??
        'N/A';
    final invoiceNo = _selectedPurchase?['invoice_no'] ?? 'N/A';
    final total = _computeClaimTotal();

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
                title: Text(
                  _selectedPurchase == null
                      ? "No purchase selected"
                      : "Invoice: $invoiceNo",
                ),
                subtitle: Text(
                  _selectedPurchase == null
                      ? "Tap search to select purchase"
                      : "Vendor: $vendorName",
                ),
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
                        DropdownMenuItem(
                          value: 'shortage',
                          child: Text('Shortage'),
                        ),
                        DropdownMenuItem(
                          value: 'damaged',
                          child: Text('Damaged'),
                        ),
                        DropdownMenuItem(
                          value: 'wrong_item',
                          child: Text('Wrong Item'),
                        ),
                        DropdownMenuItem(
                          value: 'expired',
                          child: Text('Expired'),
                        ),
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

              // 🧾 Purchase Claim – Items table
              if (_purchaseItems.isEmpty)
                const Expanded(child: Center(child: Text("No purchase items")))
              else
                Expanded(
                  child: Column(
                    children: [
                      const _ClaimTableHeader(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _purchaseItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final item = _purchaseItems[i];
                            final pid = item['id'] as int; // purchase_item_id
                            final name =
                                item['product']?['name']?.toString() ?? '—';
                            final sku = item['product']?['sku']?.toString();
                            final receivedQty =
                                (item['quantity'] ?? 0)
                                    as int; // received/accepted qty
                            final price = _toDouble(
                              item['price'],
                            ); // P.P (unit price)

                            final claimQty =
                                int.tryParse(_qtyCtrls[pid]?.text ?? '0') ?? 0;
                            final amount = (claimQty * price);

                            return SizedBox(
                              height: 44,
                              child: Row(
                                children: [
                                  // Product (+ SKU caption)
                                  Expanded(
                                    flex: 5,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (sku != null && sku.isNotEmpty)
                                            Text(
                                              "SKU: $sku",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).hintColor,
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // P.P
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(_currency.format(price)),
                                    ),
                                  ),
                                  // Received
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text("$receivedQty"),
                                    ),
                                  ),
                                  // Claim (editable)
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _qtyCtrls[pid],
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (v) {
                                        final parsed =
                                            int.tryParse(v.trim()) ?? 0;
                                        // clamp 0..receivedQty
                                        if (parsed < 0 ||
                                            parsed > receivedQty) {
                                          final clamped = parsed.clamp(
                                            0,
                                            receivedQty,
                                          );
                                          _qtyCtrls[pid]!.text = clamped
                                              .toString();
                                          _qtyCtrls[pid]!.selection =
                                              TextSelection.fromPosition(
                                                TextPosition(
                                                  offset: _qtyCtrls[pid]!
                                                      .text
                                                      .length,
                                                ),
                                              );
                                        } else {
                                          setState(() {
                                            // if you compute overall totals/refund elsewhere, trigger it here
                                            // _recalcClaimTotals(); // optional
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  // Amount (claimQty * price)
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        _currency.format(
                                          (int.tryParse(
                                                    _qtyCtrls[pid]?.text ?? '0',
                                                  ) ??
                                                  0) *
                                              price,
                                        ),
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

              // ✅ Approve & 📥 Receive Now (optional)
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
                            if (!_approveNow) _receiveNow = false;
                            if (_approveNow && _receiveNow)
                              _syncDefaultReceipt();
                          });
                        },
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Claim Total: ${_currency.format(total)}",
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
                  onPressed: _submitting ? null : () => _submitClaim(context),
                  icon: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_submitting ? "Submitting..." : "Submit Claim"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ClaimTableHeader extends StatelessWidget {
  const _ClaimTableHeader();

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
          Expanded(flex: 2, child: Text("P.P", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Received", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Claim", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Amount", style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
