import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_batch.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

/// What a bulk run leaves behind for the list screen.
class BulkRunResult {
  final BatchAction action;

  /// Ids the pre-flight held back (blocked) — they stay selected with a reason.
  final Map<int, String> held;
  final BatchOutcome? outcome;

  const BulkRunResult({required this.action, this.held = const {}, this.outcome});

  /// Ids that should remain selected: held, failed and unknown.
  Set<int> get remaining => {
        ...held.keys,
        ...?outcome?.failed.map((f) => f.id),
        ...?outcome?.unknown,
      };

  String get summaryLine {
    final o = outcome;
    if (o == null) return '';
    final parts = <String>['${action.verb}: ${o.succeeded.length} done'];
    if (o.failed.isNotEmpty) parts.add('${o.failed.length} failed');
    if (o.unknown.isNotEmpty) parts.add('${o.unknown.length} unknown');
    if (held.isNotEmpty) parts.add('${held.length} held back');
    return parts.join(' · ');
  }
}

/// Bulk action bar shown while one or more rows are selected.
class SalesOrderBulkBar extends StatelessWidget {
  final int selectedCount;
  final double selectedTotal;
  final bool canSubmit;
  final bool canApprove;
  final bool canConvert;
  final bool canCancel;
  final bool busy;
  final void Function(BatchAction action) onAction;
  final VoidCallback onClear;

  const SalesOrderBulkBar({
    super.key,
    required this.selectedCount,
    required this.selectedTotal,
    required this.canSubmit,
    required this.canApprove,
    required this.canConvert,
    required this.canCancel,
    required this.busy,
    required this.onAction,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Text('$selectedCount selected',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.navy)),
        const SizedBox(width: 8),
        Text(AppCurrency.format(selectedTotal),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textMuted)),
        const Spacer(),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (canSubmit)
            OutlinedButton.icon(
              onPressed: busy ? null : () => onAction(BatchAction.submit),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Submit'),
            ),
          if (canApprove)
            FilledButton.icon(
              onPressed: busy ? null : () => onAction(BatchAction.approve),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: const Text('Approve'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            ),
          if (canConvert)
            FilledButton.icon(
              onPressed: busy ? null : () => onAction(BatchAction.convert),
              icon: const Icon(Icons.point_of_sale_rounded, size: 16),
              label: const Text('Convert'),
            ),
          if (canApprove)
            OutlinedButton.icon(
              onPressed: busy ? null : () => onAction(BatchAction.reject),
              icon: const Icon(Icons.thumb_down_alt_outlined, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            ),
          if (canCancel)
            OutlinedButton.icon(
              onPressed: busy ? null : () => onAction(BatchAction.cancel),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            ),
          TextButton(
            onPressed: busy ? null : onClear,
            child: const Text('Clear selection'),
          ),
        ]),
      ]),
    );
  }
}

bool _eligible(BatchAction a, SalesOrder o) {
  switch (a) {
    case BatchAction.submit:
      return o.isDraft;
    case BatchAction.approve:
      return o.isSubmitted;
    case BatchAction.convert:
      return o.isApproved;
    case BatchAction.reject:
      return o.isSubmitted || o.isApproved;
    case BatchAction.cancel:
      return !o.isTerminal;
  }
}

class _Choice {
  final List<SalesOrder> orders;
  final String? paymentMode;
  final String? paymentMethod;
  final String? reason;
  const _Choice(this.orders, {this.paymentMode, this.paymentMethod, this.reason});
}

