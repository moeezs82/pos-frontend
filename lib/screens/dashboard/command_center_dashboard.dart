import 'dart:math' as math;

import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/screens/dashboard/low_stock_screen.dart';
import 'package:enterprise_pos/screens/intelligence/intelligence_hub_screen.dart';
import 'package:enterprise_pos/screens/register_shifts/register_shift_screen.dart';
import 'package:enterprise_pos/screens/sync/offline_sync_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CommandCenterDashboard extends StatefulWidget {
  final String userName;
  final String role;

  const CommandCenterDashboard({
    super.key,
    required this.userName,
    required this.role,
  });

  @override
  State<CommandCenterDashboard> createState() => _CommandCenterDashboardState();
}

enum _DashboardPreset { today, thisWeek, lastWeek, thisMonth, custom }

class _DashboardRange {
  final DateTime start;
  final DateTime end;
  final DateTime compareStart;
  final DateTime compareEnd;
  final String label;
  final String compareLabel;
  final bool singleDay;

  const _DashboardRange({
    required this.start,
    required this.end,
    required this.compareStart,
    required this.compareEnd,
    required this.label,
    required this.compareLabel,
    required this.singleDay,
  });
}

class _CommandCenterDashboardState extends State<CommandCenterDashboard> {
  final _money = const AppMoneyFormatter(decimalDigits: 3);
  final _dateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  final _dateOnly = DateFormat('yyyy-MM-dd');
  final _headerDate = DateFormat('EEEE, d MMM yyyy');
  final _shortDate = DateFormat('d MMM');
  final _shortDateYear = DateFormat('d MMM yyyy');

  _DashboardPreset _preset = _DashboardPreset.today;
  DateTimeRange? _customRange;
  late _DashboardRange _range;
  int _periodRequestGeneration = 0;

  bool _periodLoading = true;
  bool _liveLoading = true;
  bool _obscured = false;
  String? _error;

  double _netSales = 0;
  double _grossProfit = 0;
  double _discount = 0;
  int _invoices = 0;
  double _collections = 0;

  double _previousNetSales = 0;
  double _previousGrossProfit = 0;
  int _previousInvoices = 0;

  int _lowStockCount = 0;
  List<Map<String, dynamic>> _lowStockPreview = const [];
  List<Map<String, dynamic>> _topProducts = const [];
  List<_TrendPoint> _trend = const [];
  List<_PaymentSlice> _paymentMix = const [];

  bool _hasIntelligence = false;
  double _recoverableMargin = 0;
  int _marginLeakLines = 0;

  bool get _loading => _periodLoading || _liveLoading;

