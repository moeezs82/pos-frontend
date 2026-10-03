import 'dart:ui' show FontFeature;
import 'package:enterprise_pos/screens/sales/parts/sale_profit_insight.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Summary row showing item count, subtotal, and inline editable discount, tax, and shipping.
class SaleSummaryRow extends StatelessWidget {
  final int itemCount;
  final double subtotal;
  final bool canViewProfit;
  final bool showProfitInsight;
  final VoidCallback onToggleProfitInsight;
  final TextEditingController discountController;
  final FocusNode discountFocusNode;
  final TextEditingController taxController;
  final FocusNode taxFocusNode;
  final TextEditingController shippingController;

  /// Header Disc/Tax/Ship inputs. Hidden for sales orders, whose totals are
  /// derived purely from line items.
  final bool showHeaderAdjustments;
  final FocusNode shippingFocusNode;
  final double linkedReturnCredit;
  final double linkedReturnOriginalOutstanding;
  final SaleProfitSummary profitSummary;
  final VoidCallback onProfitDetails;

  const SaleSummaryRow({
    super.key,
    required this.itemCount,
    required this.subtotal,
    required this.canViewProfit,
    required this.showProfitInsight,
    required this.onToggleProfitInsight,
    required this.discountController,
    required this.discountFocusNode,
    required this.taxController,
    required this.taxFocusNode,
    required this.shippingController,
    required this.shippingFocusNode,
    this.showHeaderAdjustments = true,
    required this.linkedReturnCredit,
    required this.linkedReturnOriginalOutstanding,
    required this.profitSummary,
    required this.onProfitDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              // Item count + subtotal (read-only)
              Text(
                '$itemCount item${itemCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Sub: ${AppCurrency.format(subtotal)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (canViewProfit) ...[
                const SizedBox(width: 5),
                Tooltip(
                  message: showProfitInsight
                      ? 'Hide profit insight'
                      : 'Show profit insight',
                  child: Material(
                    color: showProfitInsight
                        ? AppTheme.primary.withOpacity(.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: onToggleProfitInsight,
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          showProfitInsight
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 15,
                          color: showProfitInsight
                              ? AppTheme.primary
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),

              if (showHeaderAdjustments) ...[
                // Order Discount (editable inline)
                const Text(
                  'Disc(-):',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Focus: Ctrl+Shift+G',
                  child: SizedBox(
                    width: 70,
                    height: 36,
                    child: TextField(
                      controller: discountController,
                      focusNode: discountFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Order Tax (editable inline)
                const Text(
                  'Tax(+):',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Focus: Ctrl+Shift+T',
                  child: SizedBox(
                    width: 70,
                    height: 36,
                    child: TextField(
                      controller: taxController,
                      focusNode: taxFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Shipping Charges (editable inline)
                const Text(
                  'Ship(+):',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Shipping Charges — Focus: Ctrl+Shift+S',
                  child: SizedBox(
                    width: 70,
                    height: 36,
                    child: TextField(
                      controller: shippingController,
                      focusNode: shippingFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (linkedReturnCredit > .004)
          Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(.22)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.assignment_return_outlined,
                  size: 15,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  'Return credit ${AppCurrency.format(linkedReturnCredit)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Old invoice outstanding ${AppCurrency.format(linkedReturnOriginalOutstanding)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Original delivery refund: 0',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: canViewProfit && showProfitInsight
              ? SaleProfitStrip(
                  key: const ValueKey('sale-profit-strip'),
                  summary: profitSummary,
                  onDetails: onProfitDetails,
                )
              : const SizedBox.shrink(
                  key: ValueKey('sale-profit-strip-hidden'),
                ),
        ),
      ],
    );
  }
}
