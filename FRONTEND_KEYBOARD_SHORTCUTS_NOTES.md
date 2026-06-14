# Frontend Keyboard Shortcuts Patch

This patch adds app-wide keyboard shortcuts for faster POS operation while keeping existing navigation and UI flow intact.

## Global shortcuts

These work after login from any screen:

- `Ctrl + /` or `F1` — open shortcut guide
- `Ctrl + H` — Home
- `Ctrl + N` or `F2` — Create Sale
- `Ctrl + L` — Sales list
- `Ctrl + O` — New Purchase
- `Ctrl + Shift + O` — Purchases list
- `Ctrl + P` — Products
- `Ctrl + I` — Stock
- `Ctrl + Shift + C` — Customers
- `Ctrl + Shift + V` — Vendors
- `Ctrl + M` — Party Payments
- `Ctrl + B` — Cash Book
- `Ctrl + E` — Add Expense
- `Ctrl + R` — Reports
- `Ctrl + U` — Users
- `Ctrl + T` — Sale Returns
- `Ctrl + Shift + B` — Branch Control, master admin only

Number shortcuts are also available:

- `Ctrl + 1` — Create Sale
- `Ctrl + 2` — Sales list
- `Ctrl + 3` — Products
- `Ctrl + 4` — Stock
- `Ctrl + 5` — Customers
- `Ctrl + 6` — Vendors
- `Ctrl + 7` — New Purchase
- `Ctrl + 8` — Party Payments
- `Ctrl + 9` — Reports
- `Ctrl + 0` — Cash Book

On macOS, the same shortcuts also work with `Cmd` for letter shortcuts.

## Create Sale page shortcuts

- `F2` or `Ctrl + I` — open item selector
- `F3` or `Ctrl + Shift + C` — select customer
- `F4` or `Ctrl + Shift + D` — select delivery boy
- `F9` — focus barcode/scanner input
- `Ctrl + Enter` — save sale

## Branch behavior

If master admin has not selected a working branch, business shortcuts redirect to Branch Control and show a warning. Normal users do not see branch switching.

## Files added

- `lib/services/app_navigator.dart`
- `lib/widgets/app_keyboard_shortcuts.dart`
- `FRONTEND_KEYBOARD_SHORTCUTS_NOTES.md`

## Files updated

- `lib/main.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/sales/sale_create.dart`
