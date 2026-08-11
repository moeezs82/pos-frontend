import 'dart:ui';

import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/dashboard/low_stock_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';

/// Home-screen "how's today going" snapshot: a row of KPI cards (today's
/// net sales, invoice count, gross profit, top product) plus a low-stock
/// alert card. Everything here is read from enterprise reporting endpoints
/// that already exist on the backend (sales-summary, sales top/bottom,
/// low-stock) — there is no new backend surface for this widget.
class TodaySnapshotSection extends StatefulWidget {
  const TodaySnapshotSection({super.key});

  @override
  State<TodaySnapshotSection> createState() => _TodaySnapshotSectionState();
}

class _TodaySnapshotSectionState extends State<TodaySnapshotSection> {
  final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  final _moneyFmt = const AppMoneyFormatter(decimalDigits: 0);

  bool _loading = true;
  String? _error;
  bool _obscured = true;

  double _netSales = 0;
  int _invoices = 0;
  double _grossProfit = 0;
  double _discounts = 0;
  String? _topProductName;
  double _topProductRevenue = 0;
  int _lowStockCount = 0;
  List<Map<String, dynamic>> _lowStockPreview = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({String from, String to}) _todayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return (from: _dateTimeFmt.format(start), to: _dateTimeFmt.format(end));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final service = ReportsService(token: token);
      final range = _todayRange();

      final results = await Future.wait([
        service.runEnterpriseReport(
          reportKey: 'sales-summary',
          filters: {'from': range.from, 'to': range.to, 'per_page': 5},
        ),
        service.getTopBottomProducts(
          from: range.from,
          to: range.to,
          sortBy: 'revenue',
          direction: 'desc',
          page: 1,
          perPage: 1,
        ),
        service.runEnterpriseReport(
          reportKey: 'low-stock',
          filters: {'per_page': 50},
        ),
      ].map((f) => f.catchError((Object _) => <String, dynamic>{})));

      if (!mounted) return;

      final salesSummary = results[0];
      final totals = (salesSummary['totals'] as Map?)?.cast<String, dynamic>() ?? const {};

      final topBottom = results[1];
      final topRows = (topBottom['rows'] as List?) ?? const [];
      final topProduct = topRows.isNotEmpty ? Map<String, dynamic>.from(topRows.first as Map) : null;

      final lowStock = results[2];
      final lowStockRows = ((lowStock['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final lowStockPagination = (lowStock['pagination'] as Map?)?.cast<String, dynamic>();

      setState(() {
        _netSales = _asDouble(totals['net_sales']);
        _invoices = _asInt(totals['invoices']);
        _grossProfit = _asDouble(totals['gross_profit']);
        _discounts = _asDouble(totals['discount']);
        _topProductName = topProduct?['product']?.toString() ?? topProduct?['name']?.toString();
        _topProductRevenue = _asDouble(topProduct?['revenue'] ?? topProduct?['total']);
        _lowStockPreview = lowStockRows.take(5).toList();
        _lowStockCount = _asInt(lowStockPagination?['total']) > 0
            ? _asInt(lowStockPagination?['total'])
            : lowStockRows.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load today\'s snapshot: $e';
        _loading = false;
      });
    }
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Today at a glance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            // Privacy toggle — eye icon
            Tooltip(
              message: _obscured ? 'Show figures' : 'Hide figures',
              child: InkWell(
                onTap: () => setState(() => _obscured = !_obscured),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _obscured ? Colors.grey.shade100 : AppTheme.primary.withOpacity(.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _obscured ? AppTheme.border : AppTheme.primary.withOpacity(.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 16,
                        color: _obscured ? AppTheme.textMuted : AppTheme.primary,
                      ),
                      const SizedBox(width: 5),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _obscured ? 'Hidden' : 'Visible',
                          key: ValueKey(_obscured),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _obscured ? AppTheme.textMuted : AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _loading ? _buildSkeleton() : _buildCards(context),
      ],
    );
  }

  Widget _buildSkeleton() {
    return const SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCards(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.point_of_sale_rounded,
          color: AppTheme.primary,
          label: "Today's Net Sales",
          value: _moneyFmt.format(_netSales),
          obscured: _obscured,
        ),
        _StatCard(
          icon: Icons.receipt_long_rounded,
          color: AppTheme.info,
          label: 'Invoices Today',
          value: '$_invoices',
          obscured: _obscured,
        ),
        _StatCard(
          icon: Icons.trending_up_rounded,
          color: AppTheme.success,
          label: 'Gross Profit',
          value: _moneyFmt.format(_grossProfit),
          obscured: _obscured,
        ),
        _StatCard(
          icon: Icons.percent_rounded,
          color: AppTheme.warning,
          label: 'Discounts Given',
          value: _moneyFmt.format(_discounts),
          obscured: _obscured,
        ),
        _StatCard(
          icon: Icons.star_rounded,
          color: AppTheme.purple,
          label: 'Top Product Today',
          value: _topProductName ?? '—',
          subtitle: _topProductName != null ? _moneyFmt.format(_topProductRevenue) : 'No sales yet',
          obscured: _obscured,
        ),
        _LowStockCard(
          count: _lowStockCount,
          preview: _lowStockPreview,
          obscured: _obscured,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LowStockScreen())),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? subtitle;
  final bool obscured;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.obscured,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          _BlurShield(
            obscured: obscured,
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navy)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 12)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            _BlurShield(
              obscured: obscured,
              child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final int count;
  final List<Map<String, dynamic>> preview;
  final bool obscured;
  final VoidCallback onTap;

  const _LowStockCard({required this.count, required this.preview, required this.obscured, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasAlerts = count > 0;
    final color = hasAlerts ? AppTheme.danger : AppTheme.success;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: hasAlerts ? color.withOpacity(.35) : AppTheme.border),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                    child: Icon(hasAlerts ? Icons.warning_amber_rounded : Icons.check_circle_rounded, color: color, size: 20),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: 10),
              _BlurShield(
                obscured: obscured,
                child: Text('$count', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navy)),
              ),
              const SizedBox(height: 2),
              const Text('Low Stock Items', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 12)),
              if (hasAlerts && preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  preview.map((r) => (r['product'] ?? r['sku'] ?? '').toString()).where((s) => s.isNotEmpty).take(2).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Smoothly blurs its child when [obscured] is true.
/// Uses [TweenAnimationBuilder] so the blur sigma animates in and out
/// without requiring a StatefulWidget or an AnimationController.
class _BlurShield extends StatelessWidget {
  final Widget child;
  final bool obscured;

  const _BlurShield({required this.child, required this.obscured});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: obscured ? 9.0 : 0.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: child,
      builder: (_, sigma, innerChild) {
        if (sigma < 0.05) return innerChild!;
        return ClipRect(
          child: Stack(
            children: [
              innerChild!,
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
