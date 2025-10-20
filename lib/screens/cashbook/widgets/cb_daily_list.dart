import 'package:flutter/material.dart';

class CBDailyList extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String>? onViewDay;
  const CBDailyList({super.key, required this.rows, this.onViewDay});

  @override
  State<CBDailyList> createState() => _CBDailyListState();
}

class _CBDailyListState extends State<CBDailyList> {
  // Column widths
  static const double _wDate = 96.0;
  static const double _wAmt = 88.0; // Opening/In/Out/Expense/Net/Closing
  static const double _wAct = 56.0; // was 72
  static const double _hPad = 12.0;

  late final double _tableWidth = _wDate + _wAmt * 7 + _wAct;
  late final double _contentWidth =
      _tableWidth + _hPad * 2; // <-- add gutters to content width

  // Horizontal controllers to keep header & body aligned
  final _hHeader = ScrollController();
  final _hBody = ScrollController();

  bool _syncing = false;
  void _onBodyScroll() {
    if (_syncing) return;
    _syncing = true;
    if (_hHeader.hasClients) _hHeader.jumpTo(_hBody.offset);
    _updateFades();
    _syncing = false;
  }

  // Edge-fade state
  bool _showFadeLeft = false;
  bool _showFadeRight = false;

  void _updateFades() {
    if (!_hBody.hasClients) return;
    final max = _hBody.position.maxScrollExtent;
    final off = _hBody.offset;
    final showL = off > 2.0;
    final showR = (max - off) > 2.0;
    if (showL != _showFadeLeft || showR != _showFadeRight) {
      setState(() {
        _showFadeLeft = showL;
        _showFadeRight = showR;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _hBody.addListener(_onBodyScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    _hBody.removeListener(_onBodyScroll);
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('No daily data'));
    }

    final theme = Theme.of(context);
    final divider = theme.dividerColor.withOpacity(0.35);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withOpacity(0.65),
      letterSpacing: 0.2,
    );
    final cellStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );

    return Column(
      children: [
        // HEADER (horizontally scrollable & synced)
        Stack(
          children: [
            ScrollConfiguration(
              behavior: const _TouchyBehavior(),
              child: SingleChildScrollView(
                controller: _hHeader,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: _contentWidth, // <-- includes gutters
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: _hPad, // <-- left/right padding
                    ),
                    child: Row(
                      children: [
                        _HCell('DATE', width: _wDate, style: headerStyle),
                        _HCell(
                          'OPEN',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          'IN',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          'OUT',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          'EXP',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          'NET',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          'CLOSE',
                          width: _wAmt,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                        _HCell(
                          '',
                          width: _wAct,
                          alignEnd: true,
                          style: headerStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _EdgeFade(showLeft: _showFadeLeft, showRight: _showFadeRight),
          ],
        ),
        Divider(height: 1, color: divider),

        // BODY (vertical list inside a single horizontal scroller)
        Expanded(
          child: Stack(
            children: [
              ScrollConfiguration(
                behavior: const _TouchyBehavior(),
                child: SingleChildScrollView(
                  controller: _hBody,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: _contentWidth, // <-- includes gutters
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: divider),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final date = (r['date'] ?? '').toString();
                        final opening = _fmt(r['opening']);
                        final pin = _fmt(r['in']);
                        // final pin = _fmt(r['payment_in']);
                        // final pout = _fmt(r['payment_out']);
                        final pout = _fmt(r['out']);
                        final exp = _fmt(r['expense']);
                        final net = _fmt(r['net']);
                        final closing = _fmt(r['closing']);

                        final netVal = _toDouble(r['net']);
                        final netColor = netVal >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700;

                        final rowBg = i.isEven
                            ? theme.colorScheme.surface
                            : theme.colorScheme.surface.withOpacity(0.96);

                        return InkWell(
                          onTap: () => widget.onViewDay?.call(date),
                          child: Container(
                            color: rowBg,
                            width: _contentWidth, // <-- lock to content width
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: _hPad, // <-- left/right padding
                            ),
                            child: Row(
                              children: [
                                _Cell(date, width: _wDate, style: cellStyle),
                                _Cell(
                                  opening,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle,
                                ),
                                _Cell(
                                  pin,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle,
                                ),
                                _Cell(
                                  pout,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle,
                                ),
                                _Cell(
                                  exp,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle,
                                ),
                                _Cell(
                                  net,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle?.copyWith(color: netColor),
                                ),
                                _Cell(
                                  closing,
                                  width: _wAmt,
                                  alignEnd: true,
                                  style: cellStyle,
                                ),
                                // VIEW action
                                SizedBox(
                                  width: _wAct,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton.filledTonal(
                                      tooltip: 'View details',
                                      onPressed: () =>
                                          widget.onViewDay?.call(date),
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                      ),
                                      style: IconButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(
                                          36,
                                          32,
                                        ), // compact, but tappable
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              _EdgeFade(showLeft: _showFadeLeft, showRight: _showFadeRight),
            ],
          ),
        ),
      ],
    );
  }
}

class _HCell extends StatelessWidget {
  final String text;
  final double width;
  final bool alignEnd;
  final TextStyle? style;
  const _HCell(
    this.text, {
    required this.width,
    this.alignEnd = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style:
            style ??
            Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool alignEnd;
  final TextStyle? style;
  const _Cell(
    this.text, {
    required this.width,
    this.alignEnd = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: style,
      ),
    );
  }
}

/// Subtle left/right gradient overlays that hint horizontal scrolling (mobile-friendly)
class _EdgeFade extends StatelessWidget {
  final bool showLeft;
  final bool showRight;
  const _EdgeFade({required this.showLeft, required this.showRight});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      ignoring: true,
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: showLeft ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              width: 16,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [bg, bg.withOpacity(0.0)],
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
          AnimatedOpacity(
            opacity: showRight ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              width: 16,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [bg, bg.withOpacity(0.0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ScrollBehavior enabling touch drag on all platforms (nice on mobile & web)
class _TouchyBehavior extends ScrollBehavior {
  const _TouchyBehavior();
  @override
  Widget buildViewportChrome(
    BuildContext context,
    Widget child,
    AxisDirection axisDirection,
  ) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

// -------- helpers --------
double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
  return 0.0;
}

String _fmt(dynamic v) => _toDouble(v).toStringAsFixed(2);
