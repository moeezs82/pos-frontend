import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_batch.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/sales_order_bulk_actions.dart';
import 'package:flutter_test/flutter_test.dart';

SalesOrder order(int id, String status) => SalesOrder.fromJson({
      'id': id,
      'order_number': 'SO-$id',
      'status': status,
      'total': 100,
      'items': [],
    });

BatchSuccess ok(int id, String status, {String? stopped}) => BatchSuccess(
      id: id,
      orderNumber: 'SO-$id',
      status: status,
      stoppedBecause: stopped,
    );

void main() {
  group('BulkRunResult.remaining', () {
    test('keeps advanced, unfinished orders selected so the next stage needs no re-selection', () {
      final outcome = BatchOutcome()
        ..succeeded.addAll([
          ok(1, 'SUBMITTED'),
          ok(2, 'APPROVED'),
          ok(3, 'CONVERTED'),
          ok(4, 'CANCELLED'),
          ok(5, 'REJECTED'),
        ])
        ..failed.add(const BatchFailure(id: 6, orderNumber: 'SO-6', code: 'X', message: 'm'))
        ..unknown.add(7);
      final r = BulkRunResult(action: BatchAction.submit, held: const {8: 'blocked'}, outcome: outcome);
      expect(r.remaining, {1, 2, 6, 7, 8});
    });

    test('a fully finished run leaves nothing selected', () {
      final outcome = BatchOutcome()..succeeded.addAll([ok(1, 'CONVERTED'), ok(2, 'CONVERTED')]);
      expect(BulkRunResult(action: BatchAction.process, outcome: outcome).remaining, isEmpty);
    });
  });

  group('process eligibility', () {
    test('accepts draft, submitted and approved; rejects finished orders', () {
      for (final s in ['DRAFT', 'SUBMITTED', 'APPROVED']) {
        expect(isBatchEligible(BatchAction.process, order(1, s)), isTrue, reason: s);
      }
      for (final s in ['CONVERTED', 'CANCELLED', 'REJECTED']) {
        expect(isBatchEligible(BatchAction.process, order(1, s)), isFalse, reason: s);
      }
    });

    test('per-stage actions stay strict single-status gates', () {
      expect(isBatchEligible(BatchAction.convert, order(1, 'DRAFT')), isFalse);
      expect(isBatchEligible(BatchAction.approve, order(1, 'SUBMITTED')), isTrue);
      expect(isBatchEligible(BatchAction.submit, order(1, 'APPROVED')), isFalse);
    });
  });

  group('messages', () {
    test('pastTense never appends to the verb', () {
      expect(BatchAction.convert.pastTense, 'converted');
      expect(BatchAction.submit.pastTense, 'submitted');
      expect(BatchAction.cancel.pastTense, 'cancelled');
      expect(BatchAction.approve.pastTense, 'approved');
      expect(BatchAction.reject.pastTense, 'rejected');
      expect(BatchAction.process.pastTense, 'processed');
      for (final a in BatchAction.values) {
        expect(a.pastTense, isNot(contains('convertd')));
        expect(a.pastTense, isNot(contains('cancelld')));
      }
    });

    test('status breakdown names what was selected', () {
      final text = statusBreakdown([order(1, 'DRAFT'), order(2, 'SUBMITTED'), order(3, 'SUBMITTED')]);
      expect(text, contains('1 draft'));
      expect(text, contains('2 '));
    });

    test('process cap matches convert', () {
      expect(BatchAction.process.cap, 25);
      expect(BatchAction.process.path, 'process');
    });
  });

  group('processPreview', () {
    final mixed = [
      ...List.generate(4, (i) => order(i + 1, 'DRAFT')),
      ...List.generate(4, (i) => order(i + 11, 'SUBMITTED')),
      ...List.generate(2, (i) => order(i + 21, 'APPROVED')),
    ];

    test('counts match the selection breakdown', () {
      final text = processPreview(
        orders: mixed,
        blockedIds: const {},
        toInvoice: true,
        canApprove: true,
        canConvert: true,
        paymentMode: 'credit',
      );
      expect(text, 'This will submit 4, approve 8 and invoice 10 as credit.');
    });

    test('blocked orders are submitted but stop before approval', () {
      final text = processPreview(
        orders: mixed,
        blockedIds: const {1, 11},
        toInvoice: true,
        canApprove: true,
        canConvert: true,
        paymentMode: 'credit',
      );
      expect(text, contains('approve 6'));
      expect(text, contains('invoice 8'));
      expect(text, contains('2 orders have blocking issues'));
    });

    test('approve-only never promises an invoice', () {
      final text = processPreview(
        orders: mixed,
        blockedIds: const {},
        toInvoice: false,
        canApprove: true,
        canConvert: true,
        paymentMode: 'credit',
      );
      expect(text, isNot(contains('invoice')));
    });

    test('a user without approve or convert authority sees what they can actually do', () {
      final text = processPreview(
        orders: mixed,
        blockedIds: const {},
        toInvoice: true,
        canApprove: false,
        canConvert: false,
        paymentMode: 'credit',
      );
      expect(text, 'This will submit 4.');
    });
  });

  test('stoppedShort groups by what the operator should do next and skips full runs', () {
    final groups = stoppedShort([
      ok(1, 'APPROVED', stopped: 'no_convert_permission'),
      ok(2, 'APPROVED', stopped: 'no_convert_permission'),
      ok(3, 'SUBMITTED', stopped: 'blocking_issues'),
      ok(4, 'CONVERTED'),
      ok(5, 'APPROVED', stopped: 'stop_at_reached'),
    ]);
    expect(groups['awaiting conversion']!.length, 2);
    expect(groups['stopped before approval — blocking issues']!.length, 1);
    expect(groups.length, 2);
  });
}
