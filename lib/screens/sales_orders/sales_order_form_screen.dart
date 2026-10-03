import 'dart:async';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/product_stock.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/widgets/party_autocomplete_field.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

typedef PartyMap = Map<String, dynamic>;

class SalesOrderFormScreen extends StatefulWidget {
  /// Pre-selects a customer when opened from a customer screen.
  final Map<String, dynamic>? initialCustomer;

  /// When supplied, the screen edits that existing order through
  /// PUT /sales-orders/{id} instead of creating a new one.
  final SalesOrder? editOrder;

  const SalesOrderFormScreen({
    super.key,
    this.initialCustomer,
    this.editOrder,
  });

  @override
  State<SalesOrderFormScreen> createState() => _SalesOrderFormScreenState();
}

class _SalesOrderFormItem {
  final Map<String, dynamic> product;
  int productId;
  String productName;
  String productSku;
  ProductPackaging? selectedPackaging;
  double packagingQuantity;
  double quantity;
  double unitPrice;
  double discount;
  double taxRate;
  String? notes;
  double? stockQty;
  String? stockUnit;
  QuantityRule quantityRule;

  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController discountCtrl;
  final TextEditingController taxCtrl;
  final FocusNode qtyFocus;
  final FocusNode priceFocus;
  final FocusNode discountFocus;
  final FocusNode taxFocus;

  _SalesOrderFormItem({
    required this.product,
    required this.productId,
    required this.productName,
    required this.productSku,
    this.selectedPackaging,
    this.packagingQuantity = 1.0,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
    this.taxRate = 0.0,
    this.notes,
    this.stockQty,
    this.stockUnit,
    required this.quantityRule,
  })  : qtyCtrl = TextEditingController(
          text: selectedPackaging != null
              ? (packagingQuantity == packagingQuantity.roundToDouble()
                  ? packagingQuantity.toInt().toString()
                  : packagingQuantity.toString())
              : (quantity == quantity.roundToDouble()
                  ? quantity.toInt().toString()
                  : quantity.toString()),
        ),
        priceCtrl = TextEditingController(
          text: unitPrice.toStringAsFixed(2),
        ),
        discountCtrl = TextEditingController(
          text: discount > 0 ? discount.toStringAsFixed(2) : '0',
        ),
        taxCtrl = TextEditingController(
          text: taxRate > 0 ? taxRate.toStringAsFixed(1) : '0',
        ),
        qtyFocus = FocusNode(),
        priceFocus = FocusNode(),
        discountFocus = FocusNode(),
        taxFocus = FocusNode();

  double get gross {
    if (selectedPackaging != null) {
      return packagingQuantity * unitPrice;
    }
    return quantity * unitPrice;
  }

  double get lineTotal {
    final net = (gross - discount).clamp(0.0, double.infinity);
    return net + (net * (taxRate / 100.0));
  }

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
    taxCtrl.dispose();
    qtyFocus.dispose();
    priceFocus.dispose();
    discountFocus.dispose();
    taxFocus.dispose();
  }
}

class _SalesOrderFormScreenState extends State<SalesOrderFormScreen> {
  final _pageFocusNode = FocusNode();
  final _barcodeFocusNode = FocusNode();
  final _barcodeController = TextEditingController();
  final _notesController = TextEditingController();
  final _customerFocusNode = FocusNode();
  final _customerController = TextEditingController();
  final _salesmanFocusNode = FocusNode();
  final _salesmanController = TextEditingController();

  final _money = const AppMoneyFormatter();

  PartyMap? _selectedCustomer;
  PartyMap? _selectedSalesman;
  DateTime _orderDate = DateTime.now();
  DateTime? _deliveryDate;

  final List<_SalesOrderFormItem> _items = [];
  bool _saving = false;
  DateTime? _stockFetchedAt;

  Map<int, Map<String, String>> _itemErrors = {};
  Map<String, String> _fieldErrors = {};

  bool get _isEdit => widget.editOrder != null;

