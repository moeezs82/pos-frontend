import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/line_errors.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

/// Full-detail view of a dead-lettered offline sale.
///
/// Shows the complete sale as it was captured offline: customer, items,
/// payments, totals, and the exact error that caused it to dead-letter.
///
/// Provides two recovery actions:
///   1. **Create as New Sale** — submits a replica to the backend with a
///      fresh [client_ref] and no [offline_invoice_no]. On server success,
///      purges the corrupted queue row. The original transaction date is
///      preserved so the audit trail is correct.
///   2. **Discard from Queue** — after manager confirmation, hard-deletes
///      the queue row without creating a server record.
///
/// Returns `true` to the caller ([OfflineSyncScreen]) when the queue has
/// changed (replay success or discard) so it knows to reload the list.
class OfflineSaleDetailScreen extends StatefulWidget {
  final OfflineSaleQueueItem item;

  const OfflineSaleDetailScreen({super.key, required this.item});

  @override
  State<OfflineSaleDetailScreen> createState() => _OfflineSaleDetailScreenState();
}

class _OfflineSaleDetailScreenState extends State<OfflineSaleDetailScreen> {
  bool _replaying = false;
  bool _discarding = false;
  bool _approvingCredit = false;

  // ── Field-level errors ───────────────────────────────────────────────────

  /// Per-line errors parsed out of [OfflineSaleQueueItem.lastError].
  ///
  /// OfflineSyncService writes a 422's field bag into last_error as
  /// `items.0.quantity: <message>` lines, because the queue row is the only
  /// record of the rejection once the request is gone. Mapping them back to
  /// the line index is what turns "the server rejected this sale" into a
  /// specific, correctable complaint about one product.
  ///
  /// Keyed by line index; the value is the message.
  Map<int, LineError> get _lineErrors {
    return {
      for (final le in parseStoredLineErrors(widget.item.lastError))
        le.index: le,
    };
  }

  // ── Payload accessors ────────────────────────────────────────────────────

  Map<String, dynamic> get _meta =>
      (widget.item.payload['meta'] as Map?)?.cast<String, dynamic>() ?? {};

  Map<String, dynamic> get _totals =>
      (_meta['totals_snapshot'] as Map?)?.cast<String, dynamic>() ?? {};

  Map<String, dynamic> get _customer =>
      (_meta['customer_snapshot'] as Map?)?.cast<String, dynamic>() ?? {};

  List<Map<String, dynamic>> get _items {
    final raw = widget.item.payload['items'] as List? ?? [];
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  List<Map<String, dynamic>> get _payments {
    // Prefer meta snapshot (has readable method labels) over raw payload.
    final raw = (_meta['payments_snapshot'] as List?) ??
        (widget.item.payload['payments'] as List?) ??
        [];
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // ── Replay action ─────────────────────────────────────────────────────────

  Future<void> _replay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create as New Sale?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          'A new sale will be posted to the server with a fresh reference number. '
          'The original transaction date is preserved.\n\n'
          'The corrupted queue item will be removed once the server confirms the sale.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create Sale')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _replaying = true);

