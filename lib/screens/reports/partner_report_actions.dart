import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/partner_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/capital_reassign_dialog.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart' show kOwnerEquityPermission;
import 'package:enterprise_pos/screens/cash_ledger/partners_screen.dart';
import 'package:enterprise_pos/screens/profit_allocation/profit_allocation_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Action bar shown on the partner reports (Owner Equity, Partner Statement,
/// Profit Share, Profit Allocations) so the fixes for what the report shows
/// are one click away: manage partners, reassign unassigned capital, and
/// open Profit Allocation. The reports themselves stay read-only; every
/// action is enforced by the backend.
class PartnerReportActions extends StatelessWidget {
  final String reportKey;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;

  /// Called after something changed (partner saved, capital reassigned) so
  /// the report can be run again.
  final VoidCallback onChanged;

  const PartnerReportActions({super.key, required this.reportKey, required this.rows, required this.totals, required this.onChanged});

  static num _num(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;

  /// Book closing of the "Unassigned (no partner)" row (Partner Statement).
  num get _unassigned {
    for (final r in rows) {
      if (r['partner_id'] is num && (r['partner_id'] as num) == 0) return _num(r['book_closing']);
    }
    return 0;
  }

  /// Active ownership total, or null when this report does not show it.
  num? get _activePercent {
    if (reportKey == 'profit-share') return _num(totals['allocated_percent']);
    if (reportKey != 'partner-statement') return null;
    num total = 0;
    for (final r in rows) {
      if (r['status'] == 'active') total += _num(r['ownership_percent']);
    }
    return total;
  }

  Future<void> _openPartners(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (d) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          height: 620,
          child: PartnersScreen(onBack: () => Navigator.of(d).pop()),
        ),
      ),
    );
    onChanged();
  }

  Future<void> _reassign(BuildContext context, num fallback) async {
    final token = context.read<AuthProvider>().token ?? '';
    final ledger = CashLedgerService(token: token);
    // The amount that can be reassigned today; the report's figure is only
    // as of its end date. Falls back to it without cash-ledger access.
    num available = fallback;
    try {
      final summary = await ledger.getOwnerEquitySummary();
      available = _num(summary['unassigned_capital']);
    } catch (_) {}
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CapitalReassignDialog(service: ledger, partners: PartnerService(token: token), unassigned: available),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capital reassigned to partner.')));
      onChanged();
    }
  }

  void _openAllocation() => PosNavigation.openSingleton(
        routeId: PosRouteIds.profitAllocation,
        builder: (_) => const ProfitAllocationScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManageEquity = auth.hasPermission(kOwnerEquityPermission);
    final canAllocate = auth.hasPermission('view-reports') || auth.hasPermission('view-cashbook') || auth.hasPermission(kProfitAllocationPermission);
    final money = const AppMoneyFormatter();
    final unassigned = _unassigned;
    final pct = _activePercent;
    final pctOff = pct != null && (pct - 100).abs() >= 0.005;

    final messages = <Widget>[
      if (unassigned > 0.004)
        _Line(
          text: '${money.format(unassigned)} of capital is not assigned to any partner (the "Unassigned" row). '
              'Reassign it to the partner it belongs to; no cash moves.',
          action: canManageEquity
              ? FilledButton.icon(
                  onPressed: () => _reassign(context, unassigned),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Reassign to partner'),
                )
              : null,
        ),
      if (pctOff)
        _Line(
          text: pct == 0
              ? 'No active partners yet. Add every partner with their ownership % (together exactly 100%).'
              : 'Active partners add up to ${pct.toStringAsFixed(2)}%, not 100%. Add the missing partner(s) or correct the percentages; '
                  'profit cannot be allocated until the total is exactly 100%.',
          action: canManageEquity
              ? FilledButton.icon(
                  onPressed: () => _openPartners(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add / edit partners'),
                )
              : null,
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: messages.isEmpty ? Theme.of(context).colorScheme.surface : AppTheme.warning.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: messages.isEmpty ? Theme.of(context).dividerColor : AppTheme.warning.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...messages,
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Partners & profit:', style: TextStyle(fontWeight: FontWeight.w800)),
              OutlinedButton.icon(
                onPressed: () => _openPartners(context),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: Text(canManageEquity ? 'Manage partners' : 'View partners'),
              ),
              if (canAllocate)
                OutlinedButton.icon(
                  onPressed: _openAllocation,
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: const Text('Profit allocation'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Line({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
