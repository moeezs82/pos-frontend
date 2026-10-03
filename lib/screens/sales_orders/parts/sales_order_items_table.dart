import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SalesOrderItemsTable extends StatelessWidget {
  final List<SalesOrderItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final bool canViewProfit;

  const SalesOrderItemsTable({
    super.key,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.canViewProfit = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceSoft,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Order Line Items (${items.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 800),
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                horizontalMargin: 16,
                columnSpacing: 18,
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
                columns: [
                  const DataColumn(label: Text('#')),
                  const DataColumn(label: Text('Product')),
                  const DataColumn(label: Text('Qty'), numeric: true),
                  const DataColumn(label: Text('Unit Price'), numeric: true),
                  if (canViewProfit)
                    const DataColumn(label: Text('Cost'), numeric: true),
                  const DataColumn(label: Text('Discount'), numeric: true),
                  const DataColumn(label: Text('Tax Rate'), numeric: true),
                  if (canViewProfit)
                    const DataColumn(label: Text('Margin'), numeric: true),
                  const DataColumn(label: Text('Total'), numeric: true),
                ],
                rows: List.generate(items.length, (index) {
                  final item = items[index];
                  final margin = item.total - (item.unitCost * item.quantity);
                  final marginPct = item.total > 0 ? (margin / item.total) * 100 : 0.0;

                  return DataRow(
                    cells: [
                      DataCell(Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.productName.isNotEmpty
                                  ? item.productName
                                  : 'Product #${item.productId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            if (item.productSku.isNotEmpty)
                              Text(
                                'SKU: ${item.productSku}',
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      DataCell(_qtyCell(item)),
                      DataCell(_unitPriceCell(item)),
                      if (canViewProfit)
                        DataCell(Text(
                          AppCurrency.format(item.unitCost),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMuted,
                          ),
                        )),
                      DataCell(_discountCell(item)),
                      DataCell(Text(
                        item.taxRate > 0 ? '${item.taxRate.toStringAsFixed(1)}%' : '-',
                        style: const TextStyle(fontSize: 12.5),
                      )),
                      if (canViewProfit)
                        DataCell(Text(
                          '${AppCurrency.format(margin)} (${marginPct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: margin >= 0 ? AppTheme.success : AppTheme.danger,
                          ),
                        )),
                      DataCell(Text(
                        AppCurrency.format(item.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: AppTheme.primary,
                        ),
                      )),
                    ],
                  );
                }),
              ),
            ),
          ),

          // Totals summary section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceSoft,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 260),
                  child: Column(
                    children: [
                      _summaryRow('Subtotal', AppCurrency.format(subtotal)),
                      if (discount > 0)
                        _summaryRow('Discount', '- ${AppCurrency.format(discount)}',
                            valueColor: AppTheme.danger),
                      if (tax > 0)
                        _summaryRow('Tax', '+ ${AppCurrency.format(tax)}'),
                      const Divider(height: 16),
                      _summaryRow(
                        'Total Booked Value',
                        AppCurrency.format(total),
                        isBold: true,
                        valueColor: AppTheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 12.5,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: isBold ? AppTheme.navy : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 24),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 15 : 12.5,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor ?? (isBold ? AppTheme.navy : AppTheme.navy),
            ),
          ),
        ],
      ),
    );
  }

  static String _packLabel(SalesOrderItem item) {
    final short = (item.packagingShortNameSnapshot ?? '').trim();
    final name = (item.packagingNameSnapshot ?? '').trim();
    return short.isNotEmpty ? short : (name.isNotEmpty ? name : 'pack');
  }

  /// Packaged lines read the way they were entered: `2 Box (20 pc)`.
  Widget _qtyCell(SalesOrderItem item) {
    const style = TextStyle(fontWeight: FontWeight.w800, fontSize: 13);
    if (item.isPackaged && item.packagingQuantity != null) {
      return Text(
        '${_formatQty(item.packagingQuantity!)} ${_packLabel(item)} '
        '(${_formatQty(item.quantity)} pc)',
        style: style,
      );
    }
    return Text(_formatQty(item.quantity), style: style);
  }

  Widget _unitPriceCell(SalesOrderItem item) {
    const style = TextStyle(fontSize: 12.5);
    if (item.isPackaged && item.packagingUnitPrice != null) {
      return Text(
        '${AppCurrency.format(item.packagingUnitPrice!)} per ${_packLabel(item)}',
        style: style,
      );
    }
    return Text(AppCurrency.format(item.unitPrice), style: style);
  }

  /// What was entered (`2 %`, `Rs 50 / Box`), the resolved money beneath it,
  /// and any flat extra discount.
  Widget _discountCell(SalesOrderItem item) {
    if (item.discount <= 0) {
      return const Text('-',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted));
    }
    final String entered;
    if (item.discountPct <= 0) {
      entered = '';
    } else if (item.discountType == 'fixed') {
      entered = item.isPackaged
          ? '${AppCurrency.format(item.packagingDiscountSnapshot ?? item.discountPct)} / ${_packLabel(item)}'
          : '${AppCurrency.format(item.discountPct)} / pc';
    } else {
      entered = '${_formatQty(item.discountPct)} %';
    }
    const danger = TextStyle(
        fontSize: 12.5, color: AppTheme.danger, fontWeight: FontWeight.w700);
    const muted = TextStyle(fontSize: 11, color: AppTheme.textMuted);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(entered.isNotEmpty ? entered : AppCurrency.format(item.discount),
            style: danger),
        if (entered.isNotEmpty)
          Text('- ${AppCurrency.format(item.discount - item.extraDiscount)}',
              style: muted),
        if (item.extraDiscount > 0)
          Text('+ ${AppCurrency.format(item.extraDiscount)} extra',
              style: muted),
      ],
    );
  }

  String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(2);
  }
}
