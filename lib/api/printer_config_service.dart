import 'package:enterprise_pos/api/core/api_client.dart';

import '../models/printer_config.dart';

class PrinterConfigService {
  final ApiClient _client;

  PrinterConfigService({required String token}) : _client = ApiClient(token: token);

  /// The settings that apply to the current user's branch (or the global
  /// default if their branch has none). Any signed-in user can call this.
  Future<PrinterConfig> getPrinterConfig() async {
    final res = await _client.post("/printer-config");

    if (res["success"] == true) {
      final data = res["data"] ?? {};
      return PrinterConfig.fromJson(data);
    }

    throw Exception(res["message"] ?? "Failed to fetch printer config");
  }

  /// Every configured row (per-branch + the global default), for the
  /// master-admin settings screen. 403s for non-master-admin users.
  Future<List<PrinterConfig>> getAllPrinterSettings() async {
    final res = await _client.get("/printer-config/all");

    if (res["success"] == true) {
      final rows = (res["data"]?["settings"] as List? ?? []);
      return rows
          .whereType<Map>()
          .map((e) => PrinterConfig.fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    throw Exception(res["message"] ?? "Failed to fetch printer settings");
  }

  /// Create or update the row for [branchId] (null = the global default).
  /// Master-admin only; the backend returns a 403 for anyone else.
  Future<PrinterConfig> savePrinterConfig({
    int? branchId,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    required String activeConnection, // network | local | none
    String? networkIp,
    int networkPort = 9100,
    String? localPrinterName,
    bool kitchenPrintEnabled = false,
    String? kitchenNetworkIp,
    int kitchenNetworkPort = 9100,
    String? kitchenLocalPrinterName,
  }) async {
    final res = await _client.post("/printer-config/save", body: {
      'branch_id': branchId,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
      'kitchen_print_enabled': kitchenPrintEnabled,
      'kitchen_network_ip': kitchenNetworkIp,
      'kitchen_network_port': kitchenNetworkPort,
      'kitchen_local_printer_name': kitchenLocalPrinterName,
    });

    if (res["success"] == true) {
      return PrinterConfig.fromJson(res["data"] ?? {});
    }

    throw Exception(res["message"] ?? "Failed to save printer settings");
  }

  /// Asks the backend to sanity-check a destination before the app actually
  /// attempts the test print itself (the real byte-level print always
  /// happens on-device; the backend has no path to a counter's printer).
  Future<void> validateTestDestination({
    required String activeConnection,
    String? networkIp,
    int networkPort = 9100,
    String? localPrinterName,
  }) async {
    final res = await _client.post("/printer-config/test", body: {
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
    });

    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Destination looks invalid");
    }
  }
}