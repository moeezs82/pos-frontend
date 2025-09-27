import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class CBTotals extends StatelessWidget {
  final bool dailyMode;

  // daily (grand)
  final String dOpening, dIn, dOut, dExp, dNet, dClosing;
  // daily (page)
  final String dPageIn, dPageOut, dPageExp, dPageNet;

  // txn (grand)
  final String opening, inflow, outflow, net, closing;
  // txn (page)
  final String pageInflow, pageOutflow;

  final double Function(String) parse;

  const CBTotals({
    super.key,
    required this.dailyMode,
    required this.dOpening,
    required this.dIn,
    required this.dOut,
    required this.dExp,
    required this.dNet,
    required this.dClosing,
    required this.dPageIn,
    required this.dPageOut,
    required this.dPageExp,
    required this.dPageNet,
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.closing,
    required this.pageInflow,
    required this.pageOutflow,
    required this.parse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSubtle = theme.colorScheme.onSurface.withOpacity(0.7);
    final border = theme.dividerColor.withOpacity(0);

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: onSubtle,
      letterSpacing: 0.2,
      height: 1.0,
    );
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.0,
    );

    final grand = dailyMode
        ? <Widget>[
            _chip('Grand', context),
            _stat('Open', dOpening, labelStyle, valueStyle),
            _stat('In',   dIn,      labelStyle, valueStyle),
            _stat('Out',  dOut,     labelStyle, valueStyle),
            _stat('Exp',  dExp,     labelStyle, valueStyle),
            _stat('Net',  dNet,     labelStyle, valueStyle, color: _signColor(parse(dNet))),
            _stat('Close',dClosing, labelStyle, valueStyle),
          ]
        : <Widget>[
            _chip('Grand', context),
            _stat('Open',  opening, labelStyle, valueStyle),
            _stat('In',    inflow,  labelStyle, valueStyle),
            _stat('Out',   outflow, labelStyle, valueStyle),
            _stat('Net',   net,     labelStyle, valueStyle, color: _signColor(parse(net))),
            _stat('Close', closing, labelStyle, valueStyle),
          ];

    final page = dailyMode
        ? <Widget>[
            _chip('Page', context),
            _stat('In',  dPageIn,  labelStyle, valueStyle),
            _stat('Out', dPageOut, labelStyle, valueStyle),
            _stat('Exp', dPageExp, labelStyle, valueStyle),
            _stat('Net', dPageNet, labelStyle, valueStyle, color: _signColor(parse(dPageNet))),
          ]
        : <Widget>[
            _chip('Page', context),
            _stat('In',  pageInflow,  labelStyle, valueStyle),
            _stat('Out', pageOutflow, labelStyle, valueStyle),
          ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // a bit larger
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // <-- left aligned
        children: [
          _hScroll(Row(
            mainAxisSize: MainAxisSize.min,
            children: _withGaps(grand, gap: 16), // slightly wider gaps
          )),
          const SizedBox(height: 6),
          Container(height: 1, color: border),
          const SizedBox(height: 6),
          _hScroll(Row(
            mainAxisSize: MainAxisSize.min,
            children: _withGaps(page, gap: 16),
          )),
        ],
      ),
    );
  }

  // --- helpers ---

  static List<Widget> _withGaps(List<Widget> items, {double gap = 12}) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) out.add(SizedBox(width: gap));
    }
    return out;
  }

  static Widget _hScroll(Widget child) {
    return Align( // ensure left start, not centered
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: child,
      ),
    );
  }

  static Color _signColor(double v) =>
      v >= 0 ? Colors.green.shade700 : Colors.red.shade700;

  static Widget _chip(String text, BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.28)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11, // slightly larger than before
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          height: 1.0,
        ),
      ),
    );
  }

  static Widget _stat(
    String label,
    String value,
    TextStyle? labelStyle,
    TextStyle? valueStyle, {
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:', style: labelStyle),
        const SizedBox(width: 6),
        Text(value, style: (valueStyle ?? const TextStyle()).copyWith(color: color)),
      ],
    );
  }
}
