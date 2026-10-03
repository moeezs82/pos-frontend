class SaleCheckoutTotals {
  final double subtotal;
  final double discount;
  final double tax;
  final double shipping;
  final double saleTotal;
  final double returnCredit;
  final double originalOutstanding;
  final double appliedToOriginal;
  final double afterOriginal;
  final double appliedToExchange;
  final double refundDue;
  final double customerPays;
  final double signedTotal;
  final List<Map<String, dynamic>> paymentsToSend;
  final Map<String, dynamic>? refundToSend;
  final double paid;
  final double balance;
  final double cashDue;
  final double enteredCashReceived;
  final double cashReceived;
  final double changeAmount;

  const SaleCheckoutTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.shipping,
    required this.saleTotal,
    required this.returnCredit,
    required this.originalOutstanding,
    required this.appliedToOriginal,
    required this.afterOriginal,
    required this.appliedToExchange,
    required this.refundDue,
    required this.customerPays,
    required this.signedTotal,
    required this.paymentsToSend,
    required this.refundToSend,
    required this.paid,
    required this.balance,
    required this.cashDue,
    required this.enteredCashReceived,
    required this.cashReceived,
    required this.changeAmount,
  });

  static double _pmAmt(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0.0;

  static double _rowNum(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0.0;

  factory SaleCheckoutTotals.calculate({
    required List<Map<String, dynamic>> items,
    required double Function(Map<String, dynamic>) lineTotalCalculator,
    required double discount,
    required double tax,
    required double shipping,
    required List<Map<String, dynamic>> splitPayments,
    required bool autoCashIfEmpty,
    required String effectiveMethod,
    required bool isDrawerMethod,
    required String saleReference,
    required double enteredCashReceived,
  }) {
    final subtotal = items.fold<double>(0.0, (sum, i) {
      final qty = _rowNum(i['quantity']);
      if (qty <= 0) return sum;
      return sum + lineTotalCalculator(i);
    });

    final saleTotal = subtotal - discount + tax + shipping;

    final linkedReturns = items
        .where((i) => _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] != null)
        .toList(growable: false);

    final returnCredit = linkedReturns.fold<double>(
      0.0,
      (sum, i) => sum + _rowNum(i['return_credit']).abs(),
    );

    final originalOutstanding = linkedReturns.isEmpty
        ? 0.0
        : _rowNum(linkedReturns.first['return_original_outstanding']);

    final appliedToOriginal =
        returnCredit.clamp(0.0, originalOutstanding).toDouble();
    final afterOriginal =
        (returnCredit - appliedToOriginal).clamp(0.0, double.infinity).toDouble();
    final appliedToExchange =
        afterOriginal.clamp(0.0, saleTotal.clamp(0.0, double.infinity)).toDouble();
    final refundDue =
        (afterOriginal - appliedToExchange).clamp(0.0, double.infinity).toDouble();
    final customerPays =
        (saleTotal - appliedToExchange).clamp(0.0, double.infinity).toDouble();

    final signedTotal =
        customerPays > 0.004 ? customerPays : -refundDue;

    final List<Map<String, dynamic>> paymentsToSend = [];
    if (customerPays > 0 && splitPayments.isNotEmpty) {
      for (final p in splitPayments) {
        final ref = (p['reference'] ?? '').toString().trim();
        paymentsToSend.add({
          "amount": _pmAmt(p['amount']).toStringAsFixed(2),
          "method": p['method'] ?? 'cash',
          if (ref.isNotEmpty) "reference": ref,
        });
      }
    } else if (autoCashIfEmpty && customerPays > 0) {
      paymentsToSend.add({
        "amount": customerPays.toStringAsFixed(2),
        "method": effectiveMethod,
        if (!isDrawerMethod && saleReference.trim().isNotEmpty)
          "reference": saleReference.trim(),
      });
    }

    final Map<String, dynamic>? refundToSend =
        linkedReturns.isNotEmpty && autoCashIfEmpty && refundDue > 0.004
            ? {
                'mode': 'auto',
                'method': effectiveMethod,
                if (!isDrawerMethod && saleReference.trim().isNotEmpty)
                  'reference': saleReference.trim(),
              }
            : null;

    final paid = paymentsToSend.fold<double>(
      0.0,
      (sum, payment) => sum + _rowNum(payment['amount']),
    );

    final balance = customerPays - paid;

    double cashDue;
    if (splitPayments.isNotEmpty) {
      cashDue = splitPayments
          .where((p) => p['method'] == 'cash' || p['affects_drawer'] == true)
          .fold<double>(0.0, (s, p) => s + _pmAmt(p['amount']));
    } else if (autoCashIfEmpty && customerPays > 0) {
      cashDue = isDrawerMethod ? customerPays : 0.0;
    } else {
      cashDue = 0.0;
    }

    final cashReceived =
        enteredCashReceived > 0 ? enteredCashReceived : cashDue;
    final changeAmount = cashDue > 0
        ? (cashReceived - cashDue).clamp(0.0, double.infinity).toDouble()
        : 0.0;

    return SaleCheckoutTotals(
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      shipping: shipping,
      saleTotal: saleTotal,
      returnCredit: returnCredit,
      originalOutstanding: originalOutstanding,
      appliedToOriginal: appliedToOriginal,
      afterOriginal: afterOriginal,
      appliedToExchange: appliedToExchange,
      refundDue: refundDue,
      customerPays: customerPays,
      signedTotal: signedTotal,
      paymentsToSend: paymentsToSend,
      refundToSend: refundToSend,
      paid: paid,
      balance: balance,
      cashDue: cashDue,
      enteredCashReceived: enteredCashReceived,
      cashReceived: cashReceived,
      changeAmount: changeAmount,
    );
  }
}
