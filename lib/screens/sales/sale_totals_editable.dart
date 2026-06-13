import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

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

  // -------- Helpers --------
  String _money(num v) => "\$${v.toStringAsFixed(2)}";

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowStatic(
    String label,
    String value, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double size = 14,
  }) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: weight,
          color: color,
          fontSize: size,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 0,
            ),
            suffixIcon: Icon(Icons.edit_outlined, size: 16, color: t.hintColor),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 20,
              minHeight: 20,
            ),
          ),
          style: t.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () {
        // Make the whole row focus the field
        FocusScope.of(context).requestFocus(FocusNode());
      },
    );
  }

  Widget _chip(BuildContext context, String text) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: t.colorScheme.surfaceVariant.withOpacity(.6),
      ),
      child: Text(
        text,
        style: t.textTheme.labelSmall?.copyWith(
          color: t.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    // -------- Parse inputs --------
    final subtotal = double.tryParse(widget.sale['subtotal'].toString()) ?? 0.0;
    final discount =
        double.tryParse(widget.discountController.text.trim()) ?? 0.0;
    final tax = double.tryParse(widget.taxController.text.trim()) ?? 0.0;
    final total = (subtotal - discount + tax).clamp(0, double.infinity);
    final paid = widget.paid;
    final outstanding = (total - paid).clamp(0, double.infinity);

    final ar = widget.sale['customer']?['ar_summary'];
    final hasAR = ar is Map && ar.isNotEmpty;
    final balance = hasAR
        ? (double.tryParse((ar['balance'] ?? 0).toString()) ?? 0.0)
        : 0.0;
    final String? asOf = hasAR
        ? (ar['as_of']?.toString().trim().isEmpty ?? true
              ? null
              : ar['as_of'].toString())
        : null;

    // --- Determine if AR includes this invoice ---
    final String? createdAtStr = widget.sale['created_at']?.toString();
    DateTime? createdAtDT = DateTime.tryParse(createdAtStr ?? '');

    DateTime? asOfDT;
    if (asOf != null) {
      asOfDT = DateTime.tryParse(asOf);
    }
    // Rules:
    // - If AR missing: assume excludes (can't include).
    // - If as_of is null: treat as live/now => includes.
    // - Else includes when as_of >= created_at.
    bool includesThisInvoice = false;
    if (hasAR) {
      if (asOfDT == null || createdAtDT == null) {
        includesThisInvoice = true; // safest: assume AR includes it
      } else {
        includesThisInvoice = !asOfDT.isBefore(createdAtDT);
      }
    }

    // Correct exposure:
    // - If AR already includes this invoice -> exposure = AR balance
    // - Else -> exposure = AR balance + current invoice total
    // final double exposure = includesThisInvoice ? balance : (balance + total);
    final double exposure = balance + total;

    // UI colors
    Color outstandingColor = outstanding > 0
        ? Colors.amber[800]!
        : t.textTheme.bodyMedium!.color!;
    Color balanceColor = balance > 0
        ? Colors.amber[800]!
        : (balance < 0 ? Colors.green[700]! : t.textTheme.bodyMedium!.color!);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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

            // -------- Invoice block --------
            _sectionHeader("Invoice"),
            _rowStatic("Subtotal", _money(subtotal)),
            _rowEditable(
              context,
              label: "Discount",
              controller: widget.discountController,
              prefix: "-\$",
              textColor: Colors.red[700],
            ),
            _rowEditable(
              context,
              label: "Tax",
              controller: widget.taxController,
              prefix: "\$",
              textColor: Colors.orange[800],
            ),
            const Divider(height: 12),
            _rowStatic(
              "Total (Invoice)",
              _money(total),
              weight: FontWeight.w800,
              size: 18,
            ),
            // _rowStatic("Paid", _money(paid)),
            // _rowStatic(
            //   "Invoice Outstanding",
            //   _money(outstanding),
            //   weight: FontWeight.w800,
            //   color: outstandingColor,
            // ),

            const SizedBox(height: 6),
            const Divider(height: 12),

            // -------- Customer AR block (ignoring branch) --------
            _sectionHeader("Customer Balance"),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasAR ? _money(balance) : "Balance unavailable",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: hasAR ? balanceColor : t.hintColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasAR) // show "As of" chip when present; ignoring branch per your ask
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    if (asOf != null) _chip(context, "As of: $asOfDT"),
                    if (asOf == null) _chip(context, "As of: Now"),
                  ],
                ),
              ),

            // -------- Exposure (optional but helpful) --------
            if (hasAR) ...[
              const SizedBox(height: 2),
              _sectionHeader("Exposure"),
              ListTile(
                dense: true,
                title: Row(
                  children: [
                    Text(
                      includesThisInvoice
                          ? "Exposure (AR already includes this invoice)"
                          : "Exposure (AR excludes this invoice)",
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: includesThisInvoice
                          ? "Exposure equals the AR balance because the snapshot already contains this invoice."
                          : "AR snapshot predates this invoice, so exposure adds this invoice’s total.",
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: t.hintColor,
                      ),
                    ),
                  ],
                ),
                trailing: Text(
                  _money(exposure),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: const VisualDensity(vertical: -2),
              ),
            ],

            const SizedBox(height: 8),

            // -------- Save row --------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _dirty
                        ? () {
                            widget.discountController.text = _initialDiscount;
                            widget.taxController.text = _initialTax;
                          }
                        : null,
                    child: const Text("Reset"),
                  ),
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
}