    try {
      final token = context.read<AuthProvider>().token!;
      final client = ApiClient(token: token);

      // Build a clean payload: new idempotency key, no offline reference
      // (avoids any collision), no register_shift_client_ref (let the backend
      // find the cashier's current open shift).
      final newPayload = Map<String, dynamic>.from(widget.item.payload)
        ..['client_ref'] = const Uuid().v4()
        ..remove('offline_invoice_no')
        ..remove('register_shift_client_ref');

      final res = await client
          .post('/sales', body: newPayload)
          .timeout(const Duration(seconds: 30));

      final data = res['data'] as Map? ?? {};
      final sale = data['sale'] as Map? ?? {};
      final invoiceNo = (data['invoice_no'] ?? sale['invoice_no'] ?? '—').toString();

      // Server confirmed — safe to remove the corrupted queue row.
      await OfflineSalesQueueService.instance.purge(widget.item.clientRef);

      if (!mounted) return;
      AppFeedback.success(context, 'Sale created as $invoiceNo.');
      Navigator.pop(context, true); // signal reload
    } catch (e) {
      if (!mounted) return;
      setState(() => _replaying = false);
      final msg = e is ApiException
          ? 'Server rejected the sale: ${e.message}'
          : 'Could not reach the server. Check your connection and try again.';
      AppFeedback.error(context, msg);
    }
  }

  // ── Correction action ─────────────────────────────────────────────────────

  /// Corrects one line's quantity and re-queues the sale.
  ///
  /// This is the counterpart to "Create as New Sale": that path re-sends the
  /// sale unchanged and only helps when the server-side cause has gone away.
  /// A quantity the unit forbids will be refused identically forever, so the
  /// only way out is to change the payload.
  Future<void> _correctQuantity(int index) async {
    final items = _items;
    if (index < 0 || index >= items.length) return;

    final lineError = _lineErrors[index];
    final error = lineError?.display ?? '';
    final rule = lineError?.assertedRule ?? QuantityRule.permissive;
    final current = _num(items[index]['quantity']);
    // Pre-fill with the quantity AS CAPTURED, fraction and all, not with a
    // rounded suggestion — the manager has to see what the cashier actually
    // rang up before deciding what it should have been.
    final initial = QuantityRule.permissive.format(current);
    final controller = TextEditingController(text: initial);
    String? fieldError = rule.validateText(initial);

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Correct Quantity',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: rule.allowDecimal,
                  signed: true,
                ),
                onChanged: (v) =>
                    setLocal(() => fieldError = rule.validateText(v)),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  errorText: fieldError,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'The sale totals are recalculated from the corrected lines. '
                'Recorded payments are left exactly as they were taken, so the '
                'balance may change — check it before handing the receipt over.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                final parsed = double.tryParse(text);
                final invalid = rule.validateText(text) ??
                    (parsed == null || parsed == 0
                        ? 'Enter a non-zero quantity.'
                        : null);
                if (invalid != null) {
                  setLocal(() => fieldError = invalid);
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save & Re-queue'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    final newQty = double.tryParse(controller.text.trim());
    if (newQty == null) return;

    try {
      await OfflineSalesQueueService.instance.updatePayloadAndReset(
        widget.item.clientRef,
        _payloadWithQuantity(index, newQty),
      );
      if (!mounted) return;
      AppFeedback.success(
          context, 'Quantity corrected. The sale is queued to sync again.');
      Navigator.pop(context, true); // signal reload
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not save the correction: $e');
    }
  }

  /// A deep-enough copy of the payload with line [index]'s quantity replaced
  /// and the totals snapshot recomputed.
  ///
  /// The snapshot is what the receipt prints from, so leaving a stale subtotal
  /// behind would put a number on paper that the posted sale never had. Paid
  /// is untouched — money already taken is a fact, not a derivation — so the
  /// balance absorbs the difference.
  Map<String, dynamic> _payloadWithQuantity(int index, double quantity) {
    final payload = Map<String, dynamic>.from(widget.item.payload);

    final items = _items
        .map((line) => Map<String, dynamic>.from(line))
        .toList(growable: false);
    items[index]['quantity'] = quantity;
    payload['items'] = items;

    // Same line formula the sale screen uses: qty x price, less the line's
    // own percentage discount.
    var subtotal = 0.0;
    for (final line in items) {
      final qty = _num(line['quantity']);
      final price = _num(line['price']);
      final discPct = _num(line['discount_pct']).clamp(0.0, 100.0);
      subtotal += qty * price * (1 - discPct / 100);
    }

    final discount = _num(payload['discount']);
    final tax = _num(payload['tax']);
    final total = subtotal - discount + tax;

    final meta = Map<String, dynamic>.from(
        (payload['meta'] as Map?)?.cast<String, dynamic>() ?? {});
    final totals = Map<String, dynamic>.from(
        (meta['totals_snapshot'] as Map?)?.cast<String, dynamic>() ?? {});
    final paid = _num(totals['paid']);

    totals['subtotal'] = subtotal;
    totals['total'] = total;
    totals['balance'] = total - paid;
    meta['totals_snapshot'] = totals;
    payload['meta'] = meta;

    return payload;
  }

  CreditLimitIssue? get _creditLimitIssue =>
      CreditLimitIssue.fromStoredError(widget.item.lastError);

  /// Adds an audited override reason to the SAME queued sale and resets it to
  /// pending. The original client_ref/offline reference are preserved, so the
  /// normal idempotent sync path is used and no replacement invoice is made.
  Future<void> _approveCreditOverride() async {
    final issue = _creditLimitIssue;
    if (issue == null) return;
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('override-party-credit-limit')) {
      AppFeedback.error(
        context,
        'You do not have permission to override a party credit limit.',
      );
      return;
    }

    final reason = await showCreditLimitOverrideDialog(context, issue);
    if (reason == null || !mounted) return;
    setState(() => _approvingCredit = true);
    try {
      final payload = Map<String, dynamic>.from(widget.item.payload)
        ..['credit_limit_override'] = {'reason': reason};
      await OfflineSalesQueueService.instance.updatePayloadAndReset(
        widget.item.clientRef,
        payload,
      );
      if (!mounted) return;
      AppFeedback.success(
        context,
        'Credit override added. The original sale is queued to sync again.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _approvingCredit = false);
      AppFeedback.error(context, 'Could not save the credit override: $e');
    }
  }

  // ── Discard action ────────────────────────────────────────────────────────

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard this Sale?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          'This will permanently delete the queued sale from this device. '
          'No record will be sent to the server.\n\n'
          'Only discard if you are certain this sale should not be recorded — '
          'for example, it was a test or a duplicate you already handled manually.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Discard')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _discarding = true);
    try {
      await OfflineSalesQueueService.instance.purge(widget.item.clientRef);
      if (!mounted) return;
      Navigator.pop(context, true); // signal reload
    } catch (e) {
      if (!mounted) return;
      setState(() => _discarding = false);
      AppFeedback.error(context, 'Could not discard the sale: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final creditIssue = _creditLimitIssue;
    final isBusy = _replaying || _discarding || _approvingCredit;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.offlineInvoiceNo != null
              ? 'Sale — ${item.offlineInvoiceNo}'
              : 'Offline Sale Details',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          // ── Scrollable content ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error banner — shown only for failed items
                  if (item.status == OfflineSaleStatus.failed &&
                      (item.lastError?.isNotEmpty ?? false)) ...[
                    _ErrorBanner(message: item.lastError!),
                    const SizedBox(height: 16),
                  ],

                  // Sale summary card
                  _SectionCard(
                    title: 'Sale Information',
                    child: Column(
                      children: [
                        _Row(label: 'Customer',
                            value: item.displayCustomerName),
                        if ((_customer['phone'] as String?)?.isNotEmpty ?? false)
                          _Row(label: 'Phone',
                              value: _customer['phone'].toString()),
                        if ((_customer['address'] as String?)?.isNotEmpty ?? false)
                          _Row(label: 'Address',
                              value: _customer['address'].toString()),
                        _Row(label: 'Date / Time',
                            value: _fmtDateTime(item.occurredAt)),
                        if (item.offlineInvoiceNo != null)
                          _Row(label: 'Offline Ref',
                              value: item.offlineInvoiceNo!),
                        _Row(label: 'Status',
                            value: _statusLabel(item.status),
                            valueColor: _statusColor(item.status)),
                        if (item.attempts > 0)
                          _Row(label: 'Sync Attempts',
                              value: '${item.attempts}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Items card
                  _SectionCard(
                    title: 'Items (${_items.length})',
                    child: _items.isEmpty
                        ? const Text('No items recorded.',
                            style: TextStyle(color: AppTheme.textMuted))
                        : Column(
                            children: [
                              // Header
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: const [
                                    Expanded(
                                        flex: 4,
                                        child: Text('Product',
                                            style: _headerStyle)),
                                    SizedBox(
                                        width: 48,
                                        child: Text('Qty',
                                            style: _headerStyle,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: 72,
                                        child: Text('Price',
                                            style: _headerStyle,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: 80,
                                        child: Text('Subtotal',
                                            style: _headerStyle,
                                            textAlign: TextAlign.right)),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              const SizedBox(height: 4),
                              ..._items.asMap().entries.map(
                                    (e) => _buildItemRow(e.value, e.key),
                                  ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Totals card
                  _SectionCard(
                    title: 'Totals',
                    child: Column(
                      children: [
                        if (_totals['subtotal'] != null)
                          _Row(label: 'Subtotal',
                              value: _fmtAmt(_totals['subtotal'])),
                        if (_totals['discount'] != null &&
                            (_totals['discount'] as num?) != 0)
                          _Row(label: 'Discount',
                              value: '− ${_fmtAmt(_totals['discount'])}',
                              valueColor: AppTheme.success),
                        if (_totals['tax'] != null &&
                            (_totals['tax'] as num?) != 0)
                          _Row(label: 'Tax',
                              value: _fmtAmt(_totals['tax'])),
                        const Divider(height: 12),
                        _Row(
                          label: 'Total',
                          value: _fmtAmt(_totals['total'] ?? item.displayTotal),
                          valueBold: true,
                        ),
                        if (_totals['paid'] != null)
                          _Row(label: 'Paid',
                              value: _fmtAmt(_totals['paid']),
                              valueColor: AppTheme.success),
                        if (_totals['balance'] != null &&
                            (_totals['balance'] as num?) != 0)
                          _Row(label: 'Balance Due',
                              value: _fmtAmt(_totals['balance']),
                              valueColor: AppTheme.danger),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Payments card
                  if (_payments.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Payments',
                      child: Column(
                        children: _payments.map(_buildPaymentRow).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Notes
                  if ((widget.item.payload['notes'] as String?)?.isNotEmpty ??
                      false) ...[
                    _SectionCard(
                      title: 'Notes',
                      child: Text(
                        widget.item.payload['notes'].toString(),
                        style: const TextStyle(
                            fontSize: 13.5, color: AppTheme.navy),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Extra padding so content clears the bottom action bar
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Bottom action bar ────────────────────────────────────────────
          if (item.status == OfflineSaleStatus.failed)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  // Discard button
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _discard,
                    icon: _discarding
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('Discard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: BorderSide(
                          color: AppTheme.danger.withOpacity(.4)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Credit-limit failures must retain the same sale and
                  // idempotency reference. Other dead letters keep the legacy
                  // manager replay action.
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusy
                          ? null
                          : (creditIssue != null
                              ? _approveCreditOverride
                              : _replay),
                      icon: (_replaying || _approvingCredit)
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(
                              creditIssue != null
                                  ? Icons.verified_user_rounded
                                  : Icons.add_circle_outline_rounded,
                              size: 18,
                            ),
                      label: Text(creditIssue != null
                          ? (_approvingCredit
                              ? 'Approving…'
                              : 'Approve & Re-queue')
                          : (_replaying
                              ? 'Creating…'
                              : 'Create as New Sale')),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item, int index) {
    final productId = item['product_id']?.toString() ?? '?';
    final qty = _num(item['quantity']);
    final price = _num(item['price']);
    final discPct = _num(item['discount_pct']);
    final linePrice = discPct > 0 ? price * (1 - discPct / 100) : price;
    final subtotal = linePrice * qty;
    final lineError = _lineErrors[index];
    final correctable = lineError != null &&
        widget.item.status == OfflineSaleStatus.failed &&
        lineError.assertedRule != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Product #$productId',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: lineError != null
                                ? AppTheme.danger
                                : AppTheme.navy)),
                    if (discPct > 0)
                      Text('${discPct.toStringAsFixed(0)}% off',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.success)),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('×${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: lineError != null
                            ? FontWeight.w800
                            : FontWeight.normal,
                        color: lineError != null
                            ? AppTheme.danger
                            : AppTheme.textMuted)),
              ),
              SizedBox(
                width: 72,
                child: Text(_fmtAmt(price),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13)),
              ),
              SizedBox(
                width: 80,
                child: Text(_fmtAmt(subtotal),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          // The line the server actually complained about, said in full and
          // attached to the line rather than buried in the banner above.
          if (lineError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 14, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(lineError.display,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppTheme.danger)),
                  ),
                  if (correctable)
                    TextButton(
                      onPressed: _replaying || _discarding
                          ? null
                          : () => _correctQuantity(index),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Fix quantity',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(Map<String, dynamic> payment) {
    final method = (payment['method'] as String? ?? 'cash').toUpperCase();
    final amount = _num(payment['amount']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(method,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: .3)),
          ),
          const Spacer(),
          Text(_fmtAmt(amount),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static const _headerStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
      letterSpacing: .2);

  String _fmtAmt(dynamic v) {
    final n = _num(v);
    return AppCurrency.format(n);
  }

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  String _statusLabel(OfflineSaleStatus s) => switch (s) {
        OfflineSaleStatus.pending  => 'Pending Sync',
        OfflineSaleStatus.syncing  => 'Syncing',
        OfflineSaleStatus.synced   => 'Synced',
        OfflineSaleStatus.failed   => 'Failed — Needs Attention',
      };

  Color _statusColor(OfflineSaleStatus s) => switch (s) {
        OfflineSaleStatus.pending  => AppTheme.warning,
        OfflineSaleStatus.syncing  => AppTheme.info,
        OfflineSaleStatus.synced   => AppTheme.success,
        OfflineSaleStatus.failed   => AppTheme.danger,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withOpacity(.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded,
                color: AppTheme.danger, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w600,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: .5)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: valueBold ? FontWeight.w800 : FontWeight.w700,
                  color: valueColor ?? AppTheme.navy),
            ),
          ),
        ],
      ),
    );
  }
}