  @override
  void initState() {
    super.initState();
    _range = _rangeFor(_preset, custom: _customRange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);
  DateTime _endOfDay(DateTime value) => DateTime(value.year, value.month, value.day, 23, 59, 59);

  DateTime _startOfIsoWeek(DateTime value) {
    final day = _startOfDay(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  DateTime _sameClockPreviousMonth(DateTime now) {
    final previousMonth = now.month == 1 ? 12 : now.month - 1;
    final previousYear = now.month == 1 ? now.year - 1 : now.year;
    final lastDay = DateTime(previousYear, previousMonth + 1, 0).day;
    final day = math.min(now.day, lastDay).toInt();
    return DateTime(previousYear, previousMonth, day, now.hour, now.minute, now.second);
  }

  _DashboardRange _rangeFor(_DashboardPreset preset, {DateTimeRange? custom}) {
    final now = DateTime.now();
    switch (preset) {
      case _DashboardPreset.today:
        final start = _startOfDay(now);
        final compareStart = start.subtract(const Duration(days: 1));
        return _DashboardRange(
          start: start,
          end: now,
          compareStart: compareStart,
          compareEnd: compareStart.add(now.difference(start)),
          label: 'Today',
          compareLabel: 'Yesterday',
          singleDay: true,
        );
      case _DashboardPreset.thisWeek:
        final start = _startOfIsoWeek(now);
        final compareStart = start.subtract(const Duration(days: 7));
        return _DashboardRange(
          start: start,
          end: now,
          compareStart: compareStart,
          compareEnd: compareStart.add(now.difference(start)),
          label: 'This Week',
          compareLabel: 'Previous Week • same elapsed period',
          singleDay: false,
        );
      case _DashboardPreset.lastWeek:
        final thisWeekStart = _startOfIsoWeek(now);
        final start = thisWeekStart.subtract(const Duration(days: 7));
        final end = thisWeekStart.subtract(const Duration(seconds: 1));
        return _DashboardRange(
          start: start,
          end: end,
          compareStart: start.subtract(const Duration(days: 7)),
          compareEnd: end.subtract(const Duration(days: 7)),
          label: 'Last Week',
          compareLabel: 'Week Before',
          singleDay: false,
        );
      case _DashboardPreset.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final compareStart = now.month == 1 ? DateTime(now.year - 1, 12, 1) : DateTime(now.year, now.month - 1, 1);
        return _DashboardRange(
          start: start,
          end: now,
          compareStart: compareStart,
          compareEnd: _sameClockPreviousMonth(now),
          label: 'This Month',
          compareLabel: 'Previous Month • same elapsed period',
          singleDay: false,
        );
      case _DashboardPreset.custom:
        final selected = custom ?? DateTimeRange(start: _startOfDay(now), end: _startOfDay(now));
        final start = _startOfDay(selected.start);
        final end = _endOfDay(selected.end);
        final days = _startOfDay(selected.end).difference(start).inDays + 1;
        final compareEndDay = start.subtract(const Duration(days: 1));
        final compareStart = compareEndDay.subtract(Duration(days: days - 1));
        return _DashboardRange(
          start: start,
          end: end,
          compareStart: _startOfDay(compareStart),
          compareEnd: _endOfDay(compareEndDay),
          label: '${_shortDate.format(start)} – ${_shortDateYear.format(end)}',
          compareLabel: '${_shortDate.format(compareStart)} – ${_shortDateYear.format(compareEndDay)}',
          singleDay: days == 1,
        );
    }
  }

  String _rangeStart(_DashboardRange range) => _dateTime.format(range.start);
  String _rangeEnd(_DashboardRange range) => _dateTime.format(range.end);
  String _rangeStartDate(_DashboardRange range) => _dateOnly.format(range.start);
  String _rangeEndDate(_DashboardRange range) => _dateOnly.format(range.end);

  Future<void> _loadAll() async {
    await Future.wait<void>([
      _loadPeriodData(),
      _loadLiveData(),
    ]);
  }

  Future<void> _loadLiveData() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || !auth.hasPermission('view-reports')) {
      if (mounted) setState(() => _liveLoading = false);
      return;
    }
    setState(() => _liveLoading = true);
    try {
      final report = await ReportsService(token: token).runEnterpriseReport(
        reportKey: 'low-stock',
        filters: const {'per_page': 5},
      );
      final rows = _mapRows(report['rows']);
      final pagination = _asMap(report['pagination']);
      if (!mounted) return;
      setState(() {
        _lowStockPreview = rows;
        final total = _toInt(pagination['total']);
        _lowStockCount = total > 0 ? total : rows.length;
        _liveLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _liveLoading = false);
    }
  }

  Future<void> _loadPeriodData() async {
    if (!mounted) return;
    final generation = ++_periodRequestGeneration;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null) {
      if (mounted) setState(() => _periodLoading = false);
      return;
    }
    final range = _range;

    setState(() {
      _periodLoading = true;
      _error = null;
    });

    final intelligenceAllowed = auth.hasAddon('intelligence') &&
        auth.hasPermission('view-margin-intelligence');

    try {
      double recoverable = 0;
      int leakLines = 0;
      if (intelligenceAllowed) {
        try {
          final env = await IntelligenceService(token: token).marginLeaks(
            startDate: _rangeStartDate(range),
            endDate: _rangeEndDate(range),
            groupBy: 'product',
            page: 1,
            perPage: 1,
          );
          final result = _asMap(env.result);
          final totals = _asMap(result['totals']);
          recoverable = _toDouble(totals['recoverable']);
          leakLines = _toInt(totals['lines_flagged']);
        } catch (_) {
          // Intelligence remains optional on Home.
        }
      }

      if (!auth.hasPermission('view-reports')) {
        if (!mounted || generation != _periodRequestGeneration) return;
        setState(() {
          _hasIntelligence = intelligenceAllowed;
          _recoverableMargin = recoverable;
          _marginLeakLines = leakLines;
          _periodLoading = false;
        });
        return;
      }

      final reports = ReportsService(token: token);
      final currentFilters = <String, dynamic>{
        'start_date': _rangeStart(range),
        'end_date': _rangeEnd(range),
      };
      final previousFilters = <String, dynamic>{
        'start_date': _dateTime.format(range.compareStart),
        'end_date': _dateTime.format(range.compareEnd),
      };

      final results = await Future.wait<Map<String, dynamic>>([
        reports.runEnterpriseReport(
          reportKey: 'sales-summary',
          filters: {...currentFilters, 'per_page': 500},
        ).catchError((_) => <String, dynamic>{}),
        reports.runEnterpriseReport(
          reportKey: 'sales-summary',
          filters: {...previousFilters, 'per_page': 500},
        ).catchError((_) => <String, dynamic>{}),
        reports.runEnterpriseReport(
          reportKey: 'dashboard-sales-trend',
          filters: {...currentFilters, 'per_page': 500},
        ).catchError((_) => <String, dynamic>{}),
        reports.runEnterpriseReport(
          reportKey: 'sales-by-payment-method',
          filters: {...currentFilters, 'per_page': 100},
        ).catchError((_) => <String, dynamic>{}),
        reports.getTopBottomProducts(
          startDate: _rangeStart(range),
          endDate: _rangeEnd(range),
          sortBy: 'revenue',
          direction: 'desc',
          page: 1,
          perPage: 5,
        ).catchError((_) => <String, dynamic>{}),
      ]);

      final currentTotals = _asMap(results[0]['totals']);
      final previousTotals = _asMap(results[1]['totals']);
      final trendRows = _mapRows(results[2]['rows']);
      final trend = <_TrendPoint>[];
      for (var i = 0; i < trendRows.length; i++) {
        final row = trendRows[i];
        final dateText = row['bucket_date']?.toString() ?? '';
        final hourText = row['bucket_hour']?.toString();
        final hour = int.tryParse(hourText ?? '');
        final parsedDate = DateTime.tryParse(dateText);
        final label = hour != null
            ? _hourLabel(hour)
            : parsedDate == null
                ? dateText
                : DateFormat('d MMM').format(parsedDate);
        final x = hour != null
            ? (hour / 23.0).clamp(0.0, 1.0).toDouble()
            : trendRows.length <= 1
                ? .5
                : i / (trendRows.length - 1);
        trend.add(_TrendPoint(
          label: label,
          x: x,
          sales: _toDouble(row['net_sales']),
          profit: _toDouble(row['gross_profit']),
          invoices: _toInt(row['invoices']),
        ));
      }

      final paymentRows = _mapRows(results[3]['rows']);
      final payments = paymentRows
          .map((row) => _PaymentSlice(
                method: _cleanMethod(row['method']?.toString()),
                amount: _toDouble(row['amount']),
                payments: _toInt(row['payments']),
              ))
          .where((row) => row.amount > 0)
          .toList(growable: false)
        ..sort((a, b) => b.amount.compareTo(a.amount));

      if (!mounted || generation != _periodRequestGeneration) return;
      setState(() {
        _netSales = _toDouble(currentTotals['net_sales']);
        _grossProfit = _toDouble(currentTotals['gross_profit']);
        _discount = _toDouble(currentTotals['discount']);
        _invoices = _toInt(currentTotals['invoices']);
        _collections = payments.fold<double>(0, (sum, row) => sum + row.amount);
        _previousNetSales = _toDouble(previousTotals['net_sales']);
        _previousGrossProfit = _toDouble(previousTotals['gross_profit']);
        _previousInvoices = _toInt(previousTotals['invoices']);
        _trend = trend;
        _paymentMix = payments;
        _topProducts = _mapRows(results[4]['rows']);
        _hasIntelligence = intelligenceAllowed;
        _recoverableMargin = recoverable;
        _marginLeakLines = leakLines;
        _periodLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _periodRequestGeneration) return;
      setState(() {
        _error = e.toString();
        _periodLoading = false;
      });
    }
  }

  Future<void> _selectPreset(_DashboardPreset preset) async {
    if (_preset == preset && preset != _DashboardPreset.custom) return;
    if (preset == _DashboardPreset.custom) {
      await _pickCustomRange();
      return;
    }
    setState(() {
      _preset = preset;
      _customRange = null;
      _range = _rangeFor(preset);
    });
    await _loadPeriodData();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: now,
      initialDateRange: initial,
      helpText: 'Select dashboard date range',
      saveText: 'Apply',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _preset = _DashboardPreset.custom;
      _customRange = selected;
      _range = _rangeFor(_DashboardPreset.custom, custom: selected);
    });
    await _loadPeriodData();
  }

