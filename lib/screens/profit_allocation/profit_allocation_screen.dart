import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/profit_allocation_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Posting and reversing need this permission (backend enforces it); reading
/// needs it, view-reports or view-cashbook. All of it needs add-on owner_equity.
const kProfitAllocationPermission = 'manage-profit-allocation';

String _errorText(Object e) {
  if (e is ApiException) {
    final errs = e.body?['errors'];
    if (errs is Map && errs.isNotEmpty) {
      final first = errs.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }
    if (e.message.trim().isNotEmpty) return e.message;
  }
  return e.toString().replaceFirst('Exception: ', '');
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
num _num(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;
List<Map<String, dynamic>> _maps(dynamic v) =>
    List<Map<String, dynamic>>.from((v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

/// Finance → Profit Allocation (phase 7). Posts each partner's share of a
/// closed period's net profit to their current account (DR 3050 / CR 3020),
/// once per period, and locks the books through the end of that period.
class ProfitAllocationScreen extends StatefulWidget {
  const ProfitAllocationScreen({super.key});

  @override
  State<ProfitAllocationScreen> createState() => _ProfitAllocationScreenState();
}

class _ProfitAllocationScreenState extends State<ProfitAllocationScreen> {
  late final ProfitAllocationService _api;
  final _money = const AppMoneyFormatter();

  bool _loading = true;
  String? _error;
  String _status = 'all';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _api = ProfitAllocationService(token: context.read<AuthProvider>().token ?? '');
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.list(status: _status == 'all' ? null : _status);
      if (!mounted) return;
      setState(() {
        _data = data;
        _items = _maps(data['items']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  void _openReport(String key) => PosNavigation.openSingleton(
        routeId: PosRouteIds.report(key),
        builder: (_) => EnterpriseReportsWorkspaceScreen(initialReportKey: key),
      );

  Future<void> _sync() async {
    final posted = await showDialog<bool>(context: context, builder: (_) => _SyncProfitDialog(api: _api));
    if (posted == true) _fetch();
  }

  Future<void> _reverse(Map<String, dynamic> a) async {
    final done = await showDialog<bool>(context: context, builder: (_) => _ReverseDialog(api: _api, allocation: a));
    if (done == true) _fetch();
  }

  /// Only the latest posted allocation (highest period end) can be reversed.
  int? get _latestPostedId {
    Map<String, dynamic>? latest;
    for (final a in _items) {
      if (a['status'] != 'posted') continue;
      if (latest == null || '${a['period_to']}'.compareTo('${latest['period_to']}') > 0) latest = a;
    }
    return latest == null ? null : (latest['id'] as num).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.hasPermission(kProfitAllocationPermission);
    final canReport = auth.hasPermission('view-reports');
    final suggested = _data['suggested'] is Map ? Map<String, dynamic>.from(_data['suggested'] as Map) : null;

    return EnterprisePage(
      title: 'Profit Allocation',
      subtitle: 'Post each partner\'s share of a closed period\'s profit to their current account. Once per period; the period is then locked.',
      icon: Icons.call_split_rounded,
      actions: [
        if (canManage)
          FilledButton.icon(onPressed: _sync, icon: const Icon(Icons.sync_rounded, size: 18), label: const Text('Sync profit')),
        if (canReport)
          OutlinedButton.icon(onPressed: () => _openReport('profit-allocations'), icon: const Icon(Icons.list_alt_rounded, size: 18), label: const Text('Allocations Report')),
        if (canReport)
          OutlinedButton.icon(onPressed: () => _openReport('partner-statement'), icon: const Icon(Icons.handshake_outlined, size: 18), label: const Text('Partner Statement')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(label: 'Allocated (posted)', value: _money.format(_num(_data['posted_total'])), icon: Icons.call_split_rounded, color: AppTheme.success),
              _StatCard(label: 'Allocated through', value: '${_data['last_allocated_to'] ?? '—'}', icon: Icons.event_available_rounded, color: AppTheme.info),
              _StatCard(label: 'Books locked through', value: '${_data['lock_through'] ?? '—'}', icon: Icons.lock_clock_outlined, color: AppTheme.warning),
              _StatCard(
                label: 'Next period',
                value: suggested == null ? 'Up to date' : '${suggested['period_from']} – ${suggested['period_to']}',
                icon: Icons.update_rounded,
                color: AppTheme.purple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'posted', label: Text('Posted')),
                ButtonSegment(value: 'reversed', label: Text('Reversed')),
              ],
              selected: {_status},
              onSelectionChanged: (s) {
                setState(() => _status = s.first);
                _fetch();
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildList(canManage)),
        ],
      ),
    );
  }

  Widget _buildList(bool canManage) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ]),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No profit allocations yet. Use "Sync profit" to allocate a closed period.', style: TextStyle(color: AppTheme.textMuted)),
      );
    }
    final latest = _latestPostedId;
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final a = _items[i];
          final id = (a['id'] as num).toInt();
          final reversed = a['status'] == 'reversed';
          final lines = _maps(a['lines']).map((l) => '${l['partner']} ${_money.format(_num(l['amount']))}').join(' · ');
          final who = reversed
              ? 'Reversed ${'${a['reversed_at'] ?? ''}'.split(' ').first} by ${a['reversed_by_name'] ?? '—'}: ${a['reversal_reason'] ?? ''}'
              : 'Posted ${'${a['created_at'] ?? ''}'.split(' ').first} by ${a['created_by_name'] ?? '—'}';
          return ListTile(
            leading: Icon(Icons.call_split_rounded, color: reversed ? AppTheme.textMuted : AppTheme.success),
            title: Text(
              '#$id  ·  ${a['period_from']} – ${a['period_to']}',
              style: TextStyle(fontWeight: FontWeight.w800, decoration: reversed ? TextDecoration.lineThrough : null),
            ),
            subtitle: Text('$lines\n$who', maxLines: 3, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_money.format(_num(a['net_profit'])), style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                _StatusChip(status: '${a['status']}'),
                if (canManage && id == latest)
                  IconButton(tooltip: 'Reverse', onPressed: () => _reverse(a), icon: const Icon(Icons.undo_rounded, size: 20)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sync profit (preview → confirm → post) ─────────────────────────────────

class _SyncProfitDialog extends StatefulWidget {
  final ProfitAllocationService api;
  const _SyncProfitDialog({required this.api});

  @override
  State<_SyncProfitDialog> createState() => _SyncProfitDialogState();
}

class _SyncProfitDialogState extends State<_SyncProfitDialog> {
  final _money = const AppMoneyFormatter();
  final _note = TextEditingController();
  String? _from;
  String? _to;
  Map<String, dynamic>? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.preview(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _preview = data;
        _from = data['period_from']?.toString() ?? _from;
        _to = data['period_to']?.toString() ?? _to;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool isFrom) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final current = DateTime.tryParse((isFrom ? _from : _to) ?? '') ?? yesterday;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(yesterday) ? yesterday : current,
      firstDate: DateTime(2020),
      lastDate: yesterday,
      helpText: isFrom ? 'Period from' : 'Period to (must be before today)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = _ymd(picked);
        _to ??= _from;
      } else {
        _to = _ymd(picked);
        _from ??= _to;
      }
    });
    _load();
  }

  Future<void> _post() async {
    final p = _preview;
    if (p == null || p['can_post'] != true || _busy) return;
    final lockTo = p['lock_will_raise_to'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Post profit allocation?'),
        content: SizedBox(
          width: 420,
          child: Text(
            'This posts ${_money.format(_num(p['net_profit']))} for $_from – $_to to the partners\' current accounts '
            '(DR 3050 / CR 3020), dated today.'
            '${lockTo != null ? '\n\nThe books will be locked through $lockTo: nothing dated on or before that day can be posted afterwards. Reversing the allocation does not unlock it.' : ''}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(d, true), child: const Text('Post allocation')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post(from: _from!, to: _to!, expectedNetProfit: _num(p['net_profit']), note: _note.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profit for $_from – $_to allocated to partners.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(e);
      });
      // The figures may have changed (stale preview): show the current ones.
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final lines = _maps(p?['lines']);
    final blockers = _maps(p?['blockers']);
    final warnings = _maps(p?['warnings']);
    final pct = _num(p?['percent_total']);
    final canPost = p != null && p['can_post'] == true && !_busy;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _post},
      child: AlertDialog(
        title: const Text('Sync profit to partners'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _DateButton(label: 'From', value: _from, onTap: _busy ? null : () => _pick(true))),
                    const SizedBox(width: 12),
                    Expanded(child: _DateButton(label: 'To', value: _to, onTap: _busy ? null : () => _pick(false))),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Only fully closed days can be allocated. Allocated periods cannot overlap; losses are not allocated.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (_busy && p == null) const LinearProgressIndicator(),
                if (_error != null) _Message(text: _error!, color: AppTheme.danger, icon: Icons.error_outline_rounded),
                ...blockers.map((b) => _Message(text: '${b['message']}', color: AppTheme.danger, icon: Icons.block_rounded)),
                ...warnings.map((w) => _Message(text: '${w['message']}', color: AppTheme.warning, icon: Icons.warning_amber_rounded)),
                if (p != null && p['period_from'] != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      _Figure(label: 'Net profit', value: _money.format(_num(p['net_profit']))),
                      _Figure(
                        label: 'Active ownership',
                        value: '${pct.toStringAsFixed(2)}%',
                        color: (pct - 100).abs() < 0.005 ? null : AppTheme.danger,
                      ),
                      _Figure(label: 'To allocate', value: _money.format(_num(p['total_allocated']))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (lines.isNotEmpty)
                    DataTable(
                      headingRowHeight: 36,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 40,
                      columns: const [
                        DataColumn(label: Text('Partner')),
                        DataColumn(label: Text('Ownership'), numeric: true),
                        DataColumn(label: Text('Amount'), numeric: true),
                      ],
                      rows: lines
                          .map((l) => DataRow(cells: [
                                DataCell(ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 240),
                                  child: Text('${l['partner']}', overflow: TextOverflow.ellipsis),
                                )),
                                DataCell(Text('${_num(l['ownership_percent']).toStringAsFixed(2)}%')),
                                DataCell(Text(_money.format(_num(l['amount'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                              ]))
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    enabled: !_busy,
                    maxLength: 2000,
                    decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: canPost ? _post : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(_busy && p != null ? 'Working…' : 'Post allocation'),
          ),
        ],
      ),
    );
  }
}

// ── Reverse ─────────────────────────────────────────────────────────────────

class _ReverseDialog extends StatefulWidget {
  final ProfitAllocationService api;
  final Map<String, dynamic> allocation;
  const _ReverseDialog({required this.api, required this.allocation});

  @override
  State<_ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends State<_ReverseDialog> {
  final _money = const AppMoneyFormatter();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_reason.text.trim().length < 5) {
      setState(() => _error = 'Give a reason of at least 5 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.reverse((widget.allocation['id'] as num).toInt(), _reason.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profit allocation reversed.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.allocation;
    return AlertDialog(
      title: Text('Reverse allocation #${a['id']}?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Posts the exact mirror entry dated today, taking ${_money.format(_num(a['net_profit']))} for ${a['period_from']} – ${a['period_to']} '
              'back out of the partners\' current accounts. The period can then be allocated again. The period lock is not lowered.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              enabled: !_busy,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Reason *', counterText: ''),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Reversing…' : 'Reverse'),
        ),
      ],
    );
  }
}

// ── small widgets ────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;
  const _DateButton({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_rounded, size: 18),
      label: Text('$label: ${value ?? 'choose'}', overflow: TextOverflow.ellipsis),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Message({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Figure({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'posted' ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
