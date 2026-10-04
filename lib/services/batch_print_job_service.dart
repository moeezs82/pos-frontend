import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/models/receipt_footer_style.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class BatchPrintJobError {
  final int saleId;
  final String invoiceNo;
  final String message;

  const BatchPrintJobError({
    required this.saleId,
    required this.invoiceNo,
    required this.message,
  });
}

enum BatchPrintJobStatus { queued, running, done, cancelled }

class BatchPrintJob extends ChangeNotifier {
  BatchPrintJob({
    required this.totalCount,
    required this.jobId,
  });

  final int totalCount;
  final String jobId;

  int completed = 0;
  int failed = 0;
  BatchPrintJobStatus status = BatchPrintJobStatus.queued;
  final List<BatchPrintJobError> errors = [];
  String? lastPrintedInvoice;

  bool get isDone =>
      status == BatchPrintJobStatus.done ||
      status == BatchPrintJobStatus.cancelled;

  double get progress =>
      totalCount == 0 ? 0 : (completed + failed) / totalCount;

  int get processed => completed + failed;

  void _markRunning() {
    status = BatchPrintJobStatus.running;
    notifyListeners();
  }

  void _recordSuccess(String invoiceNo) {
    completed++;
    lastPrintedInvoice = invoiceNo;
    notifyListeners();
  }

  void _recordError(int saleId, String invoiceNo, String message) {
    failed++;
    errors.add(BatchPrintJobError(
      saleId: saleId,
      invoiceNo: invoiceNo,
      message: message,
    ));
    notifyListeners();
  }

  void _markDone() {
    status = BatchPrintJobStatus.done;
    notifyListeners();
  }

  void cancel() {
    if (!isDone) {
      status = BatchPrintJobStatus.cancelled;
      notifyListeners();
    }
  }
}

// ---------------------------------------------------------------------------
// Snapshot of printer config captured at job-start time.
// Avoids accessing a potentially-stale BuildContext inside the async loop.
// ---------------------------------------------------------------------------

class BatchPrintConfig {
  const BatchPrintConfig({
    required this.activeConnection,
    required this.networkIp,
    required this.networkPort,
    required this.localPrinterName,
    required this.secondaryEnabled,
    required this.secondaryNetworkIp,
    required this.secondaryNetworkPort,
    required this.secondaryLocalPrinterName,
    required this.shopName,
    this.shopAddress,
    this.shopPhone,
    required this.mainTemplate,
    required this.secondaryTemplate,
    required this.secondaryHeader,
    required this.mainPaperCode,
    required this.footerLines,
    required this.footerLineStyles,
    required this.invoiceHeading,
    required this.printLogo,
    this.logoData,
    required this.printQr,
    this.qrUrl,
    required this.qrCaption,
    required this.itemDiscountDisplay,
    required this.devCreditEnabled,
    required this.devCreditText,
    required this.printSecondary,
  });

  final String activeConnection;
  final String? networkIp;
  final int networkPort;
  final String? localPrinterName;

  // Secondary printer
  final bool secondaryEnabled;
  final String? secondaryNetworkIp;
  final int secondaryNetworkPort;
  final String? secondaryLocalPrinterName;

  // Branding
  final String shopName;
  final String? shopAddress;
  final String? shopPhone;

  // Templates & paper
  final InvoiceTemplate mainTemplate;
  final InvoiceTemplate secondaryTemplate;
  final String secondaryHeader;
  final String mainPaperCode;

  // Footer / logo / QR
  final List<String> footerLines;
  final List<ReceiptFooterStyle> footerLineStyles;
  final String invoiceHeading;
  final bool printLogo;
  final String? logoData;
  final bool printQr;
  final String? qrUrl;
  final String qrCaption;
  final ItemDiscountDisplay itemDiscountDisplay;
  final bool devCreditEnabled;
  final String devCreditText;

  // Whether the user confirmed to also print on secondary in this batch
  final bool printSecondary;

