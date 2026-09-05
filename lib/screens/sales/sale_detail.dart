import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';

// parts
import 'package:enterprise_pos/screens/sales/parts/sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';

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

  ApiClient get _api =>
      ApiClient(token: Provider.of<AuthProvider>(context, listen: false).token);

  @override
  void initState() {
    super.initState();
    _fetchSale();
  }

  /* ====================== Data ====================== */

  Future<void> _fetchSale() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get("/sales/${widget.saleId}?include_balance=1");
      if (!mounted) return;
      setState(() {
        _sale = res['data'];
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

  Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _metaMap() => _mapFrom(_sale?['meta']);

  Map<String, dynamic> _metaSnapshot(String key) {
    final meta = _metaMap();
    return _mapFrom(meta[key]);
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _nameFromMap(dynamic value, {String fallback = '-'}) {
    final map = _mapFrom(value);
    final directName = _text(map['name']);
    if (directName.isNotEmpty) return directName;

    final joined = [
      _text(map['first_name']),
      _text(map['last_name']),
    ].where((part) => part.isNotEmpty).join(' ').trim();

    return joined.isNotEmpty ? joined : fallback;
  }

  String _customerDisplayName() {
    final snap = _metaSnapshot('customer_snapshot');
    final fromSnapshot = _nameFromMap(snap, fallback: '');
    if (fromSnapshot.isNotEmpty) return fromSnapshot;
    return _nameFromMap(_sale?['customer'], fallback: 'Walk-in');
  }

  String _salesmanDisplayName() {
    final snap = _metaSnapshot('salesman_snapshot');
    final fromSnapshot = _nameFromMap(snap, fallback: '');
    if (fromSnapshot.isNotEmpty) return fromSnapshot;
    return _nameFromMap(_sale?['salesman'], fallback: '-');
  }

  String _vendorDisplayName() {
    final snap = _metaSnapshot('vendor_snapshot');
    final fromSnapshot = _nameFromMap(snap, fallback: '');
    if (fromSnapshot.isNotEmpty) return fromSnapshot;
    return _nameFromMap(_sale?['vendor'], fallback: 'No Vendor');
  }

  SaleService get _saleService => SaleService(
        token: Provider.of<AuthProvider>(context, listen: false).token!,
      );

  Future<void> _openAuditedEdit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateSaleScreen(editSaleId: widget.saleId),
      ),
    );
    if (!mounted || changed != true) return;
    _updated = true;
    await _fetchSale();
  }

  Future<void> _openReturnExchange() async {
    final sale = _sale;
    if (sale == null) return;
    final invoice = (sale['invoice_no'] ?? sale['id'] ?? '').toString().trim();
    if (invoice.isEmpty) return;

    Map<String, dynamic>? customer;
    final rawCustomer = sale['customer'];
    if (rawCustomer is Map) {
      customer = rawCustomer.cast<String, dynamic>();
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateSaleScreen(
          initialCustomer: customer,
          initialReturnInvoice: invoice,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) _updated = true;
    // Always refresh because the return may have been posted even if the user
    // subsequently backed out of the exchange/new-sale screen.
    await _fetchSale();
  }

  Future<void> _showAmendmentHistory() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AmendmentHistoryDialog(
        invoiceNo: (_sale?['invoice_no'] ?? widget.saleId).toString(),
        future: _saleService.getAmendments(widget.saleId),
        canViewProfit:
            context.read<AuthProvider>().hasPermission('view-sale-profit'),
      ),
    );
  }

  Future<void> _correctReceipt(Map<String, dynamic> payment) async {
    final receiptId = int.tryParse(payment['id']?.toString() ?? '');
    if (receiptId == null) return;
    final decision = await showDialog<_SaleReceiptCorrectionDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaleReceiptCorrectionDialog(
        payment: payment,
        methods: context.read<PaymentMethodProvider>(),
      ),
    );
    if (!mounted || decision == null) return;

    final payload = <String, dynamic>{
      'reason': decision.reason,
      'replacement_amount': decision.amount,
      if (decision.amount > 0) 'replacement_method': decision.method,
      if (decision.reference.isNotEmpty)
        'replacement_reference': decision.reference,
      if (decision.note.isNotEmpty) 'replacement_note': decision.note,
    };

    Future<Map<String, dynamic>> submit() =>
        _saleService.correctSaleReceipt(widget.saleId, receiptId, payload);

    try {
      try {
        await submit();
      } on ApiException catch (e) {
        final issue = CreditLimitIssue.fromException(e);
        final auth = context.read<AuthProvider>();
        if (issue == null ||
            !issue.canOverride ||
            !auth.hasPermission('override-party-credit-limit')) {
          rethrow;
        }
        final reason = await showCreditLimitOverrideDialog(context, issue);
        if (!mounted || reason == null) return;
        payload['credit_limit_override'] = {'reason': reason};
        await submit();
      }
      if (!mounted) return;
      _updated = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment corrected. The original receipt was preserved as reversed history.',
          ),
        ),
      );
      await _fetchSale();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment correction failed: $message')),
      );
    }
  }

  /* ====================== Print ====================== */

  Future<void> _printInvoice() async {
    if (_sale == null) return;

    double _d(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

    final sale = _sale!;
    final itemsRaw = (sale['items'] as List?) ?? const [];
    final paymentsRaw = (sale['payments'] as List?) ?? const [];
    final activePayments = paymentsRaw.where((p) {
      if (p is! Map) return false;
      final reversedAt = p['reversed_at'];
      return reversedAt == null || reversedAt.toString().trim().isEmpty;
    }).toList(growable: false);

    final subtotal = _d(sale['subtotal']);
    final discount = _d(sale['discount']);
    final tax = _d(sale['tax']);
    final delivery = _d(sale['delivery']); // if your API returns it
    final total = _d(sale['total']);

    final paid = sale['net_paid'] != null
        ? _d(sale['net_paid'])
        : activePayments.fold<double>(
            0,
            (sum, p) => sum + _d((p as Map)['amount']),
          );
    final revisionNo = int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0;

    // ---- meta from response (preferred) ----
    final meta = _mapFrom(sale['meta']);

    // ---- build customer snapshot: from meta, otherwise from customer object ----
    Map<String, dynamic> customerSnap = {};
    final snapRaw = _mapFrom(meta['customer_snapshot']);
    if (snapRaw.isNotEmpty) {
      customerSnap = Map<String, dynamic>.from(snapRaw);
      // New sales snapshot customer identity directly. For an older sale whose
      // snapshot predates customer codes, use the live customer relation as a
      // best-effort fallback without changing the stored historical metadata.
      final c = sale['customer'];
      if (c is Map) {
        final code = (c['customer_code'] ?? '').toString().trim();
        if ((customerSnap['customer_code'] ?? '').toString().trim().isEmpty &&
            code.isNotEmpty) {
          customerSnap['customer_code'] = code;
        }
        if (customerSnap['customer_type'] == null && c['customer_type'] != null) {
          customerSnap['customer_type'] = c['customer_type'];
        }
      }
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
          if ((c['customer_code'] ?? '').toString().trim().isNotEmpty)
            "customer_code": c['customer_code'],
          if (c['customer_type'] != null)
            "customer_type": c['customer_type'],
        };
      } else {
        customerSnap = {"name": "Walk-in", "phone": "", "address": ""};
      }
    }

    // Original receipts may preserve a cash-tender/change snapshot. Once the
    // invoice is amended, that old tender snapshot no longer describes the
    // revised invoice reliably (especially after a refund/customer credit), so
    // reprints use the authoritative net settlement and never invent change.
    final cashReceived = revisionNo > 0
        ? paid
        : (meta['cash_received'] is num)
            ? (meta['cash_received'] as num).toDouble()
            : _d(meta['cash_received']) != 0
                ? _d(meta['cash_received'])
                : paid;
    final changeAmount = revisionNo > 0
        ? 0.0
        : (cashReceived - total).clamp(0, double.infinity).toDouble();

    // For revised invoices the sale row is authoritative, including an
    // intentional change from a non-zero delivery fee to zero.
    final metaDelivery = (meta['delivery'] is num)
        ? (meta['delivery'] as num).toDouble()
        : _d(meta['delivery']);
    final effectiveDelivery =
        revisionNo > 0 ? delivery : (metaDelivery != 0 ? metaDelivery : delivery);

    // ---- final meta for printing (ensure keys exist) ----
    final printMeta = <String, dynamic>{
      ...meta,
      "customer_snapshot": customerSnap,
      "cash_received": cashReceived,
      "change_amount": changeAmount,
      "delivery": effectiveDelivery,
      "payments": activePayments,
      "payments_snapshot": activePayments,
      "sale_source_snapshot": _mapFrom(meta['sale_source_snapshot']).isNotEmpty
          ? _mapFrom(meta['sale_source_snapshot'])
          : <String, dynamic>{
              if (sale['sale_source_id'] != null) "id": sale['sale_source_id'],
              "name": (sale['sale_source_name'] ?? 'Counter').toString(),
            },
      "revision_no": revisionNo,
      if (sale['amended_at'] != null) "amended_at": sale['amended_at'],
    };

    // For reprints: use the official invoice_no. Also surface the offline
    // reference in the receipt footer via meta so the cashier can correlate
    // a printed offline receipt with the synced sale.
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

      final gross = (price * qty).abs();
      final net = lineTotal.abs();
      final lineDiscount = gross > net ? gross - net : 0.0;
      final product = m['product'];
      final unitRaw = m['unit_name'] ??
          m['unit_symbol'] ??
          (product is Map ? product['unit'] : null);
      final unitName = unitRaw is Map
          ? (unitRaw['symbol'] ?? unitRaw['name'] ?? '').toString()
          : (unitRaw ?? '').toString();
      final secondaryName = (product is Map
              ? (product['secondary_name'] ?? '')
              : (m['secondary_name'] ?? ''))
          .toString()
          .trim();
      return SaleReceiptItem(
        name: name,
        secondaryName: secondaryName.isEmpty ? null : secondaryName,
        price: price,
        qty: qty,
        total: lineTotal,
        unitName: unitName,
        discountAmount: lineDiscount,
        discountType: (m['discount_type'] ?? 'percentage').toString(),
        discountValue: _d(m['discount']),
      );
    }).toList();

    final printerConfig = context.read<PrinterConfigProvider>();

    if (!printerConfig.isConfigured) {
      try {
        final token = context.read<AuthProvider>().token;
        if (token != null) await printerConfig.refresh(token);
      } catch (e, s) {
        debugPrint('Printer config refresh failed: $e');
        debugPrintStack(stackTrace: s);
      }
    }

    final effectiveShopName = printerConfig.shopName.isNotEmpty ? printerConfig.shopName : 'My Shop';
    final effectiveShopAddress = printerConfig.shopAddress.isNotEmpty ? printerConfig.shopAddress : null;
    final effectiveShopPhone = printerConfig.shopPhone.isNotEmpty ? printerConfig.shopPhone : null;
    final mainTemplate = printerConfig.mainInvoiceTemplate;
    final secondaryTemplate = printerConfig.secondaryInvoiceTemplate;
    final secondaryHeader = printerConfig.secondaryReceiptHeader.trim().isEmpty
        ? 'KITCHEN COPY'
        : printerConfig.secondaryReceiptHeader.trim();
    final footerLines = printerConfig.footerLines;
    final footerLineStyles = printerConfig.footerLineStyles;
    printMeta['item_discount_display'] = printerConfig.itemDiscountDisplay.value;

    debugPrint('Active printer connection: ${printerConfig.activeConnection}, template: ${mainTemplate.value}');

    var printedToHardware = false;
    if (printerConfig.isNetworkPrinter && mainTemplate.supportsRawNetwork && (printerConfig.networkIp ?? '').trim().isNotEmpty) {
      try {
        await ThermalPrinterService.instance.printSaleReceiptNetwork(
          printerIp: printerConfig.networkIp!.trim(),
          port: printerConfig.networkPort,
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: dateTime,
          items: receiptItems,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          cashReceived: cashReceived,
          changeAmount: changeAmount,
          meta: printMeta,
          sections: mainTemplate.sections,
          paperWidth: printerConfig.mainPaperCode,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          showLogo: printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
          logoData: printerConfig.printLogoData,
          showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
          qrUrl: printerConfig.qrCodeUrl,
          qrCaption: printerConfig.qrCodeCaption,
          template: mainTemplate,
          devCreditEnabled: printerConfig.devCreditEnabled,
          devCreditText: printerConfig.devCreditText,
        );
        printedToHardware = true;

        if (printerConfig.secondaryPrintEnabled && (printerConfig.secondaryNetworkIp ?? '').trim().isNotEmpty) {
          await ThermalPrinterService.instance.printSaleReceiptNetwork(
            printerIp: printerConfig.secondaryNetworkIp!.trim(),
            port: printerConfig.secondaryNetworkPort,
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: dateTime,
            items: receiptItems,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: printMeta,
            sections: secondaryTemplate.sections,
            paperWidth: secondaryTemplate.paperWidthCode,
            footerLines: footerLines,
            footerLineStyles: footerLineStyles,
            receiptHeader: secondaryHeader,
            template: secondaryTemplate,
            devCreditEnabled: printerConfig.devCreditEnabled,
            devCreditText: printerConfig.devCreditText,
          );
        }
      } catch (e, s) {
        debugPrint('PRINT ERROR (network): $e');
        debugPrintStack(stackTrace: s);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Sale created but printing failed: $e")),
          );
        }
      }
    } else if (printerConfig.isLocalPrinter && (printerConfig.localPrinterName ?? '').trim().isNotEmpty) {
      try {
        await LocalPrinterService.instance.printSaleReceipt(
          printerName: printerConfig.localPrinterName!.trim(),
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: dateTime,
          items: receiptItems,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          cashReceived: cashReceived,
          changeAmount: changeAmount,
          meta: printMeta,
          sections: mainTemplate.sections,
          paperWidth: printerConfig.mainPaperCode,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          invoiceHeading: printerConfig.invoiceHeading,
          showLogo: printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
          logoData: printerConfig.printLogoData,
          showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
          qrUrl: printerConfig.qrCodeUrl,
          qrCaption: printerConfig.qrCodeCaption,
          template: mainTemplate,
          devCreditEnabled: printerConfig.devCreditEnabled,
          devCreditText: printerConfig.devCreditText,
        );
        printedToHardware = true;

        if (printerConfig.secondaryPrintEnabled &&
            (printerConfig.secondaryLocalPrinterName ?? '').trim().isNotEmpty) {
          await LocalPrinterService.instance.printSaleReceipt(
            printerName: printerConfig.secondaryLocalPrinterName!.trim(),
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: dateTime,
            items: receiptItems,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: printMeta,
            sections: secondaryTemplate.sections,
            paperWidth: secondaryTemplate.paperWidthCode,
            footerLines: footerLines,
            footerLineStyles: footerLineStyles,
            receiptHeader: secondaryHeader,
            template: secondaryTemplate,
            jobName: 'Secondary Copy $receiptNo',
            devCreditEnabled: printerConfig.devCreditEnabled,
            devCreditText: printerConfig.devCreditText,
          );
        }
      } catch (e, s) {
        debugPrint('PRINT ERROR (local): $e');
        debugPrintStack(stackTrace: s);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Sale created but printing failed: $e")),
          );
        }
      }
    }

    if (!printedToHardware) {
      await ReceiptPreviewService.instance.previewReceipt(
        shopName: effectiveShopName,
        shopAddress: effectiveShopAddress,
        shopPhone: effectiveShopPhone,
        receiptNo: receiptNo,
        dateTime: dateTime,
        items: receiptItems,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        grandTotal: total,
        meta: printMeta,
        sections: mainTemplate.sections,
        paperWidth: printerConfig.mainPaperCode,
        footerLines: footerLines,
        footerLineStyles: footerLineStyles,
        invoiceHeading: printerConfig.invoiceHeading,
        showLogo: printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
        logoData: printerConfig.printLogoData,
        showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
        qrUrl: printerConfig.qrCodeUrl,
        qrCaption: printerConfig.qrCodeCaption,
        template: mainTemplate,
        devCreditEnabled: printerConfig.devCreditEnabled,
        devCreditText: printerConfig.devCreditText,
      );
    }
  }

  /* ====================== Build ====================== */

  @override
  Widget build(BuildContext context) {
    final paid = double.tryParse(_sale?['net_paid']?.toString() ?? '') ?? 0.0;
    final total = double.tryParse(_sale?['total']?.toString() ?? "0") ?? 0.0;
    final remaining = double.tryParse(_sale?['balance']?.toString() ?? '') ??
        (total - paid);

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
          actions: [
            if (!_loading &&
                _sale != null &&
                context.watch<AuthProvider>().hasPermission('refund-sale'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: OutlinedButton.icon(
                  onPressed: _openReturnExchange,
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Return / Exchange'),
                ),
              ),
            if (!_loading && _sale != null &&
                context.watch<AuthProvider>().hasPermission('amend-sales'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.icon(
                  onPressed: _openAuditedEdit,
                  icon: const Icon(Icons.edit_note_rounded, size: 19),
                  label: const Text('Edit Sale'),
                ),
              ),
            if (!_loading && _sale != null &&
                (int.tryParse(_sale?['revision_no']?.toString() ?? '') ?? 0) > 0)
              IconButton(
                tooltip: 'Amendment history',
                onPressed: _showAmendmentHistory,
                icon: const Icon(Icons.history_rounded),
              ),
            const BranchIndicator(tappable: false),
          ],
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
                            Text("Salesman: ${_salesmanDisplayName()}"),
                            Text("Vendor: ${_vendorDisplayName()}"),
                            Text("Customer: ${_customerDisplayName()}"),
                            Text("Sale From: ${(_sale!['sale_source_name'] ?? 'Counter')}"),
                            if ((int.tryParse(_sale!['revision_no']?.toString() ?? '') ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  'Audited revision ${_sale!['revision_no']} • Last amended ${_sale!['amended_at'] ?? '-'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            // Show the original offline receipt reference when
                            // the sale was created while the device was offline.
                            if ((_sale!['offline_invoice_no'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.offline_bolt,
                                      size: 13,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        "Original Offline Ref: ${_sale!['offline_invoice_no']}",
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Text("Branch: ${_sale!['branch']?['name']}"),
                            // Text("Status: ${_sale!['status']}"),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((int.tryParse(_sale!['revision_no']?.toString() ?? '') ?? 0) > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'REV ${_sale!['revision_no']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: 'Print current invoice revision',
                              icon: const Icon(Icons.print_rounded),
                              onPressed: _printInvoice,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items section
                    SaleItemsSection(
                      sale: _sale!,
                      editable: false,
                    ),

                    const SizedBox(height: 12),

                    _PostedSaleSummaryCard(
                      sale: _sale!,
                      paid: paid,
                      balance: remaining,
                      balanceColor: balanceColor,
                    ),

                    if (((_sale!['returns'] as List?) ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SaleReturnHistoryCard(
                        returns: ((_sale!['returns'] as List?) ?? const [])
                            .whereType<Map>()
                            .map((e) => e.cast<String, dynamic>())
                            .toList(growable: false),
                      ),
                    ],

                    const SizedBox(height: 12),

                    _SalePaymentHistoryCard(
                      payments: ((_sale!['payments'] as List?) ?? const [])
                          .whereType<Map>()
                          .map((e) => e.cast<String, dynamic>())
                          .toList(growable: false),
                      canCorrect: context
                              .watch<AuthProvider>()
                              .hasPermission('amend-sales') &&
                          context
                              .watch<AuthProvider>()
                              .hasPermission('reverse-party-payments'),
                      onCorrect: _correctReceipt,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SaleReturnHistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> returns;

  const _SaleReturnHistoryCard({required this.returns});

  double _n(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0.0;

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false)
      : const <Map<String, dynamic>>[];

  String _date(dynamic value) {
    final text = (value ?? '').toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  Widget _metric(String label, double amount, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            AppCurrency.format(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_return_outlined, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Returns / Credit Notes',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Text(
                  '${returns.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...returns.map((ret) {
              final items = _maps(ret['items']);
              final refunds = _maps(ret['refunds']);
              final applications = _maps(ret['applications']);
              final credit = _n(ret['total']);
              final refunded = refunds.fold<double>(
                0,
                (sum, row) => sum + _n(row['amount']),
              );
              final applied = applications.fold<double>(
                0,
                (sum, row) => sum + _n(row['amount']),
              );
              final remainingCredit = (credit - refunded - applied).clamp(0.0, double.infinity);
              final productText = items.map((row) {
                final name = (row['product_name'] ?? 'Product').toString();
                final qty = _n(row['quantity']);
                return '$name × ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 3)}';
              }).join(' • ');

              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (ret['return_no'] ?? 'Return').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${(ret['status'] ?? 'completed').toString().toUpperCase()} • ${_date(ret['created_at'])}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (productText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        productText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const Divider(height: 14),
                    _metric('Merchandise after discounts', _n(ret['subtotal'])),
                    if (_n(ret['invoice_discount']) > .004)
                      _metric('Invoice discount allocated', _n(ret['invoice_discount'])),
                    _metric('Tax reversed', _n(ret['tax'])),
                    _metric('Original delivery refunded', _n(ret['delivery_refund'])),
                    _metric('Return credit', credit, emphasized: true),
                    if (applied > .004) _metric('Applied to invoice balance / exchange', applied),
                    if (refunded > .004) _metric('Actually refunded', refunded),
                    if (remainingCredit > .004) _metric('Customer credit remaining', remainingCredit),
                    if ((ret['reason'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Reason: ${ret['reason']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SalePaymentHistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final bool canCorrect;
  final Future<void> Function(Map<String, dynamic> payment) onCorrect;

  const _SalePaymentHistoryCard({
    required this.payments,
    required this.canCorrect,
    required this.onCorrect,
  });

  double _n(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<PaymentMethodProvider>();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Payment History',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                if (canCorrect)
                  Text(
                    'Corrections are reversal + replacement',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (payments.isEmpty)
              Text(
                'No receipts recorded for this invoice.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...payments.map((payment) {
                final reversed = payment['reversed_at'] != null &&
                    payment['reversed_at'].toString().trim().isNotEmpty;
                final method = (payment['method'] ?? '').toString();
                final reference =
                    (payment['reference'] ?? '').toString().trim();
                return Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(.38),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        reversed ? Icons.undo_rounded : Icons.check_circle_outline,
                        size: 18,
                        color: reversed
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Colors.green.shade700,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${pm.displayNameFor(method)} • ${AppCurrency.format(_n(payment['amount']))}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration:
                                    reversed ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            Text(
                              [
                                'Receipt #${payment['id'] ?? '-'}',
                                payment['received_at']?.toString() ?? '',
                                if (reference.isNotEmpty) reference,
                                if (reversed) 'Reversed: ${payment['reversal_reason'] ?? '-'}',
                              ].where((e) => e.toString().trim().isNotEmpty).join(' • '),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (canCorrect && !reversed)
                        TextButton.icon(
                          onPressed: () => onCorrect(payment),
                          icon: const Icon(Icons.change_circle_outlined, size: 17),
                          label: const Text('Correct'),
                        ),
                    ],
                  ),
                );
              }),
            if (payments.any((p) => p['reversed_at'] != null)) ...[
              const SizedBox(height: 3),
              Text(
                'Reversed receipts remain visible by design; they are never deleted from financial history.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaleReceiptCorrectionDecision {
  final String reason;
  final double amount;
  final String method;
  final String reference;
  final String note;

  const _SaleReceiptCorrectionDecision({
    required this.reason,
    required this.amount,
    required this.method,
    required this.reference,
    required this.note,
  });
}

class _SaleReceiptCorrectionDialog extends StatefulWidget {
  final Map<String, dynamic> payment;
  final PaymentMethodProvider methods;

  const _SaleReceiptCorrectionDialog({
    required this.payment,
    required this.methods,
  });

  @override
  State<_SaleReceiptCorrectionDialog> createState() =>
      _SaleReceiptCorrectionDialogState();
}

class _SaleReceiptCorrectionDialogState
    extends State<_SaleReceiptCorrectionDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  late final TextEditingController _note;
  final _reason = TextEditingController();
  String? _method;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (double.tryParse(widget.payment['amount']?.toString() ?? '') ?? 0)
          .toStringAsFixed(2),
    );
    _reference = TextEditingController(
      text: (widget.payment['reference'] ?? '').toString(),
    );
    _note = TextEditingController(
      text: (widget.payment['note'] ?? '').toString(),
    );
    final original = (widget.payment['method'] ?? '').toString();
    final active = widget.methods.activeMethods;
    _method = active.any((m) => m.method == original)
        ? original
        : widget.methods.defaultMethod?.method;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amount.text.trim());
    final reason = _reason.text.trim();
    if (amount == null || amount < 0) {
      setState(() => _error = 'Replacement amount must be 0 or greater.');
      return;
    }
    if (amount > 0 && (_method == null || _method!.isEmpty)) {
      setState(() => _error = 'Select a replacement payment method.');
      return;
    }
    if (reason.length < 5) {
      setState(() => _error = 'Enter a correction reason of at least 5 characters.');
      return;
    }
    Navigator.pop(
      context,
      _SaleReceiptCorrectionDecision(
        reason: reason,
        amount: amount,
        method: amount > 0 ? _method! : '',
        reference: _reference.text.trim(),
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final originalAmount =
        double.tryParse(widget.payment['amount']?.toString() ?? '') ?? 0.0;
    final originalMethod = widget.methods.displayNameFor(
      widget.payment['method']?.toString(),
    );
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.change_circle_outlined),
          SizedBox(width: 9),
          Text('Correct Posted Payment'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(.55),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Original receipt #${widget.payment['id']} • $originalMethod • ${AppCurrency.format(originalAmount)}\n'
                  'The original receipt and journal will be reversed, not edited or deleted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Replacement amount',
                        helperText: 'Use 0 to reverse without replacement',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _method,
                      decoration: const InputDecoration(
                        labelText: 'Replacement method',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.methods.activeMethods
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.method,
                              child: Text(m.displayName),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) => setState(() => _method = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Replacement note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Correction reason *',
                  hintText: 'e.g. Cash was selected instead of KNET',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'This correction is atomic. If the reversal, replacement receipt, ledger posting, register movement, rider custody, or credit control fails, nothing is committed.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Reverse & Apply Correction'),
        ),
      ],
    );
  }
}

class _PostedSaleSummaryCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final double paid;
  final double balance;
  final Color balanceColor;

  const _PostedSaleSummaryCard({
    required this.sale,
    required this.paid,
    required this.balance,
    required this.balanceColor,
  });

  double _n(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0.0;

  Widget _row(
    BuildContext context,
    String label,
    double value, {
    bool strong = false,
    Color? color,
    String? prefix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '${prefix ?? ''}${AppCurrency.format(value)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: strong ? 16 : 14,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _n(sale['subtotal']);
    final discount = _n(sale['discount']);
    final tax = _n(sale['tax']);
    final delivery = _n(sale['delivery']);
    final total = _n(sale['total']);
    final status = (sale['status'] ?? '').toString();
    final revision = int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Posted Invoice Summary',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    revision > 0 ? 'Revision $revision • $status' : status,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _row(context, 'Subtotal', subtotal),
          if (discount != 0)
            _row(context, 'Discount', discount, color: Colors.red.shade700, prefix: '-'),
          if (delivery != 0) _row(context, 'Shipping Charges', delivery),
          if (tax != 0) _row(context, 'Tax', tax),
          const Divider(height: 1),
          _row(context, 'Invoice Total', total, strong: true),
          _row(context, 'Net Settled', paid),
          _row(
            context,
            balance >= 0 ? 'Balance Due' : 'Customer Credit',
            balance.abs(),
            strong: true,
            color: balanceColor,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Posted values are read-only here. Authorized corrections use Edit Sale so stock, COGS and ledger changes stay audited and atomic.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmendmentHistoryDialog extends StatelessWidget {
  final String invoiceNo;
  final Future<Map<String, dynamic>> future;
  final bool canViewProfit;

  const _AmendmentHistoryDialog({
    required this.invoiceNo,
    required this.future,
    required this.canViewProfit,
  });

  double _n(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 14, 8),
      title: Row(
        children: [
          const Icon(Icons.history_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Amendment History'),
                Text(
                  invoiceNo,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 480,
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load amendment history.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final raw = snapshot.data?['data'];
            final rows = raw is List ? raw.whereType<Map>().toList() : const <Map>[];
            if (rows.isEmpty) {
              return const Center(
                child: Text('This invoice has no posted amendments.'),
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = rows[index];
                final revision = row['revision_no'] ?? '-';
                final totalBefore = _n(row['total_before']);
                final totalAfter = _n(row['total_after']);
                final profitBefore = _n(row['gross_profit_before']);
                final profitAfter = _n(row['gross_profit_after']);
                final inventoryDelta = _n(row['inventory_value_delta']);
                final inventoryVariance = _n(row['inventory_variance']);
                final user = (row['created_by_name'] ?? 'User ${row['created_by'] ?? '-'}').toString();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Revision $revision',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${row['created_at'] ?? '-'} • $user',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (row['journal_entry_id'] != null)
                            Text(
                              'Journal #${row['journal_entry_id']}',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        (row['reason'] ?? '-').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (row['sale_source_changed'] == true) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.hub_outlined, size: 15, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Text(
                              'Sale From: ${row['sale_source_before'] ?? '-'} → ${row['sale_source_after'] ?? '-'}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 18,
                        runSpacing: 7,
                        children: [
                          _HistoryMetric(
                            label: 'Invoice',
                            before: totalBefore,
                            after: totalAfter,
                          ),
                          if (canViewProfit)
                            _HistoryMetric(
                              label: 'COGS',
                              before: _n(row['cogs_before']),
                              after: _n(row['cogs_after']),
                            ),
                          if (canViewProfit)
                            _HistoryMetric(
                              label: 'Gross Profit',
                              before: profitBefore,
                              after: profitAfter,
                            ),
                          if (canViewProfit && inventoryDelta.abs() > .004)
                            _HistoryDeltaMetric(
                              label: 'Inventory Value Δ',
                              value: inventoryDelta,
                            ),
                          if (canViewProfit && inventoryVariance.abs() > .004)
                            _HistoryDeltaMetric(
                              label: 'Valuation Variance • 5205',
                              value: inventoryVariance,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HistoryDeltaMetric extends StatelessWidget {
  final String label;
  final double value;

  const _HistoryDeltaMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(.55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            '${value >= 0 ? '+' : ''}${AppCurrency.format(value)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final String label;
  final double before;
  final double after;

  const _HistoryMetric({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final delta = after - before;
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            '${AppCurrency.format(before)} → ${AppCurrency.format(after)}  (${delta >= 0 ? '+' : ''}${AppCurrency.format(delta)})',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

