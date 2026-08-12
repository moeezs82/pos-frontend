import 'package:pdf/widgets.dart' as pw;

class ArabicPdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const ArabicPdfFonts({required this.regular, required this.bold});
}

/// Non-IO fallback. The receipt renderer will try PdfGoogleFonts when a local
/// operating-system Arabic font is not available (for example on web).
Future<ArabicPdfFonts?> loadSystemArabicPdfFonts() async => null;
