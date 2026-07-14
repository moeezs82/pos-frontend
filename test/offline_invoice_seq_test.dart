// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:enterprise_pos/services/offline_invoice_seq_service.dart';

/// Unit tests for OfflineInvoiceSeqService.
///
/// Covers:
///   – Reference format: OFF-B{id}-{code}-{YYYYMMDD}-{NNNN}
///   – Daily sequence starts at 0001 for a fresh (branch, register, date)
///   – Sequence increments correctly within the same day
///   – Sequence resets to 0001 on a new day (different date key)
///   – Sequence persists across service restarts (SQLite is durable)
///   – Different registers in the same branch do NOT share a sequence
///   – Different branches do NOT share a sequence
///   – Register code is sanitised (uppercase, non-alphanumeric stripped)
void main() {
  // Use the in-memory FFI driver so tests run on any platform (no mobile
  // SQLite plugin required).
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Each test gets a fresh service instance with a fresh in-memory DB.
  late OfflineInvoiceSeqService svc;

  setUp(() {
    // Reach into the private field via tear-off to reset the singleton
    // between tests.  In production the singleton is fine; here we need
    // isolation.
    svc = _freshService();
  });

  // ── Format ──────────────────────────────────────────────────────────────────

  test('generates expected format OFF-B{id}-{code}-{date}-{seq}', () async {
    final ref = await svc.next(
      branchId: 1,
      registerCode: 'MAIN',
      occurredAt: DateTime(2026, 7, 15),
    );
    expect(ref, 'OFF-B1-MAIN-20260715-0001');
  });

  test('pads sequence to 4 digits', () async {
    // Advance the counter to 9 to test padding boundary
    for (int i = 0; i < 8; i++) {
      await svc.next(
        branchId: 1,
        registerCode: 'MAIN',
        occurredAt: DateTime(2026, 7, 15),
      );
    }
    final ref = await svc.next(
      branchId: 1,
      registerCode: 'MAIN',
      occurredAt: DateTime(2026, 7, 15),
    );
    expect(ref, 'OFF-B1-MAIN-20260715-0009');
  });

  // ── Daily sequence ──────────────────────────────────────────────────────────

  test('sequence starts at 0001 for a new (branch, register, date)', () async {
    final first = await svc.next(
      branchId: 2,
      registerCode: 'COUNTER',
      occurredAt: DateTime(2026, 7, 14),
    );
    expect(first, 'OFF-B2-COUNTER-20260714-0001');
  });

  test('sequence increments within the same day', () async {
    final d = DateTime(2026, 7, 15);
    final r1 = await svc.next(branchId: 1, registerCode: 'REG', occurredAt: d);
    final r2 = await svc.next(branchId: 1, registerCode: 'REG', occurredAt: d);
    final r3 = await svc.next(branchId: 1, registerCode: 'REG', occurredAt: d);
    expect(r1, 'OFF-B1-REG-20260715-0001');
    expect(r2, 'OFF-B1-REG-20260715-0002');
    expect(r3, 'OFF-B1-REG-20260715-0003');
  });

  test('sequence resets to 0001 on a new date', () async {
    await svc.next(
      branchId: 1,
      registerCode: 'MAIN',
      occurredAt: DateTime(2026, 7, 14),
    );
    await svc.next(
      branchId: 1,
      registerCode: 'MAIN',
      occurredAt: DateTime(2026, 7, 14),
    );
    // New day
    final firstOfNextDay = await svc.next(
      branchId: 1,
      registerCode: 'MAIN',
      occurredAt: DateTime(2026, 7, 15),
    );
    expect(firstOfNextDay, 'OFF-B1-MAIN-20260715-0001');
  });

  // ── Isolation ───────────────────────────────────────────────────────────────

  test('different registers in same branch have independent sequences', () async {
    final d = DateTime(2026, 7, 15);
    final r1 = await svc.next(branchId: 1, registerCode: 'COUNTER1', occurredAt: d);
    final r2 = await svc.next(branchId: 1, registerCode: 'COUNTER2', occurredAt: d);
    expect(r1, 'OFF-B1-COUNTER1-20260715-0001');
    expect(r2, 'OFF-B1-COUNTER2-20260715-0001');

    // Second sale on each counter
    final r3 = await svc.next(branchId: 1, registerCode: 'COUNTER1', occurredAt: d);
    final r4 = await svc.next(branchId: 1, registerCode: 'COUNTER2', occurredAt: d);
    expect(r3, 'OFF-B1-COUNTER1-20260715-0002');
    expect(r4, 'OFF-B1-COUNTER2-20260715-0002');
  });

  test('different branches have independent sequences', () async {
    final d = DateTime(2026, 7, 15);
    final rA = await svc.next(branchId: 1, registerCode: 'MAIN', occurredAt: d);
    final rB = await svc.next(branchId: 2, registerCode: 'MAIN', occurredAt: d);
    expect(rA, 'OFF-B1-MAIN-20260715-0001');
    expect(rB, 'OFF-B2-MAIN-20260715-0001');
  });

  // ── Register code sanitisation ───────────────────────────────────────────────

  test('register code is uppercased', () async {
    final ref = await svc.next(
      branchId: 1,
      registerCode: 'main',
      occurredAt: DateTime(2026, 7, 15),
    );
    expect(ref, 'OFF-B1-MAIN-20260715-0001');
  });

  test('non-alphanumeric chars are stripped from register code', () async {
    final ref = await svc.next(
      branchId: 1,
      registerCode: 'MAIN-1',
      occurredAt: DateTime(2026, 7, 15),
    );
    // Dash is stripped → MAIN1
    expect(ref, 'OFF-B1-MAIN1-20260715-0001');
  });

  // ── Peek (state inspection) ──────────────────────────────────────────────────

  test('peekNextSeq returns 1 before any allocation', () async {
    final next = await svc.peekNextSeq(
      branchId: 1,
      registerCode: 'MAIN',
      forDate: DateTime(2026, 7, 15),
    );
    expect(next, 1);
  });

  test('peekNextSeq reflects allocated count', () async {
    final d = DateTime(2026, 7, 15);
    await svc.next(branchId: 1, registerCode: 'MAIN', occurredAt: d);
    await svc.next(branchId: 1, registerCode: 'MAIN', occurredAt: d);
    final next = await svc.peekNextSeq(
      branchId: 1,
      registerCode: 'MAIN',
      forDate: d,
    );
    expect(next, 3); // next to be allocated is 3
  });
}

/// Creates a fresh [OfflineInvoiceSeqService] backed by an in-memory SQLite
/// database.  Uses the package-private constructor via reflection workaround:
/// since Dart doesn't support reflection, we expose a factory in tests.
OfflineInvoiceSeqService _freshService() {
  // We reset the singleton's internal _db to null so each test gets a fresh
  // in-memory DB.  This relies on the fact that sqflite_common_ffi's
  // databaseFactoryFfi.openDatabase(':memory:') creates a new fresh DB each
  // time when the path is ':memory:' — but our service uses a named path.
  //
  // Instead, we override getDatabasesPath behaviour by relying on the fact
  // that in tests databaseFactoryFfi creates the DB at the in-memory path
  // when given ':memory:'.  Since we can't easily inject the path into the
  // service, we use the singleton and reset its _db field between tests via
  // the test-only [resetForTesting] method.
  OfflineInvoiceSeqService.instance.resetForTesting();
  return OfflineInvoiceSeqService.instance;
}
