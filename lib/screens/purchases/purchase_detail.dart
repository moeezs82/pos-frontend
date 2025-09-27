import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
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

  ApiClient get _api =>
      ApiClient(token: Provider.of<AuthProvider>(context, listen: false).token);

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
      if (!mounted) return;
      setState(() {
        _purchase = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to load purchase")));
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

  /* ===================== Payments ===================== */

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

  Future<void> _editPayment(Map<String, dynamic> p) async {
    final amountCtl = TextEditingController(text: _money(p['amount']));
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _api.put(
                  "/purchases/${widget.purchaseId}/payments/${p['id']}",
                  body: {
                    "amount":
                        double.tryParse(amountCtl.text.trim()) ??
                        _doubleVal(p['amount']),
                    "method": method,
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                _updated = true;
                _fetchPurchase();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
              }
            },
            child: const Text("Save"),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, delete"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete("/purchases/${widget.purchaseId}/payments/$paymentId");
      _updated = true;
      _fetchPurchase();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    }
  }

  /* ===================== Items ===================== */

  Future<void> _addItem() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final vendorId = _purchase?['vendor_id'];
    final product = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: ProductPickerSheet(token: token, vendorId: vendorId),
      ),
    );
    if (product == null) return;

    final qtyCtl = TextEditingController(text: "1");
    final priceCtl = TextEditingController(
      text:
          (product['cost_price'] ??
                  product['wholesale_price'] ??
                  product['price'] ??
                  0)
              .toString(),
    );
    final rcvCtl = TextEditingController(text: "0"); // optional spot receipt

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
              decoration: const InputDecoration(
                labelText: "Quantity",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Purchase Price",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rcvCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Receive Now (optional)",
                border: OutlineInputBorder(),
              ),
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
              final qty = int.tryParse(qtyCtl.text.trim()) ?? 1;
              final price = double.tryParse(priceCtl.text.trim()) ?? 0.0;
              var rcv = int.tryParse(rcvCtl.text.trim()) ?? 0;
              rcv = rcv.clamp(0, qty);
              try {
                await _api.post(
                  "/purchases/${widget.purchaseId}/items",
                  body: {
                    "product_id": product['id'],
                    "quantity": qty,
                    "price": price,
                    if (rcv > 0) "received_qty": rcv,
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                _updated = true;
                _fetchPurchase();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Add item failed: $e")));
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final qtyCtl = TextEditingController(
      text: _intVal(item['quantity']).toString(),
    );
    final priceCtl = TextEditingController(text: _money(item['price']));
    final rcvCtl = TextEditingController(
      text: _intVal(item['received_qty']).toString(),
    );

    final ordered = _intVal(item['quantity']);

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
              decoration: const InputDecoration(
                labelText: "Quantity (ordered)",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                // keep received within range in UI
                final newQty = int.tryParse(v) ?? ordered;
                final r = int.tryParse(rcvCtl.text) ?? 0;
                if (r > newQty) rcvCtl.text = newQty.toString();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Purchase Price",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rcvCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Received Qty",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final q = int.tryParse(qtyCtl.text) ?? ordered;
                final r = int.tryParse(v) ?? 0;
                if (r > q) rcvCtl.text = q.toString();
                if (r < 0) rcvCtl.text = '0';
              },
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
              final body = <String, dynamic>{};
              if (qtyCtl.text.trim().isNotEmpty)
                body['quantity'] = int.tryParse(qtyCtl.text.trim());
              if (priceCtl.text.trim().isNotEmpty)
                body['price'] = double.tryParse(priceCtl.text.trim());
              if (rcvCtl.text.trim().isNotEmpty) {
                final q = body['quantity'] ?? ordered;
                final r = (int.tryParse(rcvCtl.text.trim()) ?? 0).clamp(0, q);
                body['received_qty'] = r;
              }
              try {
                await _api.put(
                  "/purchases/${widget.purchaseId}/items/${item['id']}",
                  body: body,
                );
                if (!mounted) return;
                Navigator.pop(context);
                _updated = true;
                _fetchPurchase();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
              }
            },
            child: const Text("Save"),
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
        content: const Text(
          "Remove this item from the purchase? Received qty (if any) will be reversed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, delete"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete("/purchases/${widget.purchaseId}/items/$itemId");
      _updated = true;
      _fetchPurchase();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    }
  }

  /* ===================== Receive / Cancel ===================== */

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
      if (remaining > 0)
        controllers[pid] = TextEditingController(text: remaining.toString());
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

  /* ===================== Build ===================== */

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
            BranchIndicator(tappable: false),
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _editItem(i),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _deleteItem(i['id'] as int),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: OutlinedButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add),
                              label: const Text("Add Item"),
                            ),
                          ),
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
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () =>
                                        _editPayment(p as Map<String, dynamic>),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _deletePayment(_intVal(p['id'])),
                                  ),
                                ],
                              ),
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
