import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SeasonsScreen extends StatefulWidget {
  const SeasonsScreen({super.key});

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  IntelligenceService? _service;
  IntelligenceEnvelope? _data;
  Object? _error;
  bool _loading = false;
  String _search = '';
  String _typeFilter = 'all';

  IntelligenceService _api() => _service ??= IntelligenceService(token: context.read<AuthProvider>().token!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final envelope = await _api().seasons();
      if (mounted) setState(() => _data = envelope);
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
      appBar: AppBar(
        title: const Text('Business Seasons'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add season'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? IntelligenceError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(),
    );
  }

  Widget _body() {
    final rows = asMapList(_data!.result);
    final annual = rows.where((r) => r['recurrence'] == 'annual_fixed').length;
    final dated = rows.where((r) => r['recurrence'] == 'dated').length;
    final missingYear = rows.where((r) => r['missing_current_year'] == true).length;
    final active = rows.where((r) => r['is_active'] == true).length;

    final filtered = rows.where((row) {
      if (_typeFilter == 'annual' && row['recurrence'] != 'annual_fixed') return false;
      if (_typeFilter == 'dated' && row['recurrence'] != 'dated') return false;
      if (_typeFilter == 'attention' && row['missing_current_year'] != true) return false;
      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (row['name']?.toString() ?? '').toLowerCase().contains(q) ||
          (row['notes']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const IntelligencePageHeader(
            title: 'Business Seasons',
            subtitle: 'Tell CounterIQ when your business expects seasonal demand so replenishment can explain and measure the uplift using your own sales history.',
          ),
          const SizedBox(height: 14),
          IntelligenceMetaBar(
            computedAt: _data!.computedAt,
            stale: _data!.stale,
            refreshing: _loading,
            onRefresh: _load,
          ),
          const SizedBox(height: 16),
          _introBanner(),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _summaryCard(
                icon: Icons.event_note_rounded,
                color: AppTheme.purple,
                title: 'Configured seasons',
                value: '${rows.length}',
                caption: '$active active in this branch',
              ),
              _summaryCard(
                icon: Icons.repeat_rounded,
                color: AppTheme.info,
                title: 'Annual fixed',
                value: '$annual',
                caption: 'Same month/day pattern every year',
              ),
              _summaryCard(
                icon: Icons.date_range_rounded,
                color: AppTheme.warning,
                title: 'Declared dates',
                value: '$dated',
                caption: 'Year-specific dates entered manually',
              ),
              _summaryCard(
                icon: Icons.warning_amber_rounded,
                color: missingYear > 0 ? AppTheme.danger : AppTheme.success,
                title: 'Needs attention',
                value: '$missingYear',
                caption: missingYear == 0 ? 'All dated seasons are current' : 'Missing current-year declared dates',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _filterBar(),
          const SizedBox(height: 18),
          if (filtered.isEmpty)
            IntelligenceEmptyState(
              title: rows.isEmpty ? 'No business seasons configured' : 'No seasons match these filters',
              subtitle: rows.isEmpty
                  ? 'Add Ramadan, Eid, summer, wedding season or any other period that affects your branch demand.'
                  : 'Clear the search or select another season type.',
              icon: Icons.event_busy_outlined,
            )
          else
            _seasonTable(filtered),
        ],
      ),
    );
  }

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7DEFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.purple),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calendar explains why. Your sales history measures what.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                  'Use Annual Fixed for predictable calendar periods. Use Declared Dates for dates that must be confirmed each year. CounterIQ never calculates or guesses religious dates such as Ramadan or Eid.',
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
                labelText: 'Search seasons',
                hintText: 'Name or notes',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          _filterChip('all', 'All'),
          _filterChip('annual', 'Annual fixed'),
          _filterChip('dated', 'Declared dates'),
          _filterChip('attention', 'Needs attention'),
          OutlinedButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add season'),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _typeFilter == value,
      onSelected: (_) => setState(() => _typeFilter = value),
    );
  }

  Widget _seasonTable(List<Map<String, dynamic>> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 1100 ? 1100.0 : constraints.maxWidth;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.softShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    _tableHeader(),
                    ...rows.map(_seasonRow),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableHeader() {
    const style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: AppTheme.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      color: const Color(0xFFFAFBFC),
      child: const Row(
        children: [
          Expanded(flex: 26, child: Text('Season', style: style)),
          Expanded(flex: 14, child: Text('Type', style: style)),
          Expanded(flex: 20, child: Text('Date range', style: style)),
          Expanded(flex: 12, child: Text('Year', style: style)),
          Expanded(flex: 14, child: Text('Status', style: style)),
          Expanded(flex: 24, child: Text('Notes', style: style)),
          SizedBox(width: 52),
        ],
      ),
    );
  }

  Widget _seasonRow(Map<String, dynamic> row) {
    final recurrence = row['recurrence']?.toString() ?? 'annual_fixed';
    final missingCurrentYear = row['missing_current_year'] == true;
    final status = _seasonStatus(row);
    final statusColor = _statusColor(status, missingCurrentYear);

    return InkWell(
      onTap: () => _showSeasonDetail(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
        child: Row(
          children: [
            Expanded(
              flex: 26,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (missingCurrentYear ? AppTheme.warning : AppTheme.purple).withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      missingCurrentYear ? Icons.warning_amber_rounded : Icons.event_repeat_rounded,
                      color: missingCurrentYear ? AppTheme.warning : AppTheme.purple,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['name']?.toString() ?? 'Season',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ID ${row['id'] ?? '—'} • Click to review',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 14, child: Align(alignment: Alignment.centerLeft, child: _modePill(recurrence))),
            Expanded(
              flex: 20,
              child: Text(
                _displayRange(row),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                recurrence == 'dated' ? '${row['occurrence_year'] ?? '—'}' : 'Every year',
                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 14,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: statusColor.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
                  child: Text(status, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: statusColor)),
                ),
              ),
            ),
            Expanded(
              flex: 24,
              child: Text(
                (row['notes']?.toString() ?? '').trim().isEmpty ? '—' : row['notes'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, height: 1.3),
              ),
            ),
            SizedBox(
              width: 52,
              child: PopupMenuButton<String>(
                tooltip: 'Manage season',
                onSelected: (value) {
                  if (value == 'edit') _edit(existing: row);
                  if (value == 'tag') _tag(row);
                  if (value == 'delete') _delete(row);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true)),
                  PopupMenuItem(value: 'tag', child: ListTile(leading: Icon(Icons.sell_outlined), title: Text('Apply to products'), dense: true)),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppTheme.danger), title: Text('Delete', style: TextStyle(color: AppTheme.danger)), dense: true)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modePill(String recurrence) {
    final dated = recurrence == 'dated';
    final color = dated ? AppTheme.warning : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Text(
        dated ? 'Declared dates' : 'Annual fixed',
        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _displayRange(Map<String, dynamic> row) {
    if (row['recurrence'] == 'dated') {
      return '${_prettyDate(row['starts_on']?.toString())} → ${_prettyDate(row['ends_on']?.toString())}';
    }
    final sm = (row['start_month'] as num?)?.toInt();
    final sd = (row['start_day'] as num?)?.toInt();
    final em = (row['end_month'] as num?)?.toInt();
    final ed = (row['end_day'] as num?)?.toInt();
    return '${_monthDay(sm, sd)} → ${_monthDay(em, ed)}';
  }

  String _prettyDate(String? raw) {
    final value = DateTime.tryParse(raw ?? '');
    if (value == null) return '—';
    return '${value.day.toString().padLeft(2, '0')} ${_months[value.month - 1]} ${value.year}';
  }

  String _monthDay(int? month, int? day) {
    if (month == null || day == null || month < 1 || month > 12) return '—';
    return '${day.toString().padLeft(2, '0')} ${_months[month - 1]}';
  }

  String _seasonStatus(Map<String, dynamic> row) {
    if (row['is_active'] != true) return 'Inactive';
    if (row['missing_current_year'] == true) return 'Needs dates';

    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    if (row['recurrence'] == 'dated') {
      start = DateTime.tryParse(row['starts_on']?.toString() ?? '');
      end = DateTime.tryParse(row['ends_on']?.toString() ?? '');
    } else {
      final sm = (row['start_month'] as num?)?.toInt();
      final sd = (row['start_day'] as num?)?.toInt();
      final em = (row['end_month'] as num?)?.toInt();
      final ed = (row['end_day'] as num?)?.toInt();
      if (sm != null && sd != null && em != null && ed != null) {
        start = DateTime(now.year, sm, sd);
        end = DateTime(now.year, em, ed, 23, 59, 59);
        if (end.isBefore(start)) {
          if (now.isBefore(end)) {
            start = DateTime(now.year - 1, sm, sd);
          } else {
            end = DateTime(now.year + 1, em, ed, 23, 59, 59);
          }
        }
      }
    }
    if (start == null || end == null) return 'Configured';
    if (!now.isBefore(start) && !now.isAfter(end)) return 'Active now';
    if (now.isBefore(start)) return 'Upcoming';
    return row['recurrence'] == 'annual_fixed' ? 'Next cycle' : 'Completed';
  }

  Color _statusColor(String status, bool missingCurrentYear) {
    if (missingCurrentYear || status == 'Needs dates') return AppTheme.danger;
    switch (status) {
      case 'Active now':
        return AppTheme.success;
      case 'Upcoming':
      case 'Next cycle':
        return AppTheme.info;
      case 'Inactive':
        return AppTheme.textMuted;
      case 'Completed':
        return AppTheme.warning;
      default:
        return AppTheme.purple;
    }
  }

  Future<void> _showSeasonDetail(Map<String, dynamic> row) async {
    final recurrence = row['recurrence']?.toString() ?? 'annual_fixed';
    final status = _seasonStatus(row);
    final statusColor = _statusColor(status, row['missing_current_year'] == true);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 760,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: AppTheme.purple.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
                    child: const Icon(Icons.event_repeat_rounded, color: AppTheme.purple),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['name']?.toString() ?? 'Season', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(_displayRange(row), style: const TextStyle(color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _modePill(recurrence),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
                    child: Text(status, style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
                  if (recurrence == 'dated') _detailPill('Year ${row['occurrence_year'] ?? '—'}'),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  (row['notes']?.toString() ?? '').trim().isEmpty
                      ? 'No notes have been added for this season.'
                      : row['notes'].toString(),
                  style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
                ),
              ),
              if (row['missing_current_year'] == true) ...[
                const SizedBox(height: 14),
                const IntelligenceInfoBanner(
                  icon: Icons.warning_amber_rounded,
                  title: 'Current-year dates are missing',
                  message: 'Create or update the declared date occurrence for the current year before relying on this season for upcoming replenishment context.',
                  color: AppTheme.warning,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _tag(row);
                    },
                    icon: const Icon(Icons.sell_outlined),
                    label: const Text('Apply to products'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _edit(existing: row);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit season'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final notes = TextEditingController(text: existing?['notes']?.toString() ?? '');
    String recurrence = existing?['recurrence']?.toString() ?? 'annual_fixed';
    bool isActive = existing == null ? true : existing['is_active'] == true;

    DateTime? startDate;
    DateTime? endDate;
    if (recurrence == 'dated') {
      startDate = DateTime.tryParse(existing?['starts_on']?.toString() ?? '');
      endDate = DateTime.tryParse(existing?['ends_on']?.toString() ?? '');
    } else {
      final sm = (existing?['start_month'] as num?)?.toInt();
      final sd = (existing?['start_day'] as num?)?.toInt();
      final em = (existing?['end_month'] as num?)?.toInt();
      final ed = (existing?['end_day'] as num?)?.toInt();
      if (sm != null && sd != null) startDate = DateTime(2000, sm, sd);
      if (em != null && ed != null) endDate = DateTime(2000, em, ed);
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pickStart() async {
            final annual = recurrence == 'annual_fixed';
            final initial = startDate ?? (annual ? DateTime(2000, 1, 1) : DateTime.now());
            final picked = await showDatePicker(
              context: ctx,
              initialDate: initial,
              firstDate: annual ? DateTime(2000, 1, 1) : DateTime(DateTime.now().year - 2),
              lastDate: annual ? DateTime(2000, 12, 31) : DateTime(DateTime.now().year + 5, 12, 31),
              helpText: annual ? 'Select annual start day' : 'Select season start date',
            );
            if (picked != null) setLocal(() => startDate = picked);
          }

          Future<void> pickEnd() async {
            final annual = recurrence == 'annual_fixed';
            final initial = endDate ?? startDate ?? (annual ? DateTime(2000, 1, 1) : DateTime.now());
            final picked = await showDatePicker(
              context: ctx,
              initialDate: initial,
              firstDate: annual ? DateTime(2000, 1, 1) : (startDate ?? DateTime(DateTime.now().year - 2)),
              lastDate: annual ? DateTime(2000, 12, 31) : DateTime(DateTime.now().year + 5, 12, 31),
              helpText: annual ? 'Select annual end day' : 'Select season end date',
            );
            if (picked != null) setLocal(() => endDate = picked);
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(28),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 650,
              constraints: const BoxConstraints(maxHeight: 760),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: AppTheme.purple.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                        child: Icon(existing == null ? Icons.add_rounded : Icons.edit_outlined, color: AppTheme.purple),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(existing == null ? 'Add business season' : 'Edit business season', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            const Text('Set the calendar context CounterIQ should use for seasonal demand.', style: TextStyle(color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(controller: name, decoration: const InputDecoration(labelText: 'Season name', hintText: 'e.g. Ramadan, Eid, Summer, Wedding Season')),
                          const SizedBox(height: 14),
                          const Text('Date type', style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _recurrenceOption(
                                  title: 'Annual fixed',
                                  subtitle: 'Same month/day pattern every year',
                                  icon: Icons.repeat_rounded,
                                  selected: recurrence == 'annual_fixed',
                                  onTap: () => setLocal(() {
                                    recurrence = 'annual_fixed';
                                    startDate = null;
                                    endDate = null;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _recurrenceOption(
                                  title: 'Declared dates',
                                  subtitle: 'Enter exact dates each year',
                                  icon: Icons.date_range_rounded,
                                  selected: recurrence == 'dated',
                                  onTap: () => setLocal(() {
                                    recurrence = 'dated';
                                    startDate = null;
                                    endDate = null;
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _dateField(
                                  label: recurrence == 'dated' ? 'Starts on' : 'Annual start',
                                  value: startDate == null
                                      ? 'Choose date'
                                      : recurrence == 'dated'
                                          ? _prettyDate(_iso(startDate!))
                                          : _monthDay(startDate!.month, startDate!.day),
                                  onTap: pickStart,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _dateField(
                                  label: recurrence == 'dated' ? 'Ends on' : 'Annual end',
                                  value: endDate == null
                                      ? 'Choose date'
                                      : recurrence == 'dated'
                                          ? _prettyDate(_iso(endDate!))
                                          : _monthDay(endDate!.month, endDate!.day),
                                  onTap: pickEnd,
                                ),
                              ),
                            ],
                          ),
                          if (recurrence == 'dated') ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14)),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Use declared dates for Ramadan, Eid or any season whose dates are confirmed separately each year. CounterIQ will not calculate future dates for you.',
                                      style: TextStyle(color: AppTheme.textMuted, height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'Explain the business context or expected behaviour')),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: const Text('Inactive seasons remain saved but are ignored by seasonal intelligence.'),
                            value: isActive,
                            onChanged: (value) => setLocal(() => isActive = value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          final seasonName = name.text.trim();
                          if (seasonName.isEmpty || startDate == null || endDate == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Name, start date and end date are required.')));
                            return;
                          }
                          if (recurrence == 'dated' && endDate!.isBefore(startDate!)) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('End date must be on or after start date.')));
                            return;
                          }
                          final body = <String, dynamic>{
                            'name': seasonName,
                            'recurrence': recurrence,
                            'is_active': isActive,
                            'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                          };
                          if (recurrence == 'dated') {
                            body['starts_on'] = _iso(startDate!);
                            body['ends_on'] = _iso(endDate!);
                            body['occurrence_year'] = startDate!.year;
                          } else {
                            body['start_month'] = startDate!.month;
                            body['start_day'] = startDate!.day;
                            body['end_month'] = endDate!.month;
                            body['end_day'] = endDate!.day;
                          }
                          Navigator.pop(ctx, body);
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(existing == null ? 'Create season' : 'Save changes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    name.dispose();
    notes.dispose();
    if (result == null) return;

    try {
      if (existing == null) {
        await _api().createSeason(result);
      } else {
        await _api().updateSeason((existing['id'] as num).toInt(), result);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
      }
    }
  }

  Widget _recurrenceOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: selected ? Colors.white : AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: selected ? AppTheme.primary : AppTheme.textMuted, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.25)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField({required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined)),
        child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: value == 'Choose date' ? AppTheme.textMuted : AppTheme.navy)),
      ),
    );
  }

  String _iso(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _tag(Map<String, dynamic> row) async {
    String scope = 'product';
    Map<String, dynamic>? selected;

    Future<void> pickForScope(StateSetter setLocal) async {
      final token = context.read<AuthProvider>().token!;
      Map<String, dynamic>? picked;
      if (scope == 'product') {
        picked = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProductPickerSheet(token: token),
        );
      } else {
        final common = CommonService(token: token);
        final items = scope == 'brand' ? await common.getBrands() : await common.getCategories();
        if (!mounted) return;
        picked = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => _ReferencePickerDialog(
            title: scope == 'brand' ? 'Select brand' : 'Select category',
            items: items,
          ),
        );
      }
      if (picked != null) setLocal(() => selected = picked);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Container(
            width: 540,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppTheme.purple.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.sell_outlined, color: AppTheme.purple),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Apply ${row['name']} to…', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                    IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose what this season applies to. Product tags are the most specific, followed by brand and category.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: scope,
                  decoration: const InputDecoration(labelText: 'Apply season to'),
                  items: const [
                    DropdownMenuItem(value: 'product', child: Text('A specific product')),
                    DropdownMenuItem(value: 'brand', child: Text('All products in a brand')),
                    DropdownMenuItem(value: 'category', child: Text('All products in a category')),
                  ],
                  onChanged: (value) => setLocal(() {
                    scope = value ?? scope;
                    selected = null;
                  }),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => pickForScope(setLocal),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(selected == null ? 'Choose ${scope == 'product' ? 'product' : scope}' : 'Change selection'),
                  ),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selected!['name']?.toString() ?? selected!['title']?.toString() ?? 'Selected item #${selected!['id']}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Apply season'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true || selected == null) return;
    final rawId = selected!['id'];
    if (rawId is! num) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The selected item does not contain a valid ID.')));
      }
      return;
    }

    try {
      await _api().addSeasonTag((row['id'] as num).toInt(), scope: scope, scopeId: rawId.toInt());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row['name']} now applies to ${selected!['name'] ?? selected!['title'] ?? 'the selected item'} .')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete season?'),
        content: Text('Delete ${row['name']} and its season tags? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete season'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api().deleteSeason((row['id'] as num).toInt());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
        }
      }
    }
  }

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _ReferencePickerDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const _ReferencePickerDialog({required this.title, required this.items});

  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final visible = widget.items.where((item) {
      if (q.isEmpty) return true;
      return (item['name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name'),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No matching items found.', style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = visible[index];
                        return ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.label_outline_rounded, color: AppTheme.primary, size: 19),
                          ),
                          title: Text(item['name']?.toString() ?? 'Unnamed'),
                          subtitle: Text('ID ${item['id'] ?? '—'}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
