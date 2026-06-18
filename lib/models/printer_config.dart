class PrinterConfig {
  final int? branchId;
  final String? branchName;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;

  /// 'network' | 'local' | 'none'
  final String activeConnection;

  final String? networkIp;
  final int networkPort;
  final String? localPrinterName;

  final bool kitchenPrintEnabled;
  final String? kitchenNetworkIp;
  final int kitchenNetworkPort;
  final String? kitchenLocalPrinterName;

  // Legacy fields kept so older call sites (sale_create.dart, sale_detail.dart)
  // that read mainPrinterName/kitchenPrinterName keep working unchanged.
  final String? mainPrinterName;
  final String? kitchenPrinterName;

  const PrinterConfig({
    this.branchId,
    this.branchName,
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.activeConnection = 'none',
    this.networkIp,
    this.networkPort = 9100,
    this.localPrinterName,
    this.kitchenPrintEnabled = false,
    this.kitchenNetworkIp,
    this.kitchenNetworkPort = 9100,
    this.kitchenLocalPrinterName,
    this.mainPrinterName,
    this.kitchenPrinterName,
  });

  bool get isConfigured => activeConnection != 'none';

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    int toPort(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return PrinterConfig(
      branchId: json['branch_id'] is int ? json['branch_id'] as int : int.tryParse((json['branch_id'] ?? '').toString()),
      branchName: json['branch_name']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
      activeConnection: (json['active_connection'] ?? 'none').toString(),
      networkIp: json['network_ip']?.toString(),
      networkPort: toPort(json['network_port'], 9100),
      localPrinterName: json['local_printer_name']?.toString(),
      kitchenPrintEnabled: json['kitchen_print_enabled'] == true,
      kitchenNetworkIp: json['kitchen_network_ip']?.toString(),
      kitchenNetworkPort: toPort(json['kitchen_network_port'], 9100),
      kitchenLocalPrinterName: json['kitchen_local_printer_name']?.toString(),
      // Legacy keys, still returned by the backend for older clients.
      mainPrinterName: json['main_printer_name']?.toString(),
      kitchenPrinterName: json['kitchen_printer_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
  }

  PrinterConfig copyWith({
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? activeConnection,
    String? networkIp,
    int? networkPort,
    String? localPrinterName,
    bool? kitchenPrintEnabled,
    String? kitchenNetworkIp,
    int? kitchenNetworkPort,
    String? kitchenLocalPrinterName,
  }) {
    return PrinterConfig(
      branchId: branchId,
      branchName: branchName,
      shopName: shopName ?? this.shopName,
      shopAddress: shopAddress ?? this.shopAddress,
      shopPhone: shopPhone ?? this.shopPhone,
      activeConnection: activeConnection ?? this.activeConnection,
      networkIp: networkIp ?? this.networkIp,
      networkPort: networkPort ?? this.networkPort,
      localPrinterName: localPrinterName ?? this.localPrinterName,
      kitchenPrintEnabled: kitchenPrintEnabled ?? this.kitchenPrintEnabled,
      kitchenNetworkIp: kitchenNetworkIp ?? this.kitchenNetworkIp,
      kitchenNetworkPort: kitchenNetworkPort ?? this.kitchenNetworkPort,
      kitchenLocalPrinterName: kitchenLocalPrinterName ?? this.kitchenLocalPrinterName,
    );
  }
}