import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "Payables & Prepaids" tab of the Cash Ledger (add-on `extended_accounts`).
///
/// Shows what the branch owes each lender (2300), accrued expenses not yet
/// paid (2310) and prepaid expenses not yet used (1500), all read from the GL.
/// It also lists the latest loan/accrual/prepaid entries with Void, because
/// accruals and prepaid recognitions have no cash leg and therefore never
/// appear in the cash-account based Ledger tab.
class ExtendedAccountsView extends StatefulWidget {
  /// Called after an entry is recorded or voided so the parent can refresh
  /// its ledger list.
  final VoidCallback? onRecorded;

  const ExtendedAccountsView({super.key, this.onRecorded});

  @override
  State<ExtendedAccountsView> createState() => _ExtendedAccountsViewState();
}

class _ExtendedAccountsViewState extends State<ExtendedAccountsView> {
  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};
  int? _voidingId;

  /// When set, the entry form for this category is hosted inside the tab
  /// (embedded mode) so the desktop shell stays visible.
  String? _formCategory;

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
      final data = await _service.getExtendedAccountsSummary();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
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

  void _onFormClosed(bool saved) {
    setState(() => _formCategory = null);
    if (saved) {
      widget.onRecorded?.call();
      _fetch();
    }
  }

  void _openReport() {
    const key = 'loans-accruals-prepaids';
    PosNavigation.openSingleton(
      routeId: PosRouteIds.report(key),
      builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: key),
    );
  }

  Future<void> _void(Map<String, dynamic> e) async {
    final id = (e['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Void entry?'),
        content: Text(
          'Void ${e['label']} of ${_money.format(_num(e['amount']))}? '
          'A reversing journal entry is posted; the original stays on record.',
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry voided and reversed.')));
      widget.onRecorded?.call();
      await _fetch();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(err))));
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  static num _num(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canRecord = auth.hasPermission(kExtendedAccountsPermission);
    final canReport = auth.hasPermission('view-reports');

    final formCategory = _formCategory;
    if (formCategory != null) {
      return CashLedgerCreateScreen(
        key: ValueKey(formCategory),
        initialCategory: formCategory,
        lockCategory: true,
        onClose: _onFormClosed,
      );
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

    final lenders = List<Map<String, dynamic>>.from(
      (_data['lenders'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final entries = List<Map<String, dynamic>>.from(
      (_data['entries'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    Widget action(String category, String label, IconData icon, {bool primary = false}) {
      void onPressed() => setState(() => _formCategory = category);
      return primary
          ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label))
          : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
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
              _BalanceCard(label: 'Loans payable', value: _money.format(_num(_data['loans_payable'])), color: AppTheme.info, icon: Icons.account_balance_rounded),
              _BalanceCard(label: 'Accrued expenses', value: _money.format(_num(_data['accrued_expenses'])), color: AppTheme.purple, icon: Icons.pending_actions_rounded),
              _BalanceCard(label: 'Prepaid expenses', value: _money.format(_num(_data['prepaid_expenses'])), color: AppTheme.teal, icon: Icons.event_available_rounded),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'As of ${_data['as_of'] ?? '—'}. Loans received are owed back, not income; accruals and prepaid '
            'recognition move expenses into the right period without moving cash.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canRecord) action('LOAN_RECEIVED', 'Loan Received', Icons.call_received_rounded, primary: true),
              if (canRecord) action('LOAN_REPAID', 'Repay Loan', Icons.call_made_rounded),
              if (canRecord) action('ACCRUED_EXPENSE', 'Accrue Expense', Icons.pending_actions_rounded),
              if (canRecord) action('ACCRUED_PAYMENT', 'Pay Accrued', Icons.task_alt_rounded),
              if (canRecord) action('PREPAID_PAYMENT', 'Prepay Expense', Icons.event_available_rounded),
              if (canRecord) action('PREPAID_EXPENSE_RECOGNISE', 'Recognise Prepaid', Icons.update_rounded),
              if (canReport)
                OutlinedButton.icon(
                  onPressed: _openReport,
                  icon: const Icon(Icons.query_stats_rounded, size: 18),
                  label: const Text('Report'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Lenders', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (lenders.isEmpty)
            const Text('Nothing is owed to any lender.', style: TextStyle(color: AppTheme.textMuted))
          else
            ...lenders.map((l) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text('${l['name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${l['party_type'] ?? ''}'),
                  trailing: Text(_money.format(_num(l['outstanding'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                )),
          const SizedBox(height: 20),
          Text('Recent entries', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Text('No loans payable, accrual or prepaid entries yet.', style: TextStyle(color: AppTheme.textMuted))
          else
            ...entries.map((e) {
              final voided = e['status'] == 'void';
              final dir = '${e['direction']}';
              final who = (e['party'] ?? e['reference_name'] ?? '').toString();
              final id = (e['id'] as num).toInt();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  dir == 'none' ? Icons.sync_alt_rounded : (dir == 'in' ? Icons.south_west_rounded : Icons.north_east_rounded),
                  color: voided ? AppTheme.textMuted : (dir == 'none' ? AppTheme.purple : (dir == 'in' ? AppTheme.success : AppTheme.danger)),
                ),
                title: Text(
                  '${e['label']}${who.isEmpty ? '' : ' — $who'}',
                  style: TextStyle(fontWeight: FontWeight.w700, decoration: voided ? TextDecoration.lineThrough : null),
                ),
                subtitle: Text('${e['txn_date']}${dir == 'none' ? ' · no cash' : ' · ${e['method'] ?? ''}'}${voided ? ' · voided' : ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_money.format(_num(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (canRecord && e['can_void'] == true)
                      _voidingId == id
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: 'Void',
                              onPressed: _voidingId == null ? () => _void(e) : null,
                              icon: const Icon(Icons.block_rounded, size: 18),
                            ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _BalanceCard({required this.label, required this.value, required this.color, required this.icon});

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
