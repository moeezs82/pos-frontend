import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/models/whatsapp_invoice_format.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/whatsapp_invoice_service.dart';
import 'package:enterprise_pos/services/whatsapp_message_template_service.dart';
import 'package:provider/provider.dart';

class SaleReceiptDispatcher {
  static double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static String _asText(dynamic v) => (v ?? '').toString().trim();

  /// Converts raw cart items into structured [SaleReceiptItem] objects for printing and PDF generation.
  static List<SaleReceiptItem> mapCartToReceiptItems(
    List<Map<String, dynamic>> items, {
    double Function(Map<String, dynamic>)? lineTotalFallback,
  }) {
    return items.map((i) {
      final name = (i['name'] ?? i['product_name'] ?? 'Product').toString();
      final packaged = i['packaging_id'] != null;
      final basePrice = double.tryParse(i['price']?.toString() ?? '') ?? 0.0;
      final baseQty = double.tryParse(i['quantity']?.toString() ?? '') ?? 0.0;
      final price = packaged ? _asNum(i['packaging_unit_price']) : basePrice;
      final qty = packaged ? _asNum(i['packaging_quantity']) : baseQty;
      final lineTotal = double.tryParse(i['total']?.toString() ?? '') ??
          (lineTotalFallback != null ? lineTotalFallback(i) : (price * qty));
      final gross = (price * qty).abs();
      final net = lineTotal.abs();
      final extraDiscount = _asNum(i['extra_discount']).abs();
      final lineDiscount =
          (gross - net - extraDiscount).clamp(0.0, double.infinity).toDouble();
      final unitRaw = i['unit_name'] ?? i['unit_symbol'] ?? i['unit'];
      final baseUnitName = unitRaw is Map
          ? (unitRaw['symbol'] ?? unitRaw['name'] ?? '').toString()
          : (unitRaw ?? '').toString();
      final packageLabel = (i['packaging_short_name_snapshot'] ??
              i['packaging_name_snapshot'] ??
              '')
          .toString()
          .trim();
      final discountType = (i['discount_type'] ?? 'percentage').toString();
      return SaleReceiptItem(
        name: name,
        secondaryName: (i['secondary_name'] ?? '').toString().trim().isEmpty
            ? null
            : (i['secondary_name'] ?? '').toString().trim(),
        price: price,
        qty: qty,
        total: lineTotal,
        unitName: packaged && packageLabel.isNotEmpty ? packageLabel : baseUnitName,
        packagingName: packaged
            ? (i['packaging_name_snapshot'] ?? '').toString().trim()
            : null,
        packagingShortName: packaged
            ? (i['packaging_short_name_snapshot'] ?? '').toString().trim()
            : null,
        packagingFactor:
            packaged ? _asNum(i['packaging_factor_snapshot']) : null,
        baseUnitName: baseUnitName,
        discountAmount: lineDiscount,
        discountType: discountType,
        discountValue: discountType == 'fixed' && packaged
            ? _asNum(i['packaging_discount_snapshot'])
            : _asNum(i['discount_pct']),
        extraDiscountAmount: extraDiscount,
      );
    }).toList();
  }