  String _presetLabel(_DashboardPreset preset) {
    switch (preset) {
      case _DashboardPreset.today:
        return 'Today';
      case _DashboardPreset.thisWeek:
        return 'This Week';
      case _DashboardPreset.lastWeek:
        return 'Last Week';
      case _DashboardPreset.thisMonth:
        return 'This Month';
      case _DashboardPreset.custom:
        return _customRange == null ? 'Date Range' : _range.label;
    }
  }

  String get _periodCaption {
    if (_preset == _DashboardPreset.today) return 'Today so far';
    return _range.label;
  }

  String get _periodLower => _periodCaption.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final offline = context.watch<OfflineQueueProvider>();
    final shift = context.watch<RegisterShiftProvider>();
    final canSeeProfit = auth.hasPermission('view-sale-profit');
    final canViewReports = auth.hasPermission('view-reports');

    if (!canViewReports) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildOperationalOverview(offline, shift),
          if (_hasIntelligence) ...[
            const SizedBox(height: 12),
            _buildIntelligence(context),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        if (_error != null) ...[
          _ErrorStrip(message: _error!, onRetry: _loadAll),
          const SizedBox(height: 12),
        ],
        _buildKpiGrid(canSeeProfit),
        const SizedBox(height: 12),
        _buildComparison(canSeeProfit),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  _buildSalesPerformance(canSeeProfit),
                  const SizedBox(height: 12),
                  _buildAttention(context, offline, shift),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: _buildSalesPerformance(canSeeProfit)),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: _buildAttention(context, offline, shift)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 1050;
            final children = [
              _buildPaymentMix(),
              _buildTopProducts(),
              _buildIntelligence(context),
            ];
            if (narrow) {
              return Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i != children.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 9, child: children[0]),
                const SizedBox(width: 12),
                Expanded(flex: 11, child: children[1]),
                const SizedBox(width: 12),
                Expanded(flex: 10, child: children[2]),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final firstName = widget.userName.trim().split(RegExp(r'\s+')).first;
    final filters = <_DashboardPreset>[
      _DashboardPreset.today,
      _DashboardPreset.thisWeek,
      _DashboardPreset.lastWeek,
      _DashboardPreset.thisMonth,
      _DashboardPreset.custom,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _headerDate.format(DateTime.now()).toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .65,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Good ${_dayPart()}, $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.55,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Business performance for $_periodLower.',
                    style: TextStyle(
                      color: AppTheme.textMuted.withOpacity(.95),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: _obscured ? 'Show financial figures' : 'Hide financial figures',
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(_obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                label: Text(_obscured ? 'Show figures' : 'Hide figures'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Refresh dashboard',
              onPressed: _loading ? null : _loadAll,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final preset in filters)
                  Tooltip(
                    message: preset == _DashboardPreset.thisWeek
                        ? 'This Week uses Monday–Sunday. Current week compares the same elapsed period of the previous week.'
                        : preset == _DashboardPreset.custom
                            ? 'Choose any inclusive calendar date range.'
                            : _presetLabel(preset),
                    child: ChoiceChip(
                      selected: _preset == preset,
                      onSelected: (_) => _selectPreset(preset),
                      avatar: preset == _DashboardPreset.custom
                          ? const Icon(Icons.calendar_month_rounded, size: 16)
                          : null,
                      label: Text(_presetLabel(preset)),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: _preset == preset ? AppTheme.primary.withOpacity(.28) : AppTheme.border),
                      selectedColor: AppTheme.primarySoft,
                      labelStyle: TextStyle(
                        color: _preset == preset ? AppTheme.primaryDark : AppTheme.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                if (_periodLoading)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOperationalOverview(
    OfflineQueueProvider offline,
    RegisterShiftProvider shift,
  ) {
    final cards = <_OperationalCardData>[
      _OperationalCardData(
        icon: Icons.point_of_sale_rounded,
        title: 'Register status',
        value: shift.hasActiveShift ? 'Open' : 'Closed',
        caption: shift.hasActiveShift ? 'Shift #${shift.id ?? '—'} is active' : 'Open a shift before checkout',
        color: shift.hasActiveShift ? AppTheme.success : AppTheme.warning,
      ),
      _OperationalCardData(
        icon: Icons.sync_rounded,
        title: 'Offline queue',
        value: '${offline.pendingCount}',
        caption: offline.pendingCount == 0 ? 'No pending offline sales' : 'Sales waiting to sync',
        color: offline.pendingCount == 0 ? AppTheme.success : AppTheme.warning,
      ),
      _OperationalCardData(
        icon: Icons.badge_outlined,
        title: 'Access role',
        value: widget.role,
        caption: 'Dashboard adapts to your permissions',
        color: AppTheme.info,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 840
            ? (constraints.maxWidth - 20) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: _OperationalCard(data: card)),
          ],
        );
      },
    );
  }

  Widget _buildKpiGrid(bool canSeeProfit) {
    final avgInvoice = _invoices == 0 ? 0.0 : _netSales / _invoices;
    final kpis = <_KpiData>[
      _KpiData(
        label: 'NET SALES',
        value: _money.format(_netSales),
        foot: _invoices == 0 ? 'No invoices in $_periodLower' : '$_invoices invoices • $_periodCaption',
        icon: Icons.trending_up_rounded,
      ),
      if (canSeeProfit)
        _KpiData(
          label: 'GROSS PROFIT',
          value: _money.format(_grossProfit),
          foot: _netSales == 0 ? 'Margin —' : '${(_grossProfit / _netSales * 100).toStringAsFixed(1)}% margin',
          icon: Icons.insights_rounded,
        )
      else
        _KpiData(
          label: 'DISCOUNTS',
          value: _money.format(_discount),
          foot: 'Discounts • $_periodCaption',
          icon: Icons.percent_rounded,
        ),
      _KpiData(
        label: 'TRANSACTIONS',
        value: '$_invoices',
        foot: 'Avg invoice ${_money.format(avgInvoice)}',
        icon: Icons.receipt_long_rounded,
      ),
      _KpiData(
        label: 'COLLECTIONS',
        value: _money.format(_collections),
        foot: _paymentMix.isEmpty ? 'No receipts in $_periodLower' : '${_paymentMix.length} payment methods',
        icon: Icons.account_balance_wallet_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 650
                ? 2
                : 1;
        const gap = 10.0;
        final width = cols == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final kpi in kpis)
              SizedBox(width: width, child: _KpiCard(data: kpi, obscured: _obscured)),
          ],
        );
      },
    );
  }

  Widget _buildComparison(bool canSeeProfit) {
    final currentAvg = _invoices <= 0 ? 0.0 : _netSales / _invoices;
    final previousAvg = _previousInvoices <= 0 ? 0.0 : _previousNetSales / _previousInvoices;
    final rows = <_ComparisonMetric>[
      _ComparisonMetric(
        label: 'Net sales',
        current: _netSales,
        previous: _previousNetSales,
        formatter: _money.format,
        percentageAllowed: true,
      ),
      if (canSeeProfit)
        _ComparisonMetric(
          label: 'Gross profit',
          current: _grossProfit,
          previous: _previousGrossProfit,
          formatter: _money.format,
          percentageAllowed: _previousGrossProfit > 0,
        ),
      _ComparisonMetric(
        label: 'Transactions',
        current: _invoices.toDouble(),
        previous: _previousInvoices.toDouble(),
        formatter: (v) => v.round().toString(),
        percentageAllowed: true,
      ),
      _ComparisonMetric(
        label: 'Avg invoice',
        current: currentAvg,
        previous: previousAvg,
        formatter: _money.format,
        percentageAllowed: true,
      ),
    ];

    return _Panel(
      title: 'Period comparison',
      subtitle: '${_range.label} compared with ${_range.compareLabel}',
      trailing: _periodLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          if (compact) {
            return Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _ComparisonRow(metric: rows[i], obscured: _obscured),
                  if (i != rows.length - 1) const Divider(height: 1),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Expanded(child: _ComparisonTile(metric: rows[i], obscured: _obscured)),
                if (i != rows.length - 1)
                  const SizedBox(height: 62, child: VerticalDivider(width: 18)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSalesPerformance(bool canSeeProfit) {
    final maxSales = _trend.fold<double>(0, (max, point) => math.max(max, point.sales).toDouble());
    final peak = _trend.isEmpty ? null : _trend.reduce((a, b) => a.sales >= b.sales ? a : b);
    final axisLabels = _trendAxisLabels(_trend);

    return _Panel(
      title: 'Sales performance',
      subtitle: '${_range.label} • ${_range.singleDay ? 'hourly' : 'daily'} net sales',
      trailing: peak == null
          ? null
          : Text(
              'Peak ${peak.label}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_periodLoading && _trend.isEmpty)
            const SizedBox(height: 190, child: Center(child: CircularProgressIndicator()))
          else if (_trend.isEmpty)
            SizedBox(
              height: 190,
              child: Center(
                child: Text('No sales were recorded in $_periodLower.', style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
              ),
            )
          else ...[
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _TrendPainter(
                  points: _trend,
                  maxValue: maxSales,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < axisLabels.length; i++) ...[
                  if (i > 0) const Spacer(),
                  Text(axisLabels[i], style: _axisStyle),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _InlineMetric(label: _range.label, value: _money.format(_netSales), obscured: _obscured),
                _InlineMetric(label: _range.singleDay ? 'Peak hour' : 'Peak day', value: peak == null ? '—' : '${peak.label} • ${_money.format(peak.sales)}', obscured: _obscured),
                if (canSeeProfit)
                  _InlineMetric(label: 'Gross profit', value: _money.format(_grossProfit), obscured: _obscured),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<String> _trendAxisLabels(List<_TrendPoint> points) {
    if (points.isEmpty) return const [];
    if (points.length == 1) return [points.first.label];
    final indexes = <int>{
      0,
      ((points.length - 1) * .25).round(),
      ((points.length - 1) * .5).round(),
      ((points.length - 1) * .75).round(),
      points.length - 1,
    }.toList()..sort();
    return indexes.map((i) => points[i].label).toList(growable: false);
  }

  Widget _buildAttention(
    BuildContext context,
    OfflineQueueProvider offline,
    RegisterShiftProvider shift,
  ) {
    final items = <_AttentionItem>[
      _AttentionItem(
        color: _lowStockCount > 0 ? AppTheme.danger : AppTheme.success,
        title: _lowStockCount > 0 ? '$_lowStockCount products below stock threshold' : 'Stock thresholds look healthy',
        subtitle: _lowStockPreview.isEmpty ? 'Open current stock report' : 'Review low-stock products',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LowStockScreen())),
      ),
      if (_hasIntelligence)
        _AttentionItem(
          color: _marginLeakLines > 0 ? AppTheme.warning : AppTheme.success,
          title: _marginLeakLines > 0 ? '$_marginLeakLines margin-leak lines identified' : 'No margin leaks need review',
          subtitle: _marginLeakLines > 0 ? '${_money.format(_recoverableMargin)} potential recovery • ${_range.label}' : 'Money Finder is clear for ${_range.label}',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceHubScreen())),
        ),
      _AttentionItem(
        color: offline.pendingCount > 0 ? AppTheme.warning : AppTheme.success,
        title: offline.pendingCount > 0 ? '${offline.pendingCount} offline sales waiting to sync' : 'Offline sales queue is clear',
        subtitle: offline.pendingCount > 0 ? 'Review the sync queue' : 'No pending offline sales',
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineSyncScreen()));
          if (context.mounted) context.read<OfflineQueueProvider>().refresh();
        },
      ),
      _AttentionItem(
        color: shift.hasPendingCloseRequest
            ? AppTheme.warning
            : shift.hasActiveShift
                ? AppTheme.success
                : AppTheme.textMuted,
        title: shift.hasPendingCloseRequest
            ? 'Register close approval is pending'
            : shift.hasActiveShift
                ? 'Register shift #${shift.id ?? '—'} is open'
                : 'No active register shift',
        subtitle: shift.hasActiveShift ? 'Open drawer management' : 'Open a shift before checkout',
        onTap: () => PosNavigation.openSingleton(
          routeId: PosRouteIds.registerShift,
          builder: (_) => const RegisterShiftScreen(),
        ),
      ),
    ];

    return _Panel(
      title: 'Needs attention',
      subtitle: '${items.where((item) => item.color != AppTheme.success).length} items worth checking • live operations + ${_range.label}',
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _AttentionRow(item: items[i]),
            if (i != items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMix() {
    final total = _paymentMix.fold<double>(0, (sum, row) => sum + row.amount);
    return _Panel(
      title: 'Payment mix',
      subtitle: 'Customer receipts • $_periodCaption',
      child: _paymentMix.isEmpty
          ? _SmallEmpty(message: 'No customer receipts in $_periodLower.')
          : Column(
              children: [
                for (final row in _paymentMix.take(5)) ...[
                  _PaymentRow(
                    row: row,
                    total: total,
                    money: _money,
                    obscured: _obscured,
                  ),
                  if (row != _paymentMix.take(5).last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _buildTopProducts() {
    return _Panel(
      title: 'Top selling products',
      subtitle: 'Ranked by revenue • $_periodCaption',
      child: _topProducts.isEmpty
          ? _SmallEmpty(message: 'No product sales in $_periodLower.')
          : Column(
              children: [
                const _ProductTableHeader(),
                const Divider(height: 1),
                for (final row in _topProducts.take(5)) _ProductTableRow(row: row, money: _money, obscured: _obscured),
              ],
            ),
    );
  }

  Widget _buildIntelligence(BuildContext context) {
    final allowed = _hasIntelligence;
    return _Panel(
      title: 'CounterIQ Intelligence',
      subtitle: allowed ? 'Margin insight for $_periodCaption • live operational recommendations' : 'Premium business intelligence',
      trailing: allowed
          ? _StatusPill(label: 'ACTIVE', color: AppTheme.primary)
          : _StatusPill(label: 'ADD-ON', color: AppTheme.textMuted),
      child: allowed
          ? Column(
              children: [
                _IntelligenceLine(
                  icon: Icons.price_check_rounded,
                  title: 'Margin leakage',
                  subtitle: _marginLeakLines == 0 ? 'No flagged sale lines' : '$_marginLeakLines contributing sale lines',
                  value: _money.format(_recoverableMargin),
                  obscured: _obscured,
                ),
                const Divider(height: 18),
                const _IntelligenceLine(
                  icon: Icons.price_change_rounded,
                  title: 'Repricing',
                  subtitle: 'Review products whose cost no longer clears target margin',
                  value: 'Review',
                ),
                const Divider(height: 18),
                const _IntelligenceLine(
                  icon: Icons.inventory_2_outlined,
                  title: 'Replenishment',
                  subtitle: 'Velocity-based reorder recommendations',
                  value: 'Open',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceHubScreen())),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Open Intelligence'),
                  ),
                ),
              ],
            )
          : const _SmallEmpty(message: 'Intelligence is not enabled for this branch.'),
    );
  }

  String _dayPart() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _hourLabel(int hour) {
    final normalized = math.max(0, math.min(23, hour)).toInt();
    final h = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$h ${normalized < 12 ? 'AM' : 'PM'}';
  }

  static const _axisStyle = TextStyle(
    color: Color(0xFF94A3B8),
    fontSize: 10,
    fontWeight: FontWeight.w700,
  );

  String _cleanMethod(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Other';
    return text
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  static List<Map<String, dynamic>> _mapRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _OperationalCardData {
  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;

  const _OperationalCardData({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
  });
}

class _OperationalCard extends StatelessWidget {
  final _OperationalCardData data;
  const _OperationalCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 124,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: data.color.withOpacity(.08), borderRadius: BorderRadius.circular(9)),
                child: Icon(data.icon, size: 17, color: data.color),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(data.title, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w900))),
            ],
          ),
          const Spacer(),
          Text(data.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.35)),
          const SizedBox(height: 4),
          Text(data.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _KpiData {
  final String label;
  final String value;
  final String foot;
  final IconData icon;

  const _KpiData({
    required this.label,
    required this.value,
    required this.foot,
    required this.icon,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  final bool obscured;

  const _KpiCard({required this.data, required this.obscured});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                  ),
                ),
              ),
              Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, size: 17, color: const Color(0xFF475569)),
              ),
            ],
          ),
          const Spacer(),
          _PrivateText(
            value: data.value,
            obscured: obscured,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.foot,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppTheme.navy, fontSize: 14.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AttentionItem {
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AttentionItem({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _AttentionRow extends StatelessWidget {
  final _AttentionItem item;

  const _AttentionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: item.color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 10.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 19),
          ],
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool obscured;

  const _InlineMetric({required this.label, required this.value, required this.obscured});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
        _PrivateText(value: value, obscured: obscured, style: const TextStyle(color: AppTheme.navy, fontSize: 11, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _PaymentSlice {
  final String method;
  final double amount;
  final int payments;

  const _PaymentSlice({required this.method, required this.amount, required this.payments});
}

class _PaymentRow extends StatelessWidget {
  final _PaymentSlice row;
  final double total;
  final AppMoneyFormatter money;
  final bool obscured;

  const _PaymentRow({required this.row, required this.total, required this.money, required this.obscured});

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (row.amount / total).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(row.method, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w800))),
            _PrivateText(value: money.format(row.amount), obscured: obscured, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppTheme.surfaceSoft,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF64748B)),
          ),
        ),
        const SizedBox(height: 3),
        Text('${(ratio * 100).toStringAsFixed(0)}% • ${row.payments} payments', style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ProductTableHeader extends StatelessWidget {
  const _ProductTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text('Product', style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w900))),
          SizedBox(width: 54, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w900))),
          SizedBox(width: 92, child: Text('Sales', textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }
}

class _ProductTableRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final AppMoneyFormatter money;
  final bool obscured;

  const _ProductTableRow({required this.row, required this.money, required this.obscured});

  @override
  Widget build(BuildContext context) {
    final name = row['product']?.toString() ?? row['name']?.toString() ?? 'Product';
    final qty = row['qty'] ?? row['quantity'] ?? row['sold_qty'] ?? 0;
    final revenue = row['revenue'] ?? row['total'] ?? row['net_sales'] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        children: [
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w700))),
          SizedBox(width: 54, child: Text(_compactNumber(qty), textAlign: TextAlign.right, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
          SizedBox(
            width: 92,
            child: Align(
              alignment: Alignment.centerRight,
              child: _PrivateText(value: money.format(revenue), obscured: obscured, style: const TextStyle(color: AppTheme.navy, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  static String _compactNumber(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
    if ((number - number.roundToDouble()).abs() < .00001) return number.toInt().toString();
    return number.toStringAsFixed(2);
  }
}

class _IntelligenceLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final bool obscured;

  const _IntelligenceLine({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.obscured = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: const Color(0xFF475569)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.7, fontWeight: FontWeight.w600, height: 1.25)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _PrivateText(value: value, obscured: obscured, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.18))),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .4)),
    );
  }
}

