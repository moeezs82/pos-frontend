import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order_batch.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> ok(List<BatchRef> chunk, {String note = ''}) => {
      'success': true,
      'data': {
        'succeeded': [
          for (final r in chunk)
            {
              'id': r.id,
              'order_number': 'SO-${r.id}',
              'status': 'CONVERTED',
              'sale_id': r.id + 1000,
              'invoice_no': 'INV-${r.id}',
              'note': note.isEmpty ? null : note,
            }
        ],
        'failed': [],
        'summary': {'requested': chunk.length},
      },
    };

void main() {
  group('batch chunking', () {
    test('splits at the cap and preserves order', () {
      final ids = List.generate(60, (i) => i + 1);
      final chunks = chunkList(ids, BatchAction.approve.cap);
      expect(chunks.map((c) => c.length), [50, 10]);
      expect(chunks.expand((c) => c).toList(), ids);
    });

    test('convert uses the smaller cap', () {
      expect(BatchAction.convert.cap, 25);
      expect(chunkList(List.generate(26, (i) => i), BatchAction.convert.cap).length, 2);
    });

    test('empty input yields no chunks', () {
      expect(chunkList(<int>[], 25), isEmpty);
    });
  });

  group('runBatchChunks', () {
    test('sends every chunk and aggregates successes in order', () async {
      final seen = <int>[];
      final progress = <int>[];
      final outcome = await runBatchChunks(
        items: [for (var i = 1; i <= 60; i++) BatchRef(i, 1)],
        cap: 25,
        onProgress: (done, total) => progress.add(done),
        send: (chunk) async {
          seen.add(chunk.length);
          return ok(chunk);
        },
      );
      expect(seen, [25, 25, 10]);
      expect(progress, [1, 2, 3]);
      expect(outcome.succeeded.length, 60);
      expect(outcome.failed, isEmpty);
      expect(outcome.unknown, isEmpty);
    });

    test('already-converted retries bucket under succeeded', () async {
      final outcome = await runBatchChunks(
        items: [const BatchRef(1), const BatchRef(2)],
        cap: 25,
        send: (chunk) async => ok(chunk, note: 'already converted'),
      );
      expect(outcome.succeeded.length, 2);
      expect(outcome.succeeded.every((s) => s.alreadyDone), isTrue);
      expect(outcome.failed, isEmpty);
    });

    test('a malformed-envelope 422 fails the chunk with the server message', () async {
      final outcome = await runBatchChunks(
        items: [const BatchRef(1), const BatchRef(2)],
        cap: 25,
        send: (_) async =>
            throw ApiException(422, 'Open a register shift before creating a sale.'),
      );
      expect(outcome.failed.map((f) => f.id), [1, 2]);
      expect(outcome.failed.first.message, contains('register shift'));
      expect(outcome.unknown, isEmpty);
    });

    test('a transport error marks the chunk unknown, not failed, and later chunks still run', () async {
      var call = 0;
      final outcome = await runBatchChunks(
        items: [for (var i = 1; i <= 4; i++) BatchRef(i)],
        cap: 2,
        send: (chunk) async {
          call++;
          if (call == 1) throw Exception('connection reset');
          return ok(chunk);
        },
      );
      expect(outcome.unknown, [1, 2]);
      expect(outcome.failed, isEmpty);
      expect(outcome.succeeded.map((s) => s.id), [3, 4]);
      expect(outcome.unknownReason, contains('connection reset'));
    });

    test('per-order failures are grouped by code', () async {
      final outcome = await runBatchChunks(
        items: [const BatchRef(1), const BatchRef(2), const BatchRef(3)],
        cap: 25,
        send: (_) async => {
          'success': true,
          'data': {
            'succeeded': [],
            'failed': [
              {'id': 1, 'order_number': 'SO-1', 'code': 'CREDIT_LIMIT_BLOCKED', 'message': 'x'},
              {'id': 2, 'order_number': 'SO-2', 'code': 'CREDIT_LIMIT_BLOCKED', 'message': 'y'},
              {'id': 3, 'order_number': 'SO-3', 'code': 'VERSION_CONFLICT', 'message': 'z'},
            ],
          },
        },
      );
      final byCode = outcome.failuresByCode();
      expect(byCode['CREDIT_LIMIT_BLOCKED']!.length, 2);
      expect(byCode['VERSION_CONFLICT']!.length, 1);
    });
  });
}
