import 'dart:async';

import 'package:enterprise_pos/api/credit_control_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class CreditControlScreen extends StatefulWidget {
  const CreditControlScreen({super.key});

  @override
  State<CreditControlScreen> createState() => _CreditControlScreenState();
}

class _CreditControlScreenState extends State<CreditControlScreen> {
  late CreditControlService _service;
  bool _loadingOverview = true;
  Map<String, dynamic> _overview = const {};

  @override
  void initState() {
    super.initState();
    _service = CreditControlService(token: context.read<AuthProvider>().token!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOverview());
  }

  Future<void> _loadOverview() async {
    if (!mounted) return;
    setState(() => _loadingOverview = true);
    try {
      final data = await _service.overview();
      if (mounted) setState(() => _overview = data);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load credit-control overview: $e');
    } finally {
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit Control'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: BranchIndicator(tappable: false),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingOverview ? null : _loadOverview,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadOverview,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _OverviewCards(loading: _loadingOverview, data: _overview),
            const SizedBox(height: 14),
            _RiskSection(loading: _loadingOverview, rows: _list(_overview['highest_risk'])),
            const SizedBox(height: 14),
            const Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: CreditAuditPanel(showHeader: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreditAuditPanel extends StatefulWidget {
  final String? partyType;
  final int? partyId;
  final bool showHeader;

  const CreditAuditPanel({
    super.key,
    this.partyType,
    this.partyId,
    this.showHeader = false,
  });

  @override
  State<CreditAuditPanel> createState() => _CreditAuditPanelState();
}

class _CreditAuditPanelState extends State<CreditAuditPanel> {
  late CreditControlService _service;
  final _search = TextEditingController();
  Timer? _searchTimer;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  String _partyType = '';
  String _outcome = '';
  String _sourceType = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _service = CreditControlService(token: context.read<AuthProvider>().token!);
    _partyType = widget.partyType ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(page: 1));
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required int page}) async {
    if (_loading && _rows.isNotEmpty) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.audits(
        page: page,
        perPage: widget.partyId == null ? 25 : 15,
        partyType: _partyType.isEmpty ? null : _partyType,
        partyId: widget.partyId,
        outcome: _outcome.isEmpty ? null : _outcome,
        sourceType: _sourceType.isEmpty ? null : _sourceType,
        from: _date(_from),
        to: _date(_to),
        search: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _rows = _list(data['audits']);
        _page = _int(data['page'], fallback: page);
        final parsedLastPage = _int(data['last_page'], fallback: 1);
        _lastPage = parsedLastPage < 1 ? 1 : parsedLastPage;
        _total = _int(data['total']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load credit-control history: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await _service.exportAudits(
        partyType: _partyType.isEmpty ? null : _partyType,
        partyId: widget.partyId,
        outcome: _outcome.isEmpty ? null : _outcome,
        sourceType: _sourceType.isEmpty ? null : _sourceType,
        from: _date(_from),
        to: _date(_to),
        search: _search.text.trim(),
      );
      await saveReportFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: file.contentType,
      );
      if (mounted) AppFeedback.success(context, 'Credit-control CSV exported');
    } on ReportSaveCancelledException {
      // User cancelled the save dialog.
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 450), () => _load(page: 1));
  }

