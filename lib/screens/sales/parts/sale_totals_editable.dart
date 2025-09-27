import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

/// Summary card with inline editable Discount & Tax and a Save button.
/// Shows subtle edit affordances and only enables Save when value changed.
class SaleTotalsEditable extends StatefulWidget {
  final Map<String, dynamic> sale;
  final TextEditingController discountController;
  final TextEditingController taxController;
  final double paid;
  final Color balanceColor;
  final VoidCallback onSave;

  const SaleTotalsEditable({
    super.key,
    required this.sale,
    required this.discountController,
    required this.taxController,
    required this.paid,
    required this.balanceColor,
    required this.onSave,
  });

  @override
  State<SaleTotalsEditable> createState() => _SaleTotalsEditableState();
}

class _SaleTotalsEditableState extends State<SaleTotalsEditable> {
  late String _initialDiscount;
  late String _initialTax;

  @override
  void initState() {
    super.initState();
    _initialDiscount = (widget.sale['discount'] ?? 0).toString();
    _initialTax = (widget.sale['tax'] ?? 0).toString();

    widget.discountController.addListener(_onChanged);
    widget.taxController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.discountController.removeListener(_onChanged);
    widget.taxController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _dirty =>
      widget.discountController.text.trim() != _initialDiscount.trim() ||
      widget.taxController.text.trim() != _initialTax.trim();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final subtotal = double.tryParse(widget.sale['subtotal'].toString()) ?? 0.0;
    final discount = double.tryParse(widget.discountController.text.trim()) ?? 0.0;
    final tax = double.tryParse(widget.taxController.text.trim()) ?? 0.0;
    final total = (subtotal - discount + tax).clamp(0, double.infinity);
    final remaining = total - widget.paid;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            // little tip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 14, color: t.hintColor),
                  const SizedBox(width: 6),
                  Text(
                    "Tip: tap Discount/Tax to edit, then Save",
                    style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
                  ),
                ],
              ),
            ),

            _rowStatic("Subtotal", "\$${subtotal.toStringAsFixed(2)}"),
            _rowEditable(
              context,
              label: "Discount",
              controller: widget.discountController,
              prefix: "-\$",
              textColor: Colors.red,
            ),
            _rowEditable(
              context,
              label: "Tax",
              controller: widget.taxController,
              prefix: "\$",
              textColor: Colors.orange,
            ),
            const Divider(height: 8),
            ListTile(
              title: const Text("Total", style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(
                "\$${total.toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ),
            _rowStatic("Paid", "\$${widget.paid.toStringAsFixed(2)}"),
            ListTile(
              dense: true,
              title: const Text("Remaining"),
              trailing: Text(
                "\$${remaining.toStringAsFixed(2)}",
                style: TextStyle(fontWeight: FontWeight.w800, color: widget.balanceColor),
              ),
            ),

            // Save row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _dirty ? widget.onSave : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text("Save"),
                  ),
                ],
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
          Icon(Icons.edit_outlined, size: 14, color: t.hintColor),
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
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: const UnderlineInputBorder(),
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
