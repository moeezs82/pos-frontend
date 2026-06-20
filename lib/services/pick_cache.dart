/// A small generic "stale-while-revalidate" cache used by every party/product
/// picker (customers, vendors, salesmen, delivery boys, products).
///
/// Design goals (why this file exists):
///  - Opening a picker should NEVER show a blank spinner if we have any
///    data at all — even slightly-stale data beats a blocking loader for a
///    fast counter-sale flow.
///  - Every open still triggers a silent background refresh (per product
///    decision: always re-check, never trust the cache blindly) — but the
///    refresh never blocks the UI; it just patches the list in place when it
///    lands.
///  - Rapid typing must not fire N overlapping network requests. In-flight
///    requests for the same key are de-duped/cancelled-in-favor-of-latest.
///  - This is intentionally a plain singleton in-memory cache (per app run).
///    No persistence, no external package — it just needs to survive across
///    repeated picker opens within the same session.
library;

class PickCacheEntry<T> {
  List<T> items;
  DateTime fetchedAt;
  int currentPage;
  int lastPage;

  PickCacheEntry({
    required this.items,
    required this.fetchedAt,
    this.currentPage = 1,
    this.lastPage = 1,
  });
}

/// One cache "bucket" per entity scope (e.g. all customers, vendors for a
/// given branch+role, products for a given vendor). Keyed internally by a
/// string key so that e.g. salesman list and delivery-boy list (both backed
/// by UserPickerSheet) don't collide.
///
/// IMPORTANT — two different kinds of keys are used here, intentionally:
///   - `bucketKey`: identifies *what this list represents* (all customers,
///     vendors for branch X, products for vendor Y). This is what `peek()`
///     reads and what every "show cached data instantly" call site uses.
///     It does NOT include the current search text or page — the bucket
///     always holds the latest known page for that scope.
///   - `requestKey` (passed to `refresh`): identifies *this specific
///     network request* (bucket + search text + page), used purely to
///     de-dupe concurrent in-flight calls so rapid typing doesn't fire N
///     overlapping requests for the same query. Results are still written
///     back to the bucket, not the request key — otherwise a search
///     request's results would be invisible to `peek()`, which always
///     looks under the bare bucket key.
class PickCache<T> {
  final Map<String, PickCacheEntry<T>> _buckets = {};

  /// Requests currently in-flight, keyed by requestKey, so concurrent
  /// callers (e.g. picker opened twice quickly, or prefetch + open racing)
  /// share one network call instead of firing two.
  final Map<String, Future<PickCacheEntry<T>>> _inFlight = {};

  /// Returns cached data immediately for [bucketKey] (or null if nothing
  /// cached yet for that scope).
  PickCacheEntry<T>? peek(String bucketKey) => _buckets[bucketKey];

  /// Fetches fresh data using [fetcher], storing the result under
  /// [bucketKey] (so `peek(bucketKey)` sees it), while de-duping concurrent
  /// requests that share the same [requestKey] (bucket + search + page).
  Future<PickCacheEntry<T>> refresh(
    String bucketKey,
    Future<PickCacheEntry<T>> Function() fetcher, {
    String? requestKey,
  }) {
    final dedupeKey = requestKey ?? bucketKey;
    final existing = _inFlight[dedupeKey];
    if (existing != null) return existing;

    final future = fetcher().then((entry) {
      _buckets[bucketKey] = entry;
      _inFlight.remove(dedupeKey);
      return entry;
    }, onError: (e) {
      _inFlight.remove(dedupeKey);
      throw e;
    });

    _inFlight[dedupeKey] = future;
    return future;
  }

  /// Inserts a single freshly-created/updated record at the front of every
  /// cached bucket that might display it (used after "Quick Add") so the new
  /// record shows up instantly everywhere without waiting on a refetch.
  ///
  /// Only safe for caches with a single bucket in practice (e.g. "all
  /// customers", "all vendors"). For caches split into multiple buckets by
  /// scope (UserPickCache's branch+role buckets, ProductPickCache's
  /// per-vendor buckets), use [insertInto] instead so a newly created
  /// record doesn't leak into an unrelated scope (e.g. a quick-added
  /// salesman incorrectly appearing in the delivery-boy list).
  void insertEverywhere(T item, {bool Function(T)? matchesExisting}) {
    for (final entry in _buckets.values) {
      if (matchesExisting != null) {
        entry.items.removeWhere(matchesExisting);
      }
      entry.items.insert(0, item);
    }
  }

  /// Inserts a single freshly-created/updated record into just the bucket
  /// identified by [bucketKey]. If that bucket doesn't exist yet, this is a
  /// no-op (nothing to prepend to — the next real fetch will pick it up).
  void insertInto(String bucketKey, T item, {bool Function(T)? matchesExisting}) {
    final entry = _buckets[bucketKey];
    if (entry == null) return;
    if (matchesExisting != null) {
      entry.items.removeWhere(matchesExisting);
    }
    entry.items.insert(0, item);
  }

  /// Directly stores a freshly-fetched entry for [key], bypassing the
  /// de-dup/in-flight machinery. Useful when the caller already fetched
  /// data through its own request (e.g. a request that also needs to
  /// branch on resetSelection-style side effects) and just wants to record
  /// the result for next time.
  void put(String key, PickCacheEntry<T> entry) {
    _buckets[key] = entry;
  }

  void clear() {
    _buckets.clear();
    _inFlight.clear();
  }
}
