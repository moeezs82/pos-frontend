import 'dart:ui' show FontFeature;
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class AmendmentDiff {
  final int added;
  final int removed;
  final int quantityChanged;
  final int priceChanged;
  final int discountChanged;
  final int packagingChanged;
  final bool sourceChanged;

  const AmendmentDiff({
    required this.added,
    required this.removed,
    required this.quantityChanged,
    required this.priceChanged,
    required this.discountChanged,
    required this.packagingChanged,
    required this.sourceChanged,
  });

  bool get hasChanges =>
      added > 0 ||
      removed > 0 ||
      quantityChanged > 0 ||
      priceChanged > 0 ||
      discountChanged > 0 ||
      packagingChanged > 0 ||
      sourceChanged;

  static AmendmentDiff compute({
    required List<Map<String, dynamic>> originalItems,
    required List<Map<String, dynamic>> currentItems,
    bool sourceChanged = false,
  }) {
    double editNum(dynamic value) =>
        double.tryParse(value?.toString() ?? '') ?? 0.0;
    int? metaInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final beforeById = <int, Map<String, dynamic>>{};
    for (final item in originalItems) {
      final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
      if (id != null) beforeById[id] = item;
    }
    final afterIds = <int>{};
    var added = 0;
    var quantityChanged = 0;
    var priceChanged = 0;
    var discountChanged = 0;
    var packagingChanged = 0;
    for (final item in currentItems) {
      final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
      if (id == null) {
        added++;
        continue;
      }
      afterIds.add(id);
      final old = beforeById[id];
      if (old == null) {
        added++;
        continue;
      }
      if ((editNum(old['quantity']) - editNum(item['quantity'])).abs() > .0004) {
        quantityChanged++;
      }
      if ((editNum(old['price']) - editNum(item['price'])).abs() > .0004) {
        priceChanged++;
      }
      if ((editNum(old['discount_pct']) - editNum(item['discount_pct'])).abs() >
              .0004 ||
          (old['discount_type'] ?? 'percentage').toString() !=
              (item['discount_type'] ?? 'percentage').toString()) {
        discountChanged++;
      }
      final oldPackageId = metaInt(old['packaging_id']);
      final newPackageId = metaInt(item['packaging_id']);
      if (oldPackageId != newPackageId ||
          (editNum(old['packaging_factor_snapshot']) -
                      editNum(item['packaging_factor_snapshot']))
                  .abs() >
              .0004 ||
          (editNum(old['packaging_quantity']) -
                      editNum(item['packaging_quantity']))
                  .abs() >
              .0004 ||
          (editNum(old['packaging_unit_price']) -
                      editNum(item['packaging_unit_price']))
                  .abs() >
              .0004 ||
          (old['packaging_name_snapshot'] ?? '').toString() !=
              (item['packaging_name_snapshot'] ?? '').toString()) {
        packagingChanged++;
      }
    }
    final removed =
        beforeById.keys.where((id) => !afterIds.contains(id)).length;
    return AmendmentDiff(
      added: added,
      removed: removed,
      quantityChanged: quantityChanged,
      priceChanged: priceChanged,
      discountChanged: discountChanged,
      packagingChanged: packagingChanged,
      sourceChanged: sourceChanged,
    );
  }
}

class AmendmentPaymentMethod {
  final String code;
  final String label;

  const AmendmentPaymentMethod(this.code, this.label);
}

class AmendmentReviewDecision {
  final String reason;
  final String settlementAction;
  final String settlementMethod;
  final double settlementAmount;
  final String reference;

  const AmendmentReviewDecision({
    required this.reason,
    required this.settlementAction,
    required this.settlementMethod,
    required this.settlementAmount,
    required this.reference,
  });
}

class SaleAmendmentReviewDialog extends StatefulWidget {
  final String invoiceNo;
  final int revision;
  final double originalTotal;
  final double revisedTotal;
  final double netPaid;
  final bool customerAttached;
  final bool deliverySale;
  final AmendmentDiff diff;
  final SaleProfitSummary? profit;
  final List<AmendmentPaymentMethod> paymentMethods;

