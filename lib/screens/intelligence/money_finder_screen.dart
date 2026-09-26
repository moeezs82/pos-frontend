import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MoneyFinderScreen extends StatefulWidget {
  const MoneyFinderScreen({super.key});

  @override
  State<MoneyFinderScreen> createState() => _MoneyFinderScreenState();
}

class _MoneyFinderScreenState extends State<MoneyFinderScreen> {
  bool _didInitialLoad = false;
  IntelligenceService? _service;
  final Map<int, IntelligenceEnvelope> _results = <int, IntelligenceEnvelope>{};
  final Map<int, Object> _errors = <int, Object>{};
  final Set<int> _loading = <int>{};

  String _groupBy = 'product';
  String _actor = 'cashier';
  String _marginSearch = '';
  String _discountSearch = '';
  String _repricingSearch = '';
  String _deadStockSearch = '';

  IntelligenceService _api() => _service ??= IntelligenceService(token: context.read<AuthProvider>().token!);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    final available = _availableTabs(context.read<AuthProvider>());
    if (available.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(available.first));
    }
  }

  List<int> _availableTabs(AuthProvider auth) => <int>[
        if (auth.hasPermission('view-margin-intelligence')) 0,
        if (auth.hasPermission('view-staff-intelligence')) 1,
        if (auth.hasPermission('view-margin-intelligence')) 2,
        if (auth.hasPermission('view-margin-intelligence')) 3,
      ];

  String _tabLabel(int index) {
    switch (index) {
      case 0:
        return 'Margin Leaks';
      case 1:
        return 'Discount Observations';
      case 2:
        return 'Repricing Alerts';
      default:
        return 'Dead Stock';
    }
  }

  Future<void> _load(int index, {bool forceRefresh = false}) async {
    if (_loading.contains(index)) return;
    if (_results.containsKey(index) && !forceRefresh) return;
    setState(() {
      _loading.add(index);
      _errors.remove(index);
    });
    try {
      if (forceRefresh) await _api().refresh();
      final IntelligenceEnvelope result;
      switch (index) {
        case 0:
          result = await _api().marginLeaks(groupBy: _groupBy);
          break;
        case 1:
          result = await _api().discountAnomalies(actor: _actor);
          break;
        case 2:
          result = await _api().repricingAlerts();
          break;
        default:
          result = await _api().deadStock();
      }
      if (mounted) {
        setState(() {
          _results[index] = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errors[index] = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading.remove(index);
        });
      }
    }
  }

  Future<void> _forceReload(int tab) async {
    setState(() => _results.remove(tab));
    await _load(tab, forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final available = _availableTabs(auth);
    if (available.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Money Finder')),
        body: const Center(child: Text('You do not have access to Money Finder features.')),
      );
    }

    return DefaultTabController(
      length: available.length,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('Money Finder'),
          bottom: TabBar(
            isScrollable: true,
            onTap: (index) => _load(available[index]),
            tabs: [for (final tab in available) Tab(text: _tabLabel(tab))],
          ),
        ),
        body: TabBarView(
          children: [for (final tab in available) _buildTab(tab)],
        ),
      ),
    );
  }

  Widget _buildTab(int tab) {
    if (_errors.containsKey(tab)) {
      return IntelligenceError(error: _errors[tab]!, onRetry: () => _load(tab, forceRefresh: true));
    }
    if (!_results.containsKey(tab)) {
      if (!_loading.contains(tab)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load(tab));
      }
      return const Center(child: CircularProgressIndicator());
    }

    final envelope = _results[tab]!;
    switch (tab) {
      case 0:
        return _marginView(envelope);
      case 1:
        return _discountView(envelope);
      case 2:
        return _repricingView(envelope);
      default:
        return _deadStockView(envelope);
    }
  }

  Widget _page({
    required int tab,
    required IntelligenceEnvelope envelope,
    required String title,
    required String subtitle,
    required Widget body,
  }) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        IntelligencePageHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 14),
        IntelligenceMetaBar(
          computedAt: envelope.computedAt,
          stale: envelope.stale,
          refreshing: _loading.contains(tab),
          onRefresh: () => _forceReload(tab),
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }

  Widget _marginView(IntelligenceEnvelope envelope) {
    final result = asMap(envelope.result);
    final totals = asMap(result['totals']);
    final rows = asMapList(result['rows']);
    final visibleRows = rows.where((row) {
      final q = _marginSearch.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (row['group_label']?.toString() ?? '').toLowerCase().contains(q) ||
          (row['group_key']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);

    return _page(
      tab: 0,
      envelope: envelope,
      title: 'Margin Leaks',
      subtitle: 'Find products sold below cost or below your minimum margin floor.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF6FAFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD8E8FF)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What this means', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text(
                        'This report shows products or groups where completed sales slipped below cost or below your minimum margin threshold. It helps you review pricing, discounting or staff behaviour before the leakage grows.',
                        style: TextStyle(color: AppTheme.textMuted, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _summaryGrid(
            children: [
              _summaryCard(
                icon: Icons.warning_amber_rounded,
                iconColor: AppTheme.danger,
                title: 'Potential recoverable margin',
                value: money(totals['recoverable']),
                caption: 'Built from medium and high confidence rows.',
              ),
              _summaryCard(
                icon: Icons.inventory_2_outlined,
                iconColor: AppTheme.info,
                title: 'Groups with issues',
                value: '${rows.length}',
                caption: 'Current result set for the selected grouping.',
              ),
              _summaryCard(
                icon: Icons.format_list_numbered_rounded,
                iconColor: AppTheme.warning,
                title: 'Leak sale lines',
                value: '${totals['lines_flagged'] ?? 0}',
                caption: 'Flagged below-cost or below-floor lines.',
              ),
              _summaryCard(
                icon: Icons.query_stats_rounded,
                iconColor: AppTheme.purple,
                title: 'Average margin (flagged set)',
                value: _averageMargin(rows),
                caption: 'Across the rows currently shown.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Review filters', subtitle: 'Group the result set differently or search within the current view.'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 250,
                      child: DropdownButtonFormField<String>(
                        value: _groupBy,
                        decoration: const InputDecoration(labelText: 'Group results by'),
                        items: const [
                          DropdownMenuItem(value: 'product', child: Text('Product')),
                          DropdownMenuItem(value: 'customer', child: Text('Customer')),
                          DropdownMenuItem(value: 'category', child: Text('Category')),
                          DropdownMenuItem(value: 'brand', child: Text('Brand')),
                          DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                          DropdownMenuItem(value: 'area', child: Text('Area')),
                          DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                          DropdownMenuItem(value: 'salesman', child: Text('Salesman')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          final auth = context.read<AuthProvider>();
                          if ((value == 'cashier' || value == 'salesman') && !auth.hasPermission('view-staff-intelligence')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Staff grouping requires access to staff intelligence.')),
                            );
                            return;
                          }
                          setState(() {
                            _groupBy = value;
                            _results.remove(0);
                          });
                          _load(0);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        onChanged: (value) => setState(() => _marginSearch = value),
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Product, vendor, category or area',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No margin leaks found',
                    subtitle: 'Nothing in this result set is currently breaching your margin rules for the selected period.',
                    icon: Icons.check_circle_outline_rounded,
                  )
                : _buildMarginTable(visibleRows),
            side: _buildConfidencePanel(),
          ),
          if ((totals['informal_return_lines'] ?? 0) != 0) ...[
            const SizedBox(height: 12),
            IntelligenceInfoBanner(
              icon: Icons.info_outline_rounded,
              title: 'Return disclosure',
              message:
                  'Legacy negative sale lines are disclosed separately: ${totals['informal_return_lines']} lines / ${money(totals['informal_return_value'])}. They are not automatically assumed to be properly linked returns.',
              color: AppTheme.warning,
            ),
          ],
        ],
      ),
    );
  }

  Widget _discountView(IntelligenceEnvelope envelope) {
    final result = asMap(envelope.result);
    final rows = asMapList(result['rows']);
    final visibleRows = rows.where((row) {
      final q = _discountSearch.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (row['actor_name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
    final qualifyingActors = result['qualifying_actors'] ?? rows.length;
    final baselineRate = double.tryParse(result['baseline_rate']?.toString() ?? '');
    double? biggestDiff;
    int outOfShiftTotal = 0;
    for (final row in rows) {
      final rate = double.tryParse(row['discount_rate']?.toString() ?? '');
      if (rate != null && baselineRate != null) {
        final diff = rate - baselineRate;
        if (biggestDiff == null || diff.abs() > biggestDiff.abs()) biggestDiff = diff;
      }
      final out = asMap(row['out_of_shift']);
      outOfShiftTotal += (out['no_shift_linked'] as num?)?.toInt() ?? 0;
      outOfShiftTotal += (out['outside_window'] as num?)?.toInt() ?? 0;
    }
    final highConfidence = rows.where((row) => confidenceLevel(row['comparison_basis']) == 'high').length;

    return _page(
      tab: 1,
      envelope: envelope,
      title: 'Discount Observations',
      subtitle: 'Compare discount behaviour against the branch baseline without labelling normal business activity as suspicious.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.percent_rounded,
            color: AppTheme.purple,
            title: 'What this means',
            message:
                'This report shows how each ${_actor == 'salesman' ? 'salesperson' : 'cashier'} discounts compared with the branch baseline. A difference is an observation only; promotions, wholesale customers and approved discounts can all explain it.',
          ),
          const SizedBox(height: 18),
          _summaryGrid(
            children: [
              _summaryCard(
                icon: Icons.percent_rounded,
                iconColor: AppTheme.purple,
                title: 'Branch average discount',
                value: percent(result['baseline_rate']),
                caption: 'Reference rate used for branch comparison.',
              ),
              _summaryCard(
                icon: Icons.groups_rounded,
                iconColor: AppTheme.info,
                title: 'Actors reviewed',
                value: '$qualifyingActors',
                caption: '${_actor == 'salesman' ? 'Salespeople' : 'Cashiers'} with enough activity for review.',
              ),
              _summaryCard(
                icon: Icons.compare_arrows_rounded,
                iconColor: biggestDiff == null ? AppTheme.textMuted : AppTheme.warning,
                title: 'Largest gap vs branch',
                value: biggestDiff == null ? '—' : percent(biggestDiff, signed: true),
                caption: biggestDiff == null ? 'Baseline still forming.' : 'Largest observed difference from branch average.',
              ),
              _summaryCard(
                icon: Icons.schedule_rounded,
                iconColor: AppTheme.warning,
                title: 'Out-of-shift events',
                value: '$outOfShiftTotal',
                caption: 'Discounted sales without a normal linked shift window.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Review filters', subtitle: 'Choose the staff role to compare and search within the current result set.'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 250,
                      child: DropdownButtonFormField<String>(
                        value: _actor,
                        decoration: const InputDecoration(labelText: 'Compare'),
                        items: const [
                          DropdownMenuItem(value: 'cashier', child: Text('Cashiers')),
                          DropdownMenuItem(value: 'salesman', child: Text('Salespeople')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _actor = value;
                            _results.remove(1);
                          });
                          _load(1);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        onChanged: (value) => setState(() => _discountSearch = value),
                        decoration: InputDecoration(
                          labelText: 'Search',
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: _actor == 'cashier' ? 'Cashier name' : 'Salesperson name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Minimum branch-baseline sample: ${result['min_sample_invoices'] ?? 20} invoices • high-confidence comparisons: $highConfidence',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No discount comparison yet',
                    subtitle: 'CounterIQ needs more discount activity before it can compare behaviour against the branch baseline.',
                    icon: Icons.percent_rounded,
                  )
                : _buildDiscountTable(visibleRows, result),
            side: _explanationPanel(
              title: 'How to read this',
              note: 'A higher discount rate is not wrongdoing. Use the detail view to understand the measured evidence and business context before taking action.',
              items: const [
                _GuideItem('Measured rate', 'The actor’s own recorded average discount across invoices.', AppTheme.info),
                _GuideItem('Difference vs branch', 'How far the measured rate sits above or below the branch average.', AppTheme.purple),
                _GuideItem('Comparison confidence', 'Whether enough comparable branch activity exists for the statistical comparison to be meaningful.', AppTheme.success),
                _GuideItem('Out-of-shift context', 'Discounted sales that were not inside a normal linked shift window.', AppTheme.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _repricingView(IntelligenceEnvelope envelope) {
    final result = asMap(envelope.result);
    final rows = asMapList(result['rows']);
    final visibleRows = rows.where((row) {
      final q = _repricingSearch.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (row['name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
    final belowCost = rows.where((r) => r['flag'] == 'below_cost').length;
    final risingCost = rows.where((r) {
      final trend = r['purchase_price_trend_pct'];
      final value = trend is num ? trend.toDouble() : double.tryParse(trend?.toString() ?? '');
      return value != null && value > 0;
    }).length;

    return _page(
      tab: 2,
      envelope: envelope,
      title: 'Repricing Alerts',
      subtitle: 'Identify products whose current selling price no longer clears your target margin.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.price_change_outlined,
            color: AppTheme.info,
            title: 'What this means',
            message:
                'CounterIQ compares current average cost with the current selling price and your target margin. Suggestions are advisory only; no product price is changed from this screen.',
          ),
          const SizedBox(height: 18),
          _summaryGrid(
            children: [
              _summaryCard(icon: Icons.inventory_2_outlined, iconColor: AppTheme.info, title: 'Products to review', value: '${rows.length}', caption: 'Items currently on the repricing watchlist.'),
              _summaryCard(icon: Icons.trending_down_rounded, iconColor: AppTheme.danger, title: 'Below cost', value: '$belowCost', caption: 'Urgent products currently selling below average cost.'),
              _summaryCard(icon: Icons.show_chart_rounded, iconColor: AppTheme.warning, title: 'Below target margin', value: '${rows.length - belowCost}', caption: 'Still profitable, but below your configured target margin.'),
              _summaryCard(icon: Icons.trending_up_rounded, iconColor: AppTheme.purple, title: 'Rising purchase cost', value: '$risingCost', caption: 'Rows where recent purchase-price trend is positive.'),
            ],
          ),
          const SizedBox(height: 18),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Review filters', subtitle: 'Search within the current repricing watchlist.'),
                const SizedBox(height: 14),
                SizedBox(
                  width: 340,
                  child: TextField(
                    onChanged: (value) => setState(() => _repricingSearch = value),
                    decoration: const InputDecoration(
                      labelText: 'Search product',
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Product name',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No repricing alerts',
                    subtitle: 'Current selling prices are clearing the configured target margin.',
                    icon: Icons.check_circle_outline_rounded,
                  )
                : _buildRepricingTable(visibleRows),
            side: _explanationPanel(
              title: 'How to read alerts',
              note: 'Suggested price is a review aid only. CounterIQ never writes a new selling price from this screen.',
              items: const [
                _GuideItem('Below cost', 'Current selling price is lower than the current average cost.', AppTheme.danger),
                _GuideItem('Below target margin', 'The item is profitable, but the price no longer clears your configured target margin.', AppTheme.warning),
                _GuideItem('Purchase cost trend', 'Shows recent movement in weighted purchase price, not historical average-cost movement.', AppTheme.purple),
                _GuideItem('Suggested price', 'The advisory price required to clear the configured target margin using current average cost.', AppTheme.info),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deadStockView(IntelligenceEnvelope envelope) {
    final result = asMap(envelope.result);
    final rows = asMapList(result['rows']);
    final visibleRows = rows.where((row) {
      final q = _deadStockSearch.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (row['name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
    final neverSold = rows.where((r) => r['never_sold'] == true).length;
    int longestIdle = 0;
    for (final row in rows) {
      final idle = (row['days_idle'] as num?)?.toInt() ?? 0;
      if (idle > longestIdle) longestIdle = idle;
    }

    return _page(
      tab: 3,
      envelope: envelope,
      title: 'Dead Stock',
      subtitle: 'See inventory that is sitting still and how much working capital is tied up in it.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.inventory_2_outlined,
            color: AppTheme.warning,
            title: 'What this means',
            message:
                'This report highlights positive on-hand stock that has not sold for long enough to cross your configured dead-stock rule. Never-sold products are kept separate from ordinary idle-day buckets.',
          ),
          const SizedBox(height: 18),
          _summaryGrid(
            children: [
              _summaryCard(icon: Icons.lock_clock_outlined, iconColor: AppTheme.danger, title: 'Locked capital', value: money(result['locked_capital_total']), caption: 'Estimated from on-hand quantity × average cost.'),
              _summaryCard(icon: Icons.inventory_2_outlined, iconColor: AppTheme.warning, title: 'Products flagged', value: '${rows.length}', caption: 'Current dead-stock result set.'),
              _summaryCard(icon: Icons.block_rounded, iconColor: AppTheme.textMuted, title: 'Never sold', value: '$neverSold', caption: 'On-hand products with no recorded sale history.'),
              _summaryCard(icon: Icons.timelapse_rounded, iconColor: AppTheme.purple, title: 'Longest idle', value: longestIdle == 0 ? '—' : '$longestIdle days', caption: 'Longest measured idle period in the current result set.'),
            ],
          ),
          const SizedBox(height: 18),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Review filters', subtitle: 'Search within the current dead-stock result set.'),
                const SizedBox(height: 14),
                SizedBox(
                  width: 340,
                  child: TextField(
                    onChanged: (value) => setState(() => _deadStockSearch = value),
                    decoration: const InputDecoration(
                      labelText: 'Search product',
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Product name',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No dead stock identified',
                    subtitle: 'Nothing on hand is currently breaching your dead-stock threshold.',
                    icon: Icons.check_circle_outline_rounded,
                  )
                : _buildDeadStockTable(visibleRows),
            side: _explanationPanel(
              title: 'How to read this',
              note: 'Dead stock is a review signal, not an automatic markdown or disposal instruction.',
              items: const [
                _GuideItem('Never sold', 'The item is currently on hand but has no recorded sale movement.', AppTheme.textMuted),
                _GuideItem('Idle days', 'Whole business-calendar days since the last recorded sale movement.', AppTheme.warning),
                _GuideItem('Locked capital', 'Current on-hand quantity multiplied by average cost.', AppTheme.danger),
                _GuideItem('Bucket', 'Groups products by idle age so the oldest stock is easy to identify.', AppTheme.purple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarginTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1080 ? 1080.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 34, child: Text('Product', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 10, child: Text('Revenue', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 10, child: Text('Margin', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 8, child: Text('Margin %', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 9, child: Text('Sale Lines', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 18, child: Text('Issue Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 11, child: Text('Recoverable', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    Expanded(flex: 10, child: Text('Confidence', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                    SizedBox(width: 28),
                  ],
                ),
              ),
                  ...rows.map(_marginRowCard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfidencePanel() {
    return _explanationPanel(
      title: 'Confidence level',
      items: const [
        _GuideItem('Collecting data', 'Not enough history yet (less than 14 days or fewer than 5 selling days). Value is shown for visibility and may still move.', AppTheme.textMuted),
        _GuideItem('Low', 'Some history is available (at least 14 days and 5 selling days), but not yet enough for a stable estimate.', AppTheme.warning),
        _GuideItem('Medium', 'Good data coverage (around 60 days and 20 observed selling days). Suitable for the recoverable headline.', AppTheme.info),
        _GuideItem('High', 'Strong data coverage (around 180 days and 60 observed selling days). These are the most reliable estimates.', AppTheme.success),
      ],
    );
  }

  String _averageMargin(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0.0%';
    double sum = 0;
    int count = 0;
    for (final row in rows) {
      final value = row['margin_pct'];
      final v = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
      if (v == null) continue;
      sum += v;
      count++;
    }
    if (count == 0) return '0.0%';
    final avg = sum / count;
    return percent(avg);
  }

  Widget _marginRowCard(Map<String, dynamic> row) {
    final flags = (row['flags'] is List)
        ? (row['flags'] as List).map((e) => e.toString()).toSet().toList()
        : <String>[];
    final usableEstimate = confidenceHasUsableEstimate(row['basis']);
    final marginValue = double.tryParse(row['margin']?.toString() ?? '') ?? 0;

    return InkWell(
      onTap: () => _showMarginDetail(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 34,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['group_label']?.toString() ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _groupSubtext(row),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 10, child: Text(money(row['revenue']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 10,
              child: Text(
                money(row['margin']),
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: marginValue < 0 ? AppTheme.danger : AppTheme.navy),
              ),
            ),
            Expanded(flex: 8, child: Text(percent(row['margin_pct']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 9, child: Text('${row['lines'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 18,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: flags.map((flag) => _compactIssueChip(flag)).toList(),
              ),
            ),
            Expanded(
              flex: 11,
              child: Text(
                usableEstimate ? money(row['recoverable']) : '—',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w900, color: usableEstimate ? AppTheme.warning : AppTheme.textMuted),
              ),
            ),
            Expanded(
              flex: 10,
              child: Align(alignment: Alignment.center, child: ConfidenceBadge(basis: row['basis'], compact: true)),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  String _groupSubtext(Map<String, dynamic> row) {
    final groupBy = _groupBy == 'product' ? 'SKU/Group' : 'Group key';
    final key = row['group_key']?.toString() ?? '—';
    return '$groupBy: $key • Click to view contributing line items';
  }

  Widget _compactIssueChip(String flag) {
    late final String label;
    late final Color color;
    if (flag == 'below_cost') {
      label = 'Below cost';
      color = AppTheme.danger;
    } else if (flag == 'below_floor') {
      label = 'Below floor';
      color = AppTheme.warning;
    } else {
      label = flag.replaceAll('_', ' ');
      color = AppTheme.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _buildDiscountTable(List<Map<String, dynamic>> rows, Map<String, dynamic> result) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1120 ? 1120.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                    child: const Row(
                      children: [
                        Expanded(flex: 28, child: Text('Staff', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 12, child: Text('Gross Sales', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Discount', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Avg %', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Branch %', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Difference', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 9, child: Text('Invoices', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Out of Shift', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 14, child: Text('Confidence', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        SizedBox(width: 28),
                      ],
                    ),
                  ),
                  ...rows.map((row) => _discountRowCard(row, result)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _discountRowCard(Map<String, dynamic> row, Map<String, dynamic> result) {
    final discountRate = double.tryParse(row['discount_rate']?.toString() ?? '');
    final baselineRate = double.tryParse(result['baseline_rate']?.toString() ?? '');
    final difference = discountRate != null && baselineRate != null ? discountRate - baselineRate : null;
    final out = asMap(row['out_of_shift']);
    final outCount = ((out['no_shift_linked'] as num?)?.toInt() ?? 0) + ((out['outside_window'] as num?)?.toInt() ?? 0);

    return InkWell(
      onTap: () => _showDiscountDetail(row, result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            Expanded(
              flex: 28,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppTheme.purple.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.person_outline_rounded, color: AppTheme.purple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['actor_name']?.toString() ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('ID ${row['actor_id'] ?? '—'} • Click for explanation', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 12, child: Text(money(row['gross']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 11, child: Text(money(row['discount']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 11, child: Text(percent(row['discount_rate']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(flex: 11, child: Text(percent(result['baseline_rate']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 11,
              child: Text(
                difference == null ? '—' : percent(difference, signed: true),
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w900, color: difference == null ? AppTheme.textMuted : (difference > 0 ? AppTheme.warning : AppTheme.success)),
              ),
            ),
            Expanded(flex: 9, child: Text('${row['invoice_count'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(
              flex: 11,
              child: Text(
                '$outCount',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, color: outCount > 0 ? AppTheme.warning : AppTheme.navy),
              ),
            ),
            Expanded(flex: 14, child: Align(alignment: Alignment.center, child: ConfidenceBadge(basis: row['comparison_basis'], compact: true))),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildRepricingTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1040 ? 1040.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                    child: const Row(
                      children: [
                        Expanded(flex: 32, child: Text('Product', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Avg Cost', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Price', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 10, child: Text('Margin %', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Cost Trend', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 17, child: Text('Reason', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 12, child: Text('Suggested', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 13, child: Text('Confidence', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        SizedBox(width: 28),
                      ],
                    ),
                  ),
                  ...rows.map(_repricingRowCard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _repricingRowCard(Map<String, dynamic> row) {
    final belowCost = row['flag'] == 'below_cost';
    final trendRaw = row['purchase_price_trend_pct'];
    final trend = trendRaw is num ? trendRaw.toDouble() : double.tryParse(trendRaw?.toString() ?? '');
    return InkWell(
      onTap: () => _showRepricingDetail(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            Expanded(
              flex: 32,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppTheme.info.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.inventory_2_outlined, color: AppTheme.info, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['name']?.toString() ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('Product ID ${row['product_id'] ?? '—'} • Click for explanation', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 11, child: Text(money(row['avg_cost']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 11, child: Text(money(row['price']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 10, child: Text(percent(row['implied_margin_pct']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(
              flex: 11,
              child: Text(
                trend == null ? '—' : percent(trend, signed: true),
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: trend == null ? AppTheme.textMuted : (trend > 0 ? AppTheme.warning : AppTheme.success)),
              ),
            ),
            Expanded(
              flex: 17,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IssueChip(label: belowCost ? 'Below cost' : 'Below target margin', color: belowCost ? AppTheme.danger : AppTheme.warning),
              ),
            ),
            Expanded(flex: 12, child: Text(money(row['suggested_price']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primary))),
            Expanded(flex: 13, child: Align(alignment: Alignment.center, child: ConfidenceBadge(basis: row['basis'], compact: true))),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildDeadStockTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1040 ? 1040.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                    child: const Row(
                      children: [
                        Expanded(flex: 32, child: Text('Product', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 10, child: Text('On Hand', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Avg Cost', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 14, child: Text('Last Sold', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 10, child: Text('Idle', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 11, child: Text('Bucket', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 13, child: Text('Locked Capital', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        Expanded(flex: 13, child: Text('Confidence', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                        SizedBox(width: 28),
                      ],
                    ),
                  ),
                  ...rows.map(_deadStockRowCard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _deadStockRowCard(Map<String, dynamic> row) {
    final neverSold = row['never_sold'] == true;
    return InkWell(
      onTap: () => _showDeadStockDetail(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            Expanded(
              flex: 32,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppTheme.warning.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.inventory_2_outlined, color: AppTheme.warning, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['name']?.toString() ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('Product ID ${row['product_id'] ?? '—'} • Click for explanation', style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 10, child: Text(qty(row['quantity']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 11, child: Text(money(row['avg_cost']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 14, child: Text(neverSold ? 'Never sold' : (row['last_sold_at']?.toString() ?? '—'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(flex: 10, child: Text(neverSold ? '—' : '${row['days_idle'] ?? '—'} d', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(
              flex: 11,
              child: Align(
                alignment: Alignment.center,
                child: _bucketChip(row['bucket']?.toString() ?? 'unknown', neverSold: neverSold),
              ),
            ),
            Expanded(flex: 13, child: Text(money(row['locked_capital']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.warning))),
            Expanded(flex: 13, child: Align(alignment: Alignment.center, child: ConfidenceBadge(basis: row['basis'], compact: true))),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _bucketChip(String bucket, {required bool neverSold}) {
    final color = neverSold ? AppTheme.textMuted : AppTheme.warning;
    final label = neverSold ? 'Never sold' : titleCase(bucket.replaceAll('+', ' plus'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Future<void> _showMarginDetail(Map<String, dynamic> row) async {
    final groupKey = row['group_key']?.toString() ?? '';
    final title = row['group_label']?.toString() ?? 'Margin Leak Detail';
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 1080,
            height: 760,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: FutureBuilder<IntelligenceEnvelope>(
              future: _api().marginLeakDetail(groupKey: groupKey, groupBy: _groupBy),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 360,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return SizedBox(
                    height: 360,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 34),
                        const SizedBox(height: 12),
                        const Text('Unable to load contributing line items.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(snapshot.error?.toString() ?? 'Unknown error', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }

                final detail = asMap(snapshot.data!.result);
                final summary = asMap(detail['summary']);
                final items = asMapList(detail['line_items']);
                final flags = (summary['flags'] is List)
                    ? (summary['flags'] as List).map((e) => e.toString()).toList()
                    : <String>[];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              const Text(
                                'These are the contributing sale lines that caused this result to be flagged.',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _detailSummary(
                      title: 'Why this result is shown',
                      description: _marginConclusionText(summary, flags),
                      chips: flags.map((f) => _compactIssueChip(f)).toList(),
                    ),
                    const SizedBox(height: 14),
                    _detailStatGrid([
                      _detailStat('Revenue', money(summary['revenue'])),
                      _detailStat('Cost', money(summary['cost'])),
                      _detailStat('Margin', money(summary['margin'])),
                      _detailStat('Margin %', percent(summary['margin_pct'])),
                      _detailStat('Flagged line items', '${summary['line_items'] ?? items.length}'),
                      _detailStat('Potential recoverable', money(summary['recoverable'])),
                    ]),
                    const SizedBox(height: 18),
                    const Text('Contributing line items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final tableWidth = constraints.maxWidth < 980 ? 980.0 : constraints.maxWidth;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                height: constraints.maxHeight,
                                child: Column(
                                  children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(flex: 22, child: Text('Invoice', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 28, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 8, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 10, child: Text('Revenue', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 10, child: Text('Cost', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 10, child: Text('Margin', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 11, child: Text('Recoverable', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                      Expanded(flex: 21, child: Text('Reason', style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted))),
                                    ],
                                  ),
                                ),
                                if (items.isEmpty)
                                  const Expanded(
                                    child: Center(
                                      child: Text('No flagged line items found for this group.', style: TextStyle(color: AppTheme.textMuted)),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: items.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                                      itemBuilder: (context, index) {
                                        final item = items[index];
                                        final itemFlags = (item['flags'] is List)
                                            ? (item['flags'] as List).map((e) => e.toString()).toList()
                                            : <String>[];
                                        final lineMargin = double.tryParse(item['margin']?.toString() ?? '') ?? 0;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 22,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(item['invoice_no']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800)),
                                                    const SizedBox(height: 2),
                                                    Text(item['invoice_date']?.toString() ?? '—', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                                  ],
                                                ),
                                              ),
                                              Expanded(flex: 28, child: Text(item['product_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700))),
                                              Expanded(flex: 8, child: Text(item['quantity']?.toString() ?? '—', textAlign: TextAlign.right)),
                                              Expanded(flex: 10, child: Text(money(item['revenue']), textAlign: TextAlign.right)),
                                              Expanded(flex: 10, child: Text(money(item['cost']), textAlign: TextAlign.right)),
                                              Expanded(
                                                flex: 10,
                                                child: Text(
                                                  money(item['margin']),
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(fontWeight: FontWeight.w800, color: lineMargin < 0 ? AppTheme.danger : AppTheme.navy),
                                                ),
                                              ),
                                              Expanded(flex: 11, child: Text(money(item['recoverable']), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                                              Expanded(
                                                flex: 21,
                                                child: Wrap(
                                                  spacing: 6,
                                                  runSpacing: 6,
                                                  children: itemFlags.map((f) => _compactIssueChip(f)).toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
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
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDiscountDetail(Map<String, dynamic> row, Map<String, dynamic> result) async {
    final concentration = asMap(row['concentration']);
    final outOfShift = asMap(row['out_of_shift']);
    final baselineRate = double.tryParse(result['baseline_rate']?.toString() ?? '');
    final rate = double.tryParse(row['discount_rate']?.toString() ?? '');
    final diff = rate != null && baselineRate != null ? rate - baselineRate : null;
    final comparisonReady = confidenceLevel(row['comparison_basis']) != 'none' && baselineRate != null;

    await _showDetailDialog(
      title: row['actor_name']?.toString() ?? 'Discount Observation',
      subtitle: 'Why this discount observation is shown',
      leadingColor: AppTheme.purple,
      body: [
        _detailSummary(
          title: 'Conclusion',
          description: comparisonReady
              ? '${percent(row['discount_rate'])} average discount versus branch average ${percent(result['baseline_rate'])} across ${row['invoice_count'] ?? 0} invoices. This is presented as an observation only, not an accusation.'
              : 'CounterIQ can measure this person’s discount rate, but there is not yet enough evidence for a reliable branch-level comparison.',
        ),
        _detailStatGrid([
          _detailStat('Invoices', '${row['invoice_count'] ?? 0}'),
          _detailStat('Measured avg discount', percent(row['discount_rate'])),
          _detailStat('Branch avg discount', percent(result['baseline_rate'])),
          _detailStat('Difference', diff == null ? '—' : percent(diff, signed: true)),
          _detailStat('Discount amount', money(row['discount'])),
          _detailStat('Gross sales', money(row['gross'])),
        ]),
        _detailSection(
          title: 'Measured confidence vs comparison confidence',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [const Text('Measured rate: '), ConfidenceBadge(basis: row['rate_basis'])]),
                  Row(mainAxisSize: MainAxisSize.min, children: [const Text('Branch comparison: '), ConfidenceBadge(basis: row['comparison_basis'])]),
                ],
              ),
              const SizedBox(height: 10),
              _bullet('Measured rate confidence reflects the evidence behind this person’s own discount activity.'),
              _bullet('Comparison confidence reflects how safely that behaviour can be compared to the branch baseline.'),
            ],
          ),
        ),
        _detailSection(
          title: 'Supporting context',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill('No shift linked', '${outOfShift['no_shift_linked'] ?? 0}'),
              _statPill('Outside shift window', '${outOfShift['outside_window'] ?? 0}'),
              if (concentration.isNotEmpty) _statPill('Anonymous share', percent(concentration['anonymous_share'])),
              if (concentration.isNotEmpty) _statPill('Top 1 named share', percent(concentration['top_1_named_share'])),
              if (concentration.isNotEmpty) _statPill('Top 3 named share', percent(concentration['top_3_named_share'])),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showRepricingDetail(Map<String, dynamic> row) async {
    final belowCost = row['flag'] == 'below_cost';
    await _showDetailDialog(
      title: row['name']?.toString() ?? 'Repricing Alert',
      subtitle: 'Why this product needs a price review',
      leadingColor: belowCost ? AppTheme.danger : AppTheme.warning,
      body: [
        _detailSummary(
          title: 'Conclusion',
          description: belowCost
              ? 'The current selling price is below the average cost, so the product is currently selling below cost.'
              : 'The product is still profitable, but the current price no longer clears your configured target margin.',
          chips: [IssueChip(label: belowCost ? 'Below cost' : 'Below target margin', color: belowCost ? AppTheme.danger : AppTheme.warning)],
        ),
        _detailStatGrid([
          _detailStat('Average cost', money(row['avg_cost'])),
          _detailStat('Current price', money(row['price'])),
          _detailStat('Current margin', percent(row['implied_margin_pct'])),
          _detailStat('Suggested price', money(row['suggested_price'])),
          if (row['purchase_price_trend_pct'] != null) _detailStat('Purchase cost trend', percent(row['purchase_price_trend_pct'], signed: true)),
        ]),
        _detailSection(
          title: 'How CounterIQ reached this conclusion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet('Average cost was compared against the current selling price.'),
              _bullet('The implied margin was then tested against your configured target margin.'),
              _bullet('The suggested price is advisory only. CounterIQ does not change the price automatically.'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDeadStockDetail(Map<String, dynamic> row) async {
    final neverSold = row['never_sold'] == true;
    await _showDetailDialog(
      title: row['name']?.toString() ?? 'Dead Stock Detail',
      subtitle: 'Why this product is classed as dead stock',
      leadingColor: AppTheme.warning,
      body: [
        _detailSummary(
          title: 'Conclusion',
          description: neverSold
              ? 'This product is on hand and has never recorded a sale, so the full quantity is currently treated as inactive stock.'
              : 'This product is on hand and has been idle long enough to cross your dead-stock rule.',
          chips: [IssueChip(label: neverSold ? 'Never sold' : 'Idle too long', color: AppTheme.warning)],
        ),
        _detailStatGrid([
          _detailStat('On hand', qty(row['quantity'])),
          _detailStat('Average cost', money(row['avg_cost'])),
          _detailStat('Locked capital', money(row['locked_capital'])),
          _detailStat('Bucket', titleCase(row['bucket']?.toString() ?? 'Unknown')),
          _detailStat(neverSold ? 'Status' : 'Days idle', neverSold ? 'Never sold' : '${row['days_idle'] ?? '—'}'),
        ]),
        _detailSection(
          title: 'How CounterIQ reached this conclusion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet('The product was checked for current on-hand quantity.'),
              _bullet(neverSold ? 'No sale history was found for this on-hand item.' : 'The product has had no movement for long enough to exceed the configured dead-stock days.'),
              _bullet('Locked capital is estimated from on-hand quantity multiplied by average cost.'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDetailDialog({
    required String title,
    required String subtitle,
    required Color leadingColor,
    required List<Widget> body,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: leadingColor.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                        child: Icon(Icons.analytics_outlined, color: leadingColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(subtitle, style: const TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.border),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(22),
                    itemBuilder: (_, index) => body[index],
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemCount: body.length,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _marginConclusionText(Map<String, dynamic> row, List<String> flags) {
    final label = row['group_label']?.toString() ?? 'This result';
    if (flags.contains('below_cost') && flags.contains('below_floor')) {
      return '$label is shown because reviewed sale activity sold below cost and also fell below your configured minimum margin floor.';
    }
    if (flags.contains('below_cost')) {
      return '$label is shown because reviewed sale activity sold below cost.';
    }
    return '$label is shown because reviewed sale activity fell below your configured minimum margin floor.';
  }

  Widget _heroIntro({required IconData icon, required Color color, required String title, required String message}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E8FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(message, style: const TextStyle(color: AppTheme.textMuted, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid({required List<Widget> children}) {
    return Wrap(spacing: 14, runSpacing: 14, children: children);
  }

  Widget _summaryCard({required IconData icon, required Color iconColor, required String title, required String value, required String caption}) {
    return Container(
      width: 270,
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: iconColor.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.35)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(caption, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }

  Widget _resultsPanel({required String title, required String subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: _BlockTitle(title: title, subtitle: subtitle),
          ),
          child,
        ],
      ),
    );
  }

  Widget _responsiveSplit({required Widget main, required Widget side}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: main),
              const SizedBox(width: 16),
              SizedBox(width: 330, child: side),
            ],
          );
        }
        return Column(
          children: [
            main,
            const SizedBox(height: 16),
            side,
          ],
        );
      },
    );
  }

  Widget _explanationPanel({required String title, required List<_GuideItem> items, String? note}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note, style: const TextStyle(color: AppTheme.textMuted, height: 1.4)),
          ],
          const SizedBox(height: 14),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: item.color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.insights_rounded, color: item.color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(item.description, style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _clickableRowCard({required Widget child, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 860) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child]);
              }
              return child;
            },
          ),
        ),
      ),
    );
  }

  Widget _statPill(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
      ),
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

  Widget _detailSummary({required String title, required String description, List<Widget>? chips}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(color: AppTheme.textMuted, height: 1.45)),
          if (chips != null && chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }

  Widget _detailSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _detailStatGrid(List<Widget> children) {
    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }

  Widget _detailStat(String label, String value) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 8, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.textMuted, height: 1.4))),
        ],
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _BlockTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
      ],
    );
  }
}

class _GuideItem {
  final String title;
  final String description;
  final Color color;
  const _GuideItem(this.title, this.description, this.color);
}

class _ClickHint extends StatelessWidget {
  const _ClickHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, size: 14, color: AppTheme.primary),
          SizedBox(width: 6),
          Text('Click for explanation', style: TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
