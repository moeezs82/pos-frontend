import 'dart:convert';

import 'package:enterprise_pos/api/catalog_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:path/path.dart' as p;
// Windows-desktop app → sqflite via FFI, same as offline_sales_queue_service.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Outcome of a [CatalogCacheService.refresh] attempt. Refresh is always
/// best-effort — callers warm it opportunistically and must never be blocked
/// by it — so failures are reported, not thrown.
class CatalogRefreshResult {
  final bool ok;
  final bool wasFullSnapshot;
  final int productsUpserted;
  final int customersUpserted;
  final String? error;

  const CatalogRefreshResult({
    required this.ok,
    this.wasFullSnapshot = false,
    this.productsUpserted = 0,
    this.customersUpserted = 0,
    this.error,
  });
}

/// Local read-replica of the server catalog (handover doc G1 / Phase 1).
///
/// This is the INBOUND half of the offline design and the mirror image of
/// [OfflineSalesQueueService] (the OUTBOUND write-ahead log). It exists so a
/// cashier can search/select products, see the right price + tax, and pick a
/// customer with zero connectivity AND after an app restart — the gap the
/// in-memory-only pick_cache/party_prefetch left open.
///
/// It is strictly a read cache: catalog data is owned by the server and is
/// never edited on the device, which is what keeps the whole sync model
/// conflict-free. Pricing and tax are columns on the product row (this schema
/// has no per-branch price table), so they live here as columns too.
///
/// Everything is scoped by branch: rows carry a branch_id and the sync cursor
/// is stored per branch, so a master admin switching branches gets that
/// branch's catalog and its own delta cursor.
class CatalogCacheService {
  CatalogCacheService._();
  static final CatalogCacheService instance = CatalogCacheService._();

  Database? _db;

