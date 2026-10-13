import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/cash_ledger/owner_entry_form.dart';
import 'package:enterprise_pos/screens/cash_ledger/partners_screen.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  final _money = const AppMoneyFormatter();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _service = CashLedgerService(token: context.read<AuthProvider>().token ?? '');
    _fetch();
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

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
        ],
      ),
    );
  }
}

enum _OwnerEquityPane { summary, capital, drawings, partners }

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
