import 'package:flutter/material.dart';

/// The WhatsApp logo (speech bubble with a phone handset), drawn in code so no
/// asset or extra package is needed. Material Icons has no WhatsApp glyph.
///
/// [color] fills the bubble (WhatsApp green by default); the handset is cut
/// out of it, so it takes the colour of whatever is behind the icon.
class WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color color;

  const WhatsAppIcon({
    super.key,
    this.size = 18,
    this.color = const Color(0xFF25D366),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WhatsAppPainter(color)),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  final Color color;
  const _WhatsAppPainter(this.color);

  // Geometry is authored on a 24 x 24 grid and scaled to the widget size.
  static final Path _bubble = Path()
    ..addOval(Rect.fromCircle(center: const Offset(12, 11.6), radius: 9.6))
    ..moveTo(2.4, 21.6)
    ..lineTo(4.1, 15.6)
    ..lineTo(8.2, 19.3)
    ..close();

  static final Path _handset = Path()
    ..moveTo(8.664, 10.850)
    ..cubicTo(9.557, 12.604, 10.996, 14.037, 12.750, 14.936)
    ..lineTo(14.114, 13.572)
    ..cubicTo(14.282, 13.404, 14.530, 13.348, 14.747, 13.423)
    ..cubicTo(15.441, 13.652, 16.191, 13.776, 16.960, 13.776)
    ..cubicTo(17.301, 13.776, 17.580, 14.055, 17.580, 14.396)
    ..lineTo(17.580, 16.560)
    ..cubicTo(17.580, 16.901, 17.301, 17.180, 16.960, 17.180)
    ..cubicTo(11.138, 17.180, 6.420, 12.462, 6.420, 6.640)
    ..cubicTo(6.420, 6.299, 6.699, 6.020, 7.040, 6.020)
    ..lineTo(9.210, 6.020)
    ..cubicTo(9.551, 6.020, 9.830, 6.299, 9.830, 6.640)
    ..cubicTo(9.830, 7.415, 9.954, 8.159, 10.183, 8.853)
    ..cubicTo(10.252, 9.070, 10.202, 9.312, 10.028, 9.486)
    ..lineTo(8.664, 10.850)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(scale);
    canvas.drawPath(_bubble, Paint()..color = color..isAntiAlias = true);
    canvas.drawPath(
      _handset,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WhatsAppPainter old) => old.color != color;
}
