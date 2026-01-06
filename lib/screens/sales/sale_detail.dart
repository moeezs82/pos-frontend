import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// parts
import 'package:enterprise_pos/screens/sales/parts/sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_payments_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_totals_editable.dart';

class SaleDetailScreen extends StatefulWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Map<String, dynamic>? _sale;
  bool _loading = true;
  bool _updated = false;

  // optional vendor filter for add-item
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;

  // controllers for inline edit (filled from _sale on fetch)
  final discountCtl = TextEditingController();
  final taxCtl = TextEditingController();

  ApiClient get _api =>
      ApiClient(token: Provider.of<AuthProvider>(context, listen: false).token);

  @override
  void initState() {
    super.initState();
    _fetchSale();
  }

  @override
  void dispose() {
    discountCtl.dispose();
    taxCtl.dispose();
    super.dispose();
  }

  /* ====================== Data ====================== */

  Future<void> _fetchSale() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get("/sales/${widget.saleId}?include_balance=1");
      if (!mounted) return;
      setState(() {
        _sale = res['data'];
        _selectedVendorId = _sale?['vendor_id'];
        // seed controllers
        discountCtl.text = (_sale?['discount'] ?? 0).toString();
        taxCtl.text = (_sale?['tax'] ?? 0).toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load sale: $e")));
    }
  }

  Future<void> _updateDiscountTax() async {
    // push only discount & tax
    try {
      await _api.put(
        "/sales/${widget.saleId}",
        body: {
          "discount": double.tryParse(discountCtl.text.trim()) ?? 0.0,
          "tax": double.tryParse(taxCtl.text.trim()) ?? 0.0,
        },
      );
      if (!mounted) return;
      _updated = true;
      await _fetchSale();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Updated discount/tax.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    }
  }

  /* ====================== Payments ====================== */

  Future<void> _addPayment() async {
    final amountController = TextEditingController();
    String method = "cash";
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
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
              onChanged: (val) => method = val!,
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
                await _api.post(
                  "/sales/${widget.saleId}/payments",
                  body: {"amount": amountController.text, "method": method},
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Add payment failed: $e")),
                );
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _editPayment(Map p) async {
    final amountCtl = TextEditingController(text: p['amount'].toString());
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
            child: const Text("Save"),
            onPressed: () async {
              try {
                await _api.put(
                  "/sales/${widget.saleId}/payments/${p['id']}",
                  body: {"amount": amountCtl.text, "method": method},
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Update payment failed: $e")),
                );
              }
            },
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
      await _api.delete("/sales/${widget.saleId}/payments/$paymentId");
      if (!mounted) return;
      await _fetchSale();
      _updated = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Delete payment failed: $e")));
    }
  }

  /* ====================== Items ====================== */

  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final vendor = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: token),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (vendor == null) {
        _selectedVendor = null;
        _selectedVendorId = null;
      } else {
        _selectedVendor = vendor;
        _selectedVendorId = vendor['id'] as int?;
      }
    });
  }

  Future<void> _addItem() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;

    // 1) Pick product (your existing sheet)
    final product = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: ProductPickerSheet(token: token, vendorId: _selectedVendorId),
      ),
    );
    if (product == null) return;

    // --- helpers ---
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    String _money(num v) => v.toStringAsFixed(2);
    double _calcTotal(double price, double qty, double discPct) {
      final d = (discPct / 100.0).clamp(0, 100);
      final t = qty * price * (1 - d);
      return t.isFinite ? (t < 0 ? 0 : t) : 0.0;
    }

    // 2) Tabular editor state
    final priceCtl = TextEditingController(
      text: _money(_num(product['price'] ?? 0)),
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
          final qty = _num(qtyCtl.text); // allow decimals if you want; or round
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
              width: 520, // nice compact width; grows on wider screens
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
                            child: Text("T.P"),
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

                  // One tabular row
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
                        // Price
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _numberField(
                              c: priceCtl,
                              fn: priceFn,
                              label: "T.P",
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
                              integer:
                                  true, // set to false if you allow decimals
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
                      "/sales/${widget.saleId}/items",
                      body: {
                        "product_id": product['id'],
                        "quantity": int.tryParse(qtyCtl.text) ?? 1,
                        "price": _num(priceCtl.text),
                        "discount_pct": _num(discCtl.text),
                      },
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx); // close dialog
                    await _fetchSale(); // reload sale details
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

    // Cleanup (optional)
    priceFn.dispose();
    discFn.dispose();
    qtyFn.dispose();
    priceCtl.dispose();
    discCtl.dispose();
    qtyCtl.dispose();
  }

  Future<void> _editItem(Map item) async {
    final qtyCtl = TextEditingController(text: item['quantity'].toString());
    final priceCtl = TextEditingController(text: item['price'].toString());

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
                labelText: "Quantity",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Price",
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
            child: const Text("Save"),
            onPressed: () async {
              try {
                await _api.put(
                  "/sales/${widget.saleId}/items/${item['id']}",
                  body: {
                    "quantity": int.tryParse(qtyCtl.text) ?? item['quantity'],
                    "price": double.tryParse(priceCtl.text) ?? item['price'],
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
                await _fetchSale();
                _updated = true;
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Update item failed: $e")),
                );
              }
            },
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
          "Remove this item from the sale? Stock will be adjusted accordingly.",
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
      await _api.delete("/sales/${widget.saleId}/items/$itemId");
      if (!mounted) return;
      await _fetchSale();
      _updated = true;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Delete item failed: $e")));
    }
  }

  /* ====================== Print ====================== */

  Future<void> _printInvoice() async {
    if (_sale == null) return;

    double _d(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

    final sale = _sale!;
    final itemsRaw = (sale['items'] as List?) ?? const [];
    final paymentsRaw = (sale['payments'] as List?) ?? const [];

    final subtotal = _d(sale['subtotal']);
    final discount = _d(sale['discount']);
    final tax = _d(sale['tax']);
    final delivery = _d(sale['delivery']); // if your API returns it
    final total = _d(sale['total']);

    final paid = paymentsRaw.fold<double>(
      0,
      (sum, p) => sum + _d((p as Map)['amount']),
    );

    // ---- meta from response (preferred) ----
    final metaRaw = sale['meta'];
    final meta = (metaRaw is Map)
        ? metaRaw.cast<String, dynamic>()
        : <String, dynamic>{};

    // ---- build customer snapshot: from meta, otherwise from customer object ----
    Map<String, dynamic> customerSnap = {};
    final snapRaw = meta['customer_snapshot'];
    if (snapRaw is Map) {
      customerSnap = snapRaw.cast<String, dynamic>();
    } else {
      final c = sale['customer'];
      if (c is Map) {
        customerSnap = {
          "name":
              ((c['first_name'] ?? c['name'] ?? "Walk-in").toString() +
                      " " +
                      (c['last_name'] ?? "").toString())
                  .trim(),
          "phone": (c['phone'] ?? c['mobile'] ?? c['mobile_no'] ?? "")
              .toString(),
          "address": (c['address'] ?? c['full_address'] ?? "").toString(),
        };
      } else {
        customerSnap = {"name": "Walk-in", "phone": "", "address": ""};
      }
    }

    // ---- cash received: from meta first, otherwise assume paid (cash sale) ----
    final cashReceived = (meta['cash_received'] is num)
        ? (meta['cash_received'] as num).toDouble()
        : _d(meta['cash_received']) != 0
        ? _d(meta['cash_received'])
        : paid;

    // change amount
    final changeAmount = (cashReceived - total)
        .clamp(0, double.infinity)
        .toDouble();

    // delivery: from meta if exists else from sale['delivery']
    final metaDelivery = (meta['delivery'] is num)
        ? (meta['delivery'] as num).toDouble()
        : _d(meta['delivery']);
    final effectiveDelivery = metaDelivery != 0 ? metaDelivery : delivery;

    // ---- final meta for printing (ensure keys exist) ----
    final printMeta = <String, dynamic>{
      ...meta,
      "customer_snapshot": customerSnap,
      "cash_received": cashReceived,
      "delivery": effectiveDelivery,
      "payments": paymentsRaw,
    };

    final receiptNo = (sale['invoice_no'] ?? sale['id'] ?? 'N/A').toString();
    final createdAtStr = sale['created_at']?.toString();
    final dateTime = DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();

    // Build ReceiptItem list
    final receiptItems = itemsRaw.map((i) {
      final m = (i as Map);
      final name = (m['product']?['name'] ?? m['name'] ?? '-').toString();
      final price = _d(m['price']);
      final qty = _d(m['quantity']);
      final lineTotal = _d(m['total']) != 0 ? _d(m['total']) : (price * qty);

      return ReceiptItem(name: name, price: price, qty: qty, total: lineTotal);
    }).toList();

    // 🟡 set from your settings later
    final hasPrinter = false;

    if (!kIsWeb && hasPrinter) {
      const printerIp = "192.168.1.50";

      await ThermalPrinterService.instance.printSaleReceipt(
        printerIp: printerIp,
        shopName: "HT COMPUTERS",
        shopAddress: "HT Computers Clock Tower Sukkur",
        shopPhone: "+92 333 7155125",
        receiptNo: receiptNo,
        dateTime: dateTime,
        items: receiptItems,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        grandTotal: total,
        meta: printMeta,
      );
    } else {
      await ReceiptPreviewService.instance.previewReceipt(
        shopName: "HT COMPUTERS",
        shopAddress: "HT Computers Clock Tower Sukkur",
        shopPhone: "+92 333 7155125",
        receiptNo: receiptNo,
        dateTime: dateTime,
        items: receiptItems,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        grandTotal: total,
        meta: printMeta,
      );
    }
  }

  /* ====================== Build ====================== */

  @override
  Widget build(BuildContext context) {
    final payments = (_sale?['payments'] as List?) ?? [];
    final paid = payments.fold<double>(
      0,
      (sum, p) => sum + (double.tryParse(p['amount'].toString()) ?? 0.0),
    );
    final total = double.tryParse(_sale?['total']?.toString() ?? "0") ?? 0.0;
    final remaining = total - paid;

    final balanceColor = remaining > 0
        ? Colors.red
        : remaining < 0
        ? Colors.orange
        : Colors.green;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Sale Detail"),
          // actions: const [BranchIndicator(tappable: false)],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sale == null
            ? const Center(child: Text("Sale not found"))
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
                          "Invoice: ${_sale!['invoice_no']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Date: ${_sale!['created_at'].toString().substring(0, 10)}",
                            ),
                            Text(
                              "Salesman: ${_sale!['salesman']?['name'] ?? "-"}",
                            ),
                            Text(
                              "Vendor: ${_sale!['vendor']?['first_name'] ?? "No Vendor"} ${_sale!['vendor']?['last_name'] ?? ""}",
                            ),
                            Text(
                              "Customer: ${_sale!['customer']?['first_name'] ?? "Walk-in"} ${_sale!['customer']?['last_name'] ?? ""}",
                            ),
                            // Text("Branch: ${_sale!['branch']?['name']}"),
                            // Text("Status: ${_sale!['status']}"),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.print),
                          onPressed: _printInvoice,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items section
                    SaleItemsSection(
                      sale: _sale!,
                      onPickVendor: _pickVendor,
                      selectedVendor: _selectedVendor,
                      onAddItem: _addItem,
                      onEditItem: _editItem,
                      onDeleteItem: _deleteItem,
                    ),

                    const SizedBox(height: 12),

                    // Payments section
                    // SalePaymentsSection(
                    //   payments: payments,
                    //   onAddPayment: _addPayment,
                    //   onEditPayment: _editPayment,
                    //   onDeletePayment: _deletePayment,
                    // ),
                    const SizedBox(height: 12),

                    // Summary with inline editable discount/tax
                    SaleTotalsEditable(
                      sale: _sale!,
                      discountController: discountCtl,
                      taxController: taxCtl,
                      paid: paid,
                      balanceColor: balanceColor,
                      onSave: _updateDiscountTax,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