class _SmallEmpty extends StatelessWidget {
  final String message;
  const _SmallEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600))),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorStrip({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.danger.withOpacity(.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text('Some dashboard data could not be loaded. $message', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PrivateText extends StatelessWidget {
  final String value;
  final bool obscured;
  final TextStyle style;

  const _PrivateText({required this.value, required this.obscured, required this.style});

  @override
  Widget build(BuildContext context) {
    if (!obscured) {
      return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return Container(
      height: (style.fontSize ?? 14) * 1.05,
      width: math.max(52, math.min(130, value.length * ((style.fontSize ?? 14) * .56))).toDouble(),
      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(5)),
    );
  }
}

class _ComparisonMetric {
  final String label;
  final double current;
  final double previous;
  final String Function(double) formatter;
  final bool percentageAllowed;

  const _ComparisonMetric({
    required this.label,
    required this.current,
    required this.previous,
    required this.formatter,
    required this.percentageAllowed,
  });

  double get delta => current - previous;

  String get changeLabel {
    if (previous == 0) {
      if (current == 0) return 'No change';
      return current > 0 ? 'New activity' : 'Lower';
    }
    if (!percentageAllowed || previous < 0) {
      if (delta == 0) return 'No change';
      return '${delta > 0 ? '+' : ''}${formatter(delta)}';
    }
    final pct = delta / previous.abs() * 100;
    if (pct.abs() < .05) return 'No change';
    return '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
  }

  Color get changeColor {
    if (delta > 0) return AppTheme.success;
    if (delta < 0) return AppTheme.danger;
    return AppTheme.textMuted;
  }
}

class _ComparisonTile extends StatelessWidget {
  final _ComparisonMetric metric;
  final bool obscured;

  const _ComparisonTile({required this.metric, required this.obscured});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.label.toUpperCase(), style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .35)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _PrivateText(
                  value: metric.formatter(metric.current),
                  obscured: obscured,
                  style: const TextStyle(color: AppTheme.navy, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 6),
              Text(metric.changeLabel, style: TextStyle(color: metric.changeColor, fontSize: 10.5, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Previous ', style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w600)),
              Expanded(
                child: _PrivateText(
                  value: metric.formatter(metric.previous),
                  obscured: obscured,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final _ComparisonMetric metric;
  final bool obscured;

  const _ComparisonRow({required this.metric, required this.obscured});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(metric.label, style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w800))),
          SizedBox(
            width: 105,
            child: Align(
              alignment: Alignment.centerRight,
              child: _PrivateText(
                value: metric.formatter(metric.current),
                obscured: obscured,
                style: const TextStyle(color: AppTheme.navy, fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 105,
            child: Align(
              alignment: Alignment.centerRight,
              child: _PrivateText(
                value: metric.formatter(metric.previous),
                obscured: obscured,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 82,
            child: Text(metric.changeLabel, textAlign: TextAlign.right, style: TextStyle(color: metric.changeColor, fontSize: 10.5, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _TrendPoint {
  final String label;
  final double x;
  final double sales;
  final double profit;
  final int invoices;

  const _TrendPoint({
    required this.label,
    required this.x,
    required this.sales,
    required this.profit,
    required this.invoices,
  });
}

class _TrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final double maxValue;

  const _TrendPainter({required this.points, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE8EDF3)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty || maxValue <= 0) return;

    final path = Path();
    final fill = Path();
    final pointOffsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = size.width * point.x.clamp(0.0, 1.0).toDouble();
      final ratio = (point.sales / maxValue).clamp(0.0, 1.0).toDouble();
      final y = size.height - (ratio * (size.height - 10)) - 5;
      final offset = Offset(x, y);
      pointOffsets.add(offset);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(pointOffsets.last.dx, size.height);
    fill.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF64748B).withOpacity(.18),
          const Color(0xFF64748B).withOpacity(.015),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF475569);
    for (final point in pointOffsets) {
      canvas.drawCircle(point, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.maxValue != maxValue;
  }
}
