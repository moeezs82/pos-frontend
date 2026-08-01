import 'dart:async';
import 'dart:convert';

import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_template.dart';
import '../models/printer_config.dart';

/// Branch-aware printer configuration.
///
/// Every branch is an independent business, so a cached logo, shop name,
/// receipt footer, or printer target must never be reused after switching to
/// another branch. Network responses are generation-guarded as well: a slow
/// response from the previous branch is discarded if the active context has
/// already changed.
class PrinterConfigProvider extends ChangeNotifier {
  static const Duration _cacheDuration = Duration(minutes: 10);

  Timer? _cacheResetTimer;
  PrinterConfig _config = const PrinterConfig();
  bool _isLoading = false;
  String? _loadedContextKey;
  int? _branchId;
  int _generation = 0;

  PrinterConfig get config => _config;
  bool get isLoading => _isLoading;

  String? get mainPrinterName => _config.mainPrinterName;
  String? get secondaryPrinterName => _config.secondaryPrinterName;
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
  bool get secondaryPrintEnabled => _config.secondaryPrintEnabled;
  String? get secondaryNetworkIp => _config.secondaryNetworkIp;
  int get secondaryNetworkPort => _config.secondaryNetworkPort;
  String? get secondaryLocalPrinterName => _config.secondaryLocalPrinterName;
  InvoiceTemplate get mainInvoiceTemplate => _config.mainInvoiceTemplate;
  InvoiceTemplate get secondaryInvoiceTemplate =>
      _config.secondaryInvoiceTemplate;
  bool get barcodePrintEnabled => _config.barcodePrintEnabled;
  String get barcodeConnection => _config.barcodeConnection;
  String? get barcodeLocalPrinterName => _config.barcodeLocalPrinterName;
  String? get barcodeNetworkIp => _config.barcodeNetworkIp;
  int get barcodeNetworkPort => _config.barcodeNetworkPort;
  String get barcodePrinterLanguage => _config.barcodePrinterLanguage;
  double get barcodeLabelWidthMm => _config.barcodeLabelWidthMm;
  double get barcodeLabelHeightMm => _config.barcodeLabelHeightMm;
  double get barcodeLabelGapMm => _config.barcodeLabelGapMm;
  int get barcodeDpi => _config.barcodeDpi;
  String get barcodeOrientation => _config.barcodeOrientation;
  String get barcodeCurrency => _config.barcodeCurrency;
  List<String> get footerLines => _config.footerLines;

  // Compatibility getters for receipt code compiled during a rolling update.
  String? get kitchenPrinterName => secondaryPrinterName;
  bool get kitchenPrintEnabled => secondaryPrintEnabled;
  String? get kitchenNetworkIp => secondaryNetworkIp;
  int get kitchenNetworkPort => secondaryNetworkPort;
  String? get kitchenLocalPrinterName => secondaryLocalPrinterName;
  InvoiceTemplate get kitchenInvoiceTemplate => secondaryInvoiceTemplate;

  String _cacheKey(int branchId) => 'printer_config_cache_b$branchId';
  String _cacheTimeKey(int branchId) =>
      'printer_config_cache_time_b$branchId';
  String _contextKey(String token, int branchId) => '$token#$branchId';

  Future<void> _loadFromCache(int branchId, int generation) async {
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation || branchId != _branchId) return;

    final raw = prefs.getString(_cacheKey(branchId));
    final savedAt = prefs.getInt(_cacheTimeKey(branchId));
    if (raw == null || raw.isEmpty || savedAt == null) return;

    final savedTime = DateTime.fromMillisecondsSinceEpoch(savedAt);
    if (DateTime.now().difference(savedTime) > _cacheDuration) {
      await prefs.remove(_cacheKey(branchId));
      await prefs.remove(_cacheTimeKey(branchId));
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      if (generation != _generation || branchId != _branchId) return;
      _config = PrinterConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Printer config cache parse failed: $e');
    }
  }

  Future<void> _fetchFromBackend({
    required String token,
    required int branchId,
    required int generation,
  }) async {
    final freshConfig =
        await PrinterConfigService(token: token).getPrinterConfig();
    if (generation != _generation ||
        branchId != _branchId ||
        _loadedContextKey != _contextKey(token, branchId)) {
      return;
    }

    _config = freshConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(branchId),
      jsonEncode(_config.toJson()),
    );
    await prefs.setInt(
      _cacheTimeKey(branchId),
      DateTime.now().millisecondsSinceEpoch,
    );
    if (generation == _generation && branchId == _branchId) {
      notifyListeners();
    }
  }

  /// Safe to call on every auth/branch notification. A real reload happens
  /// only when token or branch changes.
  Future<void> ensureLoadedFor(String? token, {int? branchId}) async {
    if (token == null || branchId == null || branchId <= 0) {
      stopAutoRefresh();
      return;
    }
    final key = _contextKey(token, branchId);
    if (_loadedContextKey == key && _isLoading) return;
    if (_loadedContextKey == key) return;

    final generation = ++_generation;
    _cacheResetTimer?.cancel();
    _loadedContextKey = key;
    _branchId = branchId;
    _config = const PrinterConfig();
    _isLoading = true;
    notifyListeners();

    await _loadFromCache(branchId, generation);
    try {
      await _fetchFromBackend(
        token: token,
        branchId: branchId,
        generation: generation,
      );
    } catch (e) {
      // Keep a valid branch-specific cache when the backend is temporarily
      // unavailable. This method is intentionally safe when called without
      // await from the auth orchestrator.
      debugPrint('Printer config load failed: $e');
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
        _startAutoRefresh(token, branchId, generation);
      }
    }
  }

  Future<void> refresh(String token, {int? branchId}) async {
    final targetBranch = branchId ?? _branchId;
    if (targetBranch == null || targetBranch <= 0) return;
    final key = _contextKey(token, targetBranch);
    if (_loadedContextKey != key) {
      await ensureLoadedFor(token, branchId: targetBranch);
      return;
    }

    final generation = _generation;
    _isLoading = true;
    notifyListeners();
    try {
      await _fetchFromBackend(
        token: token,
        branchId: targetBranch,
        generation: generation,
      );
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> clearCache({int? branchId}) async {
    final targetBranch = branchId ?? _branchId;
    if (targetBranch == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey(targetBranch));
    await prefs.remove(_cacheTimeKey(targetBranch));
    if (targetBranch == _branchId) {
      _config = const PrinterConfig();
      notifyListeners();
    }
  }

  void _startAutoRefresh(String token, int branchId, int generation) {
    _cacheResetTimer?.cancel();
    _cacheResetTimer = Timer.periodic(_cacheDuration, (_) async {
      if (generation != _generation || branchId != _branchId) return;
      try {
        await _fetchFromBackend(
          token: token,
          branchId: branchId,
          generation: generation,
        );
      } catch (e) {
        debugPrint('Printer config auto refresh failed: $e');
      }
    });
  }

  void stopAutoRefresh() {
    ++_generation;
    _cacheResetTimer?.cancel();
    _cacheResetTimer = null;
    _loadedContextKey = null;
    _branchId = null;
    _isLoading = false;
    _config = const PrinterConfig();
    notifyListeners();
  }

  @override
  void dispose() {
    _cacheResetTimer?.cancel();
    super.dispose();
  }
}
