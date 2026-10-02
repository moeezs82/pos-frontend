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
  final DateTime occurredAt;
  final OfflineSaleStatus status;
  final String? serverInvoiceNo;
  final String? offlineInvoiceNo;
  final String? lastError;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextRetryAt;

  /// Lightweight display fields persisted alongside the JSON payload so queue
  /// history can render without decoding every historical sale.
  final String displayCustomerName;
  final double displayTotal;
  final int itemCount;
  final int? customerId;
  final double tradeExposureDelta;

  final String? _payloadJson;
  Map<String, dynamic>? _decodedPayload;

  OfflineSaleQueueItem({
    required this.id,
    required this.clientRef,
    required this.originBranchId,
    required this.originUserId,
    required this.occurredAt,
    required this.status,
    this.serverInvoiceNo,
    this.offlineInvoiceNo,
    this.lastError,
    required this.createdAt,
    this.attempts = 0,
    this.nextRetryAt,
    this.displayCustomerName = 'Walk-in customer',
    this.displayTotal = 0,
    this.itemCount = 0,
    this.customerId,
    this.tradeExposureDelta = 0,
    String? payloadJson,
  }) : _payloadJson = payloadJson;

  bool get hasPayload => _payloadJson != null;

  /// Decode only when synchronization/detail/recovery actually needs the full
  /// sale. Summary/history rows never touch this getter.
  Map<String, dynamic> get payload {
    final cached = _decodedPayload;
    if (cached != null) return cached;
    final raw = _payloadJson;
    if (raw == null || raw.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _decodedPayload = decoded;
    return decoded;
  }

  bool get isDueForAutoRetry {
    final t = nextRetryAt;
    return t == null || !t.isAfter(DateTime.now());
  }

  factory OfflineSaleQueueItem.fromMap(
    Map<String, dynamic> map, {
    bool includePayload = true,
  }) {
    final retryRaw = map['next_retry_at'] as String?;
    final customerName = (map['display_customer'] ?? '').toString().trim();
    return OfflineSaleQueueItem(
      id: map['id'] as int,
      clientRef: map['client_ref'] as String,
      originBranchId: _readPositiveInt(map['origin_branch_id']),
      originUserId: _readPositiveInt(map['origin_user_id']),
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      status: _statusFromString(map['status'] as String),
      serverInvoiceNo: map['server_invoice_no'] as String?,
      offlineInvoiceNo: map['offline_invoice_no'] as String?,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      attempts: (map['attempts'] as int?) ?? 0,
      nextRetryAt:
          (retryRaw == null || retryRaw.isEmpty) ? null : DateTime.tryParse(retryRaw),
      displayCustomerName:
          customerName.isEmpty ? 'Walk-in customer' : customerName,
      displayTotal: _finiteMapDouble(map['display_total']),
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      customerId: _readPositiveInt(map['customer_id']),
      tradeExposureDelta: _finiteMapDouble(map['trade_exposure_delta']),
      payloadJson: includePayload ? map['payload'] as String? : null,
    );
  }
}

double _finiteMapDouble(dynamic value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;
  return parsed.isFinite ? parsed : 0.0;
}

class _QueueSummary {
  final String displayCustomer;
  final double displayTotal;
  final int itemCount;
  final int? customerId;
  final double tradeExposureDelta;

  const _QueueSummary({
    required this.displayCustomer,
    required this.displayTotal,
    required this.itemCount,
    required this.customerId,
    required this.tradeExposureDelta,
  });
}

_QueueSummary _summaryFromPayload(Map<String, dynamic> payload) {
  final meta = payload['meta'] as Map?;
  final totals = meta?['totals_snapshot'] as Map?;
  final customer = meta?['customer_snapshot'] as Map?;
  final name = (customer?['name'] ?? '').toString().trim();
  final rawItems = payload['items'];
  final delta = _tradeDeltaFromPayload(payload);
  return _QueueSummary(
    displayCustomer: name.isEmpty ? 'Walk-in customer' : name,
    displayTotal: _finiteMapDouble(totals?['total'] ?? payload['total']),
    itemCount: rawItems is List ? rawItems.length : 0,
    customerId: _readPositiveInt(payload['customer_id']),
    // Preserve the previous conservative credit-control rule: only locally
    // queued balance increases consume offline credit before server posting.
    tradeExposureDelta: delta > 0.004 ? delta : 0.0,
  );
}

