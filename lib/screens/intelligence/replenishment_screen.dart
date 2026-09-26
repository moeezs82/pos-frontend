import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/product_velocity_sheet.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ReplenishmentScreen extends StatefulWidget {
  const ReplenishmentScreen({super.key});

  @override
  State<ReplenishmentScreen> createState() => _ReplenishmentScreenState();
}

class _ReplenishmentScreenState extends State<ReplenishmentScreen> {
  IntelligenceService? _service;
  IntelligenceEnvelope? _data;
  Object? _error;
  bool _loading = false;
  bool _onlyReorder = true;
  String _stockClass = '';
  String _search = '';

  IntelligenceService _api() => _service ??= IntelligenceService(token: context.read<AuthProvider>().token!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refresh) await _api().refresh();
      final envelope = await _api().replenishment(stockClass: _stockClass, onlyReorder: _onlyReorder);
      if (mounted) {
        setState(() {
          _data = envelope;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Replenishment')),
      body: _error != null
          ? IntelligenceError(error: _error!, onRetry: () => _load(refresh: true))
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(_data!),
    );
  }

  Widget _body(IntelligenceEnvelope envelope) {
    final result = asMap(envelope.result);
    final groups = asMapList(result['groups']);
    final collecting = (result['collecting_data'] as num?)?.toInt() ?? 0;
    final rows = groups.expand((g) => asMapList(g['rows'])).toList(growable: false);
    final needingReorder = rows.where((r) => r['needs_reorder'] == true).length;
    final totalCost = groups.fold<double>(0, (sum, g) => sum + (double.tryParse(g['estimated_cost']?.toString() ?? '') ?? 0));
    final visibleGroups = groups.map((group) {
      if (_search.trim().isEmpty) return group;
      final q = _search.trim().toLowerCase();
      final vendor = asMap(group['vendor']);
      final vendorMatches = (vendor['name']?.toString() ?? '').toLowerCase().contains(q);
      final matchedRows = asMapList(group['rows']).where((row) {
        if (vendorMatches) return true;
        return (row['name']?.toString() ?? '').toLowerCase().contains(q) ||
            (row['sku']?.toString() ?? '').toLowerCase().contains(q);
      }).toList(growable: false);
      if (matchedRows.isEmpty) return <String, dynamic>{};
      return <String, dynamic>{...group, 'rows': matchedRows};
    }).where((group) => group.isNotEmpty).toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const IntelligencePageHeader(
            title: 'Replenishment',
            subtitle: 'Measured reorder suggestions based on sales velocity, lead time, safety stock and current cover. Nothing is automatically purchased from this screen.',
          ),
          const SizedBox(height: 16),
          IntelligenceMetaBar(
            computedAt: envelope.computedAt,
            stale: envelope.stale,
            refreshing: _loading,
            onRefresh: () => _load(refresh: true),
          ),
          const SizedBox(height: 16),
          const IntelligenceInfoBanner(
            icon: Icons.info_outline_rounded,
            title: 'Read-only in this build',
            message: 'Suggestions are advisory. Draft purchase creation remains intentionally disabled until the purchase receiving lifecycle can guarantee exactly-once stock and accounting effects.',
            color: AppTheme.warning,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              MetricCard(title: 'Products shown', value: '${rows.length}', caption: 'Products currently in this worksheet.', icon: Icons.inventory_2_outlined, color: AppTheme.info),
              MetricCard(title: 'Need reorder now', value: '$needingReorder', caption: 'Rows where current stock cover is below the suggested requirement.', icon: Icons.shopping_cart_checkout_rounded, color: AppTheme.danger),
              MetricCard(title: 'Estimated order cost', value: money(totalCost), caption: 'Sum of vendor-group estimated costs in this view.', icon: Icons.payments_outlined, color: AppTheme.primary),
              MetricCard(title: 'Collecting data', value: '$collecting', caption: 'Products shown with limited velocity history.', icon: Icons.analytics_outlined, color: AppTheme.textMuted),
            ],
          ),
          const SizedBox(height: 16),
          IntelligenceSectionCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Only needs reorder'),
                  selected: _onlyReorder,
                  onSelected: (value) {
                    setState(() => _onlyReorder = value);
                    _load();
                  },
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    value: _stockClass,
                    decoration: const InputDecoration(labelText: 'Stock class'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All classes')),
                      DropdownMenuItem(value: 'running', child: Text('Running')),
                      DropdownMenuItem(value: 'steady', child: Text('Steady')),
                      DropdownMenuItem(value: 'slow', child: Text('Slow')),
                      DropdownMenuItem(value: 'dead', child: Text('Dead')),
                      DropdownMenuItem(value: 'new', child: Text('New / collecting')),
                    ],
                    onChanged: (value) {
                      setState(() => _stockClass = value ?? '');
                      _load();
                    },
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search product, SKU or vendor',
                    ),
                  ),
                ),
                const Text(
                  'Suggestions respect measured demand, lead time, current on-order stock and packaging constraints.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (visibleGroups.isEmpty)
            IntelligenceEmptyState(
              title: _onlyReorder ? 'Nothing currently needs reordering' : 'No replenishment rows available yet',
              subtitle: _onlyReorder
                  ? 'Based on the current measured rules, nothing in this view needs a reorder right now.'
                  : 'CounterIQ does not have enough eligible rows for the current filter selection.',
              icon: Icons.check_circle_outline_rounded,
            )
          else
            ...visibleGroups.map(_vendorGroup),
        ],
      ),
    );
  }

  Widget _vendorGroup(Map<String, dynamic> group) {
    final vendor = asMap(group['vendor']);
    final rows = asMapList(group['rows']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: IntelligenceSectionCard(
        padding: const EdgeInsets.all(0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            title: Text(vendor['name']?.toString() ?? 'Unassigned vendor', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('Lead time ${vendor['lead_time_days'] ?? '—'} days', AppTheme.info),
                  _pill(titleCase(vendor['lead_time_source']?.toString() ?? 'Unknown'), AppTheme.textMuted),
                  _pill('Est. order ${money(group['estimated_cost'])}', AppTheme.primary),
                ],
              ),
            ),
            children: [
              const Divider(height: 1, color: AppTheme.border),
              ...rows.map(_row),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> row) {
    final suggestedPackage = asMap(row['suggested_packages']);
    final season = asMap(row['season']);
    final daysOfCover = row['days_of_cover'];

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(row['name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            StockClassBadge(value: row['class']?.toString() ?? ''),
            if ((row['trend']?.toString() ?? '').isNotEmpty)
              _pill('Trend ${titleCase(row['trend'].toString())}', AppTheme.info),
          ],
        ),
        if ((row['sku']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('SKU ${row['sku']}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chipStat('On hand', qty(row['on_hand'])),
            _chipStat('On order', qty(row['on_order'])),
            _chipStat('Days of cover', daysOfCover == null ? 'Unknown' : (daysOfCover as num).toStringAsFixed(1), color: AppTheme.info),
            _chipStat('Velocity / day', (row['velocity_per_day'] as num?)?.toStringAsFixed(2) ?? '0.00'),
            _chipStat('Reorder point', qty(row['reorder_point'])),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Suggested order ${qty(row['suggested_qty'])} units • trigger ${titleCase(row['trigger_source']?.toString() ?? 'unknown')} • safety stock ${qty(row['safety_stock'])} (${titleCase(row['safety_stock_method']?.toString() ?? 'unknown')})',
          style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
        ),
        if ((row['estimated_stockout_days'] as num? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Demand estimate may be understated: about ${row['estimated_stockout_days']} stockout days were reconstructed.',
              style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
            ),
          ),
        if (season.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${season['name']} • ${titleCase(season['state']?.toString() ?? '')} • ${(season['uplift'] as num?)?.toStringAsFixed(2) ?? '1.00'}× measured uplift from ${season['prior_occurrences'] ?? 0} prior occurrences',
              style: const TextStyle(color: AppTheme.purple, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );

    final orderSummary = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(money(row['estimated_cost']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.primary)),
        const SizedBox(height: 4),
        const Text('Estimated order cost', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
        if (suggestedPackage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('${suggestedPackage['count']} ${suggestedPackage['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${qty(suggestedPackage['base_quantity'])} units total', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
        const SizedBox(height: 10),
        ConfidenceBadge(basis: row['basis'], compact: true),
        const SizedBox(height: 8),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('View demand detail', style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
            SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ],
    );

    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ProductVelocitySheet(
          productId: (row['product_id'] as num).toInt(),
          productName: row['name']?.toString() ?? 'Product',
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: orderSummary),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 18),
                orderSummary,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }

  Widget _chipStat(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(12)),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: AppTheme.navy),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}
