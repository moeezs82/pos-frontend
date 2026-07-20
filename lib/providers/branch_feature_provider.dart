import 'package:enterprise_pos/api/branch_feature_api_service.dart';
import 'package:flutter/foundation.dart';

/// Default effective features when no server record exists for a branch.
/// Matches the backend defaults (fail-open = everything enabled).
const _kDefaults = {'delivery_enabled': true, 'sale_vendor_enabled': true};

/// Branch-aware feature flag provider.
///
/// Single source of truth for runtime feature flags. Widgets and services
/// must read flags from here, never from a raw API call.
///
/// Lifecycle:
///   1. After login + branch resolution → call load(branchId, token).
///   2. After Master Admin switches branch → call load(newBranchId, token).
///   3. After Master Admin saves feature settings → call load(branchId, token).
///   4. On logout → call reset().
///
/// Offline / startup:
///   The last successfully fetched map for each branch is kept in [_cache]
///   (keyed by branch ID). If a load() call fails and the cache already has
///   an entry for that branch, the cached value is used so the UI doesn't
///   reset to defaults on a transient network hiccup. This matches the
///   spec's "use last verified cache for the same branch during offline startup".
class BranchFeatureProvider extends ChangeNotifier {
  /// branch_id → { 'delivery_enabled': bool, 'sale_vendor_enabled': bool }
  final Map<int, Map<String, bool>> _cache = {};

  /// Active branch ID whose flags are currently exposed.
  int? _activeBranchId;

  bool _loading = false;
  String? _error;

  // ── Public accessors ──────────────────────────────────────────────────

  bool get isLoading => _loading;
  String? get loadError => _error;

  /// Feature flags for the currently active branch (or defaults if unknown).
  Map<String, bool> get features {
    if (_activeBranchId == null) return Map.from(_kDefaults);
    return _cache[_activeBranchId!] ?? Map.from(_kDefaults);
  }

  bool get deliveryEnabled => features['delivery_enabled'] ?? true;
  bool get saleVendorEnabled => features['sale_vendor_enabled'] ?? true;

  // ── Load ─────────────────────────────────────────────────────────────

  /// Fetch effective features for [branchId] from the server.
  ///
  /// On success the result is cached and all listeners are notified.
  /// On failure the cached value (if any) is kept; defaults are used if
  /// no cached value exists.
  ///
  /// [forceRefresh] skips the in-memory cache and always hits the server.
  Future<void> load(int branchId, String token, {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _activeBranchId == branchId &&
        _cache.containsKey(branchId)) {
      // Already current — nothing to do.
      return;
    }

    _activeBranchId = branchId;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final svc = BranchFeatureApiService(token: token);
      final resp = await svc.getCurrent();
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final raw = data['features'] as Map<String, dynamic>? ?? {};
      _cache[branchId] = _parse(raw);
    } catch (e) {
      _error = e.toString();
      // Keep existing cache entry; callers get the last-known good value.
      if (!_cache.containsKey(branchId)) {
        _cache[branchId] = Map.from(_kDefaults);
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Admin write path ──────────────────────────────────────────────────

  /// Saves feature flags for [branchId] (Master Admin path) and refreshes
  /// the local cache. Returns the updated feature map.
  Future<Map<String, bool>> save(
    int branchId,
    Map<String, bool> values,
    String token,
  ) async {
    final svc = BranchFeatureApiService(token: token);
    final resp = await svc.updateBranchFeatures(branchId, values);
    final data = resp['data'] as Map<String, dynamic>? ?? {};
    final raw = data['features'] as Map<String, dynamic>? ?? {};
    final parsed = _parse(raw);
    _cache[branchId] = parsed;

    // If we just updated the active branch, notify immediately.
    if (_activeBranchId == branchId) {
      notifyListeners();
    }
    return parsed;
  }

  /// Load features for an arbitrary branch (Master Admin admin screen).
  /// Does NOT change _activeBranchId.
  Future<Map<String, bool>> loadForBranch(int branchId, String token) async {
    final svc = BranchFeatureApiService(token: token);
    final resp = await svc.getBranchFeatures(branchId);
    final data = resp['data'] as Map<String, dynamic>? ?? {};
    final raw = data['features'] as Map<String, dynamic>? ?? {};
    final parsed = _parse(raw);
    _cache[branchId] = parsed;
    if (_activeBranchId == branchId) notifyListeners();
    return parsed;
  }

  // ── Reset ─────────────────────────────────────────────────────────────

  void reset() {
    _activeBranchId = null;
    _cache.clear();
    _loading = false;
    _error = null;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static Map<String, bool> _parse(Map<String, dynamic> raw) {
    return {
      'delivery_enabled': _b(raw['delivery_enabled'], dflt: true),
      'sale_vendor_enabled': _b(raw['sale_vendor_enabled'], dflt: true),
    };
  }

  static bool _b(dynamic v, {required bool dflt}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return dflt;
  }
}