  /// Dispatches physical hardware printing and asynchronous WhatsApp PDF/invoice preparation.
  static Future<void> dispatch({
    required BuildContext context,
    required bool print,
    required bool prepareWhatsAppInvoice,
    required String receiptNo,
    required DateTime occurredAt,
    required List<SaleReceiptItem> receiptItems,
    required double receiptSubtotal,
    required double discount,
    required double tax,
    required double total,
    required double cashReceived,
    required double changeAmount,
    required double paid,
    required double balance,
    required Map<String, dynamic> meta,
    required String whatsappPhone,
    required dynamic rawCustomerBalance,
    required void Function({
      required String receiptNo,
      required WhatsAppInvoicePreparation prepared,
      required String message,
    }) onWhatsAppTaskPrepared,
  }) async {
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

    final effectiveShopName = printerConfig.shopName.isNotEmpty
        ? printerConfig.shopName
        : 'My Shop';
    final effectiveShopAddress =
        printerConfig.shopAddress.isNotEmpty ? printerConfig.shopAddress : null;
    final effectiveShopPhone =
        printerConfig.shopPhone.isNotEmpty ? printerConfig.shopPhone : null;
    final mainTemplate = printerConfig.mainInvoiceTemplate;
    final whatsappTemplate = printerConfig.whatsappInvoiceTemplate;
    final whatsappPaperCode = printerConfig.whatsappPaperCode;
    final secondaryTemplate = printerConfig.secondaryInvoiceTemplate;
    final secondaryHeader = printerConfig.secondaryReceiptHeader.trim().isEmpty
        ? 'KITCHEN COPY'
        : printerConfig.secondaryReceiptHeader.trim();
    final footerLines = printerConfig.footerLines;
    final footerLineStyles = printerConfig.footerLineStyles;
    final printMeta = <String, dynamic>{
      ...meta,
      'item_discount_display': printerConfig.itemDiscountDisplay.value,
    };
    final receiptPrintTime = DateTime.now();

    Future<Uint8List> buildWhatsappPdf() {
      return ReceiptPreviewService.instance.buildReceiptPdf(
        shopName: effectiveShopName,
        shopAddress: effectiveShopAddress,
        shopPhone: effectiveShopPhone,
        receiptNo: receiptNo,
        dateTime: receiptPrintTime,
        items: receiptItems,
        subtotal: receiptSubtotal,
        discount: discount,
        tax: tax,
        grandTotal: total,
        meta: printMeta,
        sections: whatsappTemplate.sections,
        paperWidth: whatsappPaperCode,
        footerLines: footerLines,
        footerLineStyles: footerLineStyles,
        invoiceHeading: printerConfig.invoiceHeading,
        showLogo: printerConfig.printLogoEnabled &&
            whatsappTemplate.isCustomerFacing,
        logoData: printerConfig.printLogoData,
        showQr: printerConfig.qrCodeEnabled &&
            whatsappTemplate.isCustomerFacing,
        qrUrl: printerConfig.qrCodeUrl,
        qrCaption: printerConfig.qrCodeCaption,
        template: whatsappTemplate,
        devCreditEnabled: printerConfig.devCreditEnabled,
        devCreditText: printerConfig.devCreditText,
      );
    }

    final mainRawNetworkWillPrint = printerConfig.isNetworkPrinter &&
        mainTemplate.supportsRawNetwork &&
        (printerConfig.networkIp ?? '').trim().isNotEmpty;
    final whatsappUsesDifferentPdf = whatsappTemplate != mainTemplate ||
        whatsappPaperCode != printerConfig.mainPaperCode;

    Future<Uint8List?>? whatsappPdfFuture;
    Object? whatsappPdfError;
    StackTrace? whatsappPdfStackTrace;
    if (prepareWhatsAppInvoice &&
        (!print || whatsappUsesDifferentPdf || mainRawNetworkWillPrint)) {
      final timing = Stopwatch()..start();
      whatsappPdfFuture = buildWhatsappPdf().then<Uint8List?>((bytes) {
        debugPrint(
          '[WHATSAPP-TIMING] PDF ready in ${timing.elapsedMilliseconds}ms bytes=${bytes.length}',
        );
        return bytes;
      }).catchError((Object error, StackTrace stackTrace) {
        whatsappPdfError = error;
        whatsappPdfStackTrace = stackTrace;
        return null;
      });
    }

    Uint8List? customerInvoicePdfBytes;

    if (print) {
      debugPrint(
          'Active printer connection: ${printerConfig.activeConnection}, template: ${mainTemplate.value}');

      var printedToHardware = false;
      if (printerConfig.isNetworkPrinter &&
          mainTemplate.supportsRawNetwork &&
          (printerConfig.networkIp ?? '').trim().isNotEmpty) {
        try {
          await ThermalPrinterService.instance.printSaleReceiptNetwork(
            printerIp: printerConfig.networkIp!.trim(),
            port: printerConfig.networkPort,
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: receiptPrintTime,
            items: receiptItems,
            subtotal: receiptSubtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: printMeta,
            sections: mainTemplate.sections,
            paperWidth: printerConfig.mainPaperCode,
            invoiceHeading: printerConfig.invoiceHeading,
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

          if (printerConfig.secondaryPrintEnabled &&
              (printerConfig.secondaryNetworkIp ?? '').trim().isNotEmpty) {
            await ThermalPrinterService.instance.printSaleReceiptNetwork(
              printerIp: printerConfig.secondaryNetworkIp!.trim(),
              port: printerConfig.secondaryNetworkPort,
              shopName: effectiveShopName,
              shopAddress: effectiveShopAddress,
              shopPhone: effectiveShopPhone,
              receiptNo: receiptNo,
              dateTime: receiptPrintTime,
              items: receiptItems,
              subtotal: receiptSubtotal,
              discount: discount,
              tax: tax,
              grandTotal: total,
              cashReceived: cashReceived,
              changeAmount: changeAmount,
              meta: printMeta,
              sections: secondaryTemplate.sections,
              paperWidth: secondaryTemplate.paperWidthCode,
              invoiceHeading: printerConfig.invoiceHeading,
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
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      } else if (printerConfig.isLocalPrinter &&
          (printerConfig.localPrinterName ?? '').trim().isNotEmpty) {
        try {
          customerInvoicePdfBytes =
              await LocalPrinterService.instance.printSaleReceipt(
            printerName: printerConfig.localPrinterName!.trim(),
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: receiptPrintTime,
            items: receiptItems,
            subtotal: receiptSubtotal,
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
              dateTime: receiptPrintTime,
              items: receiptItems,
              subtotal: receiptSubtotal,
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
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      }

      if (!printedToHardware) {
        customerInvoicePdfBytes =
            await ReceiptPreviewService.instance.previewReceipt(
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: receiptPrintTime,
          items: receiptItems,
          subtotal: receiptSubtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          meta: printMeta,
          sections: mainTemplate.sections,
          paperWidth: printerConfig.mainPaperCode,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          invoiceHeading: printerConfig.invoiceHeading,
          showLogo:
              printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
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

    if (prepareWhatsAppInvoice) {
      final whatsappFormat = printerConfig.whatsappInvoiceFormat;
      final customerSnapshotRaw = meta['customer_snapshot'];
      final customerSnapshot = customerSnapshotRaw is Map
          ? Map<String, dynamic>.from(customerSnapshotRaw)
          : const <String, dynamic>{};
      final whatsappMessage = WhatsAppMessageTemplateService.render(
        template: printerConfig.whatsappMessageTemplate,
        showCustomerBalance: printerConfig.whatsappShowCustomerBalance,
        values: {
          'customer_name': _asText(customerSnapshot['name']),
          'customer_code': _asText(customerSnapshot['customer_code']),
          'invoice_no': receiptNo,
          'invoice_amount': total.toStringAsFixed(2),
          'amount_paid': paid.toStringAsFixed(2),
          'invoice_balance': balance.toStringAsFixed(2),
          'customer_balance': rawCustomerBalance == null
              ? ''
              : _asNum(rawCustomerBalance).toStringAsFixed(2),
          'business_name': effectiveShopName,
          'date': '${occurredAt.day.toString().padLeft(2, '0')}/'
              '${occurredAt.month.toString().padLeft(2, '0')}/'
              '${occurredAt.year}',
          'currency': AppCurrency.currency,
          'attachment_format': whatsappFormat.label,
        },
      );

      final reusablePrimaryPdf = whatsappTemplate == mainTemplate &&
              whatsappPaperCode == printerConfig.mainPaperCode
          ? customerInvoicePdfBytes
          : null;

      unawaited(() async {
        try {
          final pdfTiming = Stopwatch()..start();
          Uint8List? pdfBytes = reusablePrimaryPdf;
          if (pdfBytes == null && whatsappPdfFuture != null) {
            pdfBytes = await whatsappPdfFuture;
            if (pdfBytes == null && whatsappPdfError != null) {
              Error.throwWithStackTrace(
                whatsappPdfError!,
                whatsappPdfStackTrace ?? StackTrace.current,
              );
            }
          }
          pdfBytes ??= await buildWhatsappPdf();
          debugPrint(
            '[WHATSAPP-TIMING] background PDF wait ${pdfTiming.elapsedMilliseconds}ms reused=${reusablePrimaryPdf != null}',
          );

          final prepareTiming = Stopwatch()..start();
          final prepared =
              await WhatsAppInvoiceService.instance.prepareAttachment(
            pdfBytes: pdfBytes,
            receiptNo: receiptNo,
            phone: whatsappPhone,
            format: whatsappFormat,
          );
          debugPrint(
            '[WHATSAPP-TIMING] background attachment ready in ${prepareTiming.elapsedMilliseconds}ms format=${whatsappFormat.value}',
          );
          if (!context.mounted) return;
          onWhatsAppTaskPrepared(
            receiptNo: receiptNo,
            prepared: prepared,
            message: whatsappMessage,
          );
        } catch (e, st) {
          debugPrint('WHATSAPP INVOICE ERROR: $e');
          debugPrintStack(stackTrace: st);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sale $receiptNo saved, but WhatsApp invoice preparation failed.',
              ),
              action: SnackBarAction(
                label: 'Dismiss',
                onPressed: () {},
              ),
            ),
          );
        }
      }());
    }
  }
}
