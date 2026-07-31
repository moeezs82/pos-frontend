import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

int? _readPositiveInt(dynamic value) {
  if (value is int) return value > 0 ? value : null;
  if (value is num) {
    final parsed = value.toInt();
    return parsed > 0 ? parsed : null;
  }
  final parsed = int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

class OfflineSaleQueueItem {
  final int id;
  final String clientRef;
  final int? originBranchId;
  final int? originUserId;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;
  final OfflineSaleStatus status;
  final String? serverInvoiceNo;

  /// The customer-friendly offline receipt reference generated on-device
  /// (e.g. "OFF-B1-MAIN-20260714-0001"). Printed on the receipt while the
  /// sale is pending sync. Retained after sync alongside the official
  /// invoice_no for traceability.
  final String? offlineInvoiceNo;

  final String? lastError;
  final DateTime createdAt;

  /// How many sync attempts have been made (handover doc G6). Drives
  /// exponential backoff and the give-up-after-N cap so a genuinely broken
  /// item can't loop forever on every reconnect.
  final int attempts;

  /// Earliest time the next automatic sync should try this item again — set
  /// when a retryable failure schedules a backoff. Null means "due now".
  final DateTime? nextRetryAt;

  OfflineSaleQueueItem({
    required this.id,
    required this.clientRef,
    required this.originBranchId,
    required this.originUserId,
    required this.payload,
    required this.occurredAt,
    required this.status,
    this.serverInvoiceNo,
    this.offlineInvoiceNo,
    this.lastError,
    required this.createdAt,
    this.attempts = 0,
    this.nextRetryAt,
  });

  /// True when an automatic sync should skip this item for now because its
  /// backoff window hasn't elapsed. A manual per-row "Retry" ignores this.
  bool get isDueForAutoRetry {
    final t = nextRetryAt;
    return t == null || !t.isAfter(DateTime.now());
  }

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
    final retryRaw = map['next_retry_at'] as String?;
    return OfflineSaleQueueItem(
      id: map['id'] as int,
      clientRef: map['client_ref'] as String,
      originBranchId: _readPositiveInt(map['origin_branch_id']),
      originUserId: _readPositiveInt(map['origin_user_id']),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      status: _statusFromString(map['status'] as String),
      serverInvoiceNo: map['server_invoice_no'] as String?,
      offlineInvoiceNo: map['offline_invoice_no'] as String?,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      attempts: (map['attempts'] as int?) ?? 0,
      nextRetryAt: (retryRaw == null || retryRaw.isEmpty) ? null : DateTime.tryParse(retryRaw),
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
    // Use the OS-stable app support directory so the queue database persists
    // across app restarts regardless of the process working directory.
    // On Windows this is typically:
    //   C:\Users\{user}\AppData\Roaming\{org}\{appName}\
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, 'databases'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dir.path, 'offline_sales_queue.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_sales_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_ref TEXT UNIQUE NOT NULL,
            origin_branch_id INTEGER,
            origin_user_id INTEGER,
            payload TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            server_invoice_no TEXT,
            offline_invoice_no TEXT,
            last_error TEXT,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_retry_at TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX offline_sales_queue_branch_status_idx
          ON offline_sales_queue(origin_branch_id, status, occurred_at)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: retry-bookkeeping columns (handover doc G6).
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE offline_sales_queue ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE offline_sales_queue ADD COLUMN next_retry_at TEXT');
        }
        // v2 → v3: customer-friendly offline invoice reference column.
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE offline_sales_queue ADD COLUMN offline_invoice_no TEXT');
        }
        // v3 → v4: bind every queued sale to the business/user that
        // created it. Existing rows are recovered from the immutable branch
        // snapshot stored in their payload; unrecoverable rows are quarantined
        // for manual review and are never auto-assigned to the active branch.
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE offline_sales_queue ADD COLUMN origin_branch_id INTEGER');
          await db.execute(
              'ALTER TABLE offline_sales_queue ADD COLUMN origin_user_id INTEGER');
          await _backfillTenantOrigins(db);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS offline_sales_queue_branch_status_idx
            ON offline_sales_queue(origin_branch_id, status, occurred_at)
          ''');
        }
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
    required int originBranchId,
    int? originUserId,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
    String? offlineInvoiceNo,
    String? initialError,
  }) async {
    if (originBranchId <= 0) {
      throw ArgumentError.value(
          originBranchId, 'originBranchId', 'A valid branch is required for an offline sale.');
    }
    final db = await _database;
    final tenantPayload = Map<String, dynamic>.from(payload)
      ..['origin_branch_id'] = originBranchId;
    await db.insert(
      'offline_sales_queue',
      {
        'client_ref':        clientRef,
        'origin_branch_id':  originBranchId,
        'origin_user_id':    originUserId,
        'payload':           jsonEncode(tenantPayload),
        'occurred_at':       occurredAt.toIso8601String(),
        'status':            OfflineSaleStatus.pending.name,
        'offline_invoice_no': offlineInvoiceNo,
        'last_error':        initialError,
        'created_at':        DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Queue order = oldest occurred_at first, so same-day invoice numbering
  /// stays roughly chronological once synced (§1.3, §2.4).
  ///
  /// Includes only `pending` items (not `failed`). Used by
  /// [OfflineSyncService.syncAll] so that dead-lettered items never re-enter
  /// automatic retry — they require explicit manual review and correction via
  /// [updatePayloadAndReset] before they can sync again.
  Future<List<OfflineSaleQueueItem>> pending({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'status = ? AND origin_branch_id = ?',
      whereArgs: [OfflineSaleStatus.pending.name, branchId],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(OfflineSaleQueueItem.fromMap).toList();
  }

  /// Includes both `pending` and `failed` items. Used only by the Offline
  /// Sync screen UI so managers can see dead-lettered items alongside pending
  /// ones. The sync engine uses [pending] instead.
  Future<List<OfflineSaleQueueItem>> pendingOrFailed({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'status IN (?, ?) AND origin_branch_id = ?',
      whereArgs: [OfflineSaleStatus.pending.name, OfflineSaleStatus.failed.name, branchId],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(OfflineSaleQueueItem.fromMap).toList();
  }

  Future<List<OfflineSaleQueueItem>> all({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'origin_branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(OfflineSaleQueueItem.fromMap).toList();
  }

  Future<int> pendingCount({required int branchId}) async {
    final db = await _database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_sales_queue WHERE status IN ('pending', 'failed') AND origin_branch_id = ?",
      [branchId],
    );
    final value = result.isEmpty ? null : result.first['c'];
    return (value is int) ? value : (int.tryParse(value?.toString() ?? '') ?? 0);
  }

  Future<void> markSyncing(String clientRef) async {
    await _updateStatus(clientRef, OfflineSaleStatus.syncing);
  }

  Future<void> markSynced(
    String clientRef, {
    required String serverInvoiceNo,
    String? offlineInvoiceNo,
  }) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {
        'status':            OfflineSaleStatus.synced.name,
        'server_invoice_no': serverInvoiceNo,
        // Persist the offline reference returned by the server (same as what
        // was sent, or corrected if there was a conflict).
        if (offlineInvoiceNo != null) 'offline_invoice_no': offlineInvoiceNo,
        'last_error': null,
      },
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

  /// Schedules a backoff retry for a *retryable* failure (transient 5xx/429,
  /// or a network blip) — handover doc G3/G6. Keeps the item `pending`,
  /// records the new attempt count and the earliest time an automatic sync
  /// should try it again. A manual per-row Retry ignores next_retry_at.
  Future<void> scheduleRetry(
    String clientRef, {
    required int attempts,
    required DateTime nextRetryAt,
    String? lastError,
  }) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {
        'status': OfflineSaleStatus.pending.name,
        'attempts': attempts,
        'next_retry_at': nextRetryAt.toIso8601String(),
        'last_error': lastError,
      },
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  /// Records one more attempt against an item (used when moving it to the
  /// terminal `failed` state so the dead-letter row can show how many tries
  /// it took before giving up).
  Future<void> bumpAttempts(String clientRef, int attempts) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {'attempts': attempts},
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  Future<void> markFailed(String clientRef, {required String lastError}) async {
    final db = await _database;
    await db.update(
      'offline_sales_queue',
      {
        'status': OfflineSaleStatus.failed.name,
        'last_error': lastError,
        // Dead-lettered: no automatic retry window any more (handover doc G6).
        'next_retry_at': null,
      },
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  /// Replaces the stored payload for a dead-lettered (failed) item and
  /// resets it to [pending] so the sync engine picks it up on the next run.
  ///
  /// Use this when a manager has corrected a business-validation error in
  /// the queued sale (e.g. swapped an invalid salesman for a valid one).
  /// Resetting [attempts] to 0 gives the corrected sale a fresh backoff slate.
  Future<void> updatePayloadAndReset(
    String clientRef,
    Map<String, dynamic> newPayload,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      columns: ['origin_branch_id'],
      where: 'client_ref = ?',
      whereArgs: [clientRef],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final originBranchId = _readPositiveInt(rows.first['origin_branch_id']);
    if (originBranchId == null) {
      await markFailed(
        clientRef,
        lastError: 'Legacy queue item has no recoverable business context. Manual data recovery is required.',
      );
      return;
    }
    final tenantPayload = Map<String, dynamic>.from(newPayload)
      ..['origin_branch_id'] = originBranchId;
    await db.update(
      'offline_sales_queue',
      {
        'payload': jsonEncode(tenantPayload),
        'status': OfflineSaleStatus.pending.name,
        'attempts': 0,
        'next_retry_at': null,
        'last_error': null,
      },
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  /// Replaces the offline_invoice_no in both the payload JSON and the
  /// dedicated column for a dead-lettered OFFLINE_INVOICE_NO_COLLISION item,
  /// then resets it to [pending].
  ///
  /// The [clientRef] is preserved — a new receipt reference is assigned but
  /// the idempotency key stays the same, so the backend correctly treats a
  /// second sync attempt as a fresh (non-duplicate) create.
  Future<void> reassignOfflineRef(
    String clientRef,
    String newOfflineInvoiceNo,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'client_ref = ?',
      whereArgs: [clientRef],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final current = rows.first;
    final originBranchId = _readPositiveInt(current['origin_branch_id']);
    if (originBranchId == null) {
      await markFailed(
        clientRef,
        lastError: 'Legacy queue item has no recoverable business context. Manual data recovery is required.',
      );
      return;
    }
    final payload = jsonDecode(current['payload'] as String) as Map<String, dynamic>;
    final updatedPayload = Map<String, dynamic>.from(payload)
      ..['origin_branch_id'] = originBranchId
      ..['offline_invoice_no'] = newOfflineInvoiceNo;

    await db.update(
      'offline_sales_queue',
      {
        'payload':             jsonEncode(updatedPayload),
        'offline_invoice_no':  newOfflineInvoiceNo,
        'status':              OfflineSaleStatus.pending.name,
        'attempts':            0,
        'next_retry_at':       null,
        'last_error':          null,
      },
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );
  }

  static Future<void> _backfillTenantOrigins(Database db) async {
    final rows = await db.query(
      'offline_sales_queue',
      columns: ['id', 'payload', 'origin_branch_id', 'origin_user_id', 'status', 'last_error'],
    );
    for (final row in rows) {
      final existingBranch = _readPositiveInt(row['origin_branch_id']);
      if (existingBranch != null) continue;

      Map<String, dynamic>? payload;
      try {
        payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      } catch (_) {
        payload = null;
      }
      final recoveredBranch = payload == null ? null : _originBranchFromPayload(payload);
      final recoveredUser = payload == null ? null : _readPositiveInt(payload['origin_user_id']);

      if (recoveredBranch == null) {
        const message =
            'Legacy queue item has no recoverable business context. Manual data recovery is required; automatic sync is blocked.';
        await db.update(
          'offline_sales_queue',
          {
            'status': OfflineSaleStatus.failed.name,
            'last_error': message,
            'next_retry_at': null,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        continue;
      }

      final tenantPayload = Map<String, dynamic>.from(payload!)
        ..['origin_branch_id'] = recoveredBranch;
      await db.update(
        'offline_sales_queue',
        {
          'origin_branch_id': recoveredBranch,
          'origin_user_id': recoveredUser,
          'payload': jsonEncode(tenantPayload),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  static int? _originBranchFromPayload(Map<String, dynamic> payload) {
    final direct = _readPositiveInt(payload['origin_branch_id']);
    if (direct != null) return direct;
    final meta = payload['meta'];
    if (meta is! Map) return null;
    final branchSnapshot = meta['branch_snapshot'];
    if (branchSnapshot is! Map) return null;
    return _readPositiveInt(branchSnapshot['id']);
  }

  /// Permanently removes a queue item by [clientRef].
  ///
  /// Use this ONLY after a successful server confirmation (replay succeeded)
  /// or an explicit manager discard decision. Never call this on a pending
  /// item — the sale would be lost without being recorded on the server.
  Future<void> purge(String clientRef) async {
    final db = await _database;
    await db.delete(
      'offline_sales_queue',
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
