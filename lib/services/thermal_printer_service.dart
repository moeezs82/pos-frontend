import 'dart:typed_data';

class ThermalPrinterService {
  ThermalPrinterService._();
  static final instance = ThermalPrinterService._();

  Future<void> printSaleReceiptWindows({
    required String printerName,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? logoAsset,
    Uint8List? logoBytes,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    required double cashReceived,
    required double changeAmount,
    Map<String, dynamic>? meta,
  }) async {
    throw UnsupportedError('Raw thermal printing is not supported on web.');
  }

  Future<void> printSaleReceiptNetwork({
    required String printerIp,
    int port = 9100,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? logoAsset,
    Uint8List? logoBytes,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    required double cashReceived,
    required double changeAmount,
    Map<String, dynamic>? meta,
  }) async {
    throw UnsupportedError('Network thermal printing is not supported on web.');
  }
}

class SaleReceiptItem {
  final String name;
  final double price;
  final double qty;
  final double total;

  SaleReceiptItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.total,
  });
}
