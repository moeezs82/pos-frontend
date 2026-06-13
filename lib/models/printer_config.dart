class PrinterConfig {
  final String? mainPrinterName;
  final String? kitchenPrinterName;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;

  const PrinterConfig({
    this.mainPrinterName,
    this.kitchenPrinterName,
    this.shopName,
    this.shopAddress,
    this.shopPhone,
  });

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      mainPrinterName: json['main_printer_name']?.toString(),
      kitchenPrinterName: json['kitchen_printer_name']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'main_printer_name': mainPrinterName,
      'kitchen_printer_name': kitchenPrinterName,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
    };
  }
}