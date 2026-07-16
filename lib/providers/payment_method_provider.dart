import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:enterprise_pos/api/payment_method_service.dart';
import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';

/// Shared source of active payment methods for the current session/branch.
///
/// Reloads when authentication or the selected branch changes. Operational
/// screens use [activeMethods]; historical screens can resolve a stored code
/// via [displayNameFor] even when the method is no longer active.
class PaymentMethodProvider extends ChangeNotifier {
  final PaymentMethodService Function(String token)? _serviceFactory;

  PaymentMethodProvider({PaymentMethodService Function(String token)? serviceFactory})
      : _serviceFactory = serviceFactory;

  String? _token;
  int? _branchId;

  List<PaymentMethod> _methods = const [];
  bool _loading = false;
  String? _error;

  /// Guards against redundant reloads for the same token+branch pair.
  String? _loadedKey;

  List<PaymentMethod> get activeMethods =>
      _methods.where((m) => m.isActive).toList();

  List<PaymentMethod> get all => List.unmodifiable(_methods);
  bool get isLoading => _loading;
  String? get error => _error;
  bool get hasMethods => activeMethods.isNotEmpty;

  /// A sensible default tender for a fresh cart: the drawer cash method if
  /// present, otherwise the first active method.
  PaymentMethod? get defaultMethod {
    final act = activeMethods;
    if (act.isEmpty) return null;
    return act.firstWhere(
      (m) => m.affectsCashDrawer,
      orElse: () => act.first,
    );
  }

  PaymentMethod? byCode(String? code) {
    if (code == null) return null;
    final c = code.toLowerCase().trim();
    for (final m in _methods) {
      if (m.method == c) return m;
    }
    return null;
  }

  bool affectsCashDrawer(String? code) => byCode(code)?.affectsCashDrawer ?? (code == 'cash');

  /// Human name for a (possibly historical/inactive) method code.
  String displayNameFor(String? code) {
    if (code == null || code.isEmpty) return '—';
    final m = byCode(code);
    if (m != null) return m.displayName;
    // Fallback: titleize the raw code so historical rows still render.
    return code
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Called from the auth/branch sync in main.dart. Idempotent for a given
  /// token+branch; pass [force] to reload after a config change.
  Future<void> initialize(String token, {int? branchId, bool force = false}) async {
    _token = token;
    _branchId = branchId;
    final key = '$token#${branchId ?? 'default'}';
    if (!force && _loadedKey == key && _methods.isNotEmpty) return;
    await _load(key);
  }

  Future<void> reload() async {
    if (_token == null) return;
    await _load('$_token#${_branchId ?? 'default'}', force: true);
  }

  Future<void> _load(String key, {bool force = false}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final service = _serviceFactory != null
          ? _serviceFactory!(_token!)
          : PaymentMethodService(token: _token!);
      final list = await service.getActive();
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _methods = list;
      _loadedKey = key;
      // Persist for offline sale creation (best-effort).
      unawaited(_cache(list));
    } catch (e) {
      _error = e.toString();
      // Fall back to cached methods so checkout still works offline.
      final cached = await _loadCache();
      if (cached.isNotEmpty) {
        _methods = cached;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _cache(List<PaymentMethod> list) async {
    try {
      await CatalogCacheService.instance.savePaymentMethods(
        _branchId,
        list.map((m) => m.toCache()).toList(),
      );
    } catch (_) {/* cache is best-effort */}
  }

  Future<List<PaymentMethod>> _loadCache() async {
    try {
      final rows = await CatalogCacheService.instance.loadPaymentMethods(_branchId);
      return rows
          .map<PaymentMethod>((e) => PaymentMethod.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void clear() {
    _token = null;
    _branchId = null;
    _methods = const [];
    _loadedKey = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