  bool get isNetworkPrinter => activeConnection == 'network';
  bool get isLocalPrinter => activeConnection == 'local';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class BatchPrintJobService extends ChangeNotifier {
  BatchPrintJobService._();
  static final instance = BatchPrintJobService._();

  BatchPrintJob? _currentJob;
  String? _pdfFolderPath;

  BatchPrintJob? get currentJob => _currentJob;
  String? get pdfFolderPath => _pdfFolderPath;

  void clearJob() {
    _currentJob = null;
    _pdfFolderPath = null;
    notifyListeners();
  }

  // Returns a job handle immediately; the actual loop runs in the background.
  BatchPrintJob startJob({
    required List<int> saleIds,
    required String token,
    required BatchPrintConfig config,
    // Optional: folder to save PDFs when no hardware printer is configured.
    String? pdfOutputFolder,
    // Callback so the caller can show the "open folder" notification.
    void Function(String folderPath)? onPdfFolderReady,
  }) {
    final job = BatchPrintJob(
      totalCount: saleIds.length,
      jobId: 'batch-${DateTime.now().millisecondsSinceEpoch}',
    );

    _currentJob = job;
    _pdfFolderPath = pdfOutputFolder;
    notifyListeners();

    job.addListener(notifyListeners);

    // Run entirely in the background - never awaited by the UI.
    unawaited(
      _runJob(
        job: job,
        saleIds: saleIds,
        token: token,
        config: config,
        pdfOutputFolder: pdfOutputFolder,
        onPdfFolderReady: (folderPath) {
          _pdfFolderPath = folderPath;
          notifyListeners();
          if (onPdfFolderReady != null) onPdfFolderReady(folderPath);
        },
      ),
    );

    return job;
  }

  // ---------------------------------------------------------------------------
  // Cached Printer object for local jobs.
  // Calling listPrinters() once at job-start saves ~400 ms × N invoices.
  // ---------------------------------------------------------------------------

  Printer? _cachedPrinter;
  String? _cachedPrinterName;

  Future<Printer?> _resolvePrinter(String printerName) async {
    if (_cachedPrinterName == printerName && _cachedPrinter != null) {
      return _cachedPrinter;
    }
    try {
      final printer = await LocalPrinterService.instance
          .requirePrinter(printerName);
      _cachedPrinter = printer;
      _cachedPrinterName = printerName;
      return printer;
    } catch (_) {
      _cachedPrinter = null;
      _cachedPrinterName = null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Main loop
  // ---------------------------------------------------------------------------

  Future<void> _runJob({
    required BatchPrintJob job,
    required List<int> saleIds,
    required String token,
    required BatchPrintConfig config,
    String? pdfOutputFolder,
    void Function(String folderPath)? onPdfFolderReady,
  }) async {
    job._markRunning();

    // Pre-resolve local printer once for the whole batch.
    Printer? resolvedPrinter;
    if (config.isLocalPrinter &&
        (config.localPrinterName ?? '').trim().isNotEmpty) {
      try {
        resolvedPrinter =
            await _resolvePrinter(config.localPrinterName!.trim());
      } catch (e) {
        debugPrint('[BATCH-PRINT] Could not resolve printer: $e');
        // Individual jobs will fail and be recorded as errors below.
      }
    }

    String? effectivePdfFolder = pdfOutputFolder;

    for (final saleId in saleIds) {
      if (job.status == BatchPrintJobStatus.cancelled) break;

      String invoiceNo = '#$saleId';
      try {
        // 1. Fetch full sale data
        final saleData = await _fetchSale(saleId, token);
        invoiceNo =
            (saleData['invoice_no'] ?? saleData['id'] ?? '#$saleId')
                .toString();

        // 2. Build receipt items
        final items = _buildReceiptItems(saleData);

        // 3. Compute amounts
        final amounts = _extractAmounts(saleData);

        // 4. Build print meta
        final printMeta = _buildPrintMeta(saleData, config, amounts);

        final dateTime = DateTime.tryParse(
                saleData['created_at']?.toString() ?? '') ??
            DateTime.now();

        // 5. Dispatch to appropriate print path
        final printed = await _printOne(
          job: job,
          config: config,
          resolvedPrinter: resolvedPrinter,
          receiptNo: invoiceNo,
          dateTime: dateTime,
          items: items,
          amounts: amounts,
          printMeta: printMeta,
        );

        if (!printed) {
          // PDF fallback – save to folder
          effectivePdfFolder ??= await _ensurePdfFolder();
          await _savePdfToFolder(
            folder: effectivePdfFolder,
            config: config,
            receiptNo: invoiceNo,
            dateTime: dateTime,
            items: items,
            amounts: amounts,
            printMeta: printMeta,
          );
        }

        job._recordSuccess(invoiceNo);
      } catch (e) {
        debugPrint('[BATCH-PRINT] Error on $invoiceNo: $e');
        job._recordError(saleId, invoiceNo, e.toString());
      }
    }

    if (effectivePdfFolder != null && onPdfFolderReady != null) {
      onPdfFolderReady(effectivePdfFolder);
    }

    if (job.status != BatchPrintJobStatus.cancelled) {
      job._markDone();
    }
  }

  // ---------------------------------------------------------------------------
  // Print a single invoice. Returns true if sent to hardware, false if PDF fallback needed.
  // ---------------------------------------------------------------------------

  Future<bool> _printOne({
    required BatchPrintJob job,
    required BatchPrintConfig config,
    required Printer? resolvedPrinter,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required _Amounts amounts,
    required Map<String, dynamic> printMeta,
  }) async {
    final sections = config.mainTemplate.sections;
    final secondarySections = config.secondaryTemplate.sections;
    final showLogo =
        config.printLogo && config.mainTemplate.isCustomerFacing;
    final showQr = config.printQr && config.mainTemplate.isCustomerFacing;

    // --- Network ESC/POS ---
    if (config.isNetworkPrinter &&
        config.mainTemplate.supportsRawNetwork &&
        (config.networkIp ?? '').trim().isNotEmpty) {
      await ThermalPrinterService.instance.printSaleReceiptNetwork(
        printerIp: config.networkIp!.trim(),
        port: config.networkPort,
        shopName: config.shopName,
        shopAddress: config.shopAddress,
        shopPhone: config.shopPhone,
        receiptNo: receiptNo,
        dateTime: dateTime,
        items: items,
        subtotal: amounts.subtotal,
        discount: amounts.discount,
        tax: amounts.tax,
        grandTotal: amounts.total,
        cashReceived: amounts.cashReceived,
        changeAmount: amounts.changeAmount,
        meta: printMeta,
        sections: sections,
        paperWidth: config.mainPaperCode,
        invoiceHeading: config.invoiceHeading,
        footerLines: config.footerLines,
        footerLineStyles: config.footerLineStyles,
        showLogo: showLogo,
        logoData: config.logoData,
        showQr: showQr,
        qrUrl: config.qrUrl,
        qrCaption: config.qrCaption,
        template: config.mainTemplate,
        devCreditEnabled: config.devCreditEnabled,
        devCreditText: config.devCreditText,
      );

      if (config.printSecondary &&
          (config.secondaryNetworkIp ?? '').trim().isNotEmpty) {
        await ThermalPrinterService.instance.printSaleReceiptNetwork(
          printerIp: config.secondaryNetworkIp!.trim(),
          port: config.secondaryNetworkPort,
          shopName: config.shopName,
          shopAddress: config.shopAddress,
          shopPhone: config.shopPhone,
          receiptNo: receiptNo,
          dateTime: dateTime,
          items: items,
          subtotal: amounts.subtotal,
          discount: amounts.discount,
          tax: amounts.tax,
          grandTotal: amounts.total,
          cashReceived: amounts.cashReceived,
          changeAmount: amounts.changeAmount,
          meta: printMeta,
          sections: secondarySections,
          paperWidth: config.secondaryTemplate.paperWidthCode,
          invoiceHeading: config.invoiceHeading,
          footerLines: config.footerLines,
          footerLineStyles: config.footerLineStyles,
          receiptHeader: config.secondaryHeader,
          template: config.secondaryTemplate,
          devCreditEnabled: config.devCreditEnabled,
          devCreditText: config.devCreditText,
        );
      }
      return true;
    }

    // --- Local Windows/OS printer (pre-resolved Printer object) ---
    if (config.isLocalPrinter && resolvedPrinter != null) {
      final pdfBytes = await _buildPdf(
        config: config,
        receiptNo: receiptNo,
        dateTime: dateTime,
        items: items,
        amounts: amounts,
        printMeta: printMeta,
        sections: sections,
      );

      final format = ReceiptPreviewService.instance
          .pageFormatForPaperWidth(config.mainPaperCode);
      final printed = await Printing.directPrintPdf(
        printer: resolvedPrinter,
        name: 'Batch Receipt $receiptNo',
        format: format,
        dynamicLayout: false,
        usePrinterSettings:
            config.mainPaperCode == 'mm58' || config.mainPaperCode == 'mm80',
        onLayout: (_) async => pdfBytes,
      );
      if (!printed) {
        throw Exception(
            'Windows did not accept the print job for "${resolvedPrinter.name}".');
      }

      if (config.printSecondary &&
          (config.secondaryLocalPrinterName ?? '').trim().isNotEmpty) {
        Printer? secondaryPrinter;
        try {
          secondaryPrinter = await _resolvePrinter(
              config.secondaryLocalPrinterName!.trim());
        } catch (_) {}

        if (secondaryPrinter != null) {
          final secondaryPdf = await _buildPdf(
            config: config,
            receiptNo: receiptNo,
            dateTime: dateTime,
            items: items,
            amounts: amounts,
            printMeta: printMeta,
            sections: secondarySections,
            receiptHeader: config.secondaryHeader,
            template: config.secondaryTemplate,
          );
          final secFormat = ReceiptPreviewService.instance
              .pageFormatForPaperWidth(
                  config.secondaryTemplate.paperWidthCode);
          await Printing.directPrintPdf(
            printer: secondaryPrinter,
            name: 'Batch Secondary $receiptNo',
            format: secFormat,
            dynamicLayout: false,
            usePrinterSettings: true,
            onLayout: (_) async => secondaryPdf,
          );
        }
      }
      return true;
    }

    // No hardware printer configured – caller will save PDF.
    return false;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _fetchSale(int saleId, String token) async {
    final uri = Uri.parse(
        '${ApiClient.baseUrl}/sales/$saleId?include_balance=1');
    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} fetching sale #$saleId');
    }
    final decoded = jsonDecode(res.body);
    final data = decoded['data'];
    if (data is! Map) throw Exception('Unexpected sale payload for #$saleId');
    return Map<String, dynamic>.from(data);
  }

  List<SaleReceiptItem> _buildReceiptItems(Map<String, dynamic> sale) {
    double d(dynamic v) =>
        double.tryParse(v?.toString() ?? '') ?? 0.0;

    final itemsRaw = (sale['items'] as List?) ?? const [];
    return itemsRaw.map((i) {
      final m = i as Map;
      final name =
          (m['product']?['name'] ?? m['name'] ?? '-').toString();
      final packaged = m['packaging_id'] != null;
      final basePrice = d(m['price']);
      final baseQty = d(m['quantity']);
      final price = packaged ? d(m['packaging_unit_price']) : basePrice;
      final qty = packaged ? d(m['packaging_quantity']) : baseQty;
      final lineTotal = d(m['total']) != 0 ? d(m['total']) : (price * qty);
      final gross = (price * qty).abs();
      final net = lineTotal.abs();
      final extraDiscount = d(m['extra_discount']).abs();
      final lineDiscount =
          (gross - net - extraDiscount).clamp(0.0, double.infinity).toDouble();
      final product = m['product'];
      final unitRaw =
          m['unit_name'] ?? m['unit_symbol'] ?? (product is Map ? product['unit'] : null);
      final baseUnitName = unitRaw is Map
          ? (unitRaw['symbol'] ?? unitRaw['name'] ?? '').toString()
          : (unitRaw ?? '').toString();
      final packageLabel =
          (m['packaging_short_name_snapshot'] ?? m['packaging_name_snapshot'] ?? '')
              .toString()
              .trim();
      final unitName =
          packaged && packageLabel.isNotEmpty ? packageLabel : baseUnitName;
      final secondaryName = (product is Map
              ? (product['secondary_name'] ?? '')
              : (m['secondary_name'] ?? ''))
          .toString()
          .trim();
      final discountType = (m['discount_type'] ?? 'percentage').toString();
      return SaleReceiptItem(
        name: name,
        secondaryName: secondaryName.isEmpty ? null : secondaryName,
        price: price,
        qty: qty,
        total: lineTotal,
        unitName: unitName,
        packagingName:
            packaged ? (m['packaging_name_snapshot'] ?? '').toString().trim() : null,
        packagingShortName: packaged
            ? (m['packaging_short_name_snapshot'] ?? '').toString().trim()
            : null,
        packagingFactor: packaged ? d(m['packaging_factor_snapshot']) : null,
        baseUnitName: baseUnitName,
        discountAmount: lineDiscount,
        discountType: discountType,
        discountValue: discountType == 'fixed' && packaged
            ? d(m['packaging_discount_snapshot'])
            : d(m['discount']),
        extraDiscountAmount: extraDiscount,
      );
    }).toList();
  }

  _Amounts _extractAmounts(Map<String, dynamic> sale) {
    double d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

    final paymentsRaw = (sale['payments'] as List?) ?? const [];
    final activePayments = paymentsRaw.where((p) {
      if (p is! Map) return false;
      final reversedAt = p['reversed_at'];
      return reversedAt == null || reversedAt.toString().trim().isEmpty;
    }).toList(growable: false);

    final subtotal = d(sale['subtotal']);
    final discount = d(sale['discount']);
    final tax = d(sale['tax']);
    final total = d(sale['total']);
    final paid = sale['net_paid'] != null
        ? d(sale['net_paid'])
        : activePayments.fold<double>(
            0, (sum, p) => sum + d((p as Map)['amount']));
    final revisionNo =
        int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0;
    final meta = _mapFrom(sale['meta']);

    double cashReceived;
    double changeAmount;
    if (revisionNo > 0) {
      cashReceived = paid;
      changeAmount = 0.0;
    } else {
      cashReceived = meta['cash_received'] is num
          ? (meta['cash_received'] as num).toDouble()
          : d(meta['cash_received']) != 0
              ? d(meta['cash_received'])
              : paid;
      changeAmount = (cashReceived - total).clamp(0, double.infinity).toDouble();
    }

    return _Amounts(
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      cashReceived: cashReceived,
      changeAmount: changeAmount,
    );
  }

  Map<String, dynamic> _buildPrintMeta(
    Map<String, dynamic> sale,
    BatchPrintConfig config,
    _Amounts amounts,
  ) {
    final meta = _mapFrom(sale['meta']);
    final paymentsRaw = (sale['payments'] as List?) ?? const [];
    final activePayments = paymentsRaw.where((p) {
      if (p is! Map) return false;
      final reversedAt = p['reversed_at'];
      return reversedAt == null || reversedAt.toString().trim().isEmpty;
    }).toList(growable: false);

    final revisionNo =
        int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0;

    // Build customer snapshot
    Map<String, dynamic> customerSnap = {};
    final snapRaw = _mapFrom(meta['customer_snapshot']);
    if (snapRaw.isNotEmpty) {
      customerSnap = Map<String, dynamic>.from(snapRaw);
      final c = sale['customer'];
      if (c is Map) {
        final code = (c['customer_code'] ?? '').toString().trim();
        if ((customerSnap['customer_code'] ?? '').toString().trim().isEmpty &&
            code.isNotEmpty) {
          customerSnap['customer_code'] = code;
        }
      }
    } else {
      final c = sale['customer'];
      if (c is Map) {
        final first =
            (c['first_name'] ?? c['name'] ?? 'Walk-in').toString().trim();
        final last = (c['last_name'] ?? '').toString().trim();
        final fullName = last.isEmpty ? first : '$first $last';
        customerSnap = {
          'name': fullName.isEmpty ? 'Walk-in' : fullName,
          'phone': (c['phone'] ?? c['mobile'] ?? c['mobile_no'] ?? '').toString(),
          'address': (c['address'] ?? c['full_address'] ?? '').toString(),
          if ((c['customer_code'] ?? '').toString().trim().isNotEmpty)
            'customer_code': c['customer_code'],
          if (c['customer_type'] != null) 'customer_type': c['customer_type'],
        };
      } else {
        customerSnap = {'name': 'Walk-in', 'phone': '', 'address': ''};
      }
    }

    final delivery = double.tryParse(sale['delivery']?.toString() ?? '') ?? 0.0;
    final metaDelivery = meta['delivery'] is num
        ? (meta['delivery'] as num).toDouble()
        : double.tryParse(meta['delivery']?.toString() ?? '') ?? 0.0;
    final effectiveDelivery =
        revisionNo > 0 ? delivery : (metaDelivery != 0 ? metaDelivery : delivery);

    return <String, dynamic>{
      ...meta,
      'customer_snapshot': customerSnap,
      'cash_received': amounts.cashReceived,
      'change_amount': amounts.changeAmount,
      'delivery': effectiveDelivery,
      'payments': activePayments,
      'payments_snapshot': activePayments,
      'sale_source_snapshot':
          _mapFrom(meta['sale_source_snapshot']).isNotEmpty
              ? _mapFrom(meta['sale_source_snapshot'])
              : <String, dynamic>{
                  if (sale['sale_source_id'] != null) 'id': sale['sale_source_id'],
                  'name': (sale['sale_source_name'] ?? 'Counter').toString(),
                },
      'revision_no': revisionNo,
      if (sale['amended_at'] != null) 'amended_at': sale['amended_at'],
      'item_discount_display': config.itemDiscountDisplay.value,
    };
  }

  Future<Uint8List> _buildPdf({
    required BatchPrintConfig config,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required _Amounts amounts,
    required Map<String, dynamic> printMeta,
    required InvoiceSections sections,
    String? receiptHeader,
    InvoiceTemplate? template,
  }) {
    final tpl = template ?? config.mainTemplate;
    return ReceiptPreviewService.instance.buildReceiptPdf(
      shopName: config.shopName,
      shopAddress: config.shopAddress,
      shopPhone: config.shopPhone,
      receiptNo: receiptNo,
      dateTime: dateTime,
      items: items,
      subtotal: amounts.subtotal,
      discount: amounts.discount,
      tax: amounts.tax,
      grandTotal: amounts.total,
      meta: printMeta,
      sections: sections,
      paperWidth: config.mainPaperCode,
      footerLines: config.footerLines,
      footerLineStyles: config.footerLineStyles,
      receiptHeader: receiptHeader,
      invoiceHeading: config.invoiceHeading,
      showLogo: config.printLogo && tpl.isCustomerFacing,
      logoData: config.logoData,
      showQr: config.printQr && tpl.isCustomerFacing,
      qrUrl: config.qrUrl,
      qrCaption: config.qrCaption,
      template: tpl,
      devCreditEnabled: config.devCreditEnabled,
      devCreditText: config.devCreditText,
    );
  }

  Future<String> _ensurePdfFolder() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(docs.path, 'BatchPrintExport'));
      await folder.create(recursive: true);
      return folder.path;
    } catch (_) {
      final tmp = await getTemporaryDirectory();
      final folder = Directory(p.join(tmp.path, 'BatchPrintExport'));
      await folder.create(recursive: true);
      return folder.path;
    }
  }

  Future<void> _savePdfToFolder({
    required String folder,
    required BatchPrintConfig config,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required _Amounts amounts,
    required Map<String, dynamic> printMeta,
  }) async {
    final bytes = await _buildPdf(
      config: config,
      receiptNo: receiptNo,
      dateTime: dateTime,
      items: items,
      amounts: amounts,
      printMeta: printMeta,
      sections: config.mainTemplate.sections,
    );
    final safeName = receiptNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final file = File(p.join(folder, '$safeName.pdf'));
    await file.writeAsBytes(bytes, flush: true);
  }

  static Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return <String, dynamic>{};
  }
}

// ---------------------------------------------------------------------------
// Internal helper
// ---------------------------------------------------------------------------

class _Amounts {
  const _Amounts({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.cashReceived,
    required this.changeAmount,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final double cashReceived;
  final double changeAmount;
}