/// Runs one bulk action end to end: eligibility → pre-flight → confirm →
/// chunked progress → result sheet. Returns null if the operator backs out.
Future<BulkRunResult?> runBulkAction({
  required BuildContext context,
  required SalesOrderService service,
  required BatchAction action,
  required List<SalesOrder> selected,
}) async {
  final eligible = selected.where((o) => _eligible(action, o)).toList();
  final skipped = <int, String>{
    for (final o in selected)
      if (!_eligible(action, o))
        o.id: 'Cannot ${action.verb.toLowerCase()} an order that is ${SalesOrderStatus.label(o.status)}.',
  };
  if (eligible.isEmpty) {
    AppFeedback.warning(context, 'None of the selected orders can be ${action.verb.toLowerCase()}d.');
    return null;
  }

  // Pre-flight: approve and convert are triaged by the server's own
  // revalidation. Nothing is mutated until the operator confirms.
  var ready = eligible;
  final held = <int, String>{...skipped};
  List<BatchVerdict> verdicts = const [];
  var hasOpenShift = true;
  if (action == BatchAction.approve || action == BatchAction.convert) {
    try {
      verdicts = await _withSpinner(context, 'Checking ${eligible.length} orders…',
          service.batchRevalidate(eligible.map((o) => o.id).toList()));
    } catch (e) {
      if (context.mounted) {
        AppFeedback.error(context, 'Pre-check failed: ${e.toString().replaceFirst('Exception: ', '')}');
      }
      return null;
    }
    if (!context.mounted) return null;
    final byId = {for (final v in verdicts) v.id: v};
    ready = [];
    for (final o in eligible) {
      final v = byId[o.id];
      if (v == null) {
        held[o.id] = 'Order not found.';
      } else if (v.blockingCount > 0) {
        held[o.id] = v.firstBlocking ?? 'Blocking issue.';
      } else {
        ready.add(o);
      }
    }
    hasOpenShift = verdicts.isEmpty || verdicts.every((v) => v.hasOpenShift);
  }

  final warnings = verdicts.where((v) => v.warningCount > 0 && ready.any((o) => o.id == v.id)).length;
  final choice = await showDialog<_Choice>(
    context: context,
    builder: (_) => _PreflightDialog(
      action: action,
      ready: ready,
      heldCount: held.length,
      warningCount: warnings,
      hasOpenShift: hasOpenShift,
    ),
  );
  if (choice == null || !context.mounted) {
    return held.isEmpty ? null : BulkRunResult(action: action, held: held);
  }

  final progress = ValueNotifier<(int, int)>((0, 1));
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(label: '${action.verb}ing orders', progress: progress),
  );
  final outcome = await service.batchAction(
    action,
    choice.orders.map((o) => BatchRef(o.id, o.version)).toList(),
    reason: choice.reason,
    paymentMode: choice.paymentMode,
    paymentMethod: choice.paymentMethod,
    onProgress: (done, total) => progress.value = (done, total),
  );
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialog;
  progress.dispose();

  final result = BulkRunResult(action: action, held: held, outcome: outcome);
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (_) => _ResultDialog(result: result, orders: selected),
    );
  }
  return result;
}