double _tradeDeltaFromPayload(Map<String, dynamic> payload) {
  final meta = payload['meta'] as Map?;
  final totals = meta?['totals_snapshot'] as Map?;
  final total = _finiteMapDouble(totals?['total'] ?? payload['total']);

  var receipts = 0.0;
  final rawPayments = payload['payments'];
  if (rawPayments is List) {
    for (final raw in rawPayments) {
      if (raw is Map) receipts += _finiteMapDouble(raw['amount']);
    }
  }

  var refund = 0.0;
  final rawRefund = payload['refund'];
  if (rawRefund is Map) refund = _finiteMapDouble(rawRefund['amount']);
  return total - receipts + refund;
}

class OfflineSalesQueueService {
  OfflineSalesQueueService._();
  static final OfflineSalesQueueService instance = OfflineSalesQueueService._();

  Database? _db;
  final Map<int, DateTime> _lastPrunedAt = {};

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  /// Flushes and closes the local queue database for the few milliseconds in
  /// which Backup & Restore copies/replaces its file. The next queue operation
  /// reopens it lazily.
  Future<void> closeForBackupRestore() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
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
      version: 5,
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
            next_retry_at TEXT,
            display_customer TEXT NOT NULL DEFAULT 'Walk-in customer',
            display_total REAL NOT NULL DEFAULT 0,
            item_count INTEGER NOT NULL DEFAULT 0,
            customer_id INTEGER,
            trade_exposure_delta REAL NOT NULL DEFAULT 0,
            synced_at TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX offline_sales_queue_branch_status_idx
          ON offline_sales_queue(origin_branch_id, status, occurred_at)
        ''');
        await db.execute('''
          CREATE INDEX offline_sales_queue_customer_exposure_idx
          ON offline_sales_queue(origin_branch_id, customer_id, status)
        ''');
        await db.execute('''
          CREATE INDEX offline_sales_queue_synced_at_idx
          ON offline_sales_queue(origin_branch_id, status, synced_at)
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
        //
        // NOTE: these ALTER TABLEs are guarded with try-catch because
        // onCreate was updated to include origin_branch_id/origin_user_id
        // before the version was bumped to 4. Users who did a fresh install
        // in that window already have the columns, so the ALTER would throw
        // "duplicate column name". The catch swallows only that case; the
        // backfill and index creation are safe to run regardless.
        if (oldVersion < 4) {
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN origin_branch_id INTEGER');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN origin_user_id INTEGER');
          } catch (_) {}
          await _backfillTenantOrigins(db);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS offline_sales_queue_branch_status_idx
            ON offline_sales_queue(origin_branch_id, status, occurred_at)
          ''');
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
                "ALTER TABLE offline_sales_queue ADD COLUMN display_customer TEXT NOT NULL DEFAULT 'Walk-in customer'");
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN display_total REAL NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN item_count INTEGER NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN customer_id INTEGER');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN trade_exposure_delta REAL NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute(
                'ALTER TABLE offline_sales_queue ADD COLUMN synced_at TEXT');
          } catch (_) {}
          await _backfillQueueSummaries(db);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS offline_sales_queue_customer_exposure_idx
            ON offline_sales_queue(origin_branch_id, customer_id, status)
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS offline_sales_queue_synced_at_idx
            ON offline_sales_queue(origin_branch_id, status, synced_at)
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
    final summary = _summaryFromPayload(tenantPayload);
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
        'display_customer':   summary.displayCustomer,
        'display_total':      summary.displayTotal,
        'item_count':         summary.itemCount,
        'customer_id':        summary.customerId,
        'trade_exposure_delta': summary.tradeExposureDelta,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<String>> pendingRefs({
    required int branchId,
    bool dueOnly = false,
  }) async {
    final db = await _database;
    final where = StringBuffer('status = ? AND origin_branch_id = ?');
    final args = <Object?>[OfflineSaleStatus.pending.name, branchId];
    if (dueOnly) {
      where.write(' AND (next_retry_at IS NULL OR next_retry_at <= ?)');
      args.add(DateTime.now().toIso8601String());
    }
    final rows = await db.query(
      'offline_sales_queue',
      columns: ['client_ref'],
      where: where.toString(),
      whereArgs: args,
      orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map((row) => row['client_ref'].toString()).toList();
  }

  /// Queue order = oldest occurred_at first, bounded by [limit]. Full JSON
  /// payloads are read only for the small batch currently being synchronized.
  Future<List<OfflineSaleQueueItem>> pendingBatch({
    required int branchId,
    int limit = 25,
    bool dueOnly = false,
  }) async {
    final db = await _database;
    final where = StringBuffer('status = ? AND origin_branch_id = ?');
    final args = <Object?>[OfflineSaleStatus.pending.name, branchId];
    if (dueOnly) {
      where.write(' AND (next_retry_at IS NULL OR next_retry_at <= ?)');
      args.add(DateTime.now().toIso8601String());
    }
    final rows = await db.query(
      'offline_sales_queue',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'occurred_at ASC, id ASC',
      limit: limit,
    );
    return rows.map((row) => OfflineSaleQueueItem.fromMap(row)).toList();
  }

  /// Backwards-compatible helper for callers that genuinely need every
  /// pending payload. New sync code should prefer [pendingBatch].
  Future<List<OfflineSaleQueueItem>> pending({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'status = ? AND origin_branch_id = ?',
      whereArgs: [OfflineSaleStatus.pending.name, branchId],
      orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map((row) => OfflineSaleQueueItem.fromMap(row)).toList();
  }

  Future<List<OfflineSaleQueueItem>> pendingOrFailed({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'status IN (?, ?) AND origin_branch_id = ?',
      whereArgs: [
        OfflineSaleStatus.pending.name,
        OfflineSaleStatus.failed.name,
        branchId,
      ],
      orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map((row) => OfflineSaleQueueItem.fromMap(row)).toList();
  }

  /// Lightweight history for the Offline Sync screen. The payload column is
  /// deliberately excluded, so opening the screen does not decode every sale
  /// ever queued on this device.
  Future<List<OfflineSaleQueueItem>> summaries({
    required int branchId,
    int syncedLimit = 500,
  }) async {
    await _maybePruneSyncedHistory(branchId);
    final db = await _database;
    const columns = <String>[
      'id',
      'client_ref',
      'origin_branch_id',
      'origin_user_id',
      'occurred_at',
      'status',
      'server_invoice_no',
      'offline_invoice_no',
      'last_error',
      'created_at',
      'attempts',
      'next_retry_at',
      'display_customer',
      'display_total',
      'item_count',
      'customer_id',
      'trade_exposure_delta',
    ];

    final unsynced = await db.query(
      'offline_sales_queue',
      columns: columns,
      where: 'origin_branch_id = ? AND status != ?',
      whereArgs: [branchId, OfflineSaleStatus.synced.name],
      orderBy: 'occurred_at DESC, id DESC',
    );
    final synced = await db.query(
      'offline_sales_queue',
      columns: columns,
      where: 'origin_branch_id = ? AND status = ?',
      whereArgs: [branchId, OfflineSaleStatus.synced.name],
      orderBy: 'occurred_at DESC, id DESC',
      limit: syncedLimit,
    );
    final rows = <Map<String, Object?>>[...unsynced, ...synced];
    return rows
        .map((row) => OfflineSaleQueueItem.fromMap(
              Map<String, dynamic>.from(row),
              includePayload: false,
            ))
        .toList();
  }

  /// Legacy full-history helper. Avoid using this for list UIs.
  Future<List<OfflineSaleQueueItem>> all({required int branchId}) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'origin_branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map((row) => OfflineSaleQueueItem.fromMap(row)).toList();
  }

  Future<OfflineSaleQueueItem?> loadByClientRef(String clientRef) async {
    final db = await _database;
    final rows = await db.query(
      'offline_sales_queue',
      where: 'client_ref = ?',
      whereArgs: [clientRef],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineSaleQueueItem.fromMap(rows.first);
  }

  /// Conservative customer trade exposure is now a tiny indexed SUM instead
  /// of decoding every unsynced sale payload for each credit check.
  Future<double> pendingCustomerExposure({
    required int branchId,
    required int customerId,
    String? excludingClientRef,
  }) async {
    final db = await _database;
    final where = StringBuffer(
      'origin_branch_id = ? AND customer_id = ? AND status != ?',
    );
    final args = <Object?>[
      branchId,
      customerId,
      OfflineSaleStatus.synced.name,
    ];
    if (excludingClientRef != null && excludingClientRef.isNotEmpty) {
      where.write(' AND client_ref != ?');
      args.add(excludingClientRef);
    }
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(trade_exposure_delta), 0) AS exposure '
      'FROM offline_sales_queue WHERE ${where.toString()}',
      args,
    );
    return rows.isEmpty ? 0.0 : _finiteMapDouble(rows.first['exposure']);
  }

  static double _customerTradeDelta(Map<String, dynamic> payload) =>
      _tradeDeltaFromPayload(payload);

  static double _finiteDouble(dynamic value) => _finiteMapDouble(value);

  Future<int> pendingCount({required int branchId}) async {
    final db = await _database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_sales_queue WHERE status IN ('pending', 'failed') AND origin_branch_id = ?",
      [branchId],
    );
    final value = result.isEmpty ? null : result.first['c'];
    return (value is int) ? value : (int.tryParse(value?.toString() ?? '') ?? 0);
  }

  Future<void> _maybePruneSyncedHistory(int branchId) async {
    final last = _lastPrunedAt[branchId];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    await pruneSyncedHistory(branchId: branchId);
    _lastPrunedAt[branchId] = DateTime.now();
  }

  /// Keep the queue database bounded without ever deleting work that still
  /// needs attention. Pending/failed rows are retained indefinitely; only
  /// confirmed synced history is pruned because the server is authoritative.
  Future<void> pruneSyncedHistory({
    required int branchId,
    int maxSyncedRows = 500,
    Duration maxAge = const Duration(days: 30),
  }) async {
    final db = await _database;
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();

    await db.delete(
      'offline_sales_queue',
      where:
          'origin_branch_id = ? AND status = ? AND COALESCE(synced_at, occurred_at) < ?',
      whereArgs: [branchId, OfflineSaleStatus.synced.name, cutoff],
    );

    await db.rawDelete(
      '''
      DELETE FROM offline_sales_queue
      WHERE origin_branch_id = ?
        AND status = ?
        AND id NOT IN (
          SELECT id
          FROM offline_sales_queue
          WHERE origin_branch_id = ? AND status = ?
          ORDER BY COALESCE(synced_at, occurred_at) DESC, id DESC
          LIMIT ?
        )
      ''',
      [
        branchId,
        OfflineSaleStatus.synced.name,
        branchId,
        OfflineSaleStatus.synced.name,
        maxSyncedRows,
      ],
    );
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
        'synced_at': DateTime.now().toIso8601String(),
      },
      where: 'client_ref = ?',
      whereArgs: [clientRef],
    );

    final branchRows = await db.query(
      'offline_sales_queue',
      columns: ['origin_branch_id'],
      where: 'client_ref = ?',
      whereArgs: [clientRef],
      limit: 1,
    );
    final branchId = branchRows.isEmpty
        ? null
        : _readPositiveInt(branchRows.first['origin_branch_id']);
    if (branchId != null) {
      await _maybePruneSyncedHistory(branchId);
    }
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
    final summary = _summaryFromPayload(tenantPayload);
    await db.update(
      'offline_sales_queue',
      {
        'payload': jsonEncode(tenantPayload),
        'status': OfflineSaleStatus.pending.name,
        'attempts': 0,
        'next_retry_at': null,
        'last_error': null,
        'synced_at': null,
        'display_customer': summary.displayCustomer,
        'display_total': summary.displayTotal,
        'item_count': summary.itemCount,
        'customer_id': summary.customerId,
        'trade_exposure_delta': summary.tradeExposureDelta,
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

  static Future<void> _backfillQueueSummaries(Database db) async {
    final rows = await db.query(
      'offline_sales_queue',
      columns: ['id', 'payload', 'status', 'occurred_at'],
    );
    const chunkSize = 200;
    for (var start = 0; start < rows.length; start += chunkSize) {
      final finish = (start + chunkSize < rows.length)
          ? start + chunkSize
          : rows.length;
      final batch = db.batch();
      for (var i = start; i < finish; i++) {
        final row = rows[i];
        try {
          final payload =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          final summary = _summaryFromPayload(payload);
          batch.update(
            'offline_sales_queue',
            {
              'display_customer': summary.displayCustomer,
              'display_total': summary.displayTotal,
              'item_count': summary.itemCount,
              'customer_id': summary.customerId,
              'trade_exposure_delta': summary.tradeExposureDelta,
              if ((row['status'] ?? '').toString() ==
                  OfflineSaleStatus.synced.name)
                'synced_at': row['occurred_at']?.toString(),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } catch (_) {}
      }
      await batch.commit(noResult: true);
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
