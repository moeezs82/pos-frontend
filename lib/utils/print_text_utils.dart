/// Print-safe text helpers for receipt content.
///
/// Thermal printer firmware and CounterIQ's PDF fonts do not reliably provide
/// color-emoji glyphs. Footer emojis are therefore removed at print time while
/// ordinary Latin, Arabic, digits and punctuation remain untouched.
class PrintTextUtils {
  const PrintTextUtils._();

  static bool containsUnsupportedEmoji(String value) {
    for (final rune in value.runes) {
      if (_isEmojiRune(rune)) return true;
    }
    return false;
  }

  static String sanitizeFooterText(String value) {
    final out = StringBuffer();
    var removed = false;
    for (final rune in value.runes) {
      if (_isEmojiRune(rune)) {
        removed = true;
        continue;
      }
      out.writeCharCode(rune);
    }
    if (!removed) return value.trim();

    // Removing a glyph from between spaces should not leave obvious double
    // gaps on a printed receipt. Preserve line content otherwise.
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  static bool _isEmojiRune(int rune) {
    // Joiners/selectors/modifiers/keycap components used only to compose emoji.
    if (rune == 0x200D || rune == 0xFE0F || rune == 0x20E3) return true;
    if (rune >= 0x1F3FB && rune <= 0x1F3FF) return true;

    // Main Unicode emoji/pictograph blocks.
    if (rune >= 0x1F000 && rune <= 0x1FAFF) return true;
    if (rune >= 0x2600 && rune <= 0x27BF) return true;
    if (rune >= 0x2300 && rune <= 0x23FF) return true;
    if (rune >= 0x1F1E6 && rune <= 0x1F1FF) return true;

    return false;
  }
}
