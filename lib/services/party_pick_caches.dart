import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/pick_cache.dart';

/// Each cache below is a process-wide singleton (simple static instance —
/// no DI needed for this). They live for the app session: opened once,
/// reused by every picker sheet, prefetch call, and screen that needs the
/// same list of customers/vendors/salesmen/products.

typedef PartyMap = Map<String, dynamic>;

/// ---------------- Customers ----------------
class CustomerPickCache {
  CustomerPickCache._();
  static final PickCache<PartyMap> cache = PickCache<PartyMap>();

  /// One bucket is enough for customers today (no branch/role split), but we
  /// keep a key fn for symmetry/future-proofing.
  static String keyFor() => 'all';

  static Future<PickCacheEntry<PartyMap>> fetchPage(
    CustomerService service, {
    required int page,
    String search = '',
    int? perPage,
  }) async {
    final data = await service.getCustomers(
      page: page,
      perPage: perPage,
      search: search,
      includeBalance: true,
    );
    final wrapper = data['data'] as Map<String, dynamic>;
    final items = (wrapper['customers'] as List).cast<PartyMap>();
    final lastPage = (wrapper['last_page'] ?? 1) as int;
    final currentPage = (wrapper['current_page'] ?? page) as int;
    return PickCacheEntry<PartyMap>(
      items: items,
      fetchedAt: DateTime.now(),
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  /// Hits the backend's full-database search directly for [query] — used
  /// by the autocomplete field once the user is actually typing, since a
  /// 10-100 row local cache can never represent a 10,000-row customer list.
  /// Does NOT touch the shared cache bucket; this is a one-off lookup.
  ///
  /// Offline fallback (handover doc G1): if the live search can't reach the
  /// server, fall back to the local catalog cache so a cashier can still find
  /// a previously-synced customer with no connectivity. Online, the server's
  /// answer is authoritative and the cache is not consulted.
  static Future<List<PartyMap>> searchRemote(
    CustomerService service,
    String query, {
    int perPage = 25,
    int? branchId,
  }) async {
    try {
      final entry = await fetchPage(service, page: 1, search: query, perPage: perPage);
      return entry.items;
    } catch (_) {
      return CatalogCacheService.instance
          .searchCustomers(query, branchId: branchId, limit: perPage);
    }
  }

  /// Seeds the in-memory bucket from the local catalog cache when it's empty,
  /// so the "instant list" (shown before the user types) works offline and
  /// after an app restart — not just within a single online session.
  static Future<void> hydrateFromCatalog({int? branchId}) async {
    if (cache.peek(keyFor()) != null) return; // already warm this session
    final items = await CatalogCacheService.instance
        .searchCustomers('', branchId: branchId, limit: 200);
    if (items.isEmpty || cache.peek(keyFor()) != null) return;
    cache.put(keyFor(), PickCacheEntry<PartyMap>(items: items, fetchedAt: DateTime.now()));
  }
}

/// ---------------- Vendors ----------------
class VendorPickCache {
  VendorPickCache._();
  static final PickCache<PartyMap> cache = PickCache<PartyMap>();

  static String keyFor() => 'all';

  static Future<PickCacheEntry<PartyMap>> fetchPage(
    VendorService service, {
    required int page,
    String search = '',
    int? perPage,
  }) async {
    final data = await service.getVendors(
      page: page,
      perPage: perPage,
      search: search,
      includeBalance: true,
    );
    final wrapper = data['data'] as Map<String, dynamic>;
    final items = (wrapper['vendors'] as List).cast<PartyMap>();
    final lastPage = (wrapper['last_page'] ?? 1) as int;
    final currentPage = (wrapper['current_page'] ?? page) as int;
    return PickCacheEntry<PartyMap>(
      items: items,
      fetchedAt: DateTime.now(),
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  /// Hits the backend's full-database search directly for [query] — see
  /// CustomerPickCache.searchRemote for why this bypasses the cache bucket.
  static Future<List<PartyMap>> searchRemote(
    VendorService service,
    String query, {
    int perPage = 25,
  }) async {
    final entry = await fetchPage(service, page: 1, search: query, perPage: perPage);
    return entry.items;
  }
}

/// ---------------- Users (salesmen / delivery boys / generic) ----------------
/// Bucketed by branchId+role since the same sheet/service backs salesman
/// pickers, delivery-boy pickers, and any other role-filtered user list.
class UserPickCache {
  UserPickCache._();
  static final PickCache<PartyMap> cache = PickCache<PartyMap>();

  static String keyFor({String? branchId, String? role}) =>
      '${branchId ?? ''}::${role ?? ''}';

  static Future<PickCacheEntry<PartyMap>> fetchPage(
    UsersService service, {
    required int page,
    String search = '',
    String? branchId,
    String? role,
    int perPage = 20,
  }) async {
    final res = await service.getUsers(
      page: page,
      perPage: perPage,
      search: search,
      branchId: branchId,
      role: role,
      includeDeliveryBalance: role == 'delivery',
      excludeMasterAdmin: true,
    );
    final pageData = res['data'] as Map<String, dynamic>;
    final items = (pageData['data'] as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((u) => !isMasterAdminUser(u))
        .toList();
    final lastPage = (pageData['last_page'] ?? 1) as int;
    final currentPage = (pageData['current_page'] ?? page) as int;
    return PickCacheEntry<PartyMap>(
      items: items,
      fetchedAt: DateTime.now(),
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  /// Hits the backend's full-database user search directly for [query] —
  /// see CustomerPickCache.searchRemote for why this bypasses the bucket.
  static Future<List<PartyMap>> searchRemote(
    UsersService service,
    String query, {
    String? branchId,
    String? role,
    int perPage = 25,
  }) async {
    final entry = await fetchPage(
      service,
      page: 1,
      search: query,
      branchId: branchId,
      role: role,
      perPage: perPage,
    );
    return entry.items;
  }

  static bool isMasterAdminUser(PartyMap user) {
    if (_readBool(user['is_master_admin'])) return true;
    final roles = ((user['roles'] as List?) ?? [])
        .map((e) {
          if (e is String) return e;
          if (e is Map) {
            return (e['display_name'] ?? e['label'] ?? e['name'] ?? '')
                .toString();
          }
          return '';
        })
        .map(_stripBranchSuffix)
        .toList();
    return roles.any(_isMasterRoleName);
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static bool _isMasterRoleName(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized == 'master admin' || normalized == 'super admin';
  }

  static String _stripBranchSuffix(String value) {
    return value
        .replaceFirst(
          RegExp(r'\s-\s.*\s\[branch:\d+\]$', caseSensitive: false),
          '',
        )
        .trim();
  }
}

/// ---------------- Products ----------------
class ProductPickCache {
  ProductPickCache._();
  static final PickCache<PartyMap> cache = PickCache<PartyMap>();

  static String keyFor({int? vendorId}) => '${vendorId ?? 'all'}';

  static Future<PickCacheEntry<PartyMap>> fetchPage(
    ProductService service, {
    required int page,
    String search = '',
    int? vendorId,
    int perPage = 100,
  }) async {
    final data = await service.getProducts(
      page: page,
      search: search,
      vendorId: vendorId,
      per_page: perPage,
    );

    // Response shape is intentionally tolerant here — mirrors the parsing
    // that used to live inline in ProductPickerGridSheet._fetchProducts,
    // since the backend has been observed to wrap products under
    // data.products.data, data.data, or just data as a bare list.
    List<PartyMap> items = const [];
    int lastPage = 1;
    int currentPage = page;

    dynamic root = data['data'] ?? data;
    if (root is List && root.isNotEmpty) root = root.first;

    dynamic productsNode =
        (root is Map) ? (root['products'] ?? root['data'] ?? root) : root;

    if (productsNode is Map) {
      final listNode = productsNode['data'];
      if (listNode is List) items = listNode.cast<PartyMap>();
      lastPage = _asInt(productsNode['last_page'] ?? (root is Map ? root['last_page'] : null)) ?? 1;
      currentPage = _asInt(productsNode['current_page'] ?? (root is Map ? root['current_page'] : null)) ?? page;
    } else if (productsNode is List) {
      items = productsNode.cast<PartyMap>();
      lastPage = _asInt(root is Map ? root['last_page'] : 1) ?? 1;
      currentPage = _asInt(root is Map ? root['current_page'] : page) ?? page;
    }

    return PickCacheEntry<PartyMap>(
      items: items,
      fetchedAt: DateTime.now(),
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Hits the backend's full-database product search directly for [query]
  /// — see CustomerPickCache.searchRemote for why this bypasses the bucket.
  ///
  /// Offline fallback (handover doc G1): if the live search can't reach the
  /// server, fall back to the local catalog cache so a cashier can still find
  /// and price a product with no connectivity. This is the change that makes
  /// composing a sale offline actually possible — the queue could always
  /// accept a sale, but without this the cashier couldn't build one.
  static Future<List<PartyMap>> searchRemote(
    ProductService service,
    String query, {
    int? vendorId,
    int perPage = 25,
    int? branchId,
  }) async {
    try {
      final entry = await fetchPage(
        service,
        page: 1,
        search: query,
        vendorId: vendorId,
        perPage: perPage,
      );
      return entry.items;
    } catch (_) {
      return CatalogCacheService.instance
          .searchProducts(query, branchId: branchId, vendorId: vendorId, limit: perPage);
    }
  }

  /// Seeds (or re-seeds) the in-memory bucket for [vendorId] from the local
  /// SQLite catalog so the instant-filter in [SaleProductPanel._onSearchChanged]
  /// works across the full local catalog rather than just the server warm page.
  ///
  /// Unlike the old implementation, this intentionally does NOT early-return
  /// when the bucket already exists.  [PartyPrefetch.warmProducts] populates
  /// the bucket with server page 1 (≤200 rows); that is not the full catalog.
  /// This method is called both immediately in initState (before the server
  /// warm completes) and again after [CatalogCacheService.refresh] finishes, so
  /// the bucket always ends up holding the freshest, most-complete local data.
  ///
  /// The only early-return is when SQLite has no rows yet (first ever run).
  static Future<void> hydrateFromCatalog({int? vendorId, int? branchId}) async {
    final key = keyFor(vendorId: vendorId);
    final items = await CatalogCacheService.instance
        .searchProducts('', branchId: branchId, vendorId: vendorId, limit: 500);
    if (items.isEmpty) return; // first run — nothing cached in SQLite yet
    cache.put(key, PickCacheEntry<PartyMap>(items: items, fetchedAt: DateTime.now()));
  }
}

/// Clears every process-wide picker bucket when authentication or the active
/// business changes. The backend token can stay the same during a Master Admin
/// branch switch, so token-only cache lifetime is not a safe tenant boundary.
void clearAllPartyPickCaches() {
  CustomerPickCache.cache.clear();
  VendorPickCache.cache.clear();
  UserPickCache.cache.clear();
  ProductPickCache.cache.clear();
}
