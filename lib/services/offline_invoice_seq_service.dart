import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Generates customer-friendly offline invoice references such as:
///
///   OFF-B1-MAIN-20260714-0001-A3F9B2C1
///
/// where:
///   B{branch_id}    — stable, non-editable branch identifier.
///   {register_code} — the register's short code (e.g. "MAIN", "COUNTER").
///                     Unique within a branch; set when the register was created.
///   YYYYMMDD        — the local date the sale occurred (from [occurredAt]).
///   NNNN            — daily sequence starting at 0001 per (branch_id,
///                     register_code, seq_date, device_key). Persists across
///                     app restarts because the database uses a stable OS path.
///   {deviceKey8}    — 8 hex characters generated once per install and stored
///                     in SharedPreferences. Makes every physical device's
///                     offline references globally unique even if two terminals
///                     share the same register code, or if the app is reinstalled
///                     and the sequence counter resets to 0001.
///
/// COLLISION SAFETY:
/// The device key guarantees that refs from different physical installs
/// are always distinct, even on the same (branch, register, date, seq)
/// combination. The backend UNIQUE constraint on offline_invoice_no still
/// protects against any accidental duplicates.
///
/// RESTART SAFETY:
/// Sequences are persisted in a dedicated SQLite database at the stable
/// getApplicationSupportDirectory() path — they do NOT reset when the app
/// restarts or is relaunched from a different working directory.
class OfflineInvoiceSeqService {
  OfflineInvoiceSeqService._();
  static final instance = OfflineInvoiceSeqService._();

  Database? _db;
  String? _deviceKey;

  /// Override the database path for testing (pass ':memory:' or a temp path).
  /// Must be set before the first call to [next] or [peekNextSeq].
  String? _testDbPath;

  /// Resets the internal database handle so the next operation opens a fresh
  /// database.  Used in tests to isolate each test case.
  void resetForTesting({String path = ':memory:'}) {
    _db?.close();
    _db = null;
    _deviceKey = null;
    _testDbPath = path;
  }

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  /// Flushes and closes the sequence database so Backup & Restore can take or
  /// install an exact file copy. The next sequence request reopens it lazily.
  Future<void> closeForBackupRestore() async {
    final db = _db;
    _db = null;
    _deviceKey = null;
    if (db != null) {
      await db.close();
    }
  }

  Future<Database> _open() async {
    if (_testDbPath != null) {
      return openDatabase(
        _testDbPath!,
        version: 1,
        onCreate: _createSchema,
      );
    }
    // Use the OS-stable app support directory so the sequence database
    // persists across app restarts regardless of the process working directory.
    // On Windows this is typically:
    //   C:\Users\{user}\AppData\Roaming\{org}\{appName}\
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, 'databases'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dir.path, 'offline_invoice_seq.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database db, int version) async {
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
  }

  /// Returns the 8-character uppercase hex device key, generating and persisting
  /// it on first call.  The key is cached in-memory after the first read so
  /// subsequent [next] calls do not hit SharedPreferences.
  Future<String> _getDeviceKey() async {
    if (_deviceKey != null) return _deviceKey!;
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getString('offline_device_key');
    if (stored == null) {
      // Generate once per install; UUID hex without dashes, first 8 chars.
      stored = const Uuid().v4().replaceAll('-', '').substring(0, 8).toUpperCase();
      await prefs.setString('offline_device_key', stored);
    }
    _deviceKey = stored;
    return stored;
  }

  /// Generates the next offline invoice reference for the given branch,
  /// register code, and occurrence date.
  ///
  /// Format: OFF-B{branchId}-{registerCode}-{YYYYMMDD}-{NNNN}-{DEVICEKEY8}
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
    if (branchId <= 0) {
      throw ArgumentError.value(
        branchId,
        'branchId',
        'A valid branch is required for offline invoice generation.',
      );
    }
    final db = await _database;
    final deviceKey = await _getDeviceKey();
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

    // Format: OFF-B{branchId}-{registerCode}-{YYYYMMDD}-{NNNN}-{DEVICEKEY8}
    final seqPadded = seq.toString().padLeft(4, '0');
    return 'OFF-B$branchId-$safeCode-$seqDate-$seqPadded-$deviceKey';
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
