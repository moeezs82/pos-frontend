import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/partner_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/capital_reassign_dialog.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/owner_entry_form.dart';
import 'package:enterprise_pos/screens/cash_ledger/partners_screen.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/widgets/workspace_pages.dart';

/// Owner Equity tab of the Cash Ledger (add-on `owner_equity`).
///
/// Shows lifetime capital contributed, drawings and net owner equity from the
/// GL (3000/3010), with shortcuts to record capital/drawings and to open the
/// Owner Equity report. Drawings are equity, never an expense.
class OwnerEquityView extends StatefulWidget {
  /// Called after a capital/drawings entry is recorded so the parent can
  /// refresh its ledger list.
  final VoidCallback? onRecorded;

  const OwnerEquityView({super.key, this.onRecorded});

  @override
  State<OwnerEquityView> createState() => _OwnerEquityViewState();
}

class _OwnerEquityViewState extends State<OwnerEquityView> {
  late final CashLedgerService _service;
  late final PartnerService _partners;
  final _money = const AppMoneyFormatter();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  int? _voidingId;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token ?? '';
    _service = CashLedgerService(token: token);
    _partners = PartnerService(token: token);
    _fetch();
  }

  /// Phase 7a: move capital recorded without a partner to a partner.
  Future<void> _reassign() async {
    final saved = await PosWorkspacePages.open<bool>(
      context,
      builder: (_) => CapitalReassignDialog(service: _service, partners: _partners, unassigned: _num('unassigned_capital')),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capital reassigned to partner.')));
    widget.onRecorded?.call();
    _fetch();
  }

  Future<void> _voidReassign(Map<String, dynamic> e) async {
    final id = (e['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Void reassignment?'),
        content: Text(
          'Void the reassignment of ${_money.format(num.tryParse('${e['amount']}') ?? 0)} to ${e['party'] ?? 'the partner'}? '
          'A reversing entry dated today moves it back to unassigned capital; the original stays on record.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Void')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _voidingId = id);
    try {
      await _service.voidEntry(id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reassignment voided and reversed.')));
      widget.onRecorded?.call();
      await _fetch();
    } catch (err) {
      if (!mounted) return;
      var msg = err.toString().replaceFirst('Exception: ', '');
      if (err is ApiException) {
        final errs = err.body?['errors'];
        if (errs is Map && errs.isNotEmpty && errs.values.first is List && (errs.values.first as List).isNotEmpty) {
          msg = (errs.values.first as List).first.toString();
        } else if (err.message.trim().isNotEmpty) {
          msg = err.message;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getOwnerEquitySummary();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Sub-view shown inside this tab. Forms and the partner list are hosted
  /// here instead of being pushed as routes, so the desktop shell (sidebar and
  /// top bar) stays visible.
  _OwnerEquityPane _pane = _OwnerEquityPane.summary;

  void _showPane(_OwnerEquityPane pane) => setState(() => _pane = pane);

  void _backToSummary({bool reload = false}) {
    setState(() => _pane = _OwnerEquityPane.summary);
    if (reload) _fetch();
  }

  void _onEntryClosed(bool saved) {
    if (saved) widget.onRecorded?.call();
    _backToSummary(reload: saved);
  }

  /// Reports are shell workspaces: open them like the sidebar does so the
  /// report keeps the sidebar instead of opening a standalone report hub.
  void _openReport(String key) {
    PosNavigation.openSingleton(
      routeId: PosRouteIds.report(key),
      builder: (_) => EnterpriseReportsWorkspaceScreen(initialReportKey: key),
    );
  }

  num _num(String key) => num.tryParse('${_data[key] ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canRecord = auth.hasPermission(kOwnerEquityPermission);
    final canReport = auth.hasPermission('view-reports');

    switch (_pane) {
      case _OwnerEquityPane.capital:
      case _OwnerEquityPane.drawings:
        return OwnerEntryForm(
          key: ValueKey(_pane),
          kind: _pane == _OwnerEquityPane.capital ? OwnerEntryKind.capital : OwnerEntryKind.drawings,
          summary: _data,
          onClose: _onEntryClosed,
        );
      case _OwnerEquityPane.partners:
        return PartnersScreen(onBack: () => _backToSummary(reload: true));
      case _OwnerEquityPane.summary:
        break;
    }

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
          ],
        ),
      );
    }

    final unassigned = _num('unassigned_capital');
    final reassignments = List<Map<String, dynamic>>.from(
      (_data['reassignments'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final reassignMeta = CashLedgerCategoryMeta.capitalReassign;

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (unassigned > 0) ...[
            _UnassignedBanner(
              amount: _money.format(unassigned),
              onReassign: canRecord ? _reassign : null,
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _EquityCard(label: 'Capital contributed', value: _money.format(_num('capital_contributed')), color: AppTheme.success, icon: Icons.account_balance_rounded),
              _EquityCard(label: 'Owner drawings', value: _money.format(_num('drawings')), color: AppTheme.warning, icon: Icons.person_remove_alt_1_rounded),
              _EquityCard(label: 'Net owner equity', value: _money.format(_num('net_owner_equity')), color: AppTheme.info, icon: Icons.savings_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'As of ${_data['as_of'] ?? '—'}. Capital and drawings change owner equity only — they never appear in Profit & Loss or the expense report.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canRecord)
                FilledButton.icon(
                  onPressed: () => _showPane(_OwnerEquityPane.capital),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Record Capital'),
                ),
              if (canRecord)
                OutlinedButton.icon(
                  onPressed: () => _showPane(_OwnerEquityPane.drawings),
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  label: const Text('Record Drawings'),
                ),
              OutlinedButton.icon(
                onPressed: () => _showPane(_OwnerEquityPane.partners),
                icon: const Icon(Icons.handshake_rounded, size: 18),
                label: const Text('Partners'),
              ),
              if (canReport)
                OutlinedButton.icon(
                  onPressed: () => _openReport('owner-equity'),
                  icon: const Icon(Icons.query_stats_rounded, size: 18),
                  label: const Text('Owner Equity Report'),
                ),
            ],
          ),
          if (reassignments.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Capital reassignments', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...reassignments.map((e) {
              final voided = e['status'] == 'void';
              final id = (e['id'] as num).toInt();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(reassignMeta.icon, color: voided ? AppTheme.textMuted : reassignMeta.color),
                title: Text(
                  'To ${e['party'] ?? 'partner'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, decoration: voided ? TextDecoration.lineThrough : null),
                ),
                subtitle: Text(
                  '${e['txn_date']} · no cash${voided ? ' · voided' : ''}${(e['note'] ?? '').toString().isEmpty ? '' : ' · ${e['note']}'}',
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_money.format(num.tryParse('${e['amount']}') ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (canRecord && e['can_void'] == true)
                      _voidingId == id
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: 'Void',
                              onPressed: _voidingId == null ? () => _voidReassign(e) : null,
                              icon: const Icon(Icons.block_rounded, size: 18),
                            ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

enum _OwnerEquityPane { summary, capital, drawings, partners }

/// Shown while some owner capital is not tagged to any partner (usually
/// capital recorded before the first partner was added).
class _UnassignedBanner extends StatelessWidget {
  final String amount;
  final VoidCallback? onReassign;

  const _UnassignedBanner({required this.amount, this.onReassign});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: .45)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.warning),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              '$amount of capital is not assigned to any partner (shown as "Unassigned" on the Partner Statement).',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (onReassign != null)
            FilledButton.icon(
              onPressed: onReassign,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Reassign to partner'),
            ),
        ],
      ),
    );
  }
}

class _EquityCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _EquityCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
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
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
