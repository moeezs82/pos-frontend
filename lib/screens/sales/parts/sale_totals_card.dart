import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

/// Totals card with inline editable Discount & Tax, with subtle hints.
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
    final t = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            // subtle tip line
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 14, color: t.hintColor),
                  const SizedBox(width: 6),
                  Text(
                    "Tip: tap Discount/Tax values to edit",
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
                  ),
                ],
              ),
            ),

            _rowStatic("Subtotal", "\$$subtotal"),

            // Editable Discount
            _rowEditable(
              context,
              label: "Discount",
              controller: discountController,
              prefix: "-\$",
              textColor: Colors.red,
            ),

            // Editable Tax
            _rowEditable(
              context,
              label: "Tax",
              controller: taxController,
              prefix: "\$",
              textColor: Colors.orange,
            ),

            const Divider(height: 8),
            ListTile(
              dense: false,
              title: const Text(
                "Total",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: Text(
                "\$$total",
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
            _rowStatic("Paid", "\$$paid"),
            ListTile(
              dense: true,
              title: const Text("Balance"),
              trailing: Text(
                "\$$balance",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: balanceColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowStatic(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _rowEditable(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String prefix = "\$",
    Color? textColor,
  }) {
    final t = Theme.of(context);

    bool _isZeroOrEmpty(String s) {
      final v = double.tryParse(s.trim());
      return (s.trim().isEmpty) || (v == null) || (v == 0);
    }

    final showHint = _isZeroOrEmpty(controller.text);

    return ListTile(
      dense: true,
      title: Row(
        children: [
          Text(label),
          const SizedBox(width: 6),
          Icon(Icons.edit_outlined, size: 14, color: t.hintColor), // small affordance near label
        ],
      ),
      trailing: SizedBox(
        width: 160,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            isDense: true,
            prefixText: prefix,
            hintText: showHint ? "tap to add" : null,
            hintStyle: t.textTheme.titleSmall?.copyWith(color: t.hintColor),
            // looks like text, not a box
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: const UnderlineInputBorder(), // subtle cue while typing
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            suffixIcon: Icon(Icons.edit_outlined, size: 16, color: t.hintColor),
            suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          ),
          style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