  @override
  void initState() {
    super.initState();
    _stockFetchedAt = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      final branchIdStr = _effectiveBranchIdStr();
      if (token != null) {
        PartyPrefetch.warmForSale(token, branchId: branchIdStr);
        CustomerPickCache.hydrateFromCatalog(
          branchId: int.tryParse(branchIdStr ?? ''),
        );
      }
      _initFormState(auth);
    });

    _barcodeFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pageFocusNode.dispose();
    _barcodeFocusNode.dispose();
    _barcodeController.dispose();
    _notesController.dispose();
    _customerFocusNode.dispose();
    _customerController.dispose();
    _salesmanFocusNode.dispose();
    _salesmanController.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  String? _effectiveBranchIdStr() {
    final branch = context.read<BranchProvider>().activeBranch;
    if (branch != null && branch['id'] != null) {
      return branch['id'].toString();
    }
    final auth = context.read<AuthProvider>();
    return auth.activeBranchId?.toString();
  }

  bool _canSetSalesman(AuthProvider auth) {
    if (auth.isMasterAdmin) return true;
    final role = auth.roleLabel.toLowerCase();
    if (role.contains('admin')) return true;
    final roles = auth.user?['roles'];
    if (roles is Iterable) {
      for (final r in roles) {
        final name = (r is Map ? r['name'] : r).toString().toLowerCase();
        if (name == 'admin') return true;
      }
    }
    return false;
  }

  void _initFormState(AuthProvider auth) {
    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
    }

    if (_isEdit) {
      final o = widget.editOrder!;
      if (o.customer != null) {
        _selectedCustomer = {
          'id': o.customer!.id,
          'name': o.customer!.name,
          'phone': o.customer!.phone,
          'address': o.customer!.address,
        };
      } else {
        _selectedCustomer = {'id': o.customerId, 'name': 'Customer #${o.customerId}'};
      }

      if (o.salesman != null) {
        _selectedSalesman = {
          'id': o.salesman!.id,
          'name': o.salesman!.name,
          'email': o.salesman!.email,
        };
      }

      if (o.orderDate.isNotEmpty) {
        _orderDate = DateTime.tryParse(o.orderDate) ?? DateTime.now();
      }
      if (o.deliveryDate != null && o.deliveryDate!.isNotEmpty) {
        _deliveryDate = DateTime.tryParse(o.deliveryDate!);
      }
      if (o.notes != null) {
        _notesController.text = o.notes!;
      }

      for (final line in o.items) {
        final prodMap = <String, dynamic>{
          'id': line.productId,
          'name': line.productName.isNotEmpty ? line.productName : 'Product #${line.productId}',
          'sku': line.productSku,
          'price': line.unitPrice,
        };
        final rule = QuantityRule.fromProduct(prodMap);

        ProductPackaging? pkg;
        double pkgQty = 1.0;
        double unitPrice = line.unitPrice;
        if (line.productPackagingId != null && line.productPackagingId! > 0) {
          pkg = ProductPackaging(
            id: line.productPackagingId,
            name: line.packagingNameSnapshot ?? 'Package',
            shortName: line.packagingShortNameSnapshot,
            baseQuantity: line.packagingFactorSnapshot ?? 1.0,
            retailPrice: line.packagingUnitPrice,
          );
          pkgQty = line.packagingQuantity ?? 1.0;
          unitPrice = line.packagingUnitPrice ?? (line.unitPrice * (line.packagingFactorSnapshot ?? 1.0));
        }

        final item = _SalesOrderFormItem(
          product: prodMap,
          productId: line.productId,
          productName: line.productName.isNotEmpty ? line.productName : 'Product #${line.productId}',
          productSku: line.productSku,
          selectedPackaging: pkg,
          packagingQuantity: pkgQty,
          quantity: line.quantity,
          unitPrice: unitPrice,
          discount: line.discount,
          taxRate: line.taxRate,
          notes: line.notes,
          quantityRule: rule,
        );
        _items.add(item);
      }
    } else {
      if (auth.user != null) {
        _selectedSalesman = {
          'id': auth.user!['id'],
          'name': auth.user!['name'] ?? '',
          'email': auth.user!['email'] ?? '',
        };
      }
    }

    setState(() {});
    _restoreSaleOrderFocus();
  }

  void _restoreSaleOrderFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      _pageFocusNode.requestFocus();
    });
  }

  void _focusAndSelectAll(FocusNode node, TextEditingController ctrl) {
    node.requestFocus();
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
  }

  List<ProductPackaging> _packagingsFor(Map<String, dynamic> prod) {
    final raw = prod['packagings'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ProductPackaging.fromJson(m.cast<String, dynamic>()))
        .where((p) => p.isActive && p.id != null)
        .toList();
  }

  void _addOrIncrementProduct(Map<String, dynamic> product, {double qty = 1.0}) {
    final pid = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (pid <= 0) return;

    final customerType = _selectedCustomer?['customer_type'];
    final existingIdx = _items.indexWhere((it) => it.productId == pid && it.selectedPackaging == null);

    if (existingIdx >= 0) {
      final existing = _items[existingIdx];
      final newQty = existing.quantity + qty;
      if (!existing.quantityRule.allows(newQty)) {
        AppFeedback.warning(context, existing.quantityRule.message);
        return;
      }
      existing.quantity = newQty;
      existing.qtyCtrl.text = newQty == newQty.roundToDouble()
          ? newQty.toInt().toString()
          : newQty.toString();
    } else {
      final price = SalePricing.effectiveProductPrice(product, customerType: customerType);
      final rule = QuantityRule.fromProduct(product);
      if (!rule.allows(qty)) {
        AppFeedback.warning(context, rule.message);
        return;
      }
      final stock = ProductStock.quantity(product);
      final unit = ProductStock.unitLabel(product);

      final item = _SalesOrderFormItem(
        product: product,
        productId: pid,
        productName: (product['name'] ?? '').toString(),
        productSku: (product['sku'] ?? '').toString(),
        quantity: qty,
        unitPrice: price,
        stockQty: stock,
        stockUnit: unit,
        quantityRule: rule,
      );
      _items.add(item);
    }
  }

  Future<void> _onBarcodeScanned(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    final productService = ProductService(token: token);

    Map<String, dynamic>? product;
    try {
      product = await productService.getProductByBarcode(trimmed);
    } catch (_) {
      product = null;
    }

    product ??= await CatalogCacheService.instance.productByBarcode(
      trimmed,
      branchId: int.tryParse(_effectiveBranchIdStr() ?? ''),
    );

    if (product != null) {
      setState(() => _addOrIncrementProduct(product!));
    } else {
      if (mounted) {
        AppFeedback.warning(context, 'Product not found: $trimmed');
      }
    }

    _barcodeController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  Future<void> _openProductPicker() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final customerType = (_selectedCustomer?['customer_type'] ?? 'retail').toString();
    final alreadySelectedQty = <int, double>{};
    for (final it in _items) {
      if (it.selectedPackaging == null) {
        alreadySelectedQty[it.productId] = it.quantity;
      }
    }

    final picked = await ProductPickerGridSheet.openMulti(
      context,
      token: token,
      customerType: customerType,
      alreadySelectedIds: _items.map((i) => i.productId).toList(),
      alreadySelectedQty: alreadySelectedQty,
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() {
        for (final entry in picked) {
          final prod = entry['product'] as Map<String, dynamic>;
          final q = (entry['qty'] as num?)?.toDouble() ?? 1.0;
          _addOrIncrementProduct(prod, qty: q);
        }
      });
    }
    _restoreSaleOrderFocus();
  }

  Future<void> _pickOrderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _orderDate = picked);
    }
    _restoreSaleOrderFocus();
  }

  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? _orderDate.add(const Duration(days: 3)),
      firstDate: _orderDate,
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _deliveryDate = picked);
    }
    _restoreSaleOrderFocus();
  }

  double get _subtotal => _items.fold(0.0, (sum, it) => sum + it.gross);
  double get _totalDiscount => _items.fold(0.0, (sum, it) => sum + it.discount);
  double get _totalTax => _items.fold(0.0, (sum, it) {
        final net = (it.gross - it.discount).clamp(0.0, double.infinity);
        return sum + (net * (it.taxRate / 100.0));
      });
  double get _total => _subtotal - _totalDiscount + _totalTax;

  Future<void> _saveOrder({required bool submitForApproval}) async {
    if (_saving) return;

    if (_selectedCustomer == null || (_selectedCustomer!['id'] ?? 0) <= 0) {
      AppFeedback.warning(context, 'Please select a customer for this order.');
      _customerFocusNode.requestFocus();
      return;
    }

    if (_items.isEmpty) {
      AppFeedback.warning(context, 'Please add at least one line item to the order.');
      return;
    }

    // Client-side quantity rule check
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final checkQty = it.selectedPackaging != null
          ? it.packagingQuantity * it.selectedPackaging!.baseQuantity
          : it.quantity;
      if (!it.quantityRule.allows(checkQty)) {
        AppFeedback.warning(
          context,
          'Row #${i + 1} (${it.productName}): ${it.quantityRule.message}',
        );
        it.qtyFocus.requestFocus();
        return;
      }
    }

    // Demotion guard when editing an APPROVED order (§5)
    if (_isEdit && widget.editOrder!.status == SalesOrderStatus.approved) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
              SizedBox(width: 10),
              Text('Demote Approved Order?'),
            ],
          ),
          content: const Text(
            'This order is approved. Saving changes returns it to Submitted and it will need approval again.',
            style: TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
              child: const Text('Proceed & Return to Submitted'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _itemErrors.clear();
      _fieldErrors.clear();
    });

    final token = context.read<AuthProvider>().token!;
    final service = SalesOrderService(token: token);

    final customerId = int.parse(_selectedCustomer!['id'].toString());
    final salesmanId = _selectedSalesman != null && _selectedSalesman!['id'] != null
        ? int.tryParse(_selectedSalesman!['id'].toString())
        : null;

    final dateFmt = DateFormat('yyyy-MM-dd');
    final orderDateStr = dateFmt.format(_orderDate);
    final deliveryDateStr = _deliveryDate != null ? dateFmt.format(_deliveryDate!) : null;

    final itemsPayload = _items.map((it) {
      if (it.selectedPackaging != null) {
        final factor = it.selectedPackaging!.baseQuantity;
        final baseUnits = it.packagingQuantity * factor;
        final basePrice = it.unitPrice / factor;
        return <String, dynamic>{
          'product_id': it.productId,
          'product_packaging_id': it.selectedPackaging!.id,
          'packaging_quantity': it.packagingQuantity,
          'packaging_unit_price': it.unitPrice,
          'quantity': baseUnits,
          'unit_price': basePrice,
          'discount': it.discount,
          'tax_rate': it.taxRate,
          if (it.notes != null && it.notes!.trim().isNotEmpty) 'notes': it.notes!.trim(),
        };
      }
      return <String, dynamic>{
        'product_id': it.productId,
        'quantity': it.quantity,
        'unit_price': it.unitPrice,
        'discount': it.discount,
        'tax_rate': it.taxRate,
        if (it.notes != null && it.notes!.trim().isNotEmpty) 'notes': it.notes!.trim(),
      };
    }).toList();

    try {
      if (_isEdit) {
        final body = <String, dynamic>{
          'customer_id': customerId,
          if (deliveryDateStr != null) 'delivery_date': deliveryDateStr,
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'version': widget.editOrder!.version,
          'items': itemsPayload,
        };
        final updated = await service.updateOrder(widget.editOrder!.id, body);
        if (submitForApproval && updated.status == SalesOrderStatus.draft) {
          await service.submit(updated.id, version: updated.version);
        }
        if (!mounted) return;
        AppFeedback.success(
          context,
          submitForApproval
              ? 'Sales order submitted for approval.'
              : 'Sales order changes saved.',
        );
        Navigator.pop(context, true);
      } else {
        final body = <String, dynamic>{
          'customer_id': customerId,
          if (salesmanId != null) 'salesman_id': salesmanId,
          'status': submitForApproval ? SalesOrderStatus.submitted : SalesOrderStatus.draft,
          'order_date': orderDateStr,
          if (deliveryDateStr != null) 'delivery_date': deliveryDateStr,
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          'items': itemsPayload,
        };
        await service.createOrder(body);
        if (!mounted) return;
        AppFeedback.success(
          context,
          submitForApproval
              ? 'Sales order created and submitted for approval.'
              : 'Sales order draft saved.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e is ApiException) {
        if (e.statusCode == 422 && e.body != null) {
          final errs = e.body!['errors'];
          if (errs is Map) {
            final nextItemErrors = <int, Map<String, String>>{};
            final nextFieldErrors = <String, String>{};
            errs.forEach((k, v) {
              final key = k.toString();
              final msg = (v is List && v.isNotEmpty) ? v.first.toString() : v.toString();
              if (key.startsWith('items.')) {
                final parts = key.split('.');
                if (parts.length >= 3) {
                  final idx = int.tryParse(parts[1]) ?? -1;
                  final field = parts[2];
                  if (idx >= 0 && idx < _items.length) {
                    nextItemErrors.putIfAbsent(idx, () => {})[field] = msg;
                  }
                }
              } else {
                nextFieldErrors[key] = msg;
              }
            });
            setState(() {
              _itemErrors = nextItemErrors;
              _fieldErrors = nextFieldErrors;
            });
          }
          AppFeedback.error(context, e.message);
          return;
        }
        if (e.statusCode == 409) {
          AppFeedback.error(
            context,
            'Conflict: this sales order was modified by another user. Reload and try again.',
          );
          return;
        }
        if (e.statusCode == 404) {
          AppFeedback.error(context, 'Sales order not found or access denied.');
          return;
        }
      }
      AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canSetSalesman = _canSetSalesman(auth);
    final canViewStock = auth.hasPermission('view-stock');
    final title = _isEdit
        ? 'Edit Sales Order (${widget.editOrder!.orderNumber})'
        : 'New Sales Order';

    // Shortcut bindings scoping
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (!_saving) Navigator.maybePop(context);
      },
      const SingleActivator(LogicalKeyboardKey.f2): _openProductPicker,
      _ctrl(LogicalKeyboardKey.keyI): _openProductPicker,
      const SingleActivator(LogicalKeyboardKey.f3): () {
        _customerFocusNode.requestFocus();
      },
      _ctrlShift(LogicalKeyboardKey.keyC): () {
        _customerFocusNode.requestFocus();
      },
      const SingleActivator(LogicalKeyboardKey.f9): () {
        _barcodeFocusNode.requestFocus();
      },
      if (canSetSalesman)
        _ctrlShift(LogicalKeyboardKey.keyS): () {
          _salesmanFocusNode.requestFocus();
        },
      _ctrlShift(LogicalKeyboardKey.keyP): _openProductPicker,
      _ctrl(LogicalKeyboardKey.keyS): () => _saveOrder(submitForApproval: false),
      _cmd(LogicalKeyboardKey.keyS): () => _saveOrder(submitForApproval: false),
      _ctrl(LogicalKeyboardKey.enter): () => _saveOrder(submitForApproval: true),
      _cmd(LogicalKeyboardKey.enter): () => _saveOrder(submitForApproval: true),
      _ctrl(LogicalKeyboardKey.numpadEnter): () => _saveOrder(submitForApproval: true),
      _cmd(LogicalKeyboardKey.numpadEnter): () => _saveOrder(submitForApproval: true),
      _ctrl(LogicalKeyboardKey.slash): () =>
          showAppShortcutGuide(context, includeSalesOrder: true),
      _cmd(LogicalKeyboardKey.slash): () =>
          showAppShortcutGuide(context, includeSalesOrder: true),
      const SingleActivator(LogicalKeyboardKey.f1): () =>
          showAppShortcutGuide(context, includeSalesOrder: true),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _pageFocusNode,
        autofocus: true,
        child: EnterprisePage(
          title: title,
          subtitle: _isEdit
              ? 'Update order lines and quotation'
              : 'Direct sales order booking and pricing quotation',
          icon: _isEdit ? Icons.edit_note_rounded : Icons.assignment_add,
          actions: [
            OutlinedButton.icon(
              onPressed: () => showAppShortcutGuide(context, includeSalesOrder: true),
              icon: const Icon(Icons.keyboard_rounded, size: 16),
              label: const Text('Shortcuts'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPartyAndDatesPanel(auth, canSetSalesman),
              const SizedBox(height: 10),
              if (_selectedCustomer != null) ...[
                _buildCustomerContextStrip(),
                const SizedBox(height: 10),
              ],
              _buildBarcodeAndSearchPanel(),
              const SizedBox(height: 10),
              Expanded(
                child: _buildItemsTable(canViewStock),
              ),
              const SizedBox(height: 10),
              _buildFooterCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartyAndDatesPanel(AuthProvider auth, bool canSetSalesman) {
    final token = auth.token ?? '';
    final branchIdStr = _effectiveBranchIdStr();
    final customerService = CustomerService(token: token);
    final userService = UsersService(token: token);

    final customerError = _fieldErrors['customer_id'];

    return EnterprisePanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Customer autocomplete
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 300,
                    child: PartyAutocompleteField<PartyMap>(
                      label: 'Customer *',
                      hintText: 'Type customer ID, name, area… (F3)',
                      focusNode: _customerFocusNode,
                      controller: _customerController,
                      getCachedItems: () =>
                          CustomerPickCache.cache.peek(CustomerPickCache.keyFor())?.items ??
                          const [],
                      onSearchRemote: (q) => CustomerPickCache.searchRemote(
                        customerService,
                        q,
                        branchId: int.tryParse(branchIdStr ?? ''),
                      ),
                      labelOf: CustomerDisplayUtils.fullName,
                      subtitleOf: CustomerDisplayUtils.subtitle,
                      searchTextOf: CustomerDisplayUtils.searchText,
                      idOf: (c) => (c['id'] ?? '').toString(),
                      selectedLabel: _selectedCustomer != null
                          ? CustomerDisplayUtils.fullName(_selectedCustomer!)
                          : null,
                      selectedSubtitle: _selectedCustomer != null
                          ? CustomerDisplayUtils.subtitle(_selectedCustomer!)
                          : null,
                      onSelected: (c) {
                        setState(() {
                          _selectedCustomer = c;
                          _fieldErrors.remove('customer_id');
                        });
                        _restoreSaleOrderFocus();
                      },
                      onCleared: () {
                        setState(() => _selectedCustomer = null);
                        _restoreSaleOrderFocus();
                      },
                      onBrowseAll: () async {
                        final picked = await showModalBottomSheet<PartyMap>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => CustomerPickerSheet(token: token),
                        );
                        _restoreSaleOrderFocus();
                        return picked;
                      },
                    ),
                  ),

                  // Salesman autocomplete (only when settable)
                  if (canSetSalesman)
                    SizedBox(
                      width: isNarrow ? constraints.maxWidth : 240,
                      child: PartyAutocompleteField<PartyMap>(
                        label: 'Salesman',
                        hintText: 'Type salesman… (Ctrl+Shift+S)',
                        focusNode: _salesmanFocusNode,
                        controller: _salesmanController,
                        getCachedItems: () =>
                            UserPickCache.cache
                                .peek(UserPickCache.keyFor(branchId: branchIdStr, role: 'salesman'))
                                ?.items ??
                            const [],
                        onSearchRemote: (q) => UserPickCache.searchRemote(
                          userService,
                          q,
                          branchId: branchIdStr,
                          role: 'salesman',
                        ),
                        labelOf: (u) => (u['name'] ?? '').toString(),
                        subtitleOf: (u) => (u['phone'] ?? u['email'] ?? '').toString(),
                        idOf: (u) => (u['id'] ?? '').toString(),
                        selectedLabel: _selectedSalesman != null
                            ? (_selectedSalesman!['name'] ?? '').toString()
                            : null,
                        selectedSubtitle: _selectedSalesman != null
                            ? (_selectedSalesman!['email'] ?? '').toString()
                            : null,
                        onSelected: (u) {
                          setState(() => _selectedSalesman = u);
                          _restoreSaleOrderFocus();
                        },
                        onCleared: () {
                          setState(() => _selectedSalesman = null);
                          _restoreSaleOrderFocus();
                        },
                        onBrowseAll: () async {
                          final picked = await showModalBottomSheet<PartyMap>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => UserPickerSheet(
                              token: token,
                              branchId: branchIdStr,
                              role: 'salesman',
                              title: 'Select Salesman',
                            ),
                          );
                          _restoreSaleOrderFocus();
                          return picked;
                        },
                      ),
                    ),

                  // Order date
                  InkWell(
                    onTap: _pickOrderDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Order Date', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                              Text(DateFormat('dd MMM yyyy').format(_orderDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Delivery date
                  InkWell(
                    onTap: _pickDeliveryDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_shipping_outlined, size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Expected Delivery', style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                              Text(
                                _deliveryDate != null
                                    ? DateFormat('dd MMM yyyy').format(_deliveryDate!)
                                    : 'Not specified',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _deliveryDate != null ? AppTheme.navy : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          if (_deliveryDate != null) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _deliveryDate = null),
                              child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (customerError != null) ...[
                const SizedBox(height: 6),
                Text(customerError, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCustomerContextStrip() {
    final c = _selectedCustomer!;
    final balance = double.tryParse((c['trade_balance'] ?? c['balance'] ?? 0).toString()) ?? 0.0;
    final limit = double.tryParse((c['credit_limit'] ?? 0).toString()) ?? 0.0;
    final limitMode = (c['credit_limit_mode'] ?? 'off').toString().toLowerCase();
    final hasLimit = limit > 0 && limitMode != 'off';
    final projected = balance + _total;
    final headroom = limit - projected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 20,
            color: hasLimit && headroom < 0 ? AppTheme.warning : AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Text(
            CustomerDisplayUtils.fullName(c),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(width: 14),
          _stripBadge(
            label: 'Balance',
            value: _money.format(balance),
            color: balance > 0 ? AppTheme.danger : AppTheme.textMuted,
          ),
          const SizedBox(width: 12),
          _stripBadge(
            label: 'Credit Limit',
            value: hasLimit ? _money.format(limit) : 'Unlimited',
            color: hasLimit ? AppTheme.navy : AppTheme.textMuted,
          ),
          if (hasLimit) ...[
            const SizedBox(width: 12),
            _stripBadge(
              label: 'Headroom',
              value: _money.format(headroom),
              color: headroom < 0 ? AppTheme.danger : AppTheme.success,
            ),
          ],
          const Spacer(),
          Text(
            CustomerDisplayUtils.typeLabel(c),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _stripBadge({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildBarcodeAndSearchPanel() {
    final armed = _barcodeFocusNode.hasFocus;

    return EnterprisePanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Barcode input with armed indicator (§4.3)
          Expanded(
            flex: 2,
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              textInputAction: TextInputAction.go,
              onSubmitted: _onBarcodeScanned,
              decoration: InputDecoration(
                hintText: 'Scan barcode or type SKU… (F9)',
                prefixIcon: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: armed ? AppTheme.success : AppTheme.textMuted,
                  size: 20,
                ),
                suffixIcon: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: armed ? AppTheme.success.withOpacity(0.12) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: armed ? AppTheme.success : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    armed ? 'SCANNER ARMED' : 'F9 to Arm',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: armed ? AppTheme.success : AppTheme.textMuted,
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: armed ? AppTheme.success : AppTheme.border,
                    width: armed ? 1.5 : 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: armed ? AppTheme.success : AppTheme.border,
                    width: armed ? 1.5 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.success,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Add items button (F2)
          FilledButton.icon(
            onPressed: _openProductPicker,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
            label: const Text('Add Items (F2)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTable(bool canViewStock) {
    if (_items.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_shopping_cart_rounded,
                  color: AppTheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No line items added yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan a product barcode (F9) or browse the catalog (F2) to begin quoting.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _openProductPicker,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Browse Products (F2)'),
              ),
            ],
          ),
        ),
      );
    }

    return EnterprisePanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 4, child: Text('ITEM / SKU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 3, child: Text('UNIT / PACKAGING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('QTY', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('PRICE', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('DISCOUNT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('TAX %', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMuted))),
                const SizedBox(width: 44),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (context, index) => _buildItemRow(index, canViewStock),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index, bool canViewStock) {
    final it = _items[index];
    final packagings = _packagingsFor(it.product);
    final rowErrors = _itemErrors[index] ?? {};

    final stockAsOf = _stockFetchedAt != null
        ? DateFormat('HH:mm').format(_stockFetchedAt!)
        : null;

    final isShortfall = it.stockQty != null && it.stockQty! < it.quantity;

    return Container(
      color: index % 2 == 1 ? AppTheme.surface.withOpacity(0.4) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Product Name & SKU & Stock
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.productName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (it.productSku.isNotEmpty) ...[
                          Text(
                            it.productSku,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (canViewStock && it.stockQty != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isShortfall ? AppTheme.warning.withOpacity(0.12) : AppTheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isShortfall ? AppTheme.warning : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              'Avail: ${it.stockQty!.toStringAsFixed(0)} ${it.stockUnit ?? ''} (as of $stockAsOf)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isShortfall ? AppTheme.warning : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Unit / Packaging Selector (§1.2 & §5)
              Expanded(
                flex: 3,
                child: packagings.isNotEmpty
                    ? DropdownButtonFormField<ProductPackaging?>(
                        value: it.selectedPackaging,
                        isDense: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        items: [
                          const DropdownMenuItem<ProductPackaging?>(
                            value: null,
                            child: Text('Base Unit', style: TextStyle(fontSize: 12)),
                          ),
                          ...packagings.map((p) => DropdownMenuItem<ProductPackaging?>(
                                value: p,
                                child: Text(
                                  '${p.name} (x${p.baseQuantity.toInt()})',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                        ],
                        onChanged: (pkg) {
                          setState(() {
                            it.selectedPackaging = pkg;
                            final customerType = _selectedCustomer?['customer_type'];
                            if (pkg != null) {
                              it.unitPrice = SalePricing.effectivePackagingPrice(
                                it.product,
                                pkg,
                                customerType: customerType,
                              );
                              it.packagingQuantity = 1.0;
                              it.quantity = pkg.baseQuantity;
                              it.priceCtrl.text = it.unitPrice.toStringAsFixed(2);
                              it.qtyCtrl.text = '1';
                            } else {
                              it.unitPrice = SalePricing.effectiveProductPrice(
                                it.product,
                                customerType: customerType,
                              );
                              it.quantity = 1.0;
                              it.priceCtrl.text = it.unitPrice.toStringAsFixed(2);
                              it.qtyCtrl.text = '1';
                            }
                          });
                        },
                      )
                    : const Text('Base Unit', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ),
              const SizedBox(width: 8),

              // 3. Quantity input (enter-to-advance to price)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: it.qtyCtrl,
                  focusNode: it.qtyFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: rowErrors['quantity'] ?? rowErrors['packaging_quantity'],
                  ),
                  onTap: () => _focusAndSelectAll(it.qtyFocus, it.qtyCtrl),
                  onSubmitted: (_) => _focusAndSelectAll(it.priceFocus, it.priceCtrl),
                  onChanged: (val) {
                    final d = double.tryParse(val.trim()) ?? 0.0;
                    setState(() {
                      if (it.selectedPackaging != null) {
                        it.packagingQuantity = d;
                        it.quantity = d * it.selectedPackaging!.baseQuantity;
                      } else {
                        it.quantity = d;
                      }
                      rowErrors.remove('quantity');
                      rowErrors.remove('packaging_quantity');
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),

              // 4. Unit Price input (enter-to-advance to discount)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: it.priceCtrl,
                  focusNode: it.priceFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: rowErrors['unit_price'] ?? rowErrors['packaging_unit_price'],
                  ),
                  onTap: () => _focusAndSelectAll(it.priceFocus, it.priceCtrl),
                  onSubmitted: (_) => _focusAndSelectAll(it.discountFocus, it.discountCtrl),
                  onChanged: (val) {
                    final p = double.tryParse(val.trim()) ?? 0.0;
                    setState(() {
                      it.unitPrice = p;
                      rowErrors.remove('unit_price');
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),

              // 5. Line Discount input (enter-to-advance to tax)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: it.discountCtrl,
                  focusNode: it.discountFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: rowErrors['discount'],
                  ),
                  onTap: () => _focusAndSelectAll(it.discountFocus, it.discountCtrl),
                  onSubmitted: (_) => _focusAndSelectAll(it.taxFocus, it.taxCtrl),
                  onChanged: (val) {
                    final d = double.tryParse(val.trim()) ?? 0.0;
                    setState(() {
                      it.discount = d;
                      rowErrors.remove('discount');
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),

              // 6. Tax Rate input (enter-to-advance to next row or barcode)
              Expanded(
                flex: 2,
                child: TextField(
                  controller: it.taxCtrl,
                  focusNode: it.taxFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    errorText: rowErrors['tax_rate'],
                  ),
                  onTap: () => _focusAndSelectAll(it.taxFocus, it.taxCtrl),
                  onSubmitted: (_) {
                    if (index + 1 < _items.length) {
                      _focusAndSelectAll(_items[index + 1].qtyFocus, _items[index + 1].qtyCtrl);
                    } else {
                      _barcodeFocusNode.requestFocus();
                    }
                  },
                  onChanged: (val) {
                    final t = double.tryParse(val.trim()) ?? 0.0;
                    setState(() {
                      it.taxRate = t;
                      rowErrors.remove('tax_rate');
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),

              // 7. Line Total
              Expanded(
                flex: 2,
                child: Text(
                  _money.format(it.lineTotal),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.navy),
                ),
              ),

              // 8. Delete line button
              SizedBox(
                width: 44,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 18),
                  tooltip: 'Remove item',
                  onPressed: () {
                    setState(() {
                      it.dispose();
                      _items.removeAt(index);
                      _itemErrors.remove(index);
                    });
                  },
                ),
              ),
            ],
          ),
          if (rowErrors.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              rowErrors.values.join(' • '),
              style: const TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterCard() {
    final balance = double.tryParse((_selectedCustomer?['trade_balance'] ?? _selectedCustomer?['balance'] ?? 0).toString()) ?? 0.0;
    final limit = double.tryParse((_selectedCustomer?['credit_limit'] ?? 0).toString()) ?? 0.0;
    final limitMode = (_selectedCustomer?['credit_limit_mode'] ?? 'off').toString().toLowerCase();
    final hasLimit = limit > 0 && limitMode != 'off';
    final projected = balance + _total;
    final exceededBy = projected - limit;
    final isExceeded = hasLimit && exceededBy > 0;

    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Advisory credit banner (§5)
          if (isExceeded) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This order will exceed the credit limit by ${_money.format(exceededBy)}; approval will require an override.',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.navy),
                    ),
                  ),
                ],
              ),
            ),
          ],

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notes field
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Order Notes / Delivery Instructions',
                    hintText: 'e.g. Phone order, confirm stock before dispatch…',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              // Quoted totals card (§5)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _totalRow('Subtotal', _money.format(_subtotal)),
                      const SizedBox(height: 4),
                      _totalRow('Discount', '- ${_money.format(_totalDiscount)}', isDiscount: true),
                      const SizedBox(height: 4),
                      _totalRow('Tax', _money.format(_totalTax)),
                      const Divider(height: 12),
                      _totalRow('Quoted Total', _money.format(_total), isTotal: true),
                      const SizedBox(height: 6),
                      const Text(
                        'Quoted totals — recalculated by the server on save.',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action bar (§5)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.maybePop(context),
                child: const Text('Cancel (Esc)'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _saveOrder(submitForApproval: false),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save Draft (Ctrl+S)'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : () => _saveOrder(submitForApproval: true),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Submit for Approval (Ctrl+Enter)'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool isTotal = false, bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
            color: isTotal ? AppTheme.navy : AppTheme.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 15 : 12,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: isDiscount
                ? AppTheme.danger
                : (isTotal ? AppTheme.navy : AppTheme.text),
          ),
        ),
      ],
    );
  }
}
