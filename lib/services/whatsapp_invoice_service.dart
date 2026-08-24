import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../models/whatsapp_invoice_format.dart';
import 'windows_file_clipboard.dart';

class WhatsAppInvoicePreparation {
  final List<String> attachmentPaths;
  final String normalizedPhone;
  final bool copiedToClipboard;
  final WhatsAppInvoiceFormat format;

  const WhatsAppInvoicePreparation({
    required this.attachmentPaths,
    required this.normalizedPhone,
    required this.copiedToClipboard,
    required this.format,
  });

  String get primaryPath => attachmentPaths.first;

  String get formatLabel => format.label;

  String get attachmentDescription {
    if (format == WhatsAppInvoiceFormat.pdf) return 'PDF';
    if (attachmentPaths.length == 1) return 'JPG';
    return '${attachmentPaths.length} JPG files';
  }
}

/// Implements the free, user-confirmed WhatsApp invoice workflow.
///
/// WhatsApp's public URL can select a chat and prefill text, but it cannot
/// attach a local file. On Windows we therefore place the generated invoice
/// attachment(s) on the file clipboard; the cashier only needs to press
/// Ctrl+V and Send.
class WhatsAppInvoiceService {
  WhatsAppInvoiceService._();

  static final instance = WhatsAppInvoiceService._();