Future<T> _withSpinner<T>(BuildContext context, String label, Future<T> work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 16),
        Expanded(child: Text(label)),
      ]),
    ),
  );
  try {
    return await work;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class _PreflightDialog extends StatefulWidget {
  final BatchAction action;
  final List<SalesOrder> ready;
  final int heldCount;
  final int warningCount;
  final bool hasOpenShift;

  const _PreflightDialog({
    required this.action,
    required this.ready,
    required this.heldCount,
    required this.warningCount,
    required this.hasOpenShift,
  });

  @override
  State<_PreflightDialog> createState() => _PreflightDialogState();
}

class _PreflightDialogState extends State<_PreflightDialog> {
  // Credit is the safe default for field bookings: it books no cash receipt.
  String _mode = PaymentModeValues.credit;
  String _method = 'cash';
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _needsReason =>
      widget.action == BatchAction.reject || widget.action == BatchAction.cancel;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final total = widget.ready.fold<double>(0, (s, o) => s + o.total);
    final n = widget.ready.length;
    final convert = a == BatchAction.convert;
    final canRun = n > 0 &&
        (!convert || widget.hasOpenShift) &&
        (!_needsReason || _reason.text.trim().isNotEmpty);

    return AlertDialog(
      title: Text('$n ready to ${a.verb.toLowerCase()}'
          '${widget.heldCount > 0 ? ' · ${widget.heldCount} need attention' : ''}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${a.verb} $n orders · ${AppCurrency.format(total)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          if (widget.warningCount > 0) ...[
            const SizedBox(height: 6),
            Text('${widget.warningCount} of these carry warnings (stock, price drift or age). '
                'They are not blocking — review them if unsure.',
                style: const TextStyle(color: AppTheme.warning, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          if (widget.heldCount > 0) ...[
            const SizedBox(height: 6),
            Text('${widget.heldCount} will be skipped and stay selected so you can review them.',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          ],
          if (convert) ...[
            const SizedBox(height: 14),
            const Text('Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: PaymentModeValues.credit,
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              title: const Text('Credit (collect later)'),
              subtitle: const Text('Invoices post to customer balances. No cash is booked.'),
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: PaymentModeValues.full,
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              title: const Text('Paid in full now'),
              subtitle: const Text('Books a receipt for each order total.'),
            ),
            if (_mode == PaymentModeValues.full)
              DropdownButtonFormField<String>(
                value: _method,
                decoration: const InputDecoration(labelText: 'Payment method', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
            if (!widget.hasOpenShift)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Open a register shift before converting orders.',
                    style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
          ],
          if (_needsReason) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: a == BatchAction.reject ? 'Rejection reason *' : 'Cancellation reason *',
                isDense: true,
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: canRun
              ? () => Navigator.pop(
                    context,
                    _Choice(
                      widget.ready,
                      paymentMode: convert ? _mode : null,
                      paymentMethod: convert && _mode == PaymentModeValues.full ? _method : null,
                      reason: _needsReason ? _reason.text.trim() : null,
                    ),
                  )
              : null,
          child: Text(convert && _mode == PaymentModeValues.credit
              ? '${a.verb} $n as credit'
              : '${a.verb} $n'),
        ),
      ],
    );
  }
}

/// Wire values for `payment_mode`.
class PaymentModeValues {
  static const credit = 'credit';
  static const full = 'full';
}

class _ProgressDialog extends StatelessWidget {
  final String label;
  final ValueNotifier<(int, int)> progress;
  const _ProgressDialog({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(label),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
          const SizedBox(height: 10),
          Text('Chunk ${p.$1 < p.$2 ? p.$1 + 1 : p.$2} of ${p.$2}'),
        ]),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  final BulkRunResult result;
  final List<SalesOrder> orders;
  const _ResultDialog({required this.result, required this.orders});

  @override
  Widget build(BuildContext context) {
    final o = result.outcome!;
    final byCode = o.failuresByCode();
    final firstInvoice = o.succeeded.where((s) => s.invoiceNo != null).map((s) => s.invoiceNo).firstOrNull;
    final names = {for (final x in orders) x.id: x.orderNumber};

    return AlertDialog(
      title: Text(result.summaryLine),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (o.succeeded.isNotEmpty) ...[
              Text('${o.succeeded.length} succeeded',
                  style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w800)),
              if (firstInvoice != null) Text('First invoice: $firstInvoice'),
              if (o.succeeded.any((s) => s.alreadyDone))
                Text('${o.succeeded.where((s) => s.alreadyDone).length} were already converted by an earlier run.',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
            ],
            for (final entry in byCode.entries) ...[
              Text('${entry.value.length} failed · ${entry.key}',
                  style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w800)),
              for (final f in entry.value.take(8))
                Text('${f.orderNumber.isNotEmpty ? f.orderNumber : (names[f.id] ?? '#${f.id}')}: ${f.message}',
                    style: const TextStyle(fontSize: 12.5)),
              if (entry.value.length > 8)
                Text('…and ${entry.value.length - 8} more', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
            ],
            if (o.unknown.isNotEmpty) ...[
              Text('${o.unknown.length} unknown outcome',
                  style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w800)),
              Text('${o.unknownReason ?? 'The request did not complete.'} '
                  'Run the action again: orders that already went through are reported as succeeded.',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
            ],
            if (result.held.isNotEmpty)
              Text('${result.held.length} were held back before sending and stay selected.',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
            if (o.failed.isNotEmpty)
              const Text('To retry the failed orders, run the action again — it re-checks them first.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          ]),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(result.remaining.isEmpty ? 'Done' : 'Done — keep failed selected'),
        ),
      ],
    );
  }
}
