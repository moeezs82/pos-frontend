enum ReceiptFooterAlignment { left, center, right }

enum ReceiptFooterTextSize { small, normal, large }

/// Per-line formatting for the configurable receipt footer.
///
/// The defaults intentionally reproduce CounterIQ's historic footer rendering
/// so existing branches do not change appearance after upgrading.
class ReceiptFooterStyle {
  final ReceiptFooterAlignment alignment;
  final bool bold;
  final ReceiptFooterTextSize size;

  const ReceiptFooterStyle({
    this.alignment = ReceiptFooterAlignment.center,
    this.bold = true,
    this.size = ReceiptFooterTextSize.normal,
  });

  factory ReceiptFooterStyle.fromJson(dynamic raw) {
    if (raw is! Map) return const ReceiptFooterStyle();
    final map = Map<String, dynamic>.from(raw);
    return ReceiptFooterStyle(
      alignment: _alignmentFromValue(map['alignment']?.toString()),
      bold: _bool(map['bold'], fallback: true),
      size: _sizeFromValue(map['size']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'alignment': alignment.name,
        'bold': bold,
        'size': size.name,
      };

  ReceiptFooterStyle copyWith({
    ReceiptFooterAlignment? alignment,
    bool? bold,
    ReceiptFooterTextSize? size,
  }) {
    return ReceiptFooterStyle(
      alignment: alignment ?? this.alignment,
      bold: bold ?? this.bold,
      size: size ?? this.size,
    );
  }

  static ReceiptFooterAlignment _alignmentFromValue(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'left':
        return ReceiptFooterAlignment.left;
      case 'right':
        return ReceiptFooterAlignment.right;
      default:
        return ReceiptFooterAlignment.center;
    }
  }

  static ReceiptFooterTextSize _sizeFromValue(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'small':
        return ReceiptFooterTextSize.small;
      case 'large':
        return ReceiptFooterTextSize.large;
      default:
        return ReceiptFooterTextSize.normal;
    }
  }

  static bool _bool(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().toLowerCase();
    if (const {'1', 'true', 'yes', 'on'}.contains(normalized)) return true;
    if (const {'0', 'false', 'no', 'off'}.contains(normalized)) return false;
    return fallback;
  }
}
