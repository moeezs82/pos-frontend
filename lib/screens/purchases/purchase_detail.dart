import 'package:enterprise_pos/api/purchase_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_items_section.dart';
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

  // header (discount/tax) editors
  final _discountCtl = TextEditingController();
  final _taxCtl = TextEditingController();
  bool _savingHeader = false;

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

  @override
  void dispose() {
    _discountCtl.dispose();
    _taxCtl.dispose();
    super.dispose();
  }

  Future<void> _fetchPurchase() async {
    setState(() => _loading = true);
    try {
      final data = await _purchaseService.getPurchase(widget.purchaseId);
      if (!mounted) return;
      setState(() {
        _purchase = data;
        // prefill editors from API
        _discountCtl.text = _money(_purchase?['discount']);
        _taxCtl.text = _money(_purchase?['tax']);
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

  Future<void> _saveHeader() async {
    final discount = double.tryParse(_discountCtl.text.trim()) ?? 0.0;
    final tax = double.tryParse(_taxCtl.text.trim()) ?? 0.0;

    setState(() => _savingHeader = true);
    try {
      await _api.put(
        "/purchases/${widget.purchaseId}",
        body: {"discount": discount, "tax": tax},
      );
      _updated = true;
      await _fetchPurchase(); // refresh numbers from server
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Updated")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      if (mounted) setState(() => _savingHeader = false);
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

    // 1) Pick product (same as sales flow)
    final product = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: ProductPickerSheet(token: token, vendorId: vendorId),
      ),
    );
    if (product == null) return;

    // --- helpers (same styling/logic as sales) ---
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    String _money(num v) => v.toStringAsFixed(2);
    double _calcTotal(double price, double qty, double discPct) {
      final d = (discPct / 100.0).clamp(0, 100);
      final t = qty * price * (1 - d);
      return t.isFinite ? (t < 0 ? 0 : t) : 0.0;
    }

    // 2) Tabular editor state
    final priceCtl = TextEditingController(
      text: _money(
        _num(
          product['cost_price'] ??
              product['wholesale_price'] ??
              product['price'] ??
              0,
        ),
      ),
    );
    final discCtl = TextEditingController(text: "0");
    final qtyCtl = TextEditingController(text: "1");

    final priceFn = FocusNode();
    final discFn = FocusNode();
    final qtyFn = FocusNode();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final price = _num(priceCtl.text);
          final qty = _num(qtyCtl.text); // keep integer gate below
          final disc = _num(discCtl.text);
          final total = _calcTotal(price, qty, disc);

          InputDecoration _cellDec({String? label, String? suffix}) =>
              InputDecoration(
                labelText: label,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                suffixText: suffix,
              );

          Widget _numberField({
            required TextEditingController c,
            required FocusNode fn,
            String? label,
            String? suffix,
            bool integer = false,
            VoidCallback? onNext,
          }) {
            return TextField(
              controller: c,
              focusNode: fn,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: onNext == null
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: (_) => onNext?.call(),
              onTap: () => c.selection = TextSelection(
                baseOffset: 0,
                extentOffset: c.text.length,
              ),
              onChanged: (v) {
                if (integer) {
                  final only = int.tryParse(
                    v.replaceAll(RegExp(r'[^0-9]'), ''),
                  );
                  if (only != null && only.toString() != v) {
                    c.text = only.toString();
                    c.selection = TextSelection.fromPosition(
                      TextPosition(offset: c.text.length),
                    );
                  }
                }
                setLocal(() {}); // refresh total
              },
              textAlign: TextAlign.right,
              decoration: _cellDec(label: label, suffix: suffix),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            );
          }

          return AlertDialog(
            title: Text("Add ${product['name']}"),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header row
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: const [
                        Expanded(
                          flex: 6,
                          child: Text(
                            "Product",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text("P.P"),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text("Discount (%)"),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text("Qty"),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text("Total"),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),

                  // Single row
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        // Product name
                        Expanded(
                          flex: 6,
                          child: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              (product['name'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Purchase Price
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _numberField(
                              c: priceCtl,
                              fn: priceFn,
                              label: "P.P",
                              onNext: () => discFn.requestFocus(),
                            ),
                          ),
                        ),
                        // Discount %
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _numberField(
                              c: discCtl,
                              fn: discFn,
                              label: "Discount",
                              suffix: "%",
                              onNext: () => qtyFn.requestFocus(),
                            ),
                          ),
                        ),
                        // Qty
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _numberField(
                              c: qtyCtl,
                              fn: qtyFn,
                              label: "Qty",
                              integer: true,
                              onNext: null,
                            ),
                          ),
                        ),
                        // Total
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _money(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _api.post(
                      "/purchases/${widget.purchaseId}/items",
                      body: {
                        "product_id": product['id'],
                        "quantity": int.tryParse(qtyCtl.text) ?? 1,
                        "price": _num(priceCtl.text),
                        "discount": _num(
                          discCtl.text,
                        ), // <- change to "discount" if your API expects it
                      },
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    await _fetchPurchase();
                    _updated = true;
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Add item failed: $e")),
                    );
                  }
                },
                child: const Text("Add"),
              ),
            ],
          );
        },
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

  /* ===================== Build ===================== */

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Purchase Detail"),
          actions: [
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
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items
                    PurchaseItemsSection(
                      purchase: _purchase!,
                      onAddItem: _addItem, // your purchase _addItem dialog
                      onDeleteItem: (id) => _deleteItem(id),
                    ),

                    const SizedBox(height: 12),

                    // Payments
                    // Card(
                    //   elevation: 2,
                    //   shape: RoundedRectangleBorder(
                    //     borderRadius: BorderRadius.circular(12),
                    //   ),
                    //   child: Column(
                    //     crossAxisAlignment: CrossAxisAlignment.start,
                    //     children: [
                    //       const Padding(
                    //         padding: EdgeInsets.all(12),
                    //         child: Text(
                    //           "Payments",
                    //           style: TextStyle(
                    //             fontWeight: FontWeight.bold,
                    //             fontSize: 16,
                    //           ),
                    //         ),
                    //       ),
                    //       const Divider(height: 1),
                    //       if (payments.isEmpty)
                    //         const ListTile(title: Text("No payments yet")),
                    //       ...payments.map(
                    //         (p) => ListTile(
                    //           title: Text("\$${_money(p['amount'])}"),
                    //           subtitle: Text("Method: ${p['method'] ?? '-'}"),
                    //           trailing: Row(
                    //             mainAxisSize: MainAxisSize.min,
                    //             children: [
                    //               // IconButton(
                    //               //   icon: const Icon(Icons.edit),
                    //               //   onPressed: () =>
                    //               //       _editPayment(p as Map<String, dynamic>),
                    //               // ),
                    //               IconButton(
                    //                 icon: const Icon(
                    //                   Icons.delete,
                    //                   color: Colors.red,
                    //                 ),
                    //                 onPressed: () =>
                    //                     _deletePayment(_intVal(p['id'])),
                    //               ),
                    //             ],
                    //           ),
                    //         ),
                    //       ),
                    //       Padding(
                    //         padding: const EdgeInsets.all(12.0),
                    //         child: ElevatedButton.icon(
                    //           onPressed: _addPayment,
                    //           icon: const Icon(Icons.add),
                    //           label: const Text("Add Payment"),
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // ),

                    // const SizedBox(height: 12),

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
                          // Editable Discount
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                const Expanded(child: Text("Discount")),
                                SizedBox(
                                  width: 140,
                                  child: TextField(
                                    controller: _discountCtl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      prefixText: "- \$",
                                      hintText: "0.00",
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Editable Tax
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                const Expanded(child: Text("Tax")),
                                SizedBox(
                                  width: 140,
                                  child: TextField(
                                    controller: _taxCtl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      prefixText: "+ \$",
                                      hintText: "0.00",
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Divider(),
                          // Live total preview (client-side) using edited values
                          Builder(
                            builder: (_) {
                              final sub = _doubleVal(_purchase?['subtotal']);
                              final d =
                                  double.tryParse(_discountCtl.text.trim()) ??
                                  _doubleVal(_purchase?['discount']);
                              final t =
                                  double.tryParse(_taxCtl.text.trim()) ??
                                  _doubleVal(_purchase?['tax']);
                              final previewTotal = (sub - d + t);
                              return ListTile(
                                title: const Text(
                                  "Total",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                trailing: Text(
                                  "\$${previewTotal.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              );
                            },
                          ),

                          // Save button
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: _savingHeader ? null : _saveHeader,
                                icon: _savingHeader
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text("Save Discount/Tax"),
                              ),
                            ),
                          ),
                          // ListTile(
                          //   title: const Text("Paid"),
                          //   trailing: Text("\$${_money(paid)}"),
                          // ),
                          // ListTile(
                          //   title: const Text("Remaining"),
                          //   trailing: Text(
                          //     "\$${_money(remaining)}",
                          //     style: TextStyle(
                          //       fontWeight: FontWeight.bold,
                          //       color: balanceColor,
                          //     ),
                          //   ),
                          // ),
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
