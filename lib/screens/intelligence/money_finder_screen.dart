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
      return (row['group_label']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);

    return _page(
      tab: 0,
      envelope: envelope,
      title: 'Margin Leaks',
      subtitle: 'See where selling activity eroded profit and click any result to understand the reason behind the conclusion.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.savings_outlined,
            color: AppTheme.danger,
            title: 'Where is money leaking?',
            message:
                'CounterIQ reviews completed sale lines and highlights groups that sold below cost or below your configured minimum margin floor. Click any result row to see the reasoning and evidence behind it.',
          ),
          const SizedBox(height: 16),
          _summaryGrid(
            children: [
              _summaryCard(
                icon: Icons.currency_exchange_rounded,
                iconColor: AppTheme.danger,
                title: 'Recoverable margin',
                value: money(totals['recoverable']),
                caption: 'Estimated from medium / high confidence rows only.',
              ),
              _summaryCard(
                icon: Icons.flag_outlined,
                iconColor: AppTheme.warning,
                title: 'Flagged sale lines',
                value: '${totals['lines_flagged'] ?? 0}',
                caption: 'Lines that breached below-cost or below-floor rules.',
              ),
              _summaryCard(
                icon: Icons.view_list_rounded,
                iconColor: AppTheme.info,
                title: 'Groups with issues',
                value: '${rows.length}',
                caption: 'Result groups in the current view.',
              ),
              _summaryCard(
                icon: Icons.help_outline_rounded,
                iconColor: AppTheme.textMuted,
                title: 'Excluded: missing cost',
                value: '${totals['lines_excluded_missing_cost'] ?? 0}',
                caption: 'Ignored because line cost was unavailable.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Review setup', subtitle: 'Change grouping or search the result set.'),
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
                          labelText: 'Search result',
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Product, customer, vendor or area',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tip: group by product or vendor to review pricing issues, or group by cashier / salesman when you want a staff-related view.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No margin leaks found',
                    subtitle: 'Nothing in this result set is currently breaching your margin rules for the selected period.',
                    icon: Icons.check_circle_outline_rounded,
                  )
                : _resultsPanel(
                    title: 'Results',
                    subtitle: 'Click any result row to see why it was flagged.',
                    child: Column(children: visibleRows.map(_marginRowCard).toList()),
                  ),
            side: _explanationPanel(
              title: 'Confidence guide',
              items: const [
                _GuideItem('Collecting data', 'Not enough history yet. The row is still shown for visibility, but the estimate can change materially.', AppTheme.textMuted),
                _GuideItem('Low', 'Some history is available. Good for review prompts, but still not fully stable.', AppTheme.warning),
                _GuideItem('Medium', 'Good data coverage. These rows contribute to the headline recoverable figure.', AppTheme.info),
                _GuideItem('High', 'Strong data coverage. These are the most reliable estimates in the report.', AppTheme.success),
              ],
            ),
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
    for (final row in rows) {
      final rate = double.tryParse(row['discount_rate']?.toString() ?? '');
      if (rate == null || baselineRate == null) continue;
      final diff = rate - baselineRate;
      if (biggestDiff == null || diff.abs() > biggestDiff.abs()) biggestDiff = diff;
    }
    final highConfidence = rows.where((row) => confidenceLevel(row['comparison_basis']) == 'high').length;

    return _page(
      tab: 1,
      envelope: envelope,
      title: 'Discount Observations',
      subtitle: 'Compare discount behaviour against the branch baseline in a professional, non-accusatory way.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.percent_rounded,
            color: AppTheme.purple,
            title: 'Who discounts differently from the branch average?',
            message:
                'These are observations, not accusations. CounterIQ shows measured discount behaviour and, where possible, compares it against the branch baseline. Click a row to see the reasoning in detail.',
          ),
          const SizedBox(height: 16),
          _summaryGrid(
            children: [
              _summaryCard(
                icon: Icons.analytics_outlined,
                iconColor: AppTheme.purple,
                title: 'Branch average discount',
                value: percent(result['baseline_rate']),
                caption: 'Average discount across the selected branch baseline.',
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
                iconColor: biggestDiff == null ? AppTheme.textMuted : (biggestDiff >= 0 ? AppTheme.danger : AppTheme.success),
                title: 'Strongest gap vs baseline',
                value: biggestDiff == null ? '—' : percent(biggestDiff, signed: true),
                caption: biggestDiff == null ? 'Baseline still forming.' : 'Largest observed difference from the branch average.',
              ),
              _summaryCard(
                icon: Icons.verified_rounded,
                iconColor: AppTheme.success,
                title: 'High-confidence observations',
                value: '$highConfidence',
                caption: 'Rows backed by strong comparison evidence.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _controlPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BlockTitle(title: 'Comparison setup', subtitle: 'Choose who to compare and search the result set.'),
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
                          labelText: 'Search result',
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: _actor == 'cashier' ? 'Cashier name' : 'Salesperson name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Minimum baseline sample: ${result['min_sample_invoices'] ?? 20} invoices • qualifying actors: ${result['qualifying_actors'] ?? 0}',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _responsiveSplit(
            main: visibleRows.isEmpty
                ? const IntelligenceEmptyState(
                    title: 'No discount comparison yet',
                    subtitle: 'CounterIQ needs discount activity before it can compare behaviour against the branch baseline.',
                    icon: Icons.percent_rounded,
                  )
                : _resultsPanel(
                    title: 'Observations',
                    subtitle: 'Click a row to see measured facts, comparison logic and supporting context.',
                    child: Column(children: visibleRows.map((row) => _discountRowCard(row, result)).toList()),
                  ),
            side: _explanationPanel(
              title: 'How to interpret this page',
              note:
                  'A higher rate can have legitimate reasons such as promotions, wholesale customers, approved discounts or product mix. Review business context before drawing any conclusion.',
              items: const [
                _GuideItem('Measured rate', 'The average discount directly observed from this actor’s recorded invoices.', AppTheme.info),
                _GuideItem('Branch comparison', 'A statistical comparison against the branch baseline, shown only when enough evidence exists.', AppTheme.purple),
                _GuideItem('Out-of-shift context', 'Shows whether discount activity happened without a normal linked shift window.', AppTheme.warning),
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

    return _page(
      tab: 2,
      envelope: envelope,
      title: 'Repricing Alerts',
      subtitle: 'Identify products whose current selling price no longer supports your target margin.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.price_change_outlined,
            color: AppTheme.info,
            title: 'Which products need a price review?',
            message:
                'This is advisory only. CounterIQ never changes a price from this screen. Click any row to see exactly why the alert exists and what suggested price would clear your current target margin.',
          ),
          const SizedBox(height: 16),
          _summaryGrid(
            children: [
              _summaryCard(icon: Icons.inventory_2_outlined, iconColor: AppTheme.info, title: 'Products to review', value: '${rows.length}', caption: 'Items currently on the repricing watchlist.'),
              _summaryCard(icon: Icons.trending_down_rounded, iconColor: AppTheme.danger, title: 'Below cost', value: '$belowCost', caption: 'Urgent items now selling below cost.'),
              _summaryCard(icon: Icons.show_chart_rounded, iconColor: AppTheme.warning, title: 'Below target margin', value: '${rows.length - belowCost}', caption: 'Profitable, but under the configured target margin.'),
            ],
          ),
          const SizedBox(height: 16),
          _controlPanel(
            child: SizedBox(
              width: 340,
              child: TextField(
                onChanged: (value) => setState(() => _repricingSearch = value),
                decoration: const InputDecoration(
                  labelText: 'Search product',
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Find a product in repricing alerts',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          visibleRows.isEmpty
              ? const IntelligenceEmptyState(
                  title: 'No repricing alerts',
                  subtitle: 'Current selling prices are clearing the configured target margin.',
                  icon: Icons.check_circle_outline_rounded,
                )
              : _resultsPanel(
                  title: 'Products needing review',
                  subtitle: 'Click a row to see why the price is being flagged.',
                  child: Column(children: visibleRows.map(_repricingRowCard).toList()),
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

    return _page(
      tab: 3,
      envelope: envelope,
      title: 'Dead Stock',
      subtitle: 'Highlight inventory that is sitting still so you can see where cash is locked up.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIntro(
            icon: Icons.inventory_2_outlined,
            color: AppTheme.warning,
            title: 'What stock is not moving?',
            message:
                'Dead stock shows inventory currently on hand that has not moved for long enough to cross your configured rule. Click a row to see why the item is being classed as dead stock.',
          ),
          const SizedBox(height: 16),
          _summaryGrid(
            children: [
              _summaryCard(icon: Icons.lock_clock_outlined, iconColor: AppTheme.danger, title: 'Locked capital', value: money(result['locked_capital_total']), caption: 'Estimated from on-hand quantity × average cost.'),
              _summaryCard(icon: Icons.inventory_2_outlined, iconColor: AppTheme.warning, title: 'Products flagged', value: '${rows.length}', caption: 'Products currently classed as dead stock.'),
              _summaryCard(icon: Icons.block_rounded, iconColor: AppTheme.textMuted, title: 'Never sold', value: '$neverSold', caption: 'On-hand products with no recorded sale history.'),
            ],
          ),
          const SizedBox(height: 16),
          _controlPanel(
            child: SizedBox(
              width: 340,
              child: TextField(
                onChanged: (value) => setState(() => _deadStockSearch = value),
                decoration: const InputDecoration(
                  labelText: 'Search product',
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Find a product in dead stock',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          visibleRows.isEmpty
              ? const IntelligenceEmptyState(
                  title: 'No dead stock identified',
                  subtitle: 'Nothing on hand is currently breaching your dead-stock threshold.',
                  icon: Icons.check_circle_outline_rounded,
                )
              : _resultsPanel(
                  title: 'Dead stock results',
                  subtitle: 'Click a row to see what drove the conclusion.',
                  child: Column(children: visibleRows.map(_deadStockRowCard).toList()),
                ),
        ],
      ),
    );
  }

  Widget _marginRowCard(Map<String, dynamic> row) {
    final flags = (row['flags'] is List)
        ? (row['flags'] as List).map((e) => e.toString()).toSet().toList()
        : <String>[];
    final usableEstimate = confidenceHasUsableEstimate(row['basis']);

    return _clickableRowCard(
      onTap: () => _showMarginDetail(row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row['group_label']?.toString() ?? 'Unknown',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const _ClickHint(),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statPill('Revenue', money(row['revenue'])),
                    _statPill('Cost', money(row['cost'])),
                    _statPill('Margin', money(row['margin']), color: (double.tryParse(row['margin']?.toString() ?? '') ?? 0) < 0 ? AppTheme.danger : null),
                    _statPill('Margin %', percent(row['margin_pct'])),
                    _statPill('Sale lines', '${row['lines'] ?? 0}'),
                  ],
                ),
                if (flags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: flags.map((flag) {
                      final belowCost = flag == 'below_cost';
                      return IssueChip(
                        label: belowCost ? 'Below cost detected' : 'Below minimum margin detected',
                        color: belowCost ? AppTheme.danger : AppTheme.warning,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Potential recoverable', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  usableEstimate ? money(row['recoverable']) : '—',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: usableEstimate ? AppTheme.warning : AppTheme.textMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  usableEstimate ? 'Based on current evidence' : 'Wait for more history',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: ConfidenceBadge(basis: row['basis'], compact: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _discountRowCard(Map<String, dynamic> row, Map<String, dynamic> result) {
    final discountRate = double.tryParse(row['discount_rate']?.toString() ?? '');
    final baselineRate = double.tryParse(result['baseline_rate']?.toString() ?? '');
    final difference = discountRate != null && baselineRate != null ? discountRate - baselineRate : null;
    final comparisonReady = confidenceLevel(row['comparison_basis']) != 'none' && baselineRate != null;

    return _clickableRowCard(
      onTap: () => _showDiscountDetail(row, result),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row['actor_name']?.toString() ?? 'Unknown', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    const _ClickHint(),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statPill('Invoices', '${row['invoice_count'] ?? 0}'),
                    _statPill('Measured avg', percent(row['discount_rate'])),
                    _statPill('Branch avg', percent(result['baseline_rate'])),
                    _statPill(
                      'Difference',
                      difference == null ? '—' : percent(difference, signed: true),
                      color: difference == null ? null : (difference >= 0 ? AppTheme.danger : AppTheme.success),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  comparisonReady
                      ? 'Measured against the branch baseline with enough evidence for comparison.'
                      : 'Measured rate is available, but branch comparison evidence is still forming.',
                  style: const TextStyle(color: AppTheme.textMuted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Measured', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    ConfidenceBadge(basis: row['rate_basis'], compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Comparison', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    ConfidenceBadge(basis: row['comparison_basis'], compact: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _repricingRowCard(Map<String, dynamic> row) {
    final belowCost = row['flag'] == 'below_cost';
    return _clickableRowCard(
      onTap: () => _showRepricingDetail(row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row['name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    const _ClickHint(),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statPill('Avg cost', money(row['avg_cost'])),
                    _statPill('Current price', money(row['price'])),
                    _statPill('Current margin', percent(row['implied_margin_pct'])),
                    if (row['purchase_price_trend_pct'] != null)
                      _statPill('Cost trend', percent(row['purchase_price_trend_pct'], signed: true)),
                  ],
                ),
                const SizedBox(height: 10),
                IssueChip(label: belowCost ? 'Below cost' : 'Below target margin', color: belowCost ? AppTheme.danger : AppTheme.warning),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Suggested price', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(money(row['suggested_price']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: ConfidenceBadge(basis: row['basis'], compact: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deadStockRowCard(Map<String, dynamic> row) {
    return _clickableRowCard(
      onTap: () => _showDeadStockDetail(row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row['name']?.toString() ?? 'Product', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    const _ClickHint(),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statPill('On hand', qty(row['quantity'])),
                    _statPill('Avg cost', money(row['avg_cost'])),
                    _statPill('Bucket', titleCase(row['bucket']?.toString() ?? 'Unknown')),
                    _statPill(
                      row['never_sold'] == true ? 'Status' : 'Idle time',
                      row['never_sold'] == true ? 'Never sold' : '${row['days_idle'] ?? '—'} days',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Locked capital', style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(money(row['locked_capital']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.warning)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: ConfidenceBadge(basis: row['basis'], compact: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMarginDetail(Map<String, dynamic> row) async {
    final flags = (row['flags'] is List)
        ? (row['flags'] as List).map((e) => e.toString()).toSet().toList()
        : <String>[];
    final usableEstimate = confidenceHasUsableEstimate(row['basis']);
    await _showDetailDialog(
      title: row['group_label']?.toString() ?? 'Margin Leak Detail',
      subtitle: 'Why this result was flagged',
      leadingColor: AppTheme.danger,
      body: [
        _detailSummary(
          title: 'Conclusion',
          description: _marginConclusionText(row, flags),
          chips: [
            if (flags.contains('below_cost')) IssueChip(label: 'Below cost detected', color: AppTheme.danger),
            if (flags.contains('below_floor')) IssueChip(label: 'Below minimum margin detected', color: AppTheme.warning),
          ],
        ),
        _detailStatGrid([
          _detailStat('Revenue', money(row['revenue'])),
          _detailStat('Cost', money(row['cost'])),
          _detailStat('Margin', money(row['margin'])),
          _detailStat('Margin %', percent(row['margin_pct'])),
          _detailStat('Sale lines reviewed', '${row['lines'] ?? 0}'),
          _detailStat('Potential recoverable', usableEstimate ? money(row['recoverable']) : 'Waiting for more history'),
        ]),
        _detailSection(
          title: 'How CounterIQ reached this conclusion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet('Revenue from the reviewed sale lines was compared against captured line cost.'),
              if (flags.contains('below_cost')) _bullet('At least one reviewed line sold below cost.'),
              if (flags.contains('below_floor')) _bullet('The reviewed activity also fell below your configured minimum margin floor.'),
              _bullet('The confidence badge shows how much history and how many observed selling days support this estimate.'),
            ],
          ),
        ),
        _detailSection(
          title: 'Confidence and evidence',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [const Text('Confidence: '), ConfidenceBadge(basis: row['basis'])]),
              _statPill('History days', '${asMap(row['basis'])['history_days'] ?? '—'}'),
              _statPill('Observed selling days', '${asMap(row['basis'])['observations'] ?? '—'}'),
            ],
          ),
        ),
      ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: iconColor.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.4)),
          const SizedBox(height: 6),
          Text(caption, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.35)),
        ],
      ),
    );
  }

  Widget _controlPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
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
        boxShadow: AppTheme.softShadow,
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
