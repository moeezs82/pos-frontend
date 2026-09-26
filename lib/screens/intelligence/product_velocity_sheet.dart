import 'dart:math' as math;

import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductVelocitySheet extends StatefulWidget {
  final int productId;
  final String productName;

  const ProductVelocitySheet({super.key, required this.productId, required this.productName});

  @override
  State<ProductVelocitySheet> createState() => _ProductVelocitySheetState();
}

class _ProductVelocitySheetState extends State<ProductVelocitySheet> {
  IntelligenceEnvelope? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final envelope = await IntelligenceService(
        token: context.read<AuthProvider>().token!,
      ).productVelocity(widget.productId);
      if (mounted) setState(() => _data = envelope);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final desiredHeight = math.min(screen.height * .78, 720.0).toDouble();

    return SafeArea(
      child: Container(
        height: desiredHeight,
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _error != null
            ? IntelligenceError(error: _error!, onRetry: _load)
            : _data == null
                ? const Center(child: CircularProgressIndicator())
                : _body(),
      ),
    );
  }

  Widget _body() {
    final result = asMap(_data!.result);
    final windows = _sortedWindows(asMap(result['windows']));
    final season = asMap(result['season']);
    final primaryWindow = _windowForDays(windows, 30) ?? (windows.isNotEmpty ? windows.first : <String, dynamic>{});
    final primaryVelocity = _asDouble(primaryWindow['velocity_per_day']);
    final maxVelocity = windows.fold<double>(
      0,
      (maxValue, row) => math.max(maxValue, _asDouble(row['velocity_per_day'])).toDouble(),
    );
    final stockoutDays = (result['estimated_stockout_days'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        _header(result),
        const Divider(height: 1, color: AppTheme.border),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _overviewStrip(result, primaryVelocity),
                    const SizedBox(height: 16),
                    _velocityPanel(windows, maxVelocity),
                    if (stockoutDays > 0 || season.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final children = <Widget>[
                            if (stockoutDays > 0)
                              _contextCard(
                                icon: Icons.warning_amber_rounded,
                                color: AppTheme.warning,
                                title: 'Possible understated demand',
                                body:
                                    '$stockoutDays reconstructed stockout ${stockoutDays == 1 ? 'day' : 'days'} may make measured sales velocity look lower than real demand.',
                              ),
                            if (season.isNotEmpty)
                              _seasonCard(season),
                          ];
                          if (constraints.maxWidth >= 820 && children.length == 2) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: children[0]),
                                const SizedBox(width: 14),
                                Expanded(child: children[1]),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              for (int i = 0; i < children.length; i++) ...[
                                children[i],
                                if (i != children.length - 1) const SizedBox(height: 12),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    _explanationFooter(result),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(Map<String, dynamic> result) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.insights_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Sales velocity evidence used by Replenishment',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _overviewStrip(Map<String, dynamic> result, double primaryVelocity) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final cards = <Widget>[
          _miniKpi(
            label: '30-day velocity',
            value: '${primaryVelocity.toStringAsFixed(2)} / day',
            icon: Icons.speed_rounded,
            color: AppTheme.info,
          ),
          _miniKpi(
            label: 'Stock class',
            customValue: StockClassBadge(value: result['class']?.toString() ?? ''),
            icon: Icons.inventory_2_outlined,
            color: AppTheme.primary,
          ),
          _miniKpi(
            label: 'Trend',
            value: titleCase(result['trend']?.toString() ?? 'Stable'),
            icon: Icons.trending_up_rounded,
            color: AppTheme.purple,
          ),
          _miniKpi(
            label: 'Evidence',
            customValue: ConfidenceBadge(basis: result['basis'], compact: true),
            icon: Icons.verified_outlined,
            color: _confidenceAccent(result['basis']),
          ),
        ];

        if (!compact) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i != cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: math.max(220, (constraints.maxWidth - 10) / 2).toDouble(), child: card))
              .toList(),
        );
      },
    );
  }

  Widget _miniKpi({
    required String label,
    String? value,
    Widget? customValue,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (customValue != null)
                  Align(alignment: Alignment.centerLeft, child: customValue)
                else
                  Text(
                    value ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _velocityPanel(List<Map<String, dynamic>> windows, double maxVelocity) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 17, 18, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Velocity comparison', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text(
                  'Compare short, medium and long windows in one place.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (windows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No velocity windows are available yet.', style: TextStyle(color: AppTheme.textMuted))),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              color: AppTheme.surfaceSoft,
              child: const Row(
                children: [
                  SizedBox(width: 72, child: Text('Window', style: _HeaderTextStyle.style)),
                  Expanded(flex: 3, child: Text('Velocity / day', style: _HeaderTextStyle.style)),
                  Expanded(child: Text('Sold', textAlign: TextAlign.right, style: _HeaderTextStyle.style)),
                  Expanded(child: Text('Active days', textAlign: TextAlign.right, style: _HeaderTextStyle.style)),
                  Expanded(child: Text('Observations', textAlign: TextAlign.right, style: _HeaderTextStyle.style)),
                  Expanded(flex: 2, child: Text('Evidence range', textAlign: TextAlign.right, style: _HeaderTextStyle.style)),
                ],
              ),
            ),
            for (int index = 0; index < windows.length; index++) ...[
              _velocityRow(windows[index], maxVelocity),
              if (index != windows.length - 1) const Divider(height: 1, color: AppTheme.border),
            ],
          ],
        ],
      ),
    );
  }

  Widget _velocityRow(Map<String, dynamic> window, double maxVelocity) {
    final days = (window['days'] as num?)?.toInt() ?? 0;
    final velocity = _asDouble(window['velocity_per_day']);
    final ratio = maxVelocity <= 0 ? 0.0 : (velocity / maxVelocity).clamp(0.0, 1.0).toDouble();
    final from = window['from']?.toString() ?? '';
    final to = window['to']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('$days days', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: Text('${velocity.toStringAsFixed(2)} / day', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      backgroundColor: AppTheme.surfaceSoft,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.info),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Text(qty(window['net_sold']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('${window['active_days'] ?? 0}', textAlign: TextAlign.right)),
          Expanded(child: Text('${window['observations'] ?? 0}', textAlign: TextAlign.right)),
          Expanded(
            flex: 2,
            child: Text(
              from.isEmpty && to.isEmpty ? '—' : '$from → $to',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seasonCard(Map<String, dynamic> season) {
    final uplift = _asDouble(season['uplift']);
    return _contextCard(
      icon: Icons.event_repeat_rounded,
      color: AppTheme.purple,
      title: season['name']?.toString() ?? 'Business season',
      body:
          '${titleCase(season['state']?.toString() ?? '')} • ${uplift <= 0 ? '1.00' : uplift.toStringAsFixed(2)}× measured uplift • ${season['prior_occurrences'] ?? 0} prior occurrences.',
      trailing: ConfidenceBadge(basis: season['basis'], compact: true),
    );
  }

  Widget _explanationFooter(Map<String, dynamic> result) {
    final basis = asMap(result['basis']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 19, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Replenishment uses these measured windows to classify demand. Confidence is based on ${basis['history_days'] ?? '—'} history days and ${basis['observations'] ?? '—'} observed selling days; thin history stays visible as “Collecting data” instead of being treated as a stable forecast.',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _sortedWindows(Map<String, dynamic> raw) {
    final rows = raw.values.map(asMap).where((row) => row.isNotEmpty).toList(growable: false);
    rows.sort((a, b) {
      final ad = (a['days'] as num?)?.toInt() ?? 0;
      final bd = (b['days'] as num?)?.toInt() ?? 0;
      return ad.compareTo(bd);
    });
    return rows;
  }

  Map<String, dynamic>? _windowForDays(List<Map<String, dynamic>> windows, int days) {
    for (final row in windows) {
      if ((row['days'] as num?)?.toInt() == days) return row;
    }
    return null;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Color _confidenceAccent(dynamic basis) {
    switch (confidenceLevel(basis)) {
      case 'high':
        return AppTheme.success;
      case 'medium':
        return AppTheme.info;
      case 'low':
        return AppTheme.warning;
      default:
        return AppTheme.textMuted;
    }
  }
}

class _HeaderTextStyle {
  static const TextStyle style = TextStyle(
    fontSize: 11.5,
    color: AppTheme.textMuted,
    fontWeight: FontWeight.w900,
  );
}
