import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_mutator.dart';
import 'package:enterprise_pos/screens/sales/services/sale_unit_conversion_service.dart';
import 'package:enterprise_pos/screens/sales/services/sales_order_submitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Invariant under test:
//   the order payload's implied line total == SaleCartMutator.cartLineTotal(row)
// for every discount shape and for packaged and loose rows alike.

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Dart port of sales.EconomicsForLine, fed with the order wire shape — what
/// the backend resolves a payload line to (money only; tax is always 0 here).
double backendLineTotal(Map<String, dynamic> line) {
  final type = line['discount_type'] as String;
  final pct = (line['discount_pct'] as num).toDouble();
  final extra = (line['extra_discount'] as num).toDouble();
  final packaged = line['product_packaging_id'] != null;
  double gross;
  double disc;
  if (packaged) {
    final pq = (line['packaging_quantity'] as num).toDouble();
    final pp = (line['packaging_unit_price'] as num).toDouble();
    gross = _r2(pq * pp);
    disc = type == 'fixed'
        ? _r2(pq * (line['packaging_discount_snapshot'] as num).toDouble())
        : _r2(gross * (pct.clamp(0.0, 100.0) / 100));
  } else {
    final q = (line['quantity'] as num).toDouble();
    gross = _r2(q * (line['unit_price'] as num).toDouble());
    disc = type == 'fixed'
        ? _r2(pct * q)
        : _r2(gross * (pct.clamp(0.0, 100.0) / 100));
  }
  return _r2(gross - disc - extra);
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
      expect(line['discount_pct'], 5.0);
      expect(line['discount_type'], 'percentage');
      expect(line['extra_discount'], 0);
      expect(backendLineTotal(line), 95.0);
      expect(backendLineTotal(line), SaleCartMutator.cartLineTotal(row));
    });

    test('loose line, per-unit fixed discount', () {
      final row = loose(
          qty: 4, price: 100, discountPct: 2.5, discountType: 'fixed');
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['discount_pct'], 2.5);
      expect(line['discount_type'], 'fixed');
      expect(backendLineTotal(line), 390.0);
    });

    test('loose line, extra discount only', () {
      final row = loose(qty: 2, price: 50, extra: 7);
      final line = SalesOrderSubmitter.buildItemsPayload([row]).single;
      expect(line['extra_discount'], 7.0);
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
      // Wire shape: money per PACK, in both discount_pct and the snapshot.
      expect(line['discount_type'], 'fixed');
      expect(line['discount_pct'], 50.0);
      expect(line['packaging_discount_snapshot'], 50.0);
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

    test('payload never carries the collapsed whole-line discount', () {
      final line = SalesOrderSubmitter.buildItemsPayload(
          [loose(qty: 1, price: 100, discountPct: 5)]).single;
      expect(line.containsKey('discount'), isFalse);
    });

    testWidgets('sale and sales order encode discounts identically',
        (tester) async {
      final row = await packaged(tester,
          packs: 2,
          factor: 10,
          packPrice: 1000,
          discount: 50,
          discountType: 'fixed');
      row['extra_discount'] = 4.0;
      final order = SalesOrderSubmitter.buildItemsPayload([row]).single;
      final sale = SaleService(token: 't').buildSalePayload(items: [row]);
      final saleLine = (sale['items'] as List).single as Map;
      for (final k in [
        'discount_pct',
        'discount_type',
        'extra_discount',
        'packaging_discount_snapshot',
      ]) {
        expect(order[k], saleLine[k], reason: k);
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
            'discount': 5, 'extra_discount': 5, 'discount_type': 'percentage',
            'subtotal': 100, 'total': 95,
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
        expect(lines[0]['extra_discount'], 5.0);
        expect(lines[1]['product_packaging_id'], 7);
        expect(lines[1]['packaging_quantity'], 1.0);
        expect(lines[1]['quantity'], 10.0);
        expect(lines[1]['unit_price'], 100.0);
        final total = data.items.map(SaleCartMutator.cartLineTotal)
            .reduce((a, b) => a + b);
        expect(total, closeTo(1095.0, 0.01));
      }
    });

    test('packaged fixed discount round-trips per pack <-> per base unit', () {
      final order = SalesOrder.fromJson({
        'id': 1,
        'order_number': 'SO-2',
        'status': 'SUBMITTED',
        'items': [
          {
            'product_id': 2, 'product_packaging_id': 7,
            'packaging_name_snapshot': 'Box',
            'packaging_factor_snapshot': 10, 'packaging_quantity': 2,
            'packaging_unit_price': 1000, 'quantity': 20, 'unit_price': 100,
            'discount_type': 'fixed', 'discount_pct': 50,
            'packaging_discount_snapshot': 50, 'extra_discount': 0,
            'discount': 100, 'subtotal': 2000, 'total': 1900,
          },
          {
            'product_id': 3, 'quantity': 1, 'unit_price': 250,
            'discount_type': 'percentage', 'discount_pct': 3,
            'extra_discount': 2.5, 'discount': 10, 'subtotal': 250,
            'total': 240,
          },
        ],
      });
      final rows = SalesOrderSubmitter.parseOrder(order).items;
      // Cart keeps the packaged fixed amount per base unit.
      expect(rows[0]['discount_pct'], 5.0);
      expect(rows[0]['packaging_discount_snapshot'], 50.0);
      expect(SaleCartMutator.cartLineTotal(rows[0]), closeTo(1900.0, 0.01));
      expect(SaleCartMutator.cartLineTotal(rows[1]), closeTo(240.0, 0.01));

      final lines = SalesOrderSubmitter.buildItemsPayload(rows);
      expect(lines[0]['discount_pct'], 50.0); // back to the wire shape
      expect(lines[0]['discount_type'], 'fixed');
      expect(lines[0]['packaging_discount_snapshot'], 50.0);
      expect(lines[1]['discount_pct'], 3.0);
      expect(lines[1]['discount_type'], 'percentage');
      expect(lines[1]['extra_discount'], 2.5);
    });
  });
}