  /// Guards against overlapping refreshes for the same branch (e.g. login
  /// warm + connectivity-regain firing together). Keyed by branch.
  final Set<String> _refreshing = {};

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'catalog_cache.db');
    return openDatabase(
      path,
      version: 5,
      // v1 → v2 adds the unit columns. ADDITIVE ONLY, and deliberately not a
      // table rebuild or a cache wipe: this database is a read replica, but a
      // "just delete and re-download" upgrade would strand a till that is
      // offline at the moment it updates, with no catalog and pending sales
      // in the outbound queue it can no longer price or name.
      //
      // Rows that existed before the v2 upgrade get NULL in the new columns,
      // which parses as ProductUnit.defaultAllowDecimal (true) — the
      // pre-units behaviour — until the next refresh fills them in.
      //
      // v2 → v3 retires legacy global catalog rows. Branches are independent
      // businesses, so null-branch products/customers and their global cursors
      // must never remain available as an offline fallback after an upgrade.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN unit_id INTEGER');
          await db.execute('ALTER TABLE products ADD COLUMN unit_name TEXT');
          await db.execute(
              'ALTER TABLE products ADD COLUMN unit_allow_decimal INTEGER');
        }
        if (oldVersion < 3) {
          await db.delete('products', where: 'branch_id IS NULL');
          await db.delete('customers', where: 'branch_id IS NULL');
          await db.delete(
            'sync_meta',
            where: 'key IN (?, ?, ?)',
            whereArgs: const [
              'catalog_version:all',
              'last_synced_at:all',
              'payment_methods:all',
            ],
          );
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL');

          await db.execute(
              "ALTER TABLE customers ADD COLUMN credit_limit_mode TEXT NOT NULL DEFAULT 'block'");
          await db.execute(
              'ALTER TABLE customers ADD COLUMN trade_balance REAL NOT NULL DEFAULT 0');

          // Existing rows pre-date credit-control fields. Treating the ALTER
          // defaults as real balances would falsely authorize offline credit.
          // Purge only the customer read replica and invalidate catalog cursors
          // so the next online refresh is a full authoritative snapshot.
          await db.delete('customers');
          await db.delete(
            'sync_meta',
            where: 'key LIKE ? OR key LIKE ?',
            whereArgs: const ['catalog_version:%', 'last_synced_at:%'],
          );
        }
        // v4 → v5: product discount_type column.
        // NULL is safe here — the read helper defaults to 'percentage', so
        // existing cached rows behave exactly as before until next sync.
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE products ADD COLUMN discount_type TEXT');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER NOT NULL,
            branch_id INTEGER,
            sku TEXT,
            barcode TEXT,
            name TEXT,
            name_lower TEXT,
            price REAL,
            cost_price REAL,
            wholesale_price REAL,
            tax_rate REAL,
            tax_inclusive INTEGER,
            discount REAL,
            discount_type TEXT,
            vendor_id INTEGER,
            category_id INTEGER,
            unit_id INTEGER,
            unit_name TEXT,
            unit_allow_decimal INTEGER,
            is_active INTEGER DEFAULT 1,
            updated_at TEXT,
            PRIMARY KEY (id)
          )
        ''');
        await db.execute('CREATE INDEX idx_products_branch ON products(branch_id)');
        await db.execute('CREATE INDEX idx_products_name ON products(name_lower)');
        await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');

        await db.execute('''
          CREATE TABLE customers (
            id INTEGER NOT NULL,
            branch_id INTEGER,
            first_name TEXT,
            last_name TEXT,
            phone TEXT,
            email TEXT,
            address TEXT,
            status TEXT,
            credit_limit REAL,
            credit_limit_mode TEXT NOT NULL DEFAULT 'block',
            trade_balance REAL NOT NULL DEFAULT 0,
            search_blob TEXT,
            updated_at TEXT,
            PRIMARY KEY (id)
          )
        ''');
        await db.execute('CREATE INDEX idx_customers_branch ON customers(branch_id)');
        await db.execute('CREATE INDEX idx_customers_search ON customers(search_blob)');

        await db.execute('''
          CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  String _branchKey(int? branchId) => branchId?.toString() ?? 'all';
  String _versionKey(int? branchId) => 'catalog_version:${_branchKey(branchId)}';
  String _syncedAtKey(int? branchId) => 'last_synced_at:${_branchKey(branchId)}';

  /// Pulls the catalog for [branchId] into the local cache: a full snapshot
  /// when nothing is cached yet for that branch, otherwise a delta since the
  /// stored cursor (upserts + tombstone purges). Safe to call often and from
  /// multiple triggers; overlapping calls for the same branch are ignored.
  Future<CatalogRefreshResult> refresh({
    required String token,
    int? branchId,
  }) async {
    final key = _branchKey(branchId);
    if (_refreshing.contains(key)) {
      return const CatalogRefreshResult(ok: true); // already in progress
    }
    _refreshing.add(key);
    try {
      final service = CatalogService(token: token);
      final db = await _database;
      final since = await _getMeta(_versionKey(branchId));

      final Map<String, dynamic> data;
      final bool full;
      if (since == null || since.isEmpty) {
        data = await service.snapshot(branchId: branchId);
        full = true;
      } else {
        data = await service.changes(since: since, branchId: branchId);
        full = false;
      }

      final products = (data['products'] as List?) ?? const [];
      final customers = (data['customers'] as List?) ?? const [];
      final deletedProducts = (data['deleted_products'] as List?) ?? const [];
      final deletedCustomers = (data['deleted_customers'] as List?) ?? const [];
      final newVersion = (data['catalog_version'] ?? '').toString();

      await db.transaction((txn) async {
        // On a full snapshot, clear this branch's rows first so
        // deactivated/deleted products from a previous sync can't linger.
        if (full) {
          await txn.delete('products', where: 'branch_id IS ?', whereArgs: [branchId]);
          if (branchId != null) {
            await txn.delete(
              'customers',
              where: 'branch_id = ?',
              whereArgs: [branchId],
            );
          } else {
            await txn.delete('customers');
          }
        }

        for (final raw in products) {
          await txn.insert('products', _productRow(raw as Map, branchId),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final raw in customers) {
          await txn.insert('customers', _customerRow(raw as Map),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (final id in deletedProducts) {
          await txn.delete('products', where: 'id = ?', whereArgs: [_asInt(id)]);
        }
        for (final id in deletedCustomers) {
          await txn.delete('customers', where: 'id = ?', whereArgs: [_asInt(id)]);
        }
      });

      if (newVersion.isNotEmpty) {
        await _setMeta(_versionKey(branchId), newVersion);
      }
      await _setMeta(_syncedAtKey(branchId), DateTime.now().toIso8601String());

      // Persist active payment methods so an offline cashier can still pick a
      // tender. Only present on a full snapshot; deltas leave the cache as-is.
      final paymentMethods = data['payment_methods'] as List?;
      if (paymentMethods != null && paymentMethods.isNotEmpty) {
        await savePaymentMethods(
          branchId,
          paymentMethods
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }

      return CatalogRefreshResult(
        ok: true,
        wasFullSnapshot: full,
        productsUpserted: products.length,
        customersUpserted: customers.length,
      );
    } catch (e) {
      // Best-effort: the pickers just fall back to whatever is already cached
      // (or, if online, a live search). Never surfaces to the sale flow.
      return CatalogRefreshResult(ok: false, error: e.toString());
    } finally {
      _refreshing.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Local reads (used by pickers — pure offline, no network)
  // ---------------------------------------------------------------------------

  /// Products matching [query] (name / sku / barcode), active only, scoped to
  /// [branchId] and optionally [vendorId] (products with a null vendor are
  /// always eligible, matching ProductController's vendor filter). Returns
  /// maps shaped like the product picker expects (id, name, sku, barcode,
  /// price, cost_price, wholesale_price, tax_rate).
  Future<List<Map<String, dynamic>>> searchProducts(
    String query, {
    int? branchId,
    int? vendorId,
    int limit = 50,
  }) async {
    final db = await _database;
    final q = query.trim().toLowerCase();

    final where = <String>['is_active = 1'];
    final args = <Object?>[];
    if (branchId != null) {
      where.add('branch_id = ?');
      args.add(branchId);
    }
    if (vendorId != null) {
      where.add('(vendor_id = ? OR vendor_id IS NULL)');
      args.add(vendorId);
    }
    if (q.isNotEmpty) {
      where.add('(name_lower LIKE ? OR sku LIKE ? OR barcode LIKE ?)');
      args..add('%$q%')..add('%$q%')..add('%$q%');
    }

    final rows = await db.query(
      'products',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(_productToApiShape).toList();
  }

  /// Exact-barcode lookup for the scanner path.
  Future<Map<String, dynamic>?> productByBarcode(
    String barcode, {
    int? branchId,
    int? vendorId,
  }) async {
    final db = await _database;
    final where = <String>['barcode = ?', 'is_active = 1'];
    final args = <Object?>[barcode.trim()];
    if (branchId != null) {
      where.add('branch_id = ?');
      args.add(branchId);
    }
    if (vendorId != null) {
      where.add('(vendor_id = ? OR vendor_id IS NULL)');
      args.add(vendorId);
    }
    final rows = await db.query('products',
        where: where.join(' AND '), whereArgs: args, limit: 1);
    if (rows.isEmpty) return null;
    return _productToApiShape(rows.first);
  }

  /// The cached selling price for a product, or null if not cached.
  Future<double?> priceFor(int productId) async {
    final db = await _database;
    final rows = await db.query('products',
        columns: ['price'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first['price'];
    return (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  }

  /// The cached tax rate (%) for a product, or null if not cached.
  Future<double?> taxFor(int productId) async {
    final db = await _database;
    final rows = await db.query('products',
        columns: ['tax_rate'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first['tax_rate'];
    return (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  }

  /// Customers matching [query] (name / phone / email), scoped exactly to
  /// [branchId]. Null-branch legacy rows are purged by the v3 cache migration
  /// and are never treated as shared business data.
  Future<List<Map<String, dynamic>>> searchCustomers(
    String query, {
    int? branchId,
    int limit = 50,
  }) async {
    final db = await _database;
    final q = query.trim().toLowerCase();

    final where = <String>[];
    final args = <Object?>[];
    if (branchId != null) {
      where.add('branch_id = ?');
      args.add(branchId);
    }
    if (q.isNotEmpty) {
      where.add('search_blob LIKE ?');
      args.add('%$q%');
    }

    final rows = await db.query(
      'customers',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'first_name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(_customerToApiShape).toList();
  }

  /// When the cache for [branchId] was last successfully refreshed — drives
  /// the "Catalog last updated …" freshness stamp in the UI.
  Future<DateTime?> lastSyncedAt({int? branchId}) async {
    final raw = await _getMeta(_syncedAtKey(branchId));
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// True when there is at least one cached product for [branchId] — lets a
  /// picker decide whether the local cache is worth reading before it falls
  /// through to a live search.
  Future<bool> hasProducts({int? branchId}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT 1 FROM products ${branchId != null ? 'WHERE branch_id = ?' : ''} LIMIT 1',
      branchId != null ? [branchId] : null,
    );
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Row mapping
  // ---------------------------------------------------------------------------

  Map<String, Object?> _productRow(Map raw, int? branchId) {
    final name = (raw['name'] ?? '').toString();
    // /catalog emits the unit as a nested object (or null); QuantityRule
    // flattens both that and an already-flat row into the three columns.
    final rule = QuantityRule.fromProduct(Map<String, dynamic>.from(raw));
    return {
      'id': _asInt(raw['id']),
      'branch_id': raw['branch_id'] != null ? _asInt(raw['branch_id']) : branchId,
      'sku': raw['sku']?.toString(),
      'barcode': raw['barcode']?.toString(),
      'name': name,
      'name_lower': name.toLowerCase(),
      'price': _asDouble(raw['price']),
      'cost_price': _asDouble(raw['cost_price']),
      'wholesale_price': _asDouble(raw['wholesale_price']),
      'tax_rate': _asDouble(raw['tax_rate']),
      'tax_inclusive': _asBoolInt(raw['tax_inclusive']),
      'discount': _asDouble(raw['discount']),
      'discount_type': raw['discount_type']?.toString() ?? 'percentage',
      'vendor_id': raw['vendor_id'] != null ? _asInt(raw['vendor_id']) : null,
      'category_id': raw['category_id'] != null ? _asInt(raw['category_id']) : null,
      'unit_id': rule.unitId,
      'unit_name': rule.unitName.isEmpty ? null : rule.unitName,
      'unit_allow_decimal': rule.allowDecimal ? 1 : 0,
      'is_active': _asBoolInt(raw['is_active'], defaultTrue: true),
      'updated_at': raw['updated_at']?.toString(),
    };
  }

  Map<String, Object?> _customerRow(Map raw) {
    final parts = [
      raw['first_name'],
      raw['last_name'],
      raw['phone'],
      raw['email'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' ');
    return {
      'id': _asInt(raw['id']),
      'branch_id': raw['branch_id'] != null ? _asInt(raw['branch_id']) : null,
      'first_name': raw['first_name']?.toString(),
      'last_name': raw['last_name']?.toString(),
      'phone': raw['phone']?.toString(),
      'email': raw['email']?.toString(),
      'address': raw['address']?.toString(),
      'status': raw['status']?.toString(),
      'credit_limit': raw['credit_limit'] == null ? null : _asDouble(raw['credit_limit']),
      'credit_limit_mode': (raw['credit_limit_mode'] ?? 'block').toString(),
      'trade_balance': _asDouble(raw['trade_balance']),
      'search_blob': parts.toLowerCase(),
      'updated_at': raw['updated_at']?.toString(),
    };
  }

  /// Cache row → the map shape the product pickers already consume.
  Map<String, dynamic> _productToApiShape(Map<String, Object?> row) {
    return {
      'id': row['id'],
      'name': row['name'],
      'sku': row['sku'],
      'barcode': row['barcode'],
      'price': row['price'],
      'cost_price': row['cost_price'],
      'wholesale_price': row['wholesale_price'],
      'tax_rate': row['tax_rate'],
      'tax_inclusive': (row['tax_inclusive'] == 1),
      'discount': row['discount'],
      'discount_type': row['discount_type'] ?? 'percentage',
      'vendor_id': row['vendor_id'],
      'category_id': row['category_id'],
      // Flat unit columns, read by QuantityRule.fromProduct. A row cached
      // before v2 has NULL here, which parses as decimal-allowed rather than
      // blocking quantities the cashier entered fine yesterday.
      'unit_id': row['unit_id'],
      'unit_name': row['unit_name'],
      'unit_allow_decimal': row['unit_allow_decimal'],
      '_offline': true, // marker: sourced from local cache, not a live fetch
    };
  }

  Map<String, dynamic> _customerToApiShape(Map<String, Object?> row) {
    return {
      'id': row['id'],
      'first_name': row['first_name'],
      'last_name': row['last_name'],
      'name': [row['first_name'], row['last_name']]
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .join(' ')
          .trim(),
      'phone': row['phone'],
      'email': row['email'],
      'address': row['address'],
      'status': row['status'],
      'credit_limit': row['credit_limit'],
      'credit_limit_mode': row['credit_limit_mode'],
      'trade_balance': row['trade_balance'],
      '_offline': true,
    };
  }

  // ---------------------------------------------------------------------------
  // sync_meta helpers + coercion
  // ---------------------------------------------------------------------------

  Future<String?> _getMeta(String key) async {
    final db = await _database;
    final rows = await db.query('sync_meta',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) async {
    final db = await _database;
    await db.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // Payment methods (offline sale creation)
  //
  // Stored as a small JSON blob in sync_meta keyed by branch, so no schema
  // migration/version bump is needed. Best-effort: callers must tolerate an
  // empty list.
  // ---------------------------------------------------------------------------

  String _paymentMethodsKey(int? branchId) => 'payment_methods:${_branchKey(branchId)}';

  Future<void> savePaymentMethods(int? branchId, List<Map<String, dynamic>> methods) async {
    await _setMeta(_paymentMethodsKey(branchId), jsonEncode(methods));
  }

  Future<List<Map<String, dynamic>>> loadPaymentMethods(int? branchId) async {
    final raw = await _getMeta(_paymentMethodsKey(branchId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {/* corrupt cache — ignore */}
    return const [];
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static int _asBoolInt(dynamic v, {bool defaultTrue = false}) {
    if (v == null) return defaultTrue ? 1 : 0;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v != 0 ? 1 : 0;
    final s = v.toString().toLowerCase();
    return (s == '1' || s == 'true') ? 1 : 0;
  }
}
