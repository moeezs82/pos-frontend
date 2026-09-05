class SaleProfitCostBasis {
  final double unitCost;
  final bool estimated;
  final String source;

  const SaleProfitCostBasis({
    required this.unitCost,
    required this.estimated,
    required this.source,
  });
}

class SaleProfitLine {
  final String name;
  final double quantity;
  final double unitPrice;
  final double grossRevenue;
  final double discountAmount;
  final double invoiceDiscountShare;
  final double netRevenue;
  final double unitCost;
  final double costOfGoods;
  final double profit;
  final double? marginPercent;
  final bool estimated;
  final String costSource;

  const SaleProfitLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.grossRevenue,
    required this.discountAmount,
    required this.invoiceDiscountShare,
    required this.netRevenue,
    required this.unitCost,
    required this.costOfGoods,
    required this.profit,
    required this.marginPercent,
    required this.estimated,
    required this.costSource,
  });
}

class SaleProfitSummary {
  final List<SaleProfitLine> lines;
  final double itemNetSales;
  final double invoiceDiscount;
  final double shippingRevenue;
  final double taxExcluded;
  final double netSalesBeforeTax;
  final double costOfGoods;
  final double grossProfit;
  final double? marginPercent;
  final bool estimated;
  final int profitableLines;
  final int lowMarginLines;
  final int lossLines;

  const SaleProfitSummary({
    required this.lines,
    required this.itemNetSales,
    required this.invoiceDiscount,
    required this.shippingRevenue,
    required this.taxExcluded,
    required this.netSalesBeforeTax,
    required this.costOfGoods,
    required this.grossProfit,
    required this.marginPercent,
    required this.estimated,
    required this.profitableLines,
    required this.lowMarginLines,
    required this.lossLines,
  });
}

/// Central profit preview logic for Create Sale.
///
/// Live product payloads include the active branch's product_stocks relation;
/// its avg_cost is the same carrying-cost basis the backend snapshots when a
/// sale is posted. Offline catalog rows do not carry avg_cost, so cost_price is
/// used only as a clearly-marked estimate.
class SaleProfitCalculator {
  static const String unitCostKey = '_profit_unit_cost';
  static const String estimatedKey = '_profit_cost_estimated';
  static const String sourceKey = '_profit_cost_source';

  static double _num(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0.0;

  static double _round2(double value) =>
      (value * 100).roundToDouble() / 100;

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes';
  }

  static SaleProfitCostBasis costBasisFromProduct(
    Map<String, dynamic> product,
  ) {
    // A cart line may already have an authoritative snapshot. Preserve it when
    // it passes through a picker that only carries a compact product map.
    if (product[unitCostKey] != null) {
      return SaleProfitCostBasis(
        unitCost: _num(product[unitCostKey]),
        estimated: _bool(product[estimatedKey]),
        source: (product[sourceKey] ?? 'Inventory average cost').toString(),
      );
    }

    double? avgCost;

    final direct = product['avg_cost'] ?? product['branch_avg_cost'];
    if (direct != null) {
      avgCost = double.tryParse(direct.toString());
    }

    final branchStock = product['branch_stock'];
    if (avgCost == null && branchStock is Map) {
      final raw = branchStock['avg_cost'] ?? branchStock['average_cost'];
      if (raw != null) avgCost = double.tryParse(raw.toString());
    }

    final stocks = product['stocks'];
    if (avgCost == null && stocks is Iterable) {
      for (final rawStock in stocks) {
        if (rawStock is! Map) continue;
        final raw = rawStock['avg_cost'] ?? rawStock['average_cost'];
        if (raw == null) continue;
        final parsed = double.tryParse(raw.toString());
        if (parsed != null) {
          avgCost = parsed;
          break;
        }
      }
    }

    final isOffline = product['_offline'] == true;
    if (avgCost != null && !isOffline) {
      return SaleProfitCostBasis(
        unitCost: avgCost,
        estimated: false,
        source: 'Inventory average cost',
      );
    }

    return SaleProfitCostBasis(
      unitCost: _num(product['cost_price']),
      estimated: true,
      source: isOffline ? 'Offline catalog cost' : 'Catalog cost fallback',
    );
  }

  static Map<String, dynamic> costFieldsFromProduct(
    Map<String, dynamic> product,
  ) {
    final basis = costBasisFromProduct(product);
    return <String, dynamic>{
      unitCostKey: basis.unitCost,
      estimatedKey: basis.estimated,
      sourceKey: basis.source,
    };
  }

