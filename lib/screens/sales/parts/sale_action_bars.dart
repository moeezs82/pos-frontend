import 'package:enterprise_pos/models/payment_method.dart';
import 'dart:ui' show FontFeature;
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_amendment_dialog.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Top notification banner when creating a sale prefilled from a sales order.
class SaleSalesOrderConversionHeader extends StatelessWidget {
  final String orderNumber;

  const SaleSalesOrderConversionHeader({
    super.key,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.06),
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary.withOpacity(.24)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 15, color: AppTheme.primary),
                SizedBox(width: 4),
                Text(
                  'ORDER CONVERSION',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Creating sale from order $orderNumber · changes are recorded against the order',
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header bar displayed when editing or creating a sales order quotation.
class SaleSalesOrderHeader extends StatelessWidget {
  final SalesOrder? editSalesOrder;
  final DateTime? deliveryDate;
  final ValueChanged<DateTime?> onDeliveryDateChanged;
  final TextEditingController notesController;

  const SaleSalesOrderHeader({
    super.key,
    required this.editSalesOrder,
    required this.deliveryDate,
    required this.onDeliveryDateChanged,
    required this.notesController,
  });

  @override
  Widget build(BuildContext context) {
    final isEdit = editSalesOrder != null;
    final orderNumber = editSalesOrder?.orderNumber ?? '';
    final status = editSalesOrder?.status;
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.06),
        border: const Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary.withOpacity(.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.assignment_outlined, size: 15, color: AppTheme.primary),
                const SizedBox(width: 4),
                Text(
                  isEdit ? 'EDIT SALES ORDER' : 'NEW SALES ORDER',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEdit
                  ? 'Editing order $orderNumber · quotation lines & pricing'
                  : 'Sales Order Quotation · select customer & add product lines',
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Delivery Date Picker Button
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: deliveryDate ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                onDeliveryDateChanged(picked);
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.primary),
                  const SizedBox(width: 5),
                  Text(
                    deliveryDate != null
                        ? 'Delivery: ${dateFmt.format(deliveryDate!)}'
                        : 'Set Delivery Date',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.navy),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Order Notes Button
          InkWell(
            onTap: () async {
              final textController = TextEditingController(text: notesController.text);
              final saved = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Order Notes'),
                  content: TextField(
                    controller: textController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Enter internal quotation or order instructions...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, textController.text.trim()),
                      child: const Text('Save Note'),
                    ),
                  ],
                ),
              );
              if (saved != null) {
                notesController.text = saved;
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.note_alt_outlined, size: 13, color: AppTheme.primary),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      notesController.text.trim().isNotEmpty
                          ? 'Note: ${notesController.text.trim()}'
                          : 'Add Note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.navy),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isEdit && status != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SalesOrderStatus.color(status).withOpacity(.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SalesOrderStatus.color(status)),
              ),
              child: Text(
                SalesOrderStatus.label(status),
                style: TextStyle(
                  color: SalesOrderStatus.color(status),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Header bar displayed when amending a posted sale.
class SaleAmendmentHeader extends StatelessWidget {
  final String invoiceNo;
  final int revision;
  final double originalTotal;
  final double revisedTotal;

  const SaleAmendmentHeader({
    super.key,
    required this.invoiceNo,
    required this.revision,
    required this.originalTotal,
    required this.revisedTotal,
  });

  @override
  Widget build(BuildContext context) {
    final difference = revisedTotal - originalTotal;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.09),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary.withOpacity(.18)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note_rounded, size: 15, color: AppTheme.primary),
                SizedBox(width: 4),
                Text(
                  'AUDITED EDIT',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            invoiceNo.isEmpty ? 'Posted sale' : invoiceNo,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Revision #$revision',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          AmendmentHeaderMetric(
            label: 'Original',
            value: AppCurrency.format(originalTotal),
          ),
          const SizedBox(width: 18),
          AmendmentHeaderMetric(
            label: 'Revised',
            value: AppCurrency.format(revisedTotal),
          ),
          const SizedBox(width: 18),
          AmendmentHeaderMetric(
            label: 'Difference',
            value: '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
            valueColor: difference.abs() <= .004
                ? AppTheme.textMuted
                : difference > 0
                    ? AppTheme.warning
                    : AppTheme.success,
          ),
          const SizedBox(width: 12),
          const Tooltip(
            message:
                'Posted-sale amendments require the server and are committed atomically with stock, COGS, ledger and audit history.',
            child: Icon(Icons.cloud_done_outlined, size: 16, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Action bar at the bottom when amending a posted sale.
class SaleAmendmentBottomBar extends StatelessWidget {
  final double originalTotal;
  final double total;
  final bool submitting;
  final VoidCallback onReset;
  final VoidCallback onSubmit;

  const SaleAmendmentBottomBar({
    super.key,
    required this.originalTotal,
    required this.total,
    required this.submitting,
    required this.onReset,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final difference = total - originalTotal;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_edu_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posted invoice amendment',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Original financial documents stay preserved',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          AmendmentBottomMetric(
            label: 'Original',
            value: AppCurrency.format(originalTotal),
          ),
          const SizedBox(width: 18),
          AmendmentBottomMetric(
            label: 'Revised',
            value: AppCurrency.format(total),
          ),
          const SizedBox(width: 18),
          AmendmentBottomMetric(
            label: 'Difference',
            value: '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
            valueColor: difference.abs() <= .004
                ? AppTheme.textMuted
                : difference > 0
                    ? AppTheme.warning
                    : AppTheme.success,
          ),
          const SizedBox(width: 18),
          OutlinedButton.icon(
            onPressed: submitting ? null : onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Reset Changes'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(submitting ? 'Saving…' : 'Review Changes  Ctrl+↵'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action bar at the bottom for Sales Order Quotations.
class SaleSalesOrderBottomBar extends StatelessWidget {
  final SalesOrder? editSalesOrder;
  final int itemCount;
  final double total;
  final bool submitting;
  final VoidCallback onClear;
  final VoidCallback onSaveDraft;
  final VoidCallback onSubmitForApproval;

  const SaleSalesOrderBottomBar({
    super.key,
    required this.editSalesOrder,
    required this.itemCount,
    required this.total,
    required this.submitting,
    required this.onClear,
    required this.onSaveDraft,
    required this.onSubmitForApproval,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Order summary indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_outlined, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  editSalesOrder != null
                      ? 'Order #${editSalesOrder!.orderNumber}'
                      : 'Sales Order Quotation',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),

          const Spacer(),

          // Quoted total display
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Quoted Total',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                AppCurrency.format(total.abs()),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.navy,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Clear button
          OutlinedButton(
            onPressed: submitting ? null : onClear,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppTheme.danger),
              foregroundColor: AppTheme.danger,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),

          // Save as Draft button
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: submitting ? null : onSaveDraft,
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text(
                'Save Draft',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: AppTheme.primary.withOpacity(.5)),
                foregroundColor: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Submit for Approval button
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmitForApproval,
              icon: submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 15),
              label: Text(
                submitting ? 'Submitting…' : 'Submit for Approval  Ctrl+↵',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal chips strip showing active split tender payments.
class SaleSplitTenderStrip extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final double paid;
  final double balance;
  final String Function(String? method) displayNameFor;
  final ValueChanged<int> onRemovePayment;

  const SaleSplitTenderStrip({
    super.key,
    required this.payments,
    required this.paid,
    required this.balance,
    required this.displayNameFor,
    required this.onRemovePayment,
  });

  static double _pmAmt(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: payments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final p = payments[i];
                  final name = displayNameFor(p['method']?.toString());
                  final amt = AppCurrency.format(_pmAmt(p['amount']));
                  final ref = (p['reference'] ?? '').toString().trim();
                  return InputChip(
                    label: Text(ref.isEmpty ? '$name  $amt' : '$name  $amt · $ref'),
                    onDeleted: () => onRemovePayment(i),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Paid ${AppCurrency.format(paid)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(width: 10),
          Text(
            'Balance ${AppCurrency.format(balance)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: balance.abs() < 0.005 ? AppTheme.success : AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }
}


/// Standard POS bottom checkout bar: auto-cash switch, tender dropdown, cash received / change, split payments button, total payable, and save / print buttons.
class SaleStandardBottomBar extends StatelessWidget {
  final bool autoCashIfEmpty;
  final ValueChanged<bool> onAutoCashChanged;
  final List<PaymentMethod> methods;
  final String? currentMethod;
  final ValueChanged<String?> onMethodChanged;
  final bool hasSplit;
  final bool showCashFields;
  final TextEditingController cashReceivedController;
  final FocusNode cashReceivedFocusNode;
  final double changeAmount;
  final TextEditingController saleReferenceController;
  final double total;
  final int splitPaymentsCount;
  final VoidCallback? onAddSplitPayment;
  final VoidCallback onClear;
  final bool submitting;
  final VoidCallback? onSaveOnly;
  final VoidCallback? onSaveAndPrint;

  const SaleStandardBottomBar({
    super.key,
    required this.autoCashIfEmpty,
    required this.onAutoCashChanged,
    required this.methods,
    required this.currentMethod,
    required this.onMethodChanged,
    required this.hasSplit,
    required this.showCashFields,
    required this.cashReceivedController,
    required this.cashReceivedFocusNode,
    required this.changeAmount,
    required this.saleReferenceController,
    required this.total,
    required this.splitPaymentsCount,
    required this.onAddSplitPayment,
    required this.onClear,
    required this.submitting,
    required this.onSaveOnly,
    required this.onSaveAndPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Auto Cash toggle
          const Text(
            'Auto Cash',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.8,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: autoCashIfEmpty,
              onChanged: onAutoCashChanged,
            ),
          ),
          const SizedBox(width: 8),

          // Payment method selector (single-tender only; hidden when splitting)
          if (methods.isNotEmpty && !hasSplit)
            SizedBox(
              width: 128,
              height: 44,
              child: DropdownButtonFormField<String>(
                value: currentMethod,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
                items: methods
                    .map((m) => DropdownMenuItem(
                          value: m.method,
                          child: Text(m.displayName, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: onMethodChanged,
              ),
            ),
          const SizedBox(width: 8),

          // Cash Received + Change apply only to physical drawer cash.
          if (showCashFields) ...[
            Tooltip(
              message: 'Focus: Ctrl+Shift+R',
              child: SizedBox(
                width: 110,
                height: 44,
                child: TextField(
                  controller: cashReceivedController,
                  focusNode: cashReceivedFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'Cash Recv.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppCurrency.format(changeAmount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: changeAmount > 0 ? AppTheme.success : AppTheme.navy,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ] else if (!hasSplit)
            // Non-drawer tender (KNET/card/bank/cheque): optional reference.
            SizedBox(
              width: 150,
              height: 44,
              child: TextField(
                controller: saleReferenceController,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  hintText: 'Txn / approval',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(width: 8),
          // Split tender — add another payment row (e.g. 1000 cash + 500 bank).
          OutlinedButton.icon(
            onPressed: total > .004 ? onAddSplitPayment : null,
            icon: const Icon(Icons.call_split_rounded, size: 16),
            label: Text(hasSplit ? 'Add ($splitPaymentsCount)' : 'Split'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          const Spacer(),

          // Total payable
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total < -0.004 ? 'Refund / Credit Due' : 'Total Payable',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                AppCurrency.format(total.abs()),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: total < -0.004 ? AppTheme.warning : AppTheme.navy,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Clear cart
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppTheme.danger),
              foregroundColor: AppTheme.danger,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),

          // Save without print
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: submitting ? null : onSaveOnly,
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: AppTheme.primary.withOpacity(.5)),
                foregroundColor: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Save + Print (Ctrl+↵)
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSaveAndPrint,
              icon: submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded, size: 15),
              label: Text(
                submitting ? 'Saving…' : 'Create & Print  Ctrl+↵',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
