import 'package:enterprise_pos/api/core/api_client.dart';

import '../models/invoice_template.dart';
import '../models/printer_config.dart';

class PrinterConfigService {
  final ApiClient _client;

  PrinterConfigService({required String token}) : _client = ApiClient(token: token);

  Future<PrinterConfig> getPrinterConfig() async {
    final res = await _client.post("/printer-config");
    if (res["success"] == true) {
      return PrinterConfig.fromJson(res["data"] ?? {});
    }
    throw Exception(res["message"] ?? "Failed to fetch printer config");
  }

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

  Future<List<InvoiceTemplate>> getTemplates() async {
    try {
      final res = await _client.get("/printer-config/templates");
      if (res["success"] == true) {
        final rows = (res["data"]?["templates"] as List? ?? []);
        final values = rows
            .whereType<Map>()
            .map((e) => e['value']?.toString())
            .whereType<String>()
            .toList();
        if (values.isNotEmpty) {
          return values.map(InvoiceTemplate.fromValue).toList();
        }
      }
    } catch (_) {}
    return InvoiceTemplate.values;
  }

  Future<PrinterConfig> savePrinterConfig({
    int? branchId,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    List<String> footerLines = const [],
    required String activeConnection,
    String? networkIp,
    int networkPort = 9100,
    String? localPrinterName,
    InvoiceTemplate mainInvoiceTemplate = InvoiceTemplate.standard,
    bool kitchenPrintEnabled = false,
    String? kitchenNetworkIp,
    int kitchenNetworkPort = 9100,
    String? kitchenLocalPrinterName,
    InvoiceTemplate kitchenInvoiceTemplate = InvoiceTemplate.kitchen,
  }) async {
    final res = await _client.post("/printer-config/save", body: {
      'branch_id': branchId,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
      'footer_lines': footerLines,
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
      'main_invoice_template': mainInvoiceTemplate.value,
      'kitchen_print_enabled': kitchenPrintEnabled,
      'kitchen_network_ip': kitchenNetworkIp,
      'kitchen_network_port': kitchenNetworkPort,
      'kitchen_local_printer_name': kitchenLocalPrinterName,
      'kitchen_invoice_template': kitchenInvoiceTemplate.value,
    });

    if (res["success"] == true) {
      return PrinterConfig.fromJson(res["data"] ?? {});
    }
    throw Exception(res["message"] ?? "Failed to save printer settings");
  }

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