  static SaleProfitLine line(Map<String, dynamic> item) {
    final quantity = _num(item['quantity']);
    final unitPrice = _num(item['price']);
    final discountValue = _num(item['discount_pct']);
    final discountType =
        (item['discount_type'] ?? 'percentage').toString().toLowerCase();

    final packaged = item['packaging_id'] != null;
    final packageQuantity = _num(item['packaging_quantity']);
    final packageUnitPrice = _num(item['packaging_unit_price']);
    final packageFixedDiscount = _num(item['packaging_discount_snapshot']);
    final grossRevenue = packaged
        ? _round2(packageQuantity * packageUnitPrice)
        : quantity * unitPrice;
    final discountAmount = discountType == 'fixed'
        ? (packaged
            ? _round2(packageQuantity * packageFixedDiscount)
            : quantity * discountValue)
        : (packaged
            ? _round2(grossRevenue * (discountValue.clamp(0.0, 100.0) / 100.0))
            : grossRevenue * (discountValue.clamp(0.0, 100.0) / 100.0));
    final netRevenue = packaged
        ? _round2(grossRevenue - discountAmount)
        : grossRevenue - discountAmount;

    final basis = costBasisFromProduct(item);
    final costOfGoods = quantity * basis.unitCost;
    final profit = netRevenue - costOfGoods;
    final margin = netRevenue > 0 ? (profit / netRevenue) * 100.0 : null;

    return SaleProfitLine(
      name: (item['name'] ?? 'Unnamed product').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      grossRevenue: grossRevenue,
      discountAmount: discountAmount,
      invoiceDiscountShare: 0,
      netRevenue: netRevenue,
      unitCost: basis.unitCost,
      costOfGoods: costOfGoods,
      profit: profit,
      marginPercent: margin,
      estimated: basis.estimated,
      costSource: basis.source,
    );
  }

  static SaleProfitLine _withInvoiceDiscountShare(
    SaleProfitLine line,
    double share,
  ) {
    final adjustedNetRevenue = line.netRevenue - share;
    final adjustedProfit = adjustedNetRevenue - line.costOfGoods;
    final adjustedMargin = adjustedNetRevenue > 0
        ? (adjustedProfit / adjustedNetRevenue) * 100.0
        : null;

    return SaleProfitLine(
      name: line.name,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      grossRevenue: line.grossRevenue,
      discountAmount: line.discountAmount,
      invoiceDiscountShare: share,
      netRevenue: adjustedNetRevenue,
      unitCost: line.unitCost,
      costOfGoods: line.costOfGoods,
      profit: adjustedProfit,
      marginPercent: adjustedMargin,
      estimated: line.estimated,
      costSource: line.costSource,
    );
  }

  static SaleProfitSummary invoice({
    required List<Map<String, dynamic>> items,
    required double invoiceDiscount,
    required double shippingRevenue,
    required double tax,
  }) {
    final baseLines = items.map(line).toList(growable: false);
    final itemNetSales =
        baseLines.fold<double>(0, (sum, line) => sum + line.netRevenue);

    // Allocate invoice-level discount across positive sale lines in proportion
    // to their revenue. This keeps the line-level profit view consistent with
    // the whole-invoice figure instead of making every line look healthier
    // than the final negotiated invoice actually is.
    final eligibleIndexes = <int>[];
    var eligibleSales = 0.0;
    for (var i = 0; i < baseLines.length; i++) {
      final revenue = baseLines[i].netRevenue;
      if (revenue > 0) {
        eligibleIndexes.add(i);
        eligibleSales += revenue;
      }
    }

    final shares = List<double>.filled(baseLines.length, 0.0);
    if (invoiceDiscount != 0 && eligibleSales > 0 && eligibleIndexes.isNotEmpty) {
      var allocated = 0.0;
      for (var position = 0; position < eligibleIndexes.length; position++) {
        final index = eligibleIndexes[position];
        final isLast = position == eligibleIndexes.length - 1;
        final share = isLast
            ? invoiceDiscount - allocated
            : invoiceDiscount * (baseLines[index].netRevenue / eligibleSales);
        shares[index] = share;
        allocated += share;
      }
    }

    final lines = <SaleProfitLine>[];
    for (var i = 0; i < baseLines.length; i++) {
      lines.add(_withInvoiceDiscountShare(baseLines[i], shares[i]));
    }

    final costOfGoods =
        lines.fold<double>(0, (sum, line) => sum + line.costOfGoods);

    // Tax is collected on behalf of the tax authority, so it is deliberately
    // excluded from gross-margin revenue. Shipping/delivery charged to the
    // customer is part of the backend's sales revenue posting and is included.
    final netSalesBeforeTax = itemNetSales - invoiceDiscount + shippingRevenue;
    final grossProfit = netSalesBeforeTax - costOfGoods;
    final margin = netSalesBeforeTax > 0
        ? (grossProfit / netSalesBeforeTax) * 100.0
        : null;

    var profitable = 0;
    var lowMargin = 0;
    var loss = 0;
    for (final line in lines) {
      if (line.profit < 0) {
        loss++;
      } else if ((line.marginPercent ?? 0) < 5) {
        lowMargin++;
      } else {
        profitable++;
      }
    }

    return SaleProfitSummary(
      lines: lines,
      itemNetSales: itemNetSales,
      invoiceDiscount: invoiceDiscount,
      shippingRevenue: shippingRevenue,
      taxExcluded: tax,
      netSalesBeforeTax: netSalesBeforeTax,
      costOfGoods: costOfGoods,
      grossProfit: grossProfit,
      marginPercent: margin,
      estimated: lines.any((line) => line.estimated),
      profitableLines: profitable,
      lowMarginLines: lowMargin,
      lossLines: loss,
    );
  }
}
