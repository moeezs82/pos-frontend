import 'dart:ui' show FontFeature;
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';

class TotalsCardInline extends StatelessWidget {
  final String subtotal;
  final TextEditingController discountController;
  final TextEditingController taxController;
  final String total;
  final String paid;
  final String balance;
  final Color balanceColor;

  const TotalsCardInline({
    super.key,
    required this.subtotal,
    required this.discountController,
    required this.taxController,
    required this.total,
    required this.paid,
    required this.balance,
    required this.balanceColor,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Totals', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _rowStatic('Subtotal', subtotal),
          const SizedBox(height: 8),
          _rowEditable(context, label: 'Discount', controller: discountController, textColor: AppTheme.danger),
          const SizedBox(height: 8),
          _rowEditable(context, label: 'Tax', controller: taxController, textColor: AppTheme.warning),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _summaryLine('Grand Total', total, big: true),
          const SizedBox(height: 8),
          _summaryLine('Paid', paid),
          const SizedBox(height: 8),
          _summaryLine('Balance', balance, valueColor: balanceColor),
        ],
      ),
    );
  }

  Widget _rowStatic(String label, String value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }

  Widget _rowEditable(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    Color? textColor,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
        SizedBox(
          width: 118,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              prefixText: AppCurrency.inputPrefix(),
              suffixText: AppCurrency.inputSuffix,
              hintText: '0.00',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ],
    );
  }

  Widget _summaryLine(String label, String value, {bool big = false, Color? valueColor}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppTheme.navy,
                fontSize: big ? 24 : 16,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
