import 'dart:convert';

import 'package:path/path.dart' as p;
// Driven through sqflite_common_ffi (not the plain sqflite plugin) because
// this is a Windows desktop app — see the pubspec.yaml comment next to
// sqflite_common_ffi for why. The API surface (Database, openDatabase,
// getDatabasesPath, ConflictAlgorithm) is identical either way.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local queue for sales created while the app can't reach the backend
/// (handover doc §2.1). This is the *only* local persistence the app has —
/// there is deliberately no local stock cache; stock is still only ever
/// decremented server-side, at sync time (see §2.3/§1.5).
enum OfflineSaleStatus { pending, syncing, synced, failed }

OfflineSaleStatus _statusFromString(String value) {
  return OfflineSaleStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => OfflineSaleStatus.pending,
  );
}

class OfflineSaleQueueItem {
  final int id;
  final String clientRef;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;
  final OfflineSaleStatus status;
  final String? serverInvoiceNo;
  final String? lastError;
  final DateTime createdAt;

  OfflineSaleQueueItem({
    required this.id,
    required this.clientRef,
    required this.payload,
    required this.occurredAt,
    required this.status,
    this.serverInvoiceNo,
    this.lastError,
    required this.createdAt,
  });

  /// Best-effort display total, pulled from the same `meta.totals_snapshot`
  /// that sale_create.dart already builds for the receipt (see
  /// _buildSaleMeta), so the sync screen can show an amount without needing
  /// a second round trip.
  double get displayTotal {
    final totals = (payload['meta'] as Map?)?['totals_snapshot'] as Map?;
    final value = totals?['total'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String get displayCustomerName {
    final customer = (payload['meta'] as Map?)?['customer_snapshot'] as Map?;
    final name = customer?['name']?.toString().trim();
    return (name == null || name.isEmpty) ? 'Walk-in customer' : name;
  }

  factory OfflineSaleQueueItem.fromMap(Map<String, dynamic> map) {
    return OfflineSaleQueueItem(
      id: map['id'] as int,
      clientRef: map['client_ref'] as String,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      status: _statusFromString(map['status'] as String),
      serverInvoiceNo: map['server_invoice_no'] as String?,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class OfflineSalesQueueService {
  OfflineSalesQueueService._();
  static final OfflineSalesQueueService instance = OfflineSalesQueueService._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'offline_sales_queue.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_sales_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_ref TEXT UNIQUE NOT NULL,
            payload TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            server_invoice_no TEXT,
            last_error TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Every sale gets a client_ref, online or offline (§2.2). A sale lands
  /// here whenever the initial submit failed for any reason — not just a
  /// network-unreachable failure — so [initialError] records why, purely
  /// for the cashier/manager's visibility on the sync screen. It's still
  /// queued as `pending` either way: the actual sync attempt (see
  /// OfflineSyncService) is what correctly tells apart "still offline,
  /// retry later" from "real error, needs a human" — so a genuinely broken
  /// item (e.g. a deleted product) surfaces as `failed` on its first Sync
  /// Now attempt rather than looping forever.
  Future<void> enqueue({
    required String clientRef,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
    String? initialError,
  }) async {
    final db = await _database;
    await db.insert(
      'offline_sales_queue',
      {
        'client_ref': clientRef,
        'payload': jsonEncode(payload),
        'occurred_at': occurredAt.toIso8601String(),
        'status': OfflineSaleStatus.pending.name,
        'last_error': initialError,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Queue order = oldest occurred_at first, so same-day invoice numbering
  /// stays roughly chronological once synced (§1.3, §2.4).
  Future<List<OfflineSaleQueueItem>> pendingOrFailed() async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'status IN (?, ?)',
      whereArgs: [OfflineSaleStatus.pending.name, OfflineSaleStatus.failed.name],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(OfflineSaleQueueItem.fromMap).toList();
  }

  Future<List<OfflineSaleQueueItem>> all() async {
    final db = await _database;
    final rows = await db.query('offline_sales_queue', orderBy: 'occurred_at ASC');
    return rows.map(OfflineSaleQueueItem.fromMap).toList();
  }

  Future<int> pendingCount() async {
    final db = await _database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_sales_queue WHERE status IN ('pending', 'failed')",
    );
    final value = result.isEmpty ? null : result.first['c'];
    return (value is int) ? value : (int.tryParse(value?.toString() ?? '') ?? 0);
  }

  Future<void> markSyncing(String clientRef) async {
    await _updateStatus(clientRef, OfflineSaleStatus.syncing);
  }

  Future<void> markSynced(String clientRef, {required String serverInvoiceNo}) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {'status': OfflineSaleStatus.synced.name, 'server_invoice_no': serverInvoiceNo, 'last_error': null},
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  /// Network failed again mid-sync — leave it queued for the next attempt,
  /// don't mark it failed (that's reserved for real validation errors).
  Future<void> markPending(String clientRef, {String? lastError}) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {'status': OfflineSaleStatus.pending.name, 'last_error': lastError},
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  Future<void> markFailed(String clientRef, {required String lastError}) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {'status': OfflineSaleStatus.failed.name, 'last_error': lastError},
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  Future<void> _updateStatus(String clientRef, OfflineSaleStatus status) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {'status': status.name},
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }
}
