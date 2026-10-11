import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/utils/receipt_extras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppCurrency.configure('KD'));

  group('ReceiptExtras.totalSavings', () {
    test('is zero when no discount was applied', () {
      const items = [
        SaleReceiptItem(name: 'A', price: 100, qty: 2, total: 200),
      ];
      expect(
        ReceiptExtras.totalSavings(items: items, invoiceDiscount: 0),
        0,
      );
    });

    test('adds invoice, item and extra discounts', () {
      const items = [
        SaleReceiptItem(
          name: 'A',
          price: 100,
          qty: 2,
          total: 170,
          discountAmount: 20,
          extraDiscountAmount: 10,
        ),
        SaleReceiptItem(
          name: 'B',
          price: 50,
          qty: 1,
          total: 50,
          discountAmount: 0,
        ),
      ];
      expect(
        ReceiptExtras.totalSavings(items: items, invoiceDiscount: 15.5),
        45.5,
      );
    });
  });

  group('ReceiptExtras.money', () {
    test('uses Rs. for PKR / Rs', () {
      AppCurrency.configure('PKR');
      expect(ReceiptExtras.money(120), 'Rs. 120.00');
      AppCurrency.configure('Rs');
      expect(ReceiptExtras.money(120), 'Rs. 120.00');
    });

    test('uses the branch currency otherwise', () {
      AppCurrency.configure('KD');
      expect(ReceiptExtras.money(120), 'KD 120.00');
      AppCurrency.configure(r'$');
      expect(ReceiptExtras.money(120), r'$120.00');
    });
  });

  group('ReceiptExtras.websiteFrom', () {
    test('returns null when blank or missing', () {
      expect(ReceiptExtras.websiteFrom(null), isNull);
      expect(ReceiptExtras.websiteFrom({'shop_website': '  '}), isNull);
    });

    test('returns the trimmed website', () {
      expect(
        ReceiptExtras.websiteFrom({'shop_website': ' www.shop.pk '}),
        'www.shop.pk',
      );
    });
  });

  group('PrinterConfig.barcodeLabelShopName', () {
    test('custom name wins', () {
      const c = PrinterConfig(
        shopName: 'Receipt Name',
        barcodeShopName: 'Label Name',
        barcodeBranchName: 'Main Branch',
      );
      expect(c.barcodeLabelShopName, 'Label Name');
    });

    test('defaults to the branch name', () {
      const c = PrinterConfig(
        shopName: 'Receipt Name',
        barcodeShopName: '  ',
        barcodeBranchName: 'Main Branch',
      );
      expect(c.barcodeLabelShopName, 'Main Branch');
    });

    test('falls back to the receipt shop name for older servers', () {
      const c = PrinterConfig(shopName: 'Receipt Name');
      expect(c.barcodeLabelShopName, 'Receipt Name');
    });
  });
}
