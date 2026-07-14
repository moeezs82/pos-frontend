import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Generates customer-friendly offline invoice references such as:
///
///   OFF-B1-MAIN-20260714-0001
///
/// where:
///   B{branch_id}   — stable, non-editable branch identifier derived from the
///                    database branch ID (same DB that the server uses).
///   {register_code} — the register's short code (e.g. "MAIN", "COUNTER").
///                    Unique within a branch; set when the register was created.
///   YYYYMMDD       — the local date the sale occurred (from [occurredAt]).
///   NNNN           — daily sequence starting at 0001 per (branch_id,
///                    register_code, date). Persists across app restarts.
///
/// COLLISION SAFETY:
/// Each physical device has its own SQLite database.  The sequence is scoped
/// by (branch_id, register_code, seq_date), so two devices collide ONLY if
/// they use the exact same register code within the same branch on the same
/// day.  Proper setup (one register per device) prevents this.  The backend
/// enforces global uniqueness on offline_invoice_no: if a collision does
/// occur (misconfigured setup), the second sync will fail visibly rather than
/// silently corrupting data.
///
/// RESTART SAFETY:
/// Sequences are persisted in a dedicated SQLite table — they do NOT reset
/// when the app restarts.  Row count is never used as a sequence source
/// because synced/deleted rows would cause reuse.
class OfflineInvoiceSeqService {
  OfflineInvoiceSeqService._();
  static final instance = OfflineInvoiceSeqService._();

  Database? _db;

  /// Override the database path for testing (pass ':memory:' or a temp path).
  /// Must be set before the first call to [next] or [peekNextSeq].
  String? _testDbPath;

  /// Resets the internal database handle so the next operation opens a fresh
  /// database.  Used in tests to isolate each test case.
  void resetForTesting({String path = ':memory:'}) {
    _db?.close();
    _db = null;
    _testDbPath = path;
  }

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = _testDbPath ?? p.join(await getDatabasesPath(), 'offline_invoice_seq.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE offline_invoice_seq (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            branch_id    INTEGER NOT NULL,
            register_code TEXT NOT NULL,
            seq_date     TEXT NOT NULL,
            next_seq     INTEGER NOT NULL DEFAULT 1,
            UNIQUE(branch_id, register_code, seq_date)
          )
        ''');
      },
    );
  }

  /// Generates the next offline invoice reference for the given branch,
  /// register code, and occurrence date.
  ///
  /// Thread-safe for sequential calls; each call is wrapped in a SQLite
  /// exclusive transaction so restarts and rapid successive calls cannot
  /// produce duplicates.
  ///
  /// Never throws on a normal call — all errors are rethrown so the caller
  /// (sale_create.dart) can fall back gracefully.
  Future<String> next({
    required int branchId,
    required String registerCode,
    required DateTime occurredAt,
  }) async {
    final db = await _database;
    final seqDate = _dateKey(occurredAt); // "YYYYMMDD"
    final safeCode = registerCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // Atomic read-then-increment inside an exclusive SQLite transaction.
    int seq = 0;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'offline_invoice_seq',
        where: 'branch_id = ? AND register_code = ? AND seq_date = ?',
        whereArgs: [branchId, safeCode, seqDate],
        limit: 1,
      );

      if (rows.isEmpty) {
        // First sale for this (branch, register, date): insert seq = 1,
        // next_seq becomes 2.
        seq = 1;
        await txn.insert('offline_invoice_seq', {
          'branch_id':     branchId,
          'register_code': safeCode,
          'seq_date':      seqDate,
          'next_seq':      2,
        });
      } else {
        seq = rows.first['next_seq'] as int;
        await txn.update(
          'offline_invoice_seq',
          {'next_seq': seq + 1},
          where: 'branch_id = ? AND register_code = ? AND seq_date = ?',
          whereArgs: [branchId, safeCode, seqDate],
        );
      }
    });

    // Format: OFF-B{branchId}-{registerCode}-{YYYYMMDD}-{NNNN}
    final seqPadded = seq.toString().padLeft(4, '0');
    return 'OFF-B$branchId-$safeCode-$seqDate-$seqPadded';
  }

  /// Returns the current (not yet allocated) next_seq for a given scope,
  /// without incrementing it.  Used in tests to inspect state.
  Future<int> peekNextSeq({
    required int branchId,
    required String registerCode,
    required DateTime forDate,
  }) async {
    final db = await _database;
    final seqDate = _dateKey(forDate);
    final safeCode = registerCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final rows = await db.query(
      'offline_invoice_seq',
      columns: ['next_seq'],
      where: 'branch_id = ? AND register_code = ? AND seq_date = ?',
      whereArgs: [branchId, safeCode, seqDate],
      limit: 1,
    );
    return rows.isEmpty ? 1 : (rows.first['next_seq'] as int);
  }

  // Formats a DateTime as "YYYYMMDD" for use as a sequence key.
  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
