import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/screens/sales/parts/cart_product_search.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

/// Fixed column header row for the POS cart table.
class SaleCartTableHeader extends StatelessWidget {
  const SaleCartTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('Product', style: style)),
          Expanded(
            flex: 2,
            child: Text('T.P', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Disc', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Extra Disc', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Qty', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 28),
        ],
      ),
    );
  }
}

/// Notification banner displaying active return invoice context.
class SaleReturnContextBanner extends StatelessWidget {
  final String returnInvoice;

  const SaleReturnContextBanner({
    super.key,
    required this.returnInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final invoice = returnInvoice.trim();
    if (invoice.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(.08),
        border: const Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_return_outlined,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Return / Exchange for $invoice • Enter a negative quantity on the item being returned. Original delivery is non-refundable.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Autocomplete product search input, barcode scanner focus button, and F2 add-items button.
class SaleCartInputRow extends StatelessWidget {
  final FocusNode searchFocusNode;
  final TextEditingController searchController;
  final Future<List<ProductRef>> Function(String) onQueryProducts;
  final ValueChanged<ProductRef> onProductSelected;
  final VoidCallback onFocusScanner;
  final bool scannerEnabled;
  final VoidCallback onAddItemsManual;

  const SaleCartInputRow({
    super.key,
    required this.searchFocusNode,
    required this.searchController,
    required this.onQueryProducts,
    required this.onProductSelected,
    required this.onFocusScanner,
    required this.scannerEnabled,
    required this.onAddItemsManual,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: CartProductSearch(
              focusNode: searchFocusNode,
              controller: searchController,
              onQuery: onQueryProducts,
              onSelected: onProductSelected,
            ),
          ),
          const SizedBox(width: 6),

          // Scanner toggle (F9)
          Tooltip(
            message: 'Focus barcode scanner  (F9)',
            child: InkWell(
              onTap: onFocusScanner,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scannerEnabled
                      ? AppTheme.success.withOpacity(.10)
                      : AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scannerEnabled
                        ? AppTheme.success.withOpacity(.40)
                        : AppTheme.border,
                  ),
                ),
                child: Icon(
                  scannerEnabled
                      ? Icons.check_circle_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 16,
                  color:
                      scannerEnabled ? AppTheme.success : AppTheme.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // F2 / Add Items (opens full modal picker for multi-select)
          Tooltip(
            message: 'Add items  (F2)',
            child: OutlinedButton.icon(
              onPressed: onAddItemsManual,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('F2', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding split tender payments.
Future<Map<String, dynamic>?> showSaleAddPaymentDialog({
  required BuildContext context,
  required double total,
  required double alreadyPaid,
  required PaymentMethodProvider pm,
}) async {
  var methods = pm.activeMethods;
  if (methods.isEmpty) {
    await pm.reload();
    methods = pm.activeMethods;
  }
  if (methods.isEmpty) {
    if (context.mounted) {
      AppFeedback.error(context, 'No payment methods configured for this branch.');
    }
    return null;
  }

  final remaining = total - alreadyPaid;
  final amountCtl = TextEditingController(
      text: remaining > 0 ? remaining.toStringAsFixed(2) : '');
  final refCtl = TextEditingController();
  String method = (pm.defaultMethod ?? methods.first).method;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setLocal) {
        final selected = pm.byCode(method);
        final showReference = selected != null && !selected.affectsCashDrawer;
        return AlertDialog(
          title: const Text('Add Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: method,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: methods
                    .map((m) => DropdownMenuItem(
                          value: m.method,
                          child: Text(m.displayName),
                        ))
                    .toList(),
                onChanged: (v) => setLocal(() => method = v ?? method),
              ),
              if (showReference) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: refCtl,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                    hintText: 'Txn / approval / cheque no…',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountCtl.text.trim()) ?? 0.0;
                if (amount <= 0) return;
                final ref = refCtl.text.trim();
                Navigator.pop(dialogCtx, {
                  'amount': amount,
                  'method': method,
                  if (ref.isNotEmpty) 'reference': ref,
                });
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}
