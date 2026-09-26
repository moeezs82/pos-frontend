import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/product_velocity_sheet.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/screens/purchases/purchase_create.dart';
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
  final Set<int> _selectedProductIds = <int>{};

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
      final result = asMap(envelope.result);
      final groups = asMapList(result['groups']);
      final selectable = <int>{};
      for (final group in groups) {
        final vendor = asMap(group['vendor']);
        final vendorId = (vendor['id'] as num?)?.toInt() ?? 0;
        if (vendorId <= 0) continue;
        for (final row in asMapList(group['rows'])) {
          final productId = (row['product_id'] as num?)?.toInt() ?? 0;
          final suggested = double.tryParse(row['suggested_qty']?.toString() ?? '') ?? 0;
          if (productId > 0 && row['needs_reorder'] == true && suggested > 0) selectable.add(productId);
        }
      }
      if (mounted) {
        setState(() {
          _data = envelope;
          _selectedProductIds
            ..clear()
            ..addAll(selectable);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final allRows = groups.expand((g) => asMapList(g['rows'])).toList(growable: false);
    final collecting = (result['collecting_data'] as num?)?.toInt() ?? 0;
    final needingReorder = allRows.where((r) => r['needs_reorder'] == true).length;
    final totalCost = allRows.fold<double>(
      0,
      (sum, row) => sum + (double.tryParse(row['estimated_cost']?.toString() ?? '') ?? 0),
    );
    final selectedCount = allRows.where((r) => _selectedProductIds.contains((r['product_id'] as num?)?.toInt() ?? 0)).length;

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
            subtitle: 'See what to buy, how much and why — then hand the recommendation into your existing Purchase Create screen for final review.',
          ),
          const SizedBox(height: 14),
          IntelligenceMetaBar(
            computedAt: envelope.computedAt,
            stale: envelope.stale,
            refreshing: _loading,
            onRefresh: () => _load(refresh: true),
          ),
          const SizedBox(height: 16),
          _introBanner(),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _summaryCard(
                icon: Icons.shopping_cart_checkout_rounded,
                color: AppTheme.danger,
                title: 'Need reorder now',
                value: '$needingReorder',
                caption: 'Products below their calculated reorder trigger',
              ),
              _summaryCard(
                icon: Icons.payments_outlined,
                color: AppTheme.primary,
                title: 'Estimated purchase cost',
                value: money(totalCost),
                caption: 'Estimated cost for the current suggestion set',
              ),
              _summaryCard(
                icon: Icons.checklist_rounded,
                color: AppTheme.info,
                title: 'Selected to prepare',
                value: '$selectedCount',
                caption: 'Products currently selected across vendors',
              ),
              _summaryCard(
                icon: Icons.analytics_outlined,
                color: AppTheme.textMuted,
                title: 'Collecting data',
                value: '$collecting',
                caption: 'Products with insufficient velocity history',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _filterBar(),
          const SizedBox(height: 18),
          if (visibleGroups.isEmpty)
            IntelligenceEmptyState(
              title: _onlyReorder ? 'Nothing currently needs reordering' : 'No replenishment rows match these filters',
              subtitle: _onlyReorder
                  ? 'Based on current on-hand stock and measured demand, nothing in this view needs a purchase right now.'
                  : 'Clear the search or select another stock class.',
              icon: Icons.check_circle_outline_rounded,
            )
          else
            ...visibleGroups.map(_vendorGroup),
        ],
      ),
    );
  }

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD5EFEB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recommendation first. Purchase only after your review.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                  'CounterIQ calculates suggestions from current on-hand stock, measured sales velocity, lead time, safety stock, business seasons and packaging. Prepare Purchase only prefills your normal Purchase Create screen — it creates no purchase, stock movement or accounting entry by itself.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String caption,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                labelText: 'Search suggestions',
                hintText: 'Product, SKU or vendor',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
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
          OutlinedButton.icon(
            onPressed: _selectedProductIds.isEmpty ? null : () => setState(_selectedProductIds.clear),
            icon: const Icon(Icons.remove_done_rounded),
            label: const Text('Clear selection'),
          ),
        ],
      ),
    );
  }

  Widget _vendorGroup(Map<String, dynamic> group) {
    final vendor = asMap(group['vendor']);
    final rows = asMapList(group['rows']);
    final vendorId = (vendor['id'] as num?)?.toInt() ?? 0;
    final selectedRows = rows.where((row) => _selectedProductIds.contains((row['product_id'] as num?)?.toInt() ?? 0)).toList(growable: false);
    final selectedCost = selectedRows.fold<double>(0, (sum, row) => sum + (double.tryParse(row['estimated_cost']?.toString() ?? '') ?? 0));
    final canPurchase = context.read<AuthProvider>().hasPermission('manage-purchases');
    final canPrepare = canPurchase && vendorId > 0 && selectedRows.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.softShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final header = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vendor['name']?.toString() ?? 'Unassigned vendor', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _pill('Lead time ${vendor['lead_time_days'] ?? '—'} days', AppTheme.info),
                            _pill(_leadSourceLabel(vendor['lead_time_source']?.toString()), AppTheme.textMuted),
                            _pill('${rows.length} products', AppTheme.primary),
                            _pill('${selectedRows.length} selected', selectedRows.isEmpty ? AppTheme.textMuted : AppTheme.success),
                            _pill('Selected est. ${money(selectedCost)}', AppTheme.primary),
                          ],
                        ),
                      ],
                    );
                    final action = Tooltip(
                      message: vendorId <= 0
                          ? 'Assign a vendor to these products before preparing a purchase.'
                          : !canPurchase
                              ? 'Manage Purchases permission is required.'
                              : selectedRows.isEmpty
                                  ? 'Select at least one product for this vendor.'
                                  : 'Open the existing Purchase Create screen with these suggestions prefilled.',
                      child: FilledButton.icon(
                        onPressed: canPrepare ? () => _preparePurchase(group, selectedRows) : null,
                        icon: const Icon(Icons.shopping_cart_checkout_rounded),
                        label: const Text('Prepare Purchase'),
                      ),
                    );
                    if (constraints.maxWidth < 780) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, const SizedBox(height: 14), action]);
                    }
                    return Row(children: [Expanded(child: header), const SizedBox(width: 14), action]);
                  },
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              _vendorTable(rows, vendorId),
              if (vendorId <= 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 16),
                  child: Text(
                    'These products have no vendor assigned, so CounterIQ can recommend quantity but cannot prepare a vendor purchase for them.',
                    style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vendorTable(List<Map<String, dynamic>> rows, int vendorId) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 1080 ? 1080.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  color: AppTheme.surfaceSoft,
                  child: const Row(
                    children: [
                      SizedBox(width: 42),
                      Expanded(flex: 30, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 9, child: Text('On Hand', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 10, child: Text('Velocity / Day', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 9, child: Text('Days Cover', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 10, child: Text('Reorder Point', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 13, child: Text('Suggested', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 11, child: Text('Est. Cost', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      Expanded(flex: 11, child: Text('Confidence', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                      SizedBox(width: 34),
                    ],
                  ),
                ),
                ...rows.map((row) => _row(row, canSelect: vendorId > 0)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> row, {required bool canSelect}) {
    final productId = (row['product_id'] as num?)?.toInt() ?? 0;
    final selected = _selectedProductIds.contains(productId);
    final package = asMap(row['suggested_packages']);
    final daysCover = row['days_of_cover'];
    final suggestedText = package.isNotEmpty
        ? '${package['count']} ${(package['short_name']?.toString().trim().isNotEmpty == true ? package['short_name'] : package['name'])}\n${qty(row['suggested_qty'])} units'
        : '${qty(row['suggested_qty'])} units';

    return InkWell(
      onTap: () => _showWhyQuantity(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Checkbox(
                value: selected,
                onChanged: canSelect && row['needs_reorder'] == true
                    ? (value) {
                        setState(() {
                          if (value == true) {
                            _selectedProductIds.add(productId);
                          } else {
                            _selectedProductIds.remove(productId);
                          }
                        });
                      }
                    : null,
              ),
            ),
            Expanded(
              flex: 30,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['name']?.toString() ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 7,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if ((row['sku']?.toString() ?? '').trim().isNotEmpty)
                              Text('SKU ${row['sku']}', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                            StockClassBadge(value: row['class']?.toString() ?? ''),
                            if ((row['trend']?.toString() ?? '').isNotEmpty)
                              Text('Trend ${titleCase(row['trend'].toString())}', style: const TextStyle(fontSize: 11.5, color: AppTheme.info, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 9, child: Text(qty(row['on_hand']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 10, child: Text((row['velocity_per_day'] as num?)?.toStringAsFixed(2) ?? '0.00', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 9, child: Text(daysCover == null ? '—' : (daysCover as num).toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 10, child: Text(qty(row['reorder_point']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 13,
              child: Text(
                suggestedText,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w900, color: row['needs_reorder'] == true ? AppTheme.primary : AppTheme.textMuted, height: 1.25),
              ),
            ),
            Expanded(flex: 11, child: Text(money(row['estimated_cost']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
            Expanded(flex: 11, child: Align(alignment: Alignment.center, child: ConfidenceBadge(basis: row['basis'], compact: true))),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _preparePurchase(Map<String, dynamic> group, List<Map<String, dynamic>> selectedRows) async {
    final vendor = asMap(group['vendor']);
    final vendorId = (vendor['id'] as num?)?.toInt() ?? 0;
    if (vendorId <= 0 || selectedRows.isEmpty) return;

    final items = <PurchasePrefillItem>[];
    for (final row in selectedRows) {
      final productId = (row['product_id'] as num?)?.toInt() ?? 0;
      final quantity = double.tryParse(row['suggested_qty']?.toString() ?? '') ?? 0;
      if (productId <= 0 || quantity <= 0) continue;
      final package = asMap(row['suggested_packages']);
      items.add(
        PurchasePrefillItem(
          productId: productId,
          quantity: quantity,
          packagingId: (package['id'] as num?)?.toInt(),
          packagingQuantity: package['count'] is num ? (package['count'] as num).toDouble() : null,
        ),
      );
    }
    if (items.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePurchaseScreen(
          initialVendor: <String, dynamic>{
            'id': vendorId,
            'name': vendor['name']?.toString() ?? 'Vendor',
          },
          initialItems: items,
          preparedFromIntelligence: true,
        ),
      ),
    );
    if (mounted) await _load(refresh: true);
  }

  Future<void> _showWhyQuantity(Map<String, dynamic> row) async {
    final vendor = asMap(row['vendor']);
    final package = asMap(row['suggested_packages']);
    final season = asMap(row['season']);
    final rawVelocity = (row['velocity_per_day'] as num?)?.toDouble() ?? 0;
    final effectiveVelocity = (row['effective_velocity_per_day'] as num?)?.toDouble() ?? rawVelocity;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 900,
          height: 720,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.calculate_outlined, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        const Text('Why CounterIQ suggests this purchase quantity', style: TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    _detailBox(
                      title: 'Recommendation',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _detailMetric('Current on hand', qty(row['on_hand'])),
                          _detailMetric('Reorder point', qty(row['reorder_point'])),
                          _detailMetric('Target stock', qty(row['target_stock'])),
                          _detailMetric('Raw suggestion', qty(row['raw_suggested_qty'])),
                          _detailMetric('Final suggestion', qty(row['suggested_qty']), color: AppTheme.primary),
                          _detailMetric('Estimated cost', money(row['estimated_cost'])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _detailBox(
                      title: 'How the target was calculated',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _formulaLine('Measured velocity', '${rawVelocity.toStringAsFixed(2)} units/day'),
                          if ((effectiveVelocity - rawVelocity).abs() > .0001)
                            _formulaLine('Season-adjusted velocity', '${effectiveVelocity.toStringAsFixed(2)} units/day'),
                          _formulaLine('Vendor lead time', '${vendor['lead_time_days'] ?? '—'} days • ${_leadSourceLabel(vendor['lead_time_source']?.toString())}'),
                          _formulaLine('Demand during lead time', '${qty(row['lead_time_demand'])} units'),
                          _formulaLine('Safety stock', '${qty(row['safety_stock'])} units • ${titleCase(row['safety_stock_method']?.toString() ?? 'unknown')}'),
                          _formulaLine('Review period demand', '${qty(row['review_demand'])} units over ${row['review_period_days'] ?? 0} days'),
                          const Divider(height: 22, color: AppTheme.border),
                          _formulaLine('Target stock', '${qty(row['target_stock'])} units', emphasized: true),
                          _formulaLine('Minus current on hand', '- ${qty(row['on_hand'])} units'),
                          _formulaLine('Raw suggested quantity', '${qty(row['raw_suggested_qty'])} units', emphasized: true),
                        ],
                      ),
                    ),
                    if (package.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _detailBox(
                        title: 'Packaging rounding',
                        child: Text(
                          'The raw requirement was rounded up to ${package['count']} ${(package['short_name']?.toString().trim().isNotEmpty == true ? package['short_name'] : package['name'])}. '
                          'Each package contains ${qty(package['base_quantity'])} base units, giving a final suggestion of ${qty(row['suggested_qty'])} units.',
                          style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
                        ),
                      ),
                    ],
                    if (season.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _detailBox(
                        title: 'Season context',
                        child: Text(
                          '${season['name']} is ${titleCase(season['state']?.toString() ?? '')}. The measured season uplift is ${(season['uplift'] as num?)?.toStringAsFixed(2) ?? '1.00'}× based on ${season['prior_occurrences'] ?? 0} prior occurrences. The calendar explains why; your own sales history supplies the uplift.',
                          style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
                        ),
                      ),
                    ],
                    if ((row['estimated_stockout_days'] as num? ?? 0) > 0) ...[
                      const SizedBox(height: 14),
                      IntelligenceInfoBanner(
                        icon: Icons.warning_amber_rounded,
                        title: 'Demand may be understated',
                        message: 'CounterIQ reconstructed approximately ${row['estimated_stockout_days']} stockout days. Selling velocity can look artificially low when there was no stock available to sell.',
                        color: AppTheme.warning,
                      ),
                    ],
                    const SizedBox(height: 14),
                    _detailBox(
                      title: 'Evidence confidence',
                      child: Row(
                        children: [
                          ConfidenceBadge(basis: row['basis']),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Confidence describes how much history supports the demand estimate. It does not prevent you from reviewing the current-stock arithmetic.', style: TextStyle(color: AppTheme.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ProductVelocitySheet(
                          productId: (row['product_id'] as num).toInt(),
                          productName: row['name']?.toString() ?? 'Product',
                        ),
                      );
                    },
                    icon: const Icon(Icons.insights_outlined),
                    label: const Text('View velocity detail'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailBox({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _detailMetric(String label, String value, {Color? color}) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color ?? AppTheme.navy)),
        ],
      ),
    );
  }

  Widget _formulaLine(String label, String value, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: emphasized ? AppTheme.navy : AppTheme.textMuted, fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600))),
          const SizedBox(width: 12),
          Text(value, style: TextStyle(fontWeight: emphasized ? FontWeight.w900 : FontWeight.w800, color: emphasized ? AppTheme.primary : AppTheme.navy)),
        ],
      ),
    );
  }

  String _leadSourceLabel(String? source) {
    switch ((source ?? '').toLowerCase()) {
      case 'configured':
        return 'Vendor configured';
      default:
        return 'Branch default';
    }
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}
