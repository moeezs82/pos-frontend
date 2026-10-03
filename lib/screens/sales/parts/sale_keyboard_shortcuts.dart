import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SaleShortcutBindings {
  static ShortcutActivator _ctrl(LogicalKeyboardKey key) =>
      SingleActivator(key, control: true);

  static ShortcutActivator _cmd(LogicalKeyboardKey key) =>
      SingleActivator(key, meta: true);

  static ShortcutActivator _ctrlShift(LogicalKeyboardKey key) =>
      SingleActivator(key, control: true, shift: true);

  static ShortcutActivator _cmdShift(LogicalKeyboardKey key) =>
      SingleActivator(key, meta: true, shift: true);

  static Map<ShortcutActivator, VoidCallback> buildBindings({
    required BuildContext context,
    required bool isEditing,
    required bool isSalesOrder,
    required bool deliveryEnabled,
    required bool saleVendorEnabled,
    required VoidCallback onAddItemManual,
    required VoidCallback onPickCustomer,
    required VoidCallback onPickDeliveryBoy,
    required VoidCallback onDeliveryBoyFocus,
    required VoidCallback onFocusBarcodeScanner,
    required VoidCallback onSubmitPrimary,
    required VoidCallback? onSubmitDraft,
    required VoidCallback onCustomerFocus,
    required VoidCallback onSalesmanFocus,
    required VoidCallback onProductSearchFocus,
    required VoidCallback onVendorFocus,
    required VoidCallback onWalkInNameFocus,
    required VoidCallback onWalkInPhoneFocus,
    required VoidCallback onWalkInAddressFocus,
    required VoidCallback onCashReceivedFocus,
    required VoidCallback onDiscountFocus,
    required VoidCallback onTaxFocus,
    required VoidCallback onShippingFocus,
  }) {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f2): onAddItemManual,
      _ctrl(LogicalKeyboardKey.keyI): onAddItemManual,
      _cmd(LogicalKeyboardKey.keyI): onAddItemManual,
      if (!isEditing) ...{
        const SingleActivator(LogicalKeyboardKey.f3): onPickCustomer,
        _ctrlShift(LogicalKeyboardKey.keyC): onPickCustomer,
        _cmdShift(LogicalKeyboardKey.keyC): onPickCustomer,
      },
      if (deliveryEnabled) ...{
        const SingleActivator(LogicalKeyboardKey.f4): onPickDeliveryBoy,
        _ctrlShift(LogicalKeyboardKey.keyD): onPickDeliveryBoy,
        _cmdShift(LogicalKeyboardKey.keyD): onPickDeliveryBoy,
        _ctrlShift(LogicalKeyboardKey.keyB): onDeliveryBoyFocus,
      },
      const SingleActivator(LogicalKeyboardKey.f9): onFocusBarcodeScanner,
      _ctrl(LogicalKeyboardKey.enter): onSubmitPrimary,
      _cmd(LogicalKeyboardKey.enter): onSubmitPrimary,
      _ctrl(LogicalKeyboardKey.numpadEnter): onSubmitPrimary,
      _cmd(LogicalKeyboardKey.numpadEnter): onSubmitPrimary,
      if (isSalesOrder && onSubmitDraft != null) ...{
        _ctrl(LogicalKeyboardKey.keyS): onSubmitDraft,
        _cmd(LogicalKeyboardKey.keyS): onSubmitDraft,
      },
      _ctrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(
            context,
            includeSaleCreate: !isSalesOrder,
            includeSalesOrder: isSalesOrder,
          ),
      _cmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(
            context,
            includeSaleCreate: !isSalesOrder,
            includeSalesOrder: isSalesOrder,
          ),
      if (!isEditing) _ctrlShift(LogicalKeyboardKey.keyU): onCustomerFocus,
      _ctrlShift(LogicalKeyboardKey.keyS): onSalesmanFocus,
      _ctrlShift(LogicalKeyboardKey.keyP): onProductSearchFocus,
      if (saleVendorEnabled) ...{
        _ctrlShift(LogicalKeyboardKey.keyV): onVendorFocus,
        _cmdShift(LogicalKeyboardKey.keyV): onVendorFocus,
      },
      _ctrlShift(LogicalKeyboardKey.keyN): onWalkInNameFocus,
      _ctrlShift(LogicalKeyboardKey.keyH): onWalkInPhoneFocus,
      _ctrlShift(LogicalKeyboardKey.keyA): onWalkInAddressFocus,
      _ctrlShift(LogicalKeyboardKey.keyR): onCashReceivedFocus,
      _cmdShift(LogicalKeyboardKey.keyR): onCashReceivedFocus,
      _ctrlShift(LogicalKeyboardKey.keyG): onDiscountFocus,
      _ctrlShift(LogicalKeyboardKey.keyT): onTaxFocus,
      _ctrlShift(LogicalKeyboardKey.keyS): onShippingFocus,
    };
  }
}