  String normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      // CounterIQ's local-number fallback is Pakistan. This transformation is
      // used only for the wa.me destination; the stored/printed customer phone
      // remains exactly as entered.
      digits = '92${digits.substring(1)}';
    }

    if (digits.length < 10 || digits.length > 15) {
      throw const FormatException(
        'Enter a valid WhatsApp number. Use a country code, or a local number starting with 0 (Pakistan +92 is used automatically).',
      );
    }
    return digits;
  }

  /// Generates and saves the configured attachment without touching the
  /// clipboard or opening another application. This is the fast POS path: the
  /// cashier can continue the next sale while the file is prepared, and the
  /// clipboard/WhatsApp hand-off only happens after an explicit Open action.
  Future<WhatsAppInvoicePreparation> prepareAttachment({
    required Uint8List pdfBytes,
    required String receiptNo,
    required String phone,
    WhatsAppInvoiceFormat format = WhatsAppInvoiceFormat.pdf,
  }) async {
    final totalTiming = Stopwatch()..start();
    final normalizedPhone = normalizePhone(phone);
    final saveTiming = Stopwatch()..start();
    final attachmentPaths = format == WhatsAppInvoiceFormat.jpg
        ? await saveJpgPages(pdfBytes: pdfBytes, receiptNo: receiptNo)
        : <String>[
            await savePdf(pdfBytes: pdfBytes, receiptNo: receiptNo),
          ];
    print(
      '[WHATSAPP-TIMING] ${format.label} file generation ${saveTiming.elapsedMilliseconds}ms total=${totalTiming.elapsedMilliseconds}ms',
    );
    return WhatsAppInvoicePreparation(
      attachmentPaths: attachmentPaths,
      normalizedPhone: normalizedPhone,
      copiedToClipboard: false,
      format: format,
    );
  }

  /// Prepare the configured WhatsApp attachment and copy it to the Windows
  /// file clipboard. The invoice has one source renderer: callers always pass
  /// the existing PDF bytes; JPG mode rasterises those exact PDF page(s).
  ///
  /// Does NOT open WhatsApp automatically — the cashier must press the
  /// "Open WhatsApp" button in the dialog. This prevents an unsolicited
  /// window appearing during sale finalization.
  Future<WhatsAppInvoicePreparation> prepareAndOpen({
    required Uint8List pdfBytes,
    required String receiptNo,
    required String phone,
    required String message,
    WhatsAppInvoiceFormat format = WhatsAppInvoiceFormat.pdf,
  }) async {
    final totalTiming = Stopwatch()..start();
    final prepared = await prepareAttachment(
      pdfBytes: pdfBytes,
      receiptNo: receiptNo,
      phone: phone,
      format: format,
    );
    final clipboardTiming = Stopwatch()..start();
    final copied = await copyFilesToClipboard(prepared.attachmentPaths);
    print(
      '[WHATSAPP-TIMING] clipboard ${clipboardTiming.elapsedMilliseconds}ms total=${totalTiming.elapsedMilliseconds}ms',
    );
    return WhatsAppInvoicePreparation(
      attachmentPaths: prepared.attachmentPaths,
      normalizedPhone: prepared.normalizedPhone,
      copiedToClipboard: copied,
      format: prepared.format,
    );
  }

  Future<Directory> _invoiceDirectory() async {
    // Documents is frequently redirected through OneDrive on customer PCs.
    // WhatsApp attachments are generated working files, so AppData is both
    // faster and less likely to trigger cloud-sync latency.
    final appSupport = await getApplicationSupportDirectory();
    final now = DateTime.now();
    final dateFolder =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final directory = Directory(
      p.join(appSupport.path, 'CounterIQ', 'WhatsApp Invoices', dateFolder),
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _safeReceiptNo(String receiptNo) {
    final safe = receiptNo
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return safe.isEmpty ? 'invoice' : safe;
  }

  Future<String> savePdf({
    required Uint8List pdfBytes,
    required String receiptNo,
  }) async {
    final directory = await _invoiceDirectory();
    final target = File(
      p.join(directory.path, '${_safeReceiptNo(receiptNo)}.pdf'),
    );
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(pdfBytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  /// Rasterises the existing invoice PDF so JPG output always matches the
  /// PDF/print layout exactly. Multi-page invoices become one JPG per page.
  Future<List<String>> saveJpgPages({
    required Uint8List pdfBytes,
    required String receiptNo,
  }) async {
    final encodedPages = <List<int>>[];
    await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
      final pngBytes = await page.toPng();
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) {
        throw Exception('Could not rasterise the invoice for JPG sharing.');
      }
      encodedPages.add(img.encodeJpg(decoded, quality: 90));
    }

    if (encodedPages.isEmpty) {
      throw Exception('The invoice did not contain a page to convert to JPG.');
    }

    final directory = await _invoiceDirectory();
    final baseName = _safeReceiptNo(receiptNo);
    final paths = <String>[];
    for (var i = 0; i < encodedPages.length; i++) {
      final suffix = encodedPages.length == 1 ? '' : '-${i + 1}';
      final target = File(p.join(directory.path, '$baseName$suffix.jpg'));
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(encodedPages[i], flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      paths.add(target.path);
    }
    return paths;
  }

  Future<bool> copyPdfToClipboard(String pdfPath) =>
      copyFilesToClipboard(<String>[pdfPath]);

  Future<bool> copyFilesToClipboard(List<String> filePaths) async {
    if (!Platform.isWindows || filePaths.isEmpty) return false;

    final existing = <String>[];
    for (final path in filePaths) {
      if (await File(path).exists()) existing.add(path);
    }
    if (existing.length != filePaths.length) return false;

    return WindowsFileClipboard.copyFiles(existing);
  }

  Future<void> openChat({
    required String phone,
    required String message,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    final uri = Uri.https('wa.me', '/$normalizedPhone', {'text': message});

    if (Platform.isWindows) {
      // explorer.exe treats some HTTPS URLs as filesystem locations. Use the
      // Windows URL protocol handler so the default browser/WhatsApp handoff
      // receives the URL instead.
      await Process.start(
        'rundll32.exe',
        ['url.dll,FileProtocolHandler', uri.toString()],
        runInShell: false,
        mode: ProcessStartMode.detached,
      );
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [uri.toString()], runInShell: false);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [uri.toString()], runInShell: false);
      return;
    }
    throw UnsupportedError(
      'WhatsApp invoice sharing is not supported on this platform.',
    );
  }

  Future<void> openInvoiceFolder(String attachmentPath) async {
    final directory = File(attachmentPath).parent.path;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [directory], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.start('open', [directory], runInShell: false);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [directory], runInShell: false);
    }
  }
}
