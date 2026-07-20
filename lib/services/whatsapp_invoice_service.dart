import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WhatsAppInvoicePreparation {
  final String pdfPath;
  final String normalizedPhone;
  final bool copiedToClipboard;

  const WhatsAppInvoicePreparation({
    required this.pdfPath,
    required this.normalizedPhone,
    required this.copiedToClipboard,
  });
}

/// Implements the free, user-confirmed WhatsApp invoice workflow.
///
/// WhatsApp's public URL can select a chat and prefill text, but it cannot
/// attach a local file. On Windows we therefore place the generated PDF on
/// the file clipboard; the cashier only needs to press Ctrl+V and Send.
class WhatsAppInvoiceService {
  WhatsAppInvoiceService._();

  static final instance = WhatsAppInvoiceService._();

  String normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);

    if (digits.length < 10 || digits.length > 15) {
      throw const FormatException(
        'Enter the WhatsApp number with country code, for example +965XXXXXXXX.',
      );
    }
    return digits;
  }

  Future<WhatsAppInvoicePreparation> prepareAndOpen({
    required Uint8List pdfBytes,
    required String receiptNo,
    required String phone,
    required String message,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    final pdfPath = await savePdf(pdfBytes: pdfBytes, receiptNo: receiptNo);
    final copied = await copyPdfToClipboard(pdfPath);
    await openChat(phone: normalizedPhone, message: message);

    return WhatsAppInvoicePreparation(
      pdfPath: pdfPath,
      normalizedPhone: normalizedPhone,
      copiedToClipboard: copied,
    );
  }

  Future<String> savePdf({
    required Uint8List pdfBytes,
    required String receiptNo,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final dateFolder =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final directory = Directory(
      p.join(documents.path, 'Enterprise POS', 'Invoices', dateFolder),
    );
    await directory.create(recursive: true);

    final safeReceiptNo = receiptNo
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    final target = File(
      p.join(directory.path, '${safeReceiptNo.isEmpty ? 'invoice' : safeReceiptNo}.pdf'),
    );
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(pdfBytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  Future<bool> copyPdfToClipboard(String pdfPath) async {
    if (!Platform.isWindows) return false;
    if (!await File(pdfPath).exists()) return false;

    final escapedPath = pdfPath.replaceAll("'", "''");
    final script = <String>[
      'Add-Type -AssemblyName System.Windows.Forms',
      r'$files = New-Object System.Collections.Specialized.StringCollection',
      "[void]\$files.Add('$escapedPath')",
      r'$data = New-Object System.Windows.Forms.DataObject',
      r'$data.SetFileDropList($files)',
      // The second argument persists clipboard data after PowerShell exits.
      r'[System.Windows.Forms.Clipboard]::SetDataObject($data, $true)',
    ].join('; ');

    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
      runInShell: false,
    );
    return result.exitCode == 0;
  }

  Future<void> openChat({required String phone, required String message}) async {
    final normalizedPhone = normalizePhone(phone);
    final uri = Uri.https(
      'wa.me',
      '/$normalizedPhone',
      {'text': message},
    );

    if (Platform.isWindows) {
      // explorer.exe treats some HTTPS URLs as filesystem locations. Use the
      // Windows URL protocol handler so the default browser/WhatsApp handoff
      // receives the URL instead.
      final result = await Process.run(
        'rundll32.exe',
        ['url.dll,FileProtocolHandler', uri.toString()],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        throw ProcessException(
          'rundll32.exe',
          ['url.dll,FileProtocolHandler', uri.toString()],
          'Windows could not open WhatsApp.',
          result.exitCode,
        );
      }
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
    throw UnsupportedError('WhatsApp invoice sharing is not supported on this platform.');
  }

  Future<void> openInvoiceFolder(String pdfPath) async {
    final directory = File(pdfPath).parent.path;
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [directory], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.start('open', [directory], runInShell: false);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [directory], runInShell: false);
    }
  }
}
