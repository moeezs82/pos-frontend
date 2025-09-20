import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PurchaseDetailScreen extends StatefulWidget {
  final int purchaseId;
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  Map<String, dynamic>? _purchase;
  bool _loading = true;
  bool _updated = false;

  late PurchaseService _purchaseService;

  /* ---------- numeric safety helpers ---------- */
  num _numVal(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim()) ?? 0;
    return 0;
  }

  double _doubleVal(dynamic v) => _numVal(v).toDouble();
  int _intVal(dynamic v) => _numVal(v).toInt();
  String _money(dynamic v) => _doubleVal(v).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _purchaseService = PurchaseService(token: token);
    _fetchPurchase();
  }

  Future<void> _fetchPurchase() async {
    setState(() => _loading = true);
    try {
      final data = await _purchaseService.getPurchase(widget.purchaseId);
      setState(() {
        _purchase = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Color _chipColor(String status) {
    switch (status) {
      case 'paid':
      case 'received':
        return Colors.green;
      case 'partial':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  Future<void> _addPayment() async {
    final amountCtl = TextEditingController();
    String method = "cash";

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Payment"),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtl.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              try {
                await _purchaseService.addPayment(widget.purchaseId, {
                  "amount": amt,
                  "method": method,
                });
                if (!mounted) return;
                Navigator.pop(context);
                _updated = true;
                _fetchPurchase();
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                  ),
                );
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _receiveItems() async {
    if (_purchase == null) return;

    final items = (_purchase!['items'] as List).cast<Map<String, dynamic>>();
    final remainingMap = <int, int>{};
    final controllers = <int, TextEditingController>{};

    for (final i in items) {
      final pid = _intVal(i['product_id']);
      final ordered = _intVal(i['quantity']);
      final received = _intVal(i['received_qty']);
      final remaining = (ordered - received).clamp(0, ordered);
      remainingMap[pid] = remaining;
      if (remaining > 0) {
        controllers[pid] = TextEditingController(text: remaining.toString());
      }
    }

    final refCtl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text("Receive Items"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: refCtl,
                    decoration: const InputDecoration(
                      labelText: "Reference (GRN)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...items.map((i) {
                    final pid = _intVal(i['product_id']);
                    final name = i['product']?['name'] ?? 'Product #$pid';
                    final remain = remainingMap[pid] ?? 0;

                    if (remain == 0) {
                      return ListTile(
                        dense: true,
                        title: Text(name),
                        subtitle: const Text("Already fully received"),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: controllers[pid],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: "0-$remain",
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final val = int.tryParse(v) ?? 0;
                                if (val > remain) {
                                  controllers[pid]!.text = remain.toString();
                                  controllers[pid]!.selection =
                                      TextSelection.fromPosition(
                                        TextPosition(
                                          offset: controllers[pid]!.text.length,
                                        ),
                                      );
                                } else if (val < 0) {
                                  controllers[pid]!.text = '0';
                                  controllers[pid]!.selection =
                                      const TextSelection.collapsed(offset: 1);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  final itemsPayload = <Map<String, dynamic>>[];
                  controllers.forEach((pid, ctl) {
                    final qty = int.tryParse(ctl.text.trim()) ?? 0;
                    if (qty > 0)
                      itemsPayload.add({"product_id": pid, "receive_qty": qty});
                  });

                  if (itemsPayload.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Enter at least one receive quantity"),
                      ),
                    );
                    return;
                  }

                  try {
                    await _purchaseService.receive(widget.purchaseId, {
                      if (refCtl.text.trim().isNotEmpty)
                        "reference": refCtl.text.trim(),
                      "items": itemsPayload,
                    });
                    if (!mounted) return;
                    Navigator.pop(context);
                    _updated = true;
                    _fetchPurchase();
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceFirst('Exception: ', ''),
                        ),
                      ),
                    );
                  }
                },
                child: const Text("Receive"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancelPurchase() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cancel Purchase"),
        content: const Text(
          "Are you sure? You can only cancel if nothing has been received.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, cancel"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _purchaseService.cancel(widget.purchaseId);
      _updated = true;
      _fetchPurchase();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = (_purchase?['payments'] as List?) ?? [];
    final paid = payments.fold<double>(
      0.0,
      (sum, p) => sum + _doubleVal(p['amount']),
    );
    final total = _doubleVal(_purchase?['total']);
    final remaining = total - paid;

    Color balanceColor;
    if (remaining > 0) {
      balanceColor = Colors.red;
    } else if (remaining < 0) {
      balanceColor = Colors.orange;
    } else {
      balanceColor = Colors.green;
    }

    final payStatus = (_purchase?['status'] ?? 'pending').toString();
    final recvStatus = (_purchase?['receive_status'] ?? 'ordered').toString();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Purchase Detail"),
          actions: [
            if (_purchase != null &&
                recvStatus != 'cancelled' &&
                recvStatus != 'received')
              IconButton(
                tooltip: "Receive",
                icon: const Icon(Icons.inventory_2),
                onPressed: _receiveItems,
              ),
            IconButton(
              tooltip: "Refresh",
              icon: const Icon(Icons.refresh),
              onPressed: _fetchPurchase,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _purchase == null
            ? const Center(child: Text("Purchase not found"))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          "PO: ${_purchase!['invoice_no']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Date: ${_purchase!['created_at']?.toString().substring(0, 10) ?? ''}",
                            ),
                            Text(
                              "Vendor: ${[_purchase!['vendor']?['first_name'] ?? '', _purchase!['vendor']?['last_name'] ?? ''].where((s) => s.toString().trim().isNotEmpty).join(' ').trim()}",
                            ),
                            Text(
                              "Branch: ${_purchase!['branch']?['name'] ?? 'N/A'}",
                            ),
                          ],
                        ),
                        trailing: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Chip(
                                label: Text(
                                  "Pay: ${payStatus.toUpperCase()}",
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: _chipColor(payStatus),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 4),
                              Chip(
                                label: Text(
                                  "Recv: ${recvStatus.toUpperCase()}",
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: _chipColor(recvStatus),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items
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
                          ...((_purchase!['items'] as List)
                                  .cast<Map<String, dynamic>>())
                              .map((i) {
                                final name =
                                    i['product']?['name'] ??
                                    'Product #${_intVal(i['product_id'])}';
                                final qty = _intVal(i['quantity']);
                                final rec = _intVal(i['received_qty']);
                                final price = _doubleVal(i['price']);
                                final totalLine = i['total'] != null
                                    ? _doubleVal(i['total'])
                                    : (qty * price);
                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text(
                                    "Ordered: $qty | Received: $rec | Price: \$${_money(price)}",
                                  ),
                                  trailing: Text("\$${_money(totalLine)}"),
                                );
                              }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Payments
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
                              title: Text("\$${_money(p['amount'])}"),
                              subtitle: Text("Method: ${p['method'] ?? '-'}"),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _addPayment,
                                  icon: const Icon(Icons.add),
                                  label: const Text("Add Payment"),
                                ),
                                const SizedBox(width: 12),
                                if ((_purchase?['receive_status'] ?? '') !=
                                        'cancelled' &&
                                    ((_purchase!['items'] as List).fold<int>(
                                          0,
                                          (a, i) =>
                                              a + _intVal(i['received_qty']),
                                        ) ==
                                        0))
                                  OutlinedButton.icon(
                                    onPressed: _cancelPurchase,
                                    icon: const Icon(Icons.cancel),
                                    label: const Text("Cancel Purchase"),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Summary
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text("Subtotal"),
                            trailing: Text(
                              "\$${_money(_purchase!['subtotal'])}",
                            ),
                          ),
                          ListTile(
                            title: const Text("Discount"),
                            trailing: Text(
                              "-\$${_money(_purchase!['discount'])}",
                            ),
                          ),
                          ListTile(
                            title: const Text("Tax"),
                            trailing: Text("\$${_money(_purchase!['tax'])}"),
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text(
                              "Total",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Text(
                              "\$${_money(_purchase!['total'])}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text("Paid"),
                            trailing: Text("\$${_money(paid)}"),
                          ),
                          ListTile(
                            title: const Text("Remaining"),
                            trailing: Text(
                              "\$${_money(remaining)}",
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
