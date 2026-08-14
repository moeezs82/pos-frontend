import 'dart:ui' show FontFeature;

import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SaleProfitStrip extends StatelessWidget {
  final SaleProfitSummary summary;
  final VoidCallback onDetails;

  const SaleProfitStrip({
    super.key,
    required this.summary,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final margin = summary.marginPercent;
    final isLoss = summary.grossProfit < -0.005;
    final isLowMargin = !isLoss && margin != null && margin < 5;
    final accent = isLoss
        ? AppTheme.danger
        : isLowMargin
            ? AppTheme.warning
            : AppTheme.success;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The Sale workspace is intentionally dense. Keep the insight useful
        // without forcing the totals row wider on smaller desktop windows.
        final showSupportingMetrics = constraints.maxWidth >= 650;
        final showSubtitle = constraints.maxWidth >= 540;

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withOpacity(.055),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(.20)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isLoss ? Icons.trending_down_rounded : Icons.insights_rounded,
                  size: 17,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            isLoss ? 'Invoice Loss' : 'Profit Insight',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                          ),
                        ),
                        if (summary.estimated) ...[
                          const SizedBox(width: 5),
                          _EstimateBadge(compact: true),
                        ],
                      ],
                    ),
                    if (showSubtitle) ...[
                      const SizedBox(height: 1),
                      const Text(
                        'Tax excluded • shipping included',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              if (showSupportingMetrics) ...[
                _StripMetric(
                  label: 'Net sales',
                  value: AppCurrency.format(summary.netSalesBeforeTax),
                ),
                _StripDivider(),
                _StripMetric(
                  label: 'COGS',
                  value: AppCurrency.format(summary.costOfGoods),
                ),
                _StripDivider(),
              ],
              _StripMetric(
                label: isLoss ? 'Loss' : 'Profit',
                value: AppCurrency.format(summary.grossProfit),
                valueColor: accent,
              ),
              _StripDivider(),
              _StripMetric(
                label: 'Margin',
                value: margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
                valueColor: accent,
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Open profit breakdown',
                child: IconButton(
                  onPressed: onDetails,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  color: AppTheme.navy,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  splashRadius: 17,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StripMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StripMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: valueColor ?? AppTheme.navy,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StripDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.border,
    );
  }
}

class _EstimateBadge extends StatelessWidget {
  final bool compact;

  const _EstimateBadge({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'At least one item is using catalog cost because a live inventory average cost is unavailable (for example, offline mode).',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 3,
        ),
        decoration: BoxDecoration(
          color: AppTheme.warning.withOpacity(.11),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppTheme.warning.withOpacity(.28)),
        ),
        child: Text(
          'EST.',
          style: TextStyle(
            color: AppTheme.warning,
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }
}

Future<void> showSaleProfitDetailsDialog(
  BuildContext context,
  SaleProfitSummary summary,
) {
  final margin = summary.marginPercent;
  final isLoss = summary.grossProfit < -0.005;
  final accent = isLoss ? AppTheme.danger : AppTheme.success;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.insights_rounded, color: accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Sale Profit Insight',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.navy,
                                ),
                              ),
                              if (summary.estimated) ...[
                                const SizedBox(width: 8),
                                const _EstimateBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Gross-margin preview for the current invoice. Tax is excluded from revenue; shipping charges are included.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Net Sales',
                        value: AppCurrency.format(summary.netSalesBeforeTax),
                        hint: 'After item + invoice discounts, before tax',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Cost of Goods',
                        value: AppCurrency.format(summary.costOfGoods),
                        hint: 'Current branch inventory carrying cost',
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: isLoss ? 'Gross Loss' : 'Gross Profit',
                        value: AppCurrency.format(summary.grossProfit),
                        hint: 'Net sales less COGS',
                        icon: isLoss
                            ? Icons.trending_down_rounded
                            : Icons.trending_up_rounded,
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Gross Margin',
                        value: margin == null ? '—' : '${margin.toStringAsFixed(2)}%',
                        hint: 'Profit ÷ net sales',
                        icon: Icons.percent_rounded,
                        accent: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _CountChip(
                      label: '${summary.profitableLines} profitable',
                      color: AppTheme.success,
                    ),
                    _CountChip(
                      label: '${summary.lowMarginLines} low margin',
                      color: AppTheme.warning,
                    ),
                    _CountChip(
                      label: '${summary.lossLines} below cost',
                      color: AppTheme.danger,
                    ),
                    if (summary.invoiceDiscount != 0)
                      _CountChip(
                        label:
                            'Invoice discount ${AppCurrency.format(summary.invoiceDiscount)}',
                        color: AppTheme.primary,
                      ),
                    if (summary.shippingRevenue != 0)
                      _CountChip(
                        label:
                            'Shipping revenue ${AppCurrency.format(summary.shippingRevenue)}',
                        color: AppTheme.teal,
                      ),
                  ],
                ),
              ),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: AppTheme.surfaceSoft,
                child: const Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text('Product', style: _headerStyle),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Net Sales',
                        style: _headerStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'COGS',
                        style: _headerStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Profit',
                        style: _headerStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Margin',
                        style: _headerStyle,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: summary.lines.isEmpty
                    ? const Center(
                        child: Text(
                          'Add products to see profit details.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: summary.lines.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: AppTheme.border,
                        ),
                        itemBuilder: (_, index) {
                          final line = summary.lines[index];
                          return _ProfitLineRow(line: line);
                        },
                      ),
              ),
              const Divider(height: 1, color: AppTheme.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.estimated
                            ? 'Estimated rows use the saved catalog cost because live average inventory cost is unavailable. Final accounting uses the backend stock valuation at posting time.'
                            : 'Cost basis uses the current branch average inventory cost. Final accounting is still authoritative because the backend re-reads stock valuation when the sale is posted.',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showSaleLineProfitDialog(
  BuildContext context,
  SaleProfitLine line,
) {
  final margin = line.marginPercent;
  final isLoss = line.profit < -0.005;
  final accent = isLoss ? AppTheme.danger : AppTheme.success;
  final netUnit = line.quantity == 0 ? 0.0 : line.netRevenue / line.quantity;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
        contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        title: Row(
          children: [
            Icon(Icons.insights_rounded, size: 20, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                ),
              ),
            ),
            if (line.estimated) const _EstimateBadge(),
          ],
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(label: 'Quantity', value: _quantityText(line.quantity)),
              _DetailRow(
                label: 'Sale price / unit',
                value: AppCurrency.format(line.unitPrice),
              ),
              if (line.discountAmount != 0)
                _DetailRow(
                  label: 'Item discount',
                  value: '-${AppCurrency.format(line.discountAmount.abs())}',
                ),
              if (line.invoiceDiscountShare != 0)
                _DetailRow(
                  label: 'Invoice discount share',
                  value:
                      '-${AppCurrency.format(line.invoiceDiscountShare.abs())}',
                ),
              _DetailRow(
                label: 'Net sale / unit',
                value: AppCurrency.format(netUnit),
              ),
              const Divider(height: 18, color: AppTheme.border),
              _DetailRow(
                label: 'Cost basis / unit',
                value: AppCurrency.format(line.unitCost),
                helper: line.costSource,
              ),
              _DetailRow(
                label: 'Line net sales',
                value: AppCurrency.format(line.netRevenue),
              ),
              _DetailRow(
                label: 'Line COGS',
                value: AppCurrency.format(line.costOfGoods),
              ),
              const Divider(height: 18, color: AppTheme.border),
              _DetailRow(
                label: isLoss ? 'Line loss' : 'Line profit',
                value: AppCurrency.format(line.profit),
                valueColor: accent,
                strong: true,
              ),
              _DetailRow(
                label: 'Gross margin',
                value: margin == null ? '—' : '${margin.toStringAsFixed(2)}%',
                valueColor: accent,
                strong: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

const TextStyle _headerStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w800,
  color: AppTheme.textMuted,
);

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color? accent;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.navy;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(.17)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _ProfitLineRow extends StatelessWidget {
  final SaleProfitLine line;

  const _ProfitLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final margin = line.marginPercent;
    final isLoss = line.profit < -0.005;
    final isLow = !isLoss && margin != null && margin < 5;
    final accent = isLoss
        ? AppTheme.danger
        : isLow
            ? AppTheme.warning
            : AppTheme.success;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      Text(
                        '${_quantityText(line.quantity)} × ${AppCurrency.format(line.unitPrice)} • ${line.costSource}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (line.estimated) ...[
                  const SizedBox(width: 5),
                  const _EstimateBadge(compact: true),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              AppCurrency.format(line.netRevenue),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              AppCurrency.format(line.costOfGoods),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              AppCurrency.format(line.profit),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              margin == null ? '—' : '${margin.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;
  final Color? valueColor;
  final bool strong;

  const _DetailRow({
    required this.label,
    required this.value,
    this.helper,
    this.valueColor,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: strong ? AppTheme.navy : AppTheme.textMuted,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (helper != null)
                  Text(
                    helper!,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 13 : 11,
              color: valueColor ?? AppTheme.navy,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _quantityText(double value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}
