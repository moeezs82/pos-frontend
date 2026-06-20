import 'dart:async';
import 'dart:convert';

import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_template.dart';
import '../models/printer_config.dart';

/// Created once at app startup (before anyone has logged in), so it can't
/// hold a token from the start. Every method that talks to the backend
/// takes the caller's current token instead — the caller always has one on
/// hand via `context.read<AuthProvider>().token`, since this provider has
/// no BuildContext of its own to fetch it independently.
class PrinterConfigProvider extends ChangeNotifier {
  static const String _cacheKey = 'printer_config_cache';
  static const String _cacheTimeKey = 'printer_config_cache_time';

  static const Duration _cacheDuration = Duration(minutes: 10);

  Timer? _cacheResetTimer;

  PrinterConfig _config = const PrinterConfig();
  bool _isLoading = false;
  String? _loadedForToken;

  PrinterConfig get config => _config;
  bool get isLoading => _isLoading;

  String? get mainPrinterName => _config.mainPrinterName;
  String? get kitchenPrinterName => _config.kitchenPrinterName;
  String get shopName => _config.shopName ?? '';
  String get shopAddress => _config.shopAddress ?? '';
  String get shopPhone => _config.shopPhone ?? '';

  String get activeConnection => _config.activeConnection;
  bool get isNetworkPrinter => _config.activeConnection == 'network';
  bool get isLocalPrinter => _config.activeConnection == 'local';
  bool get isConfigured => _config.isConfigured;
  String? get networkIp => _config.networkIp;
  int get networkPort => _config.networkPort;
  String? get localPrinterName => _config.localPrinterName;
  bool get kitchenPrintEnabled => _config.kitchenPrintEnabled;
  String? get kitchenNetworkIp => _config.kitchenNetworkIp;
  int get kitchenNetworkPort => _config.kitchenNetworkPort;
  String? get kitchenLocalPrinterName => _config.kitchenLocalPrinterName;
  InvoiceTemplate get mainInvoiceTemplate => _config.mainInvoiceTemplate;
  InvoiceTemplate get kitchenInvoiceTemplate => _config.kitchenInvoiceTemplate;
  List<String> get footerLines => _config.footerLines;

  /// Load whatever was cached locally — safe to call before login, since it
  /// never touches the network. Call [refresh] with a real token afterwards
  /// once one is available (e.g. right after a successful login).
  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_cacheKey);
    final savedAt = prefs.getInt(_cacheTimeKey);

    if (raw == null || raw.isEmpty || savedAt == null) return;

    final savedTime = DateTime.fromMillisecondsSinceEpoch(savedAt);
    final isExpired = DateTime.now().difference(savedTime) > _cacheDuration;

    if (isExpired) {
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      return;
    }

    try {
      final Map<String, dynamic> jsonMap = jsonDecode(raw);
      _config = PrinterConfig.fromJson(jsonMap);
      notifyListeners();
    } catch (e) {
      debugPrint('Printer config cache parse failed: $e');
    }
  }

  Future<void> fetchFromBackend(String token) async {
    debugPrint('Calling printer config backend...');
    final freshConfig = await PrinterConfigService(token: token).getPrinterConfig();

    debugPrint('activeConnection: ${freshConfig.activeConnection}');
    debugPrint('shopName: ${freshConfig.shopName}');

    _config = freshConfig;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_config.toJson()));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);

    notifyListeners();
  }

  /// Call this once a token is actually available — typically right after
  /// login succeeds, or lazily the first time a screen needs printer
  /// settings (e.g. before printing a sale receipt).
  Future<void> refresh(String token) async {
    try {
      _isLoading = true;
      notifyListeners();

      await fetchFromBackend(token);
      _loadedForToken = token;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Safe to call on every rebuild while a token is on hand (e.g. from a
  /// postFrameCallback): a no-op once already loaded or loading for that
  /// exact token, but does a real fetch and starts the background
  /// auto-refresh the first time a token appears or changes (a different
  /// user signed in).
  Future<void> ensureLoadedFor(String? token) async {
    if (token == null || token == _loadedForToken || _isLoading) return;
    await refresh(token);
    startAutoRefresh(token);
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);

    _config = const PrinterConfig();
    notifyListeners();
  }

  /// Starts a periodic background refresh once a token is available. Safe
  /// to call again after a re-login; cancels any previous timer first.
  void startAutoRefresh(String token) {
    _cacheResetTimer?.cancel();

    _cacheResetTimer = Timer.periodic(_cacheDuration, (_) async {
      try {
        await fetchFromBackend(token);
      } catch (e) {
        debugPrint('Printer config auto refresh failed: $e');
      }
    });
  }

  void stopAutoRefresh() {
    _cacheResetTimer?.cancel();
    _cacheResetTimer = null;
    _loadedForToken = null;
  }

  @override
  void dispose() {
    _cacheResetTimer?.cancel();
    super.dispose();
  }
}
