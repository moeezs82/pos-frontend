import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_mutator.dart';
import 'package:enterprise_pos/screens/sales/services/sale_unit_conversion_service.dart';
import 'package:enterprise_pos/screens/sales/services/sales_order_submitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Invariant under test:
//   the order payload's implied line total == SaleCartMutator.cartLineTotal(row)
// for every discount shape and for packaged and loose rows alike.

/// What the backend computes from a payload line (store.go: lineTotal =
/// Round2(qty*unit_price - discount + tax)).
double backendLineTotal(Map<String, dynamic> line) {
  final qty = (line['quantity'] as num).toDouble();
  final price = (line['unit_price'] as num).toDouble();
  final discount = (line['discount'] as num).toDouble();
  final taxRate = (line['tax_rate'] as num).toDouble();
  final gross = qty * price;
  final tax = (gross - discount) * (taxRate / 100.0);
  return ((gross - discount + tax) * 100).roundToDouble() / 100;
}

Map<String, dynamic> loose({
  required double qty,
  required double price,
  double discountPct = 0,
  String discountType = 'percentage',
  double extra = 0,
}) =>
    {
      'product_id': 1,
      'quantity': qty,
      'price': price,
      'discount_pct': discountPct,
      'discount_type': discountType,
      'extra_discount': extra,
    };

/// Builds a packaged row through the real cart canonicalisation.
Future<Map<String, dynamic>> packaged(
  WidgetTester tester, {
  required double packs,
  required double factor,
  required double packPrice,
  double discount = 0,
  String discountType = 'percentage',
}) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ),
  ));
  final items = <Map<String, dynamic>>[
    {
      'product_id': 2,
      'price': 10.0,
      'quantity': packs,
      'discount_pct': discount,
      'discount_type': discountType,
      'extra_discount': 0.0,
      'packagings': [
        {
          'id': 7,
          'name': 'Box',
          'base_quantity': factor,
          'retail_price': packPrice,
          'is_active': true,
        },
      ],
    },
  ];
  final next = SaleUnitConversionService.changeSellingUnitQuick(
    context: ctx,
    items: items,
    index: 0,
    packagingId: 7,
    isEditing: false,
    customerType: null,
    onEditDeferred: (_) {},
    calculateCartLineTotal: SaleCartMutator.cartLineTotal,
  );
  expect(next, isNotNull);
  return next!;
}

void main() {
  group('SalesOrderSubmitter payload fidelity', () {
    test('loose line, percentage discount', () {
      final row = loose(qty: 1, price: 100, discountPct: 5);
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['discount'], 5.0);
      expect(backendLineTotal(line), 95.0);
      expect(backendLineTotal(line), SaleCartMutator.cartLineTotal(row));
    });

    test('loose line, per-unit fixed discount', () {
      final row = loose(
          qty: 4, price: 100, discountPct: 2.5, discountType: 'fixed');
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['discount'], 10.0);
      expect(backendLineTotal(line), 390.0);
    });

    test('loose line, extra discount only', () {
      final row = loose(qty: 2, price: 50, extra: 7);
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['discount'], 7.0);
      expect(backendLineTotal(line), 93.0);
    });

    testWidgets('packaged line passes pack fields through unchanged',
        (tester) async {
      final row = await packaged(tester, packs: 2, factor: 10, packPrice: 1000);
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['product_packaging_id'], 7);
      expect(line['packaging_quantity'], 2.0);
      expect(line['packaging_unit_price'], 1000.0);
      expect(line['quantity'], 20.0);
      expect(line['unit_price'], 100.0);
      expect(backendLineTotal(line), closeTo(2000.0, 0.01));
    });

    testWidgets('packaged line, per-pack fixed discount', (tester) async {
      final row = await packaged(tester,
          packs: 2,
          factor: 10,
          packPrice: 1000,
          discount: 50,
          discountType: 'fixed');
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['discount'], 100.0);
      expect(backendLineTotal(line), closeTo(1900.0, 0.01));
      expect(backendLineTotal(line),
          closeTo(SaleCartMutator.cartLineTotal(row), 0.01));
    });

    testWidgets('packaged row missing pack fields degrades to a loose line',
        (tester) async {
      final row = await packaged(tester, packs: 2, factor: 10, packPrice: 1000)
        ..remove('packaging_quantity');
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line.containsKey('product_packaging_id'), isFalse);
    });

    testWidgets('mixed cart total equals sum of cart line totals',
        (tester) async {
      final a = loose(qty: 1, price: 100, discountPct: 5);
      final b = await packaged(tester, packs: 2, factor: 10, packPrice: 1000);
      final lines = SalesOrderSubmitter.buildItemsPayload([a, b]);
      final order = lines.map(backendLineTotal).reduce((x, y) => x + y);
      expect(order, closeTo(2095.0, 0.01));
      for (var i = 0; i < lines.length; i++) {
        expect(backendLineTotal(lines[i]),
            closeTo(SaleCartMutator.cartLineTotal([a, b][i]), 0.01));
      }
    });

    test('buildOrderPayload sends status, never submit_for_approval', () {
      Map<String, dynamic> build(bool submit) =>
          SalesOrderSubmitter.buildOrderPayload(
            customerId: 1,
            salesmanId: 0,
            deliveryDate: null,
            notes: '',
            itemsPayload: const [],
            submitForApproval: submit,
            editOrderVersion: null,
          );
      expect(build(true)['status'], 'SUBMITTED');
      expect(build(false)['status'], 'DRAFT');
      for (final p in [build(true), build(false)]) {
        expect(p.containsKey('submit_for_approval'), isFalse);
        expect(p.containsKey('discount'), isFalse);
        expect(p.containsKey('tax'), isFalse);
      }
    });

    test('stored order lines round-trip through prefill without drift', () {
      final order = SalesOrder.fromJson({
        'id': 1,
        'order_number': 'SO-1',
        'status': 'SUBMITTED',
        'discount': 5,
        'items': [
          {
            'product_id': 1, 'quantity': 1, 'unit_price': 100,
            'discount': 5, 'subtotal': 100, 'total': 95,
          },
          {
            'product_id': 2, 'product_packaging_id': 7,
            'packaging_name_snapshot': 'Box',
            'packaging_factor_snapshot': 10, 'packaging_quantity': 1,
            'packaging_unit_price': 1000, 'quantity': 10, 'unit_price': 100,
            'subtotal': 1000, 'total': 1000,
          },
        ],
      });
      for (final data in [
        SalesOrderSubmitter.parseOrder(order),
        SalesOrderSubmitter.parsePrefill(SalesOrderPrefill(order: order)),
      ]) {
        // Header discount must not be loaded: lines already carry it.
        expect(data.discount, isNull);
        expect(data.tax, isNull);
        final lines = SalesOrderSubmitter.buildItemsPayload(data.items);
        expect(lines[0]['discount'], 5.0);
        expect(lines[1]['product_packaging_id'], 7);
        expect(lines[1]['packaging_quantity'], 1.0);
        expect(lines[1]['quantity'], 10.0);
        expect(lines[1]['unit_price'], 100.0);
        final total = data.items.map(SaleCartMutator.cartLineTotal)
            .reduce((a, b) => a + b);
        expect(total, closeTo(1095.0, 0.01));
      }
    });
  });
}
