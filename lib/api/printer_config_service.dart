import 'package:enterprise_pos/api/core/api_client.dart';

import '../models/printer_config.dart';

class PrinterConfigService {
  final ApiClient _client;

  PrinterConfigService() : _client = ApiClient();

  Future<PrinterConfig> getPrinterConfig() async {
    final res = await _client.post("/printer-config");

    if (res["success"] == true) {
      final data = res["data"] ?? {};
      return PrinterConfig.fromJson(data);
    }

    throw Exception(res["message"] ?? "Failed to fetch printer config");
  }
}