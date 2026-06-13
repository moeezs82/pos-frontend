import 'dart:async';
import 'dart:convert';

import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_config.dart';

class PrinterConfigProvider extends ChangeNotifier {
  static const String _cacheKey = 'printer_config_cache';
  static const String _cacheTimeKey = 'printer_config_cache_time';

  static const Duration _cacheDuration = Duration(minutes: 10);

  final PrinterConfigService _service;

  Timer? _cacheResetTimer;

  PrinterConfigProvider({PrinterConfigService? service})
    : _service = service ?? PrinterConfigService();

  PrinterConfig _config = const PrinterConfig();
  bool _isLoading = false;

  PrinterConfig get config => _config;
  bool get isLoading => _isLoading;

  String? get mainPrinterName => _config.mainPrinterName;
  String? get kitchenPrinterName => _config.kitchenPrinterName;
  String get shopName => _config.shopName ?? '';
  String get shopAddress => _config.shopAddress ?? '';
  String get shopPhone => _config.shopPhone ?? '';

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await loadFromCache();

    try {
      await fetchFromBackend();
    } catch (e, s) {
      debugPrint('PrinterConfig init error: $e');
      debugPrintStack(stackTrace: s);
    }

    _isLoading = false;
    notifyListeners();
  }

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

  Future<void> fetchFromBackend() async {
    debugPrint('Calling printer config backend...');
    final freshConfig = await _service.getPrinterConfig();

    debugPrint('mainPrinterName: ${freshConfig.mainPrinterName}');
    debugPrint('kitchenPrinterName: ${freshConfig.kitchenPrinterName}');
    debugPrint('shopName: ${freshConfig.shopName}');

    _config = freshConfig;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_config.toJson()));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);

    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      _isLoading = true;
      notifyListeners();

      await fetchFromBackend();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);

    _config = const PrinterConfig();
    notifyListeners();
  }

  void _startCacheResetTimer() {
    _cacheResetTimer?.cancel();

    _cacheResetTimer = Timer.periodic(_cacheDuration, (_) async {
      await clearCache();

      try {
        await fetchFromBackend();
      } catch (e) {
        debugPrint('Printer config auto refresh failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _cacheResetTimer?.cancel();
    super.dispose();
  }
}
