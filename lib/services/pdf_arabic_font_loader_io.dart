import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

class ArabicPdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const ArabicPdfFonts({required this.regular, required this.bold});
}

Future<pw.Font?> _loadFirst(List<String> paths) async {
  for (final path in paths) {
    try {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      return pw.Font.ttf(ByteData.sublistView(bytes));
    } catch (_) {
      // Try the next system font. Printing must not fail just because one font
      // path exists but is unreadable on a locked-down workstation.
    }
  }
  return null;
}

/// Loads an Arabic-capable font from the operating system so bilingual invoice
/// printing remains available even when the POS workstation has no internet
/// connection. Windows is the primary CounterIQ desktop target; Linux/macOS
/// paths are included for portability.
Future<ArabicPdfFonts?> loadSystemArabicPdfFonts() async {
  final regular = await _loadFirst(const [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\tahoma.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
  ]);
  if (regular == null) return null;

  final bold = await _loadFirst(const [
        r'C:\Windows\Fonts\segoeuib.ttf',
        r'C:\Windows\Fonts\tahomabd.ttf',
        r'C:\Windows\Fonts\arialbd.ttf',
        '/usr/share/fonts/truetype/noto/NotoNaskhArabic-Bold.ttf',
        '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      ]) ??
      regular;

  return ArabicPdfFonts(regular: regular, bold: bold);
}