  Future<void> _pickDate(bool from) async {
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(picked)) _from = picked;
      }
    });
    await _load(page: 1);
  }

  bool get _hasActiveFilters =>
      _from != null ||
      _to != null ||
      _search.text.trim().isNotEmpty ||
      _outcome.isNotEmpty ||
      _sourceType.isNotEmpty ||
      (widget.partyId == null && _partyType.isNotEmpty);

  void _clearFilters() {
    _search.clear();
    setState(() {
      _partyType = widget.partyType ?? '';
      _outcome = '';
      _sourceType = '';
      _from = null;
      _to = null;
    });
    _load(page: 1);
  }

  Widget _buildFilterToolbar(bool canFilterParty) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded, size: 19, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Filter audit history', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Clear filters'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1180;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: wide ? 320 : 280,
                    child: TextField(
                      controller: _search,
                      onChanged: _searchChanged,
                      decoration: const InputDecoration(
                        labelText: 'Search',
                        hintText: 'Party, user, invoice or reason',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (canFilterParty)
                    _FilterDropdown(
                      width: 190,
                      value: _partyType,
                      label: 'Party',
                      items: const {'': 'All parties', 'customer': 'Customers', 'vendor': 'Vendors'},
                      onChanged: (v) {
                        setState(() => _partyType = v);
                        _load(page: 1);
                      },
                    ),
                  _FilterDropdown(
                    width: 205,
                    value: _outcome,
                    label: 'Event',
                    items: const {
                      '': 'All events',
                      'warning': 'Warnings',
                      'override': 'Overrides',
                      'blocked': 'Blocked attempts',
                      'correction': 'Corrections',
                    },
                    onChanged: (v) {
                      setState(() => _outcome = v);
                      _load(page: 1);
                    },
                  ),
                  _FilterDropdown(
                    width: 230,
                    value: _sourceType,
                    label: 'Source',
                    items: const {
                      '': 'All sources',
                      'sale': 'Sale',
                      'sale_adjustment': 'Sale adjustment',
                      'purchase': 'Purchase',
                      'purchase_adjustment': 'Purchase adjustment',
                      'customer_receipt_reversal': 'Receipt reversal',
                      'vendor_payment_reversal': 'Payment reversal',
                    },
                    onChanged: (v) {
                      setState(() => _sourceType = v);
                      _load(page: 1);
                    },
                  ),
                  _DateButton(width: 174, label: 'From date', date: _from, onTap: () => _pickDate(true)),
                  _DateButton(width: 174, label: 'To date', date: _to, onTap: () => _pickDate(false)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canFilterParty = widget.partyId == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Audit Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Warnings, overrides, corrections and blocked attempts.'),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: const Text('Export CSV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _buildFilterToolbar(canFilterParty),
        const SizedBox(height: 12),
        if (_loading && _rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _ErrorCard(message: _error!, onRetry: () => _load(page: _page))
        else if (_rows.isEmpty)
          const _EmptyAuditState()
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1050) {
                return _AuditTable(rows: _rows);
              }
              return Column(children: _rows.map((row) => _AuditCard(row: row)).toList());
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('$_total event${_total == 1 ? '' : 's'}')),
              IconButton(
                tooltip: 'Previous page',
                onPressed: _page > 1 && !_loading ? () => _load(page: _page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('Page $_page of $_lastPage', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                tooltip: 'Next page',
                onPressed: _page < _lastPage && !_loading ? () => _load(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OverviewCards extends StatelessWidget {
  final bool loading;
  final Map<String, dynamic> data;
  const _OverviewCards({required this.loading, required this.data});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricData('Over limit', _int(data['over_limit']), Icons.error_rounded, AppTheme.danger),
      _MetricData('Near limit', _int(data['near_limit']), Icons.warning_amber_rounded, AppTheme.warning),
      _MetricData('Overrides this month', _int(data['overrides_this_month']), Icons.verified_user_rounded, AppTheme.purple),
      _MetricData('Blocked this month', _int(data['blocked_this_month']), Icons.block_rounded, AppTheme.info),
      _MetricData('Warnings this month', _int(data['warnings_this_month']), Icons.notifications_active_rounded, AppTheme.primary),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final itemWidth = width >= 1200 ? (width - 48) / 5 : width >= 720 ? (width - 24) / 3 : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((m) => SizedBox(width: itemWidth, child: _MetricCard(data: m, loading: loading))).toList(),
        );
      },
    );
  }
}

class _RiskSection extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> rows;
  const _RiskSection({required this.loading, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Highest Credit Exposure', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Configured parties ordered by over-limit amount and utilization.'),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (rows.isEmpty)
              const Text('No customer or vendor credit limits are configured yet.')
            else
              ...rows.take(10).map((row) {
                final usage = _double(row['usage_percent']);
                final over = _double(row['over_by']);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: (over > 0 ? AppTheme.danger : AppTheme.warning).withValues(alpha: .12),
                            child: Icon(row['party_type'] == 'vendor' ? Icons.storefront_rounded : Icons.person_rounded, color: over > 0 ? AppTheme.danger : AppTheme.warning),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((row['party_name'] ?? 'Party').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text('${_title((row['party_type'] ?? '').toString())} • ${_title((row['mode'] ?? '').toString())} mode'),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${usage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: over > 0 ? AppTheme.danger : AppTheme.warning,
                                ),
                              ),
                              Text(
                                '${AppCurrency.format(row['balance'])} of ${AppCurrency.format(row['credit_limit'])}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                over > 0 ? '${AppCurrency.format(over)} over limit' : '${AppCurrency.format(row['available'])} available',
                                style: TextStyle(fontWeight: FontWeight.w700, color: over > 0 ? AppTheme.danger : null),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (usage / 100).clamp(0.0, 1.0).toDouble(),
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(over > 0 ? AppTheme.danger : AppTheme.warning),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _AuditTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _AuditTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth < 1480 ? 1480.0 : constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: DataTable(
                headingRowHeight: 50,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 76,
                horizontalMargin: 18,
                columnSpacing: 26,
                dividerThickness: .7,
                headingRowColor: MaterialStatePropertyAll(
                  scheme.surfaceContainerHighest.withValues(alpha: .72),
                ),
                border: TableBorder(
                  top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
                  bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
                  left: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
                  right: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
                  horizontalInside: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
                ),
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Party')),
                  DataColumn(label: Text('Event')),
                  DataColumn(label: Text('Transaction')),
                  DataColumn(label: Text('Before'), numeric: true),
                  DataColumn(label: Text('After'), numeric: true),
                  DataColumn(label: Text('Limit'), numeric: true),
                  DataColumn(label: Text('Exceeded'), numeric: true),
                  DataColumn(label: Text('Approved by')),
                  DataColumn(label: Text('Reason')),
                ],
                rows: List.generate(rows.length, (index) {
                  final row = rows[index];
                  return DataRow(
                    color: index.isOdd
                        ? MaterialStatePropertyAll(scheme.surfaceContainerLowest.withValues(alpha: .45))
                        : null,
                    cells: [
                      DataCell(_AuditDateCell(value: row['created_at'])),
                      DataCell(_PartyCell(row: row)),
                      DataCell(_OutcomeChip(outcome: (row['outcome'] ?? 'warning').toString())),
                      DataCell(_SourceCell(row: row)),
                      DataCell(_MoneyText(value: row['balance_before'])),
                      DataCell(_MoneyText(value: row['balance_after'], strong: true)),
                      DataCell(_MoneyText(value: row['credit_limit'])),
                      DataCell(_MoneyText(value: row['exceeded_by'], danger: _double(row['exceeded_by']) > 0)),
                      DataCell(Text((row['actor_name'] ?? 'System').toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(_ReasonCell(value: row['override_reason'])),
                    ],
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuditDateCell extends StatelessWidget {
  final dynamic value;
  const _AuditDateCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final raw = (value ?? '').toString();
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (parsed == null) return Text(raw);
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('dd MMM yyyy').format(parsed), style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(DateFormat('hh:mm a').format(parsed), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PartyCell extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PartyCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final type = (row['party_type'] ?? '').toString();
    final isVendor = type == 'vendor';
    final color = isVendor ? AppTheme.info : AppTheme.primary;
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: .11),
            child: Icon(isVendor ? Icons.storefront_rounded : Icons.person_rounded, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['party_name'] ?? 'Party').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(_title(type), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCell extends StatelessWidget {
  final Map<String, dynamic> row;
  const _SourceCell({required this.row});

  @override
  Widget build(BuildContext context) {
    final type = _title((row['source_type'] ?? '').toString().replaceAll('_', ' '));
    final reference = (row['source_reference'] ?? '').toString().trim();
    return SizedBox(
      width: 190,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            reference.isEmpty ? 'Reference unavailable' : reference,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: reference.isEmpty ? Theme.of(context).colorScheme.onSurfaceVariant : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyText extends StatelessWidget {
  final dynamic value;
  final bool strong;
  final bool danger;
  const _MoneyText({required this.value, this.strong = false, this.danger = false});

  @override
  Widget build(BuildContext context) => Text(
        AppCurrency.format(value),
        textAlign: TextAlign.end,
        style: TextStyle(
          fontWeight: strong || danger ? FontWeight.w800 : FontWeight.w600,
          color: danger ? AppTheme.danger : null,
        ),
      );
}

class _ReasonCell extends StatelessWidget {
  final dynamic value;
  const _ReasonCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final reason = (value ?? '').toString().trim();
    final display = reason.isEmpty ? '—' : reason;
    return Tooltip(
      message: reason.isEmpty ? 'No reason recorded' : reason,
      child: SizedBox(
        width: 240,
        child: Text(display, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AuditCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final reason = (row['override_reason'] ?? '').toString().trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text((row['party_name'] ?? 'Party').toString(), style: const TextStyle(fontWeight: FontWeight.w900))),
                _OutcomeChip(outcome: (row['outcome'] ?? 'warning').toString()),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_displayDate(row['created_at'])} • ${_sourceLabel(row)}'),
            const Divider(height: 20),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _ValueText('Before', AppCurrency.format(row['balance_before'])),
                _ValueText('After', AppCurrency.format(row['balance_after'])),
                _ValueText('Limit', AppCurrency.format(row['credit_limit'])),
                _ValueText('Exceeded', AppCurrency.format(row['exceeded_by'])),
                _ValueText('User', (row['actor_name'] ?? 'System').toString()),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Reason: $reason'),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  final String outcome;
  const _OutcomeChip({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final color = switch (outcome) {
      'blocked' => AppTheme.danger,
      'override' => AppTheme.purple,
      'correction' => AppTheme.info,
      _ => AppTheme.warning,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(switch (outcome) {
        'blocked' => Icons.block_rounded,
        'override' => Icons.verified_user_rounded,
        'correction' => Icons.settings_backup_restore_rounded,
        _ => Icons.warning_amber_rounded,
      }, size: 16, color: color),
      label: Text(_title(outcome), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      backgroundColor: color.withValues(alpha: .10),
      side: BorderSide(color: color.withValues(alpha: .25)),
    );
  }
}

class _MetricData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _MetricData(this.label, this.value, this.icon, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;
  final bool loading;
  const _MetricCard({required this.data, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: data.color.withValues(alpha: .12), child: Icon(data.icon, color: data.color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loading ? '—' : '${data.value}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text(data.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final double width;
  final String value;
  final String label;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  const _FilterDropdown({
    required this.width,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        menuMaxHeight: 360,
        decoration: InputDecoration(labelText: label),
        items: items.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Tooltip(
                  message: e.value,
                  child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            )
            .toList(),
        onChanged: (v) => onChanged(v ?? ''),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final double width;
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateButton({required this.width, required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = date == null ? label : DateFormat('dd MMM yyyy').format(date!);
    return SizedBox(
      width: width,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_month_rounded, size: 19),
        label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  final String label;
  final String value;
  const _ValueText(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(label, style: Theme.of(context).textTheme.bodySmall), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))],
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Card(
    color: AppTheme.danger.withValues(alpha: .08),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [Expanded(child: Text(message)), TextButton(onPressed: onRetry, child: const Text('Retry'))]),
    ),
  );
}

class _EmptyAuditState extends StatelessWidget {
  const _EmptyAuditState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 36),
    child: Column(children: [Icon(Icons.fact_check_outlined, size: 44), SizedBox(height: 8), Text('No credit-control events match these filters.')]),
  );
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! Iterable) return [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

int _int(dynamic value, {int fallback = 0}) => value is int ? value : int.tryParse((value ?? '').toString()) ?? fallback;
double _double(dynamic value) => value is num ? value.toDouble() : double.tryParse((value ?? '0').toString()) ?? 0;
String? _date(DateTime? value) => value == null ? null : DateFormat('yyyy-MM-dd').format(value);
String _displayDate(dynamic value) {
  final raw = (value ?? '').toString();
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  return parsed == null ? raw : DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
}
String _sourceLabel(Map<String, dynamic> row) {
  final source = _title((row['source_type'] ?? '').toString().replaceAll('_', ' '));
  final ref = (row['source_reference'] ?? '').toString().trim();
  return ref.isEmpty ? source : '$source • $ref';
}
String _title(String value) => value.split(' ').map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}').join(' ');