  const SaleAmendmentReviewDialog({
    super.key,
    required this.invoiceNo,
    required this.revision,
    required this.originalTotal,
    required this.revisedTotal,
    required this.netPaid,
    required this.customerAttached,
    required this.deliverySale,
    required this.diff,
    required this.profit,
    required this.paymentMethods,
  });

  @override
  State<SaleAmendmentReviewDialog> createState() =>
      _SaleAmendmentReviewDialogState();
}

class _SaleAmendmentReviewDialogState
    extends State<SaleAmendmentReviewDialog> {
  final _reasonController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String _action = 'none';
  late String _method;
  String? _error;

  double get _balance => widget.revisedTotal - widget.netPaid;
  double get _requiredAmount => _balance.abs();

  @override
  void initState() {
    super.initState();
    _method = widget.paymentMethods.isNotEmpty
        ? widget.paymentMethods.first.code
        : 'cash';
    if (!widget.customerAttached && _requiredAmount > .004) {
      _action = _balance > 0 ? 'collect' : 'refund';
    }
    _amountController.text = _requiredAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String _settlementLabel(String action) {
    if (_balance > .004) {
      return action == 'collect'
          ? 'Collect now'
          : widget.customerAttached
              ? 'Leave as customer balance'
              : 'Must collect now';
    }
    if (_balance < -.004) {
      return action == 'refund'
          ? 'Refund now'
          : widget.customerAttached
              ? 'Keep as customer credit'
              : 'Must refund now';
    }
    return 'No settlement required';
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Enter a clear amendment reason (at least 5 characters).');
      return;
    }
    var amount = 0.0;
    if (_action != 'none') {
      amount = double.tryParse(_amountController.text.trim()) ?? 0;
      if (amount < .01) {
        setState(() => _error = 'Enter a valid settlement amount.');
        return;
      }
      if (!widget.customerAttached && (amount - _requiredAmount).abs() > .004) {
        setState(() => _error =
            'A walk-in invoice must be settled exactly (${AppCurrency.format(_requiredAmount)}).');
        return;
      }
      if (amount > _requiredAmount + .004) {
        setState(() => _error =
            'Settlement cannot exceed ${AppCurrency.format(_requiredAmount)}.');
        return;
      }
    }
    Navigator.of(context).pop(
      AmendmentReviewDecision(
        reason: reason,
        settlementAction: _action,
        settlementMethod: _method,
        settlementAmount: amount,
        reference: _referenceController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final difference = widget.revisedTotal - widget.originalTotal;
    final hasBalance = _requiredAmount > .004;
    final settlementOptions = <DropdownMenuItem<String>>[
      if (widget.customerAttached || !hasBalance)
        DropdownMenuItem(
          value: 'none',
          child: Text(_settlementLabel('none')),
        ),
      if (_balance > .004)
        DropdownMenuItem(
          value: 'collect',
          child: Text(_settlementLabel('collect')),
        ),
      if (_balance < -.004)
        DropdownMenuItem(
          value: 'refund',
          child: Text(_settlementLabel('refund')),
        ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Sale Amendment',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppTheme.navy,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text(
                          '${widget.invoiceNo}  •  Revision ${widget.revision} → ${widget.revision + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ReviewMetric(
                          label: 'Original Total',
                          value: AppCurrency.format(widget.originalTotal),
                        ),
                        _ReviewMetric(
                          label: 'Revised Total',
                          value: AppCurrency.format(widget.revisedTotal),
                        ),
                        _ReviewMetric(
                          label: 'Difference',
                          value:
                              '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
                          valueColor: difference.abs() <= .004
                              ? AppTheme.textMuted
                              : difference > 0
                                  ? AppTheme.warning
                                  : AppTheme.success,
                        ),
                        _ReviewMetric(
                          label: 'Already Settled',
                          value: AppCurrency.format(widget.netPaid),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.compare_arrows_rounded,
                      title: 'Changes in this revision',
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChangeChip(
                          icon: Icons.add_circle_outline,
                          label: '${widget.diff.added} added',
                          active: widget.diff.added > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.remove_circle_outline,
                          label: '${widget.diff.removed} removed',
                          active: widget.diff.removed > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.exposure_outlined,
                          label: '${widget.diff.quantityChanged} quantity',
                          active: widget.diff.quantityChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.price_change_outlined,
                          label: '${widget.diff.priceChanged} price',
                          active: widget.diff.priceChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.percent_rounded,
                          label: '${widget.diff.discountChanged} discount',
                          active: widget.diff.discountChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.inventory_2_outlined,
                          label: '${widget.diff.packagingChanged} packaging',
                          active: widget.diff.packagingChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.hub_outlined,
                          label: 'Sale From changed',
                          active: widget.diff.sourceChanged,
                        ),
                      ],
                    ),
                    if (widget.profit != null) ...[
                      const SizedBox(height: 18),
                      const _ReviewSectionTitle(
                        icon: Icons.insights_outlined,
                        title: 'Revised profit insight',
                      ),
                      const SizedBox(height: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceSoft,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'Net Sales',
                                value: AppCurrency.format(
                                  widget.profit!.netSalesBeforeTax,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'COGS',
                                value: AppCurrency.format(
                                  widget.profit!.costOfGoods,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: widget.profit!.grossProfit < 0
                                    ? 'Loss'
                                    : 'Gross Profit',
                                value: AppCurrency.format(
                                  widget.profit!.grossProfit,
                                ),
                                valueColor: widget.profit!.grossProfit < 0
                                    ? AppTheme.danger
                                    : AppTheme.success,
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'Margin',
                                value: widget.profit!.marginPercent == null
                                    ? '—'
                                    : '${widget.profit!.marginPercent!.toStringAsFixed(1)}%',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Settlement after amendment',
                    ),
                    const SizedBox(height: 9),
                    if (widget.deliverySale) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.delivery_dining_outlined,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _action == 'collect'
                                    ? 'This delivery collection will be assigned to the selected rider’s custody (1210), exactly like a normal paid delivery sale. It will not be added to the cashier drawer.'
                                    : _action == 'refund'
                                        ? 'This refund is paid from the selected payment account. Existing rider custody is preserved because already-collected rider money is a separate historical financial movement.'
                                        : 'Changing the invoice does not rewrite historical rider custody. Only actual new collections or refunds move money.',
                                style: const TextStyle(
                                  color: AppTheme.navy,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<String>(
                      value: _action,
                      decoration: InputDecoration(
                        labelText: _balance > .004
                            ? 'Revised balance due: ${AppCurrency.format(_balance)}'
                            : _balance < -.004
                                ? 'Customer credit: ${AppCurrency.format(-_balance)}'
                                : 'Invoice is exactly settled',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: settlementOptions,
                      onChanged: hasBalance && widget.customerAttached
                          ? (value) {
                              if (value == null) return;
                              setState(() {
                                _action = value;
                                _amountController.text =
                                    _requiredAmount.toStringAsFixed(2);
                              });
                            }
                          : null,
                    ),
                    if (_action != 'none') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              readOnly: !widget.customerAttached,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: InputDecoration(
                                labelText: _action == 'refund'
                                    ? 'Refund Amount'
                                    : 'Collection Amount',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _method,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Method',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: widget.paymentMethods.isEmpty
                                  ? const [
                                      DropdownMenuItem(
                                        value: 'cash',
                                        child: Text('Cash'),
                                      ),
                                    ]
                                  : widget.paymentMethods
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m.code,
                                          child: Text(
                                            m.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _method = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _referenceController,
                              decoration: const InputDecoration(
                                labelText: 'Reference (optional)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.description_outlined,
                      title: 'Amendment reason',
                    ),
                    const SizedBox(height: 9),
                    TextField(
                      controller: _reasonController,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText:
                            'Required — e.g. Customer changed size before delivery',
                        border: OutlineInputBorder(),
                        helperText:
                            'This reason becomes part of the permanent invoice audit trail.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Stock, COGS, AR, tax and ledger deltas commit together. If any validation fails, nothing is changed.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                    label: const Text('Save Amendment'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReviewMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 166,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _ReviewSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

class _ChangeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ChangeChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(.08) : AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppTheme.primary.withOpacity(.20) : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppTheme.primary : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.navy : AppTheme.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _InlineReviewValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InlineReviewValue({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class AmendmentHeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const AmendmentHeaderMetric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class AmendmentBottomMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const AmendmentBottomMetric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}
