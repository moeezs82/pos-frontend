import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/period_lock_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Needed to change the lock (the backend enforces it as well).
const kPeriodLockPermission = 'manage-period-lock';

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

DateTime? _parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Accounting period lock for the active branch: no sale, purchase, payment,
/// expense or adjustment can be posted on or before the lock date.
class PeriodLockScreen extends StatefulWidget {
  const PeriodLockScreen({super.key});

  @override
  State<PeriodLockScreen> createState() => _PeriodLockScreenState();
}

class _PeriodLockScreenState extends State<PeriodLockScreen> {
  late final PeriodLockService _api;
  final _reasonCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _state = const {};
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    _api = PeriodLockService(token: context.read<AuthProvider>().token ?? '');
    _fetch();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String? get _current => _state['closed_through']?.toString();
  String? get _yearClose => _state['year_close_closed_through']?.toString();
  String? get _effective => _state['effective_closed_through']?.toString();
  DateTime get _today => _parse(_state['today']) ?? DateTime.now();

  /// A move backwards (or clearing the lock) re-opens posted periods.
  bool get _isBackward {
    final cur = _current;
    if (cur == null) return false;
    return _picked == null || _ymd(_picked!).compareTo(cur) < 0;
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetch();
      if (!mounted) return;
      setState(() {
        _state = data;
        _picked = _parse(data['closed_through']);
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

  Future<void> _pickDate() async {
    final today = _today;
    final floor = _parse(_yearClose);
    final initial = _picked ?? today;
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: floor ?? DateTime(2000),
      lastDate: today,
      helpText: 'Lock the books through',
    );
    if (d != null) setState(() => _picked = d);
  }

  Future<void> _save({bool clear = false}) async {
    final target = clear ? null : _picked;
    if (!clear && target == null) {
      AppFeedback.warning(context, 'Choose a date first.');
      return;
    }
    final backward = clear || _isBackward;
    if (backward && _reasonCtrl.text.trim().length < 5) {
      AppFeedback.warning(context, 'Give a reason (at least 5 characters) to reopen a locked period.');
      return;
    }
    if (backward) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reopen locked period?'),
          content: Text(clear
              ? 'This removes the lock. Postings dated on or before ${_current ?? '-'} will be accepted again.'
              : 'Postings dated from ${_ymd(target!.add(const Duration(days: 1)))} to $_current will be accepted again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reopen')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      final data = await _api.update(closedThrough: target == null ? null : _ymd(target), reason: _reasonCtrl.text);
      if (!mounted) return;
      setState(() {
        _state = data;
        _picked = _parse(data['closed_through']);
        _reasonCtrl.clear();
      });
      AppFeedback.success(context, 'Period lock saved.');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, _errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.hasPermission(kPeriodLockPermission);
    final canReopen = _state['can_reopen'] == true;

    return EnterprisePage(
      title: 'Period Lock',
      subtitle: 'Lock this branch\'s books through a date. Nothing can be posted on or before it.',
      icon: Icons.lock_clock_outlined,
      actions: [
        OutlinedButton.icon(onPressed: _loading ? null : _fetch, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EnterpriseEmptyState(icon: Icons.error_outline, title: 'Could not load the period lock', subtitle: _error!)
              : ListView(
                  children: [
                    _statusCard(),
                    const SizedBox(height: 12),
                    if (canManage) _editCard(canReopen),
                    if (canManage) const SizedBox(height: 12),
                    _historyCard(),
                  ],
                ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Theme.of(context).dividerColor)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _line(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 220, child: Text(label, style: const TextStyle(color: AppTheme.textMuted))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
        ]),
      );

  Widget _statusCard() {
    final changedAt = _state['last_changed_at']?.toString();
    return _card(title: 'Current lock', children: [
      _line('Books locked through', _effective ?? 'Not locked', color: _effective == null ? AppTheme.success : AppTheme.danger),
      _line('Lock set here', _current ?? '—'),
      if (_yearClose != null) _line('Year-close lock (read-only)', _yearClose!),
      _line('Last changed by', _state['last_changed_by']?.toString() ?? '—'),
      _line('Last changed at', changedAt ?? '—'),
      if ((_state['last_reason'] ?? '').toString().isNotEmpty) _line('Reason', _state['last_reason'].toString()),
      if (_yearClose != null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('The year-close lock was set by the financial year close and cannot be changed or lowered here.',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
    ]);
  }

  Widget _editCard(bool canReopen) {
    final backward = _isBackward;
    return _card(title: 'Change lock date', children: [
      Row(children: [
        Expanded(
          child: InkWell(
            onTap: _saving ? null : _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Lock through (inclusive)', suffixIcon: Icon(Icons.calendar_month_outlined)),
              child: Text(_picked == null ? 'Choose a date' : _ymd(_picked!)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text('Dates after today cannot be locked. Moving the lock forward is allowed for users with this permission; '
          'moving it back reopens a closed period and is Master Admin only, with a reason.',
          style: const TextStyle(color: AppTheme.textMuted)),
      if (backward || canReopen) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _reasonCtrl,
          maxLength: 500,
          decoration: InputDecoration(labelText: backward ? 'Reason for reopening *' : 'Reason (needed only to reopen)'),
        ),
      ],
      if (backward && !canReopen)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Only a Master Admin can move the lock backwards.', style: TextStyle(color: AppTheme.danger)),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _saving || (backward && !canReopen) ? null : () => _save(),
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline, size: 18),
          label: Text(backward ? 'Reopen to this date' : 'Save lock'),
        ),
        if (canReopen && _current != null)
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _save(clear: true),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Remove lock'),
          ),
      ]),
    ]);
  }

  Widget _historyCard() {
    final history = (_state['history'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return _card(title: 'Change history', children: [
      if (history.isEmpty) const Text('No changes yet.', style: TextStyle(color: AppTheme.textMuted)),
      if (history.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 38,
            columns: const [
              DataColumn(label: Text('When')),
              DataColumn(label: Text('By')),
              DataColumn(label: Text('Action')),
              DataColumn(label: Text('From')),
              DataColumn(label: Text('To')),
              DataColumn(label: Text('Reason')),
            ],
            rows: history
                .map((h) => DataRow(cells: [
                      DataCell(Text(h['created_at']?.toString() ?? '')),
                      DataCell(Text(h['actor_name']?.toString() ?? '')),
                      DataCell(Text(h['action']?.toString() ?? '')),
                      DataCell(Text(h['old_closed_through']?.toString() ?? '—')),
                      DataCell(Text(h['new_closed_through']?.toString() ?? '—')),
                      DataCell(Text(h['reason']?.toString() ?? '')),
                    ]))
                .toList(),
          ),
        ),
    ]);
  }
}
