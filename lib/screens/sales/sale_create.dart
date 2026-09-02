import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/api/sale_source_service.dart';
import 'package:enterprise_pos/api/customer_area_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_feature_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/services/offline_invoice_seq_service.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/utils/line_errors.dart';
import 'package:enterprise_pos/utils/network_failure.dart';
import 'package:enterprise_pos/utils/customer_phone_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_product_panel.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_profit_insight.dart';
import 'package:enterprise_pos/widgets/product_picker_grid_sheet.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:enterprise_pos/services/party_prefetch.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/sale_status_bar.dart';
import 'package:enterprise_pos/widgets/sale_source_manager_dialog.dart';
import 'package:enterprise_pos/widgets/reference_data_manager_dialog.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/models/whatsapp_invoice_format.dart';
import 'package:enterprise_pos/services/whatsapp_invoice_service.dart';
import 'package:enterprise_pos/services/whatsapp_message_template_service.dart';

// local widgets split into small files
import 'package:enterprise_pos/screens/sales/parts/sale_party_section.dart';


class _PendingWhatsAppTask {
  final String id;
  final String receiptNo;
  final WhatsAppInvoicePreparation prepared;
  final String message;
  bool opening;

  _PendingWhatsAppTask({
    required this.id,
    required this.receiptNo,
    required this.prepared,
    required this.message,
    this.opening = false,
  });
}

class _OfflineCreditDecision {
  final bool allowed;
  final String? message;

  const _OfflineCreditDecision._(this.allowed, this.message);

  const _OfflineCreditDecision.allow([String? message])
      : this._(true, message);

  const _OfflineCreditDecision.deny(String message)
      : this._(false, message);
}

class CreateSaleScreen extends StatefulWidget {
  final Map<String, dynamic>? initialCustomer;

  /// When opened from Sale Detail, keeps the cashier inside a clearly scoped
  /// Return / Exchange workflow. It only pre-fills the original invoice; the
  /// backend still validates every returned item and remaining quantity.
  final String? initialReturnInvoice;

  /// When supplied, this screen becomes the controlled posted-sale editor.
  /// Create mode remains unchanged; edit mode loads the current invoice and
  /// saves one audited desired-state amendment instead of POST /sales.
  final int? editSaleId;

  const CreateSaleScreen({
    super.key,
    this.initialCustomer,
    this.initialReturnInvoice,
    this.editSaleId,
  });

  @override
  State<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CreateSaleScreenState extends State<CreateSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageFocusNode = FocusNode();

  // selections
  String? _selectedBranchId;
  String? _selectedCustomerId;
  Map<String, dynamic>? _selectedBranch;
  Map<String, dynamic>? _selectedCustomer;

  String get _selectedCustomerType =>
      SalePricing.normalizeCustomerType(_selectedCustomer?['customer_type']);

  List<String> get _selectedCustomerSecondaryPhones =>
      CustomerPhoneUtils.secondaryPhones(_selectedCustomer?['phone_numbers']);

  String _whatsAppDestinationPhone() {
    if (_selectedCustomerId != null) {
      final primary = (_selectedCustomer?['phone'] ?? '').toString().trim();
      if (primary.isNotEmpty) return primary;
    }
    return customerPhoneController.text.trim();
  }
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;
  Map<String, dynamic>? _selectedUser;
  int? _selectedUserId;
  Map<String, dynamic>? _selectedDeliveryBoy;
  int? _selectedDeliveryBoyId;
  List<Map<String, dynamic>> _saleSources = const [];
  int? _selectedSaleSourceId;
  int? _saleSourcesBranchId;
  bool _saleSourcesReloadScheduled = false;
  List<Map<String, dynamic>> _customerAreas = const [];
  int? _selectedAreaId;
  int? _customerAreasBranchId;
  bool _customerAreasReloadScheduled = false;

  // cart & payments
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];

  // Selected tender for the quick single-payment flow. Null falls back to the
  // branch's default drawer method resolved from PaymentMethodProvider.
  String? _saleMethod;
  final saleReferenceController = TextEditingController();

  // discount/tax/shipping live controllers (edited inline in totals)
  final discountController = TextEditingController(text: "0");
  final taxController = TextEditingController(text: "0");
  final shippingController = TextEditingController(text: "0");
  final cashReceivedController = TextEditingController();

  final TextEditingController addressController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  bool _customerLocked = false;
  bool _sendInvoiceOnWhatsApp = false;

  // barcode (kept intact)
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;
  bool _showProfitInsight = false;

  // Named focus nodes for keyboard-shortcut field-jumping.
  // Party autocomplete fields (controllers cleared before focus so the field
  // opens with a blank query rather than leftover text).
  final _customerFocusNode = FocusNode();
  final _salesmanFocusNode = FocusNode();
  final _deliveryBoyFocusNode = FocusNode();
  final _vendorFocusNode = FocusNode();
  final _productSearchFocusNode = FocusNode();
  final _customerController = TextEditingController();
  final _salesmanController = TextEditingController();
  final _deliveryBoyController = TextEditingController();
  final _vendorController = TextEditingController();
  final _productSearchController = TextEditingController();
  // Walk-in inline fields
  final _walkInNameFocusNode = FocusNode();
  final _walkInPhoneFocusNode = FocusNode();
  final _walkInAddressFocusNode = FocusNode();
  // Summary / bottom-bar numeric fields (select-all on focus)
  final _discountFocusNode = FocusNode();
  final _taxFocusNode = FocusNode();
  final _shippingFocusNode = FocusNode();
  final _cashReceivedFocusNode = FocusNode();

  bool _submitting = false;
  bool _autoCashIfEmpty = true;
  bool _didAutoOpenPicker = false;

  // WhatsApp invoice preparation is intentionally non-blocking. Completed
  // attachments stay here until the cashier explicitly opens/dismisses them;
  // appearing tasks never steal keyboard focus from the next sale.
  final List<_PendingWhatsAppTask> _pendingWhatsAppTasks = [];
  int _postSaleTaskSequence = 0;

  // Posted-sale amendment state. None of this is used by normal Create Sale.
  bool get _isEditing => widget.editSaleId != null;
  bool _editLoading = false;
  String? _editLoadError;
  Map<String, dynamic>? _editSale;
  int _editRevision = 0;
  double _originalTotal = 0;
  double _existingNetPaid = 0;
  List<Map<String, dynamic>> _originalItems = const [];

  late ProductService _productService;
  late SaleService _saleService;
  late SaleSourceService _saleSourceService;
  late CustomerAreaService _customerAreaService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _saleService = SaleService(token: token);
    _saleSourceService = SaleSourceService(token: token);
    _customerAreaService = CustomerAreaService(token: token);
    _editLoading = _isEditing;
    _loadSaleSources();
    _loadCustomerAreas();

    // Warm customer/salesman/delivery-boy/product caches immediately, in
    // the background, before the user taps any "Select…" button. By the
    // time they actually open a picker a second or two later, it shows
    // cached data instantly instead of a blank spinner.
    final branchId = context.read<BranchProvider>().selectedBranchId?.toString();
    final features = context.read<BranchFeatureProvider>();
    PartyPrefetch.warmCustomers(token);
    PartyPrefetch.warmSalesmen(token, branchId: branchId);
    PartyPrefetch.warmProducts(token);
    // Only prefetch delivery-boy cache when module is enabled for this branch.
    if (features.deliveryEnabled) {
      PartyPrefetch.warmDeliveryBoys(token, branchId: branchId);
    }
    // Vendor prefetch for sale is also feature-gated.
    if (features.saleVendorEnabled) {
      PartyPrefetch.warmVendors(token);
    }

    // Offline composition (handover doc G1). Mirror the server catalog
    // (products + price/tax + customers) into local SQLite so a sale can be
    // built with no connectivity and after an app restart — the gap the
    // in-memory-only warm caches above leave open. Then seed the instant
    // pickers from that local cache. All fire-and-forget: if the refresh
    // can't reach the server, the pickers simply read whatever was cached
    // on the last successful sync.
    final branchIdInt = int.tryParse(branchId ?? '');
    _hydrateOfflinePickers(branchIdInt); // immediate, in case we're offline now
    CatalogCacheService.instance
        .refresh(token: token, branchId: branchIdInt)
        .then((_) {
          _hydrateOfflinePickers(branchIdInt);
          _loadSaleSources(preferCache: true);
          _loadCustomerAreas(preferCache: true);
        });

    _barcodeFocusNode.addListener(() {
      setState(() => _scannerEnabled = _barcodeFocusNode.hasFocus);
    });

    if (!_isEditing && widget.initialCustomer != null) {
      final customer = widget.initialCustomer!;
      _selectedCustomer = customer;
      _selectedCustomerId = customer['id']?.toString();
      _selectedAreaId = _metaInt(customer['area_id']);
      customerNameController.text = (customer['first_name'] ?? customer['name'] ?? '').toString();
      customerPhoneController.text = (customer['phone'] ?? '').toString();
      addressController.text = (customer['address'] ?? '').toString();
      _customerLocked = _selectedCustomerId != null;
    }

    void _recalc() => setState(() {});
    discountController.addListener(_recalc);
    taxController.addListener(_recalc);
    shippingController.addListener(_recalc);
    cashReceivedController.addListener(_recalc);

    // In the 3-panel layout the product grid is always visible — no need to
    // auto-open the picker modal. Focus the center panel search field so
    // the cashier can start typing immediately after navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isEditing) {
        _loadSaleForEdit();
      } else {
        _productSearchFocusNode.requestFocus();
      }
    });
  }


  Future<void> _loadSaleSources({bool preferCache = false}) async {
    final branchId = int.tryParse(_effectiveBranchIdStr());
    if (branchId != null && _saleSourcesBranchId != branchId && mounted) {
      setState(() {
        _saleSources = const [];
        // On a posted-sale amendment the saved source belongs to the sale
        // being loaded. Keep that id while the branch-scoped source list is
        // refreshed so the dropdown can restore the historical selection.
        // New-sale branch changes should still clear their old selection.
        if (!_isEditing) _selectedSaleSourceId = null;
        _saleSourcesBranchId = branchId;
      });
    }
    if (branchId == null) {
      if (mounted) {
        setState(() {
          _saleSources = const [];
          if (!_isEditing) _selectedSaleSourceId = null;
          _saleSourcesBranchId = null;
        });
      }
      return;
    }
    List<Map<String, dynamic>> sources = const [];
    if (!preferCache) {
      try {
        sources = await _saleSourceService.getSaleSources();
      } catch (_) {
        // Offline sale entry falls back to the catalog read replica below.
      }
    }
    if (sources.isEmpty) {
      try {
        sources = await CatalogCacheService.instance.saleSources(branchId: branchId);
      } catch (_) {/* best-effort local reference data */}
    }
    if (!mounted || sources.isEmpty) return;
    sources = sources.toList(growable: false)
      ..sort((a, b) {
        final ao = int.tryParse(a['sort_order']?.toString() ?? '') ?? 0;
        final bo = int.tryParse(b['sort_order']?.toString() ?? '') ?? 0;
        if (ao != bo) return ao.compareTo(bo);
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            );
      });
    int? next = _selectedSaleSourceId;
    final validCurrent = next != null &&
        sources.any((e) => _metaInt(e['id']) == next);
    if (!validCurrent && !_isEditing) {
      final counter = sources.where((e) =>
          _sourceDefault(e) && _sourceActive(e)).toList();
      final active = sources.where(_sourceActive).toList();
      next = _metaInt((counter.isNotEmpty ? counter.first : (active.isNotEmpty ? active.first : const <String, dynamic>{}))['id']);
    }
    setState(() {
      _saleSources = sources;
      _saleSourcesBranchId = branchId;
      if (next != null) _selectedSaleSourceId = next;
    });
  }

  bool _sourceActive(Map<String, dynamic> source) {
    final value = source['is_active'];
    return value == true || value == 1 || value?.toString().toLowerCase() == 'true';
  }

  bool _sourceDefault(Map<String, dynamic> source) {
    final value = source['is_default'];
    return value == true || value == 1 || value?.toString().toLowerCase() == 'true';
  }

  Map<String, dynamic>? get _selectedSaleSource {
    for (final source in _saleSources) {
      if (_metaInt(source['id']) == _selectedSaleSourceId) return source;
    }
    return null;
  }

  Future<void> _manageSaleSources() async {
    final result = await showSaleSourceManagerDialog(
      context: context,
      service: _saleSourceService,
      selectedId: _selectedSaleSourceId,
    );
    if (!mounted || result == null) return;
    if (result.selectedId != null) {
      setState(() => _selectedSaleSourceId = result.selectedId);
    }
    await _loadSaleSources();
    if (result.changed) {
      final branchId = int.tryParse(_effectiveBranchIdStr() ?? '');
      final token = context.read<AuthProvider>().token!;
      CatalogCacheService.instance
          .refresh(token: token, branchId: branchId)
          .then((_) => _loadSaleSources(preferCache: true));
    }
  }

  bool _areaActive(Map<String, dynamic> area) {
    final value = area['is_active'];
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  Map<String, dynamic>? _areaById(int? id) {
    if (id == null) return null;
    for (final area in _customerAreas) {
      if (_metaInt(area['id']) == id) return area;
    }
    return null;
  }

  String? get _selectedAreaName {
    final name = (_areaById(_selectedAreaId)?['name'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  }

  Future<void> _loadCustomerAreas({bool preferCache = false}) async {
    final branchId = int.tryParse(_effectiveBranchIdStr());
    if (branchId != null && _customerAreasBranchId != branchId && mounted) {
      setState(() {
        _customerAreas = const [];
        if (!_isEditing) _selectedAreaId = null;
        _customerAreasBranchId = branchId;
      });
    }
    if (branchId == null) {
      if (mounted) {
        setState(() {
          _customerAreas = const [];
          if (!_isEditing) _selectedAreaId = null;
          _customerAreasBranchId = null;
        });
      }
      return;
    }

    List<Map<String, dynamic>> areas = const [];
    if (!preferCache) {
      try {
        areas = await _customerAreaService.getAreas(activeOnly: true);
      } catch (_) {
        // Offline sale entry falls back to the catalog read replica below.
      }
    }
    if (areas.isEmpty) {
      try {
        areas = await CatalogCacheService.instance.customerAreas(
          branchId: branchId,
          activeOnly: true,
        );
      } catch (_) {/* best-effort local reference data */}
    }
    if (!mounted) return;

    areas = areas.toList(growable: false)
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));

    // Only active values are offered for new transactions. If a customer's
    // stored default area has since been deactivated it is intentionally not
    // carried into a fresh sale; the cashier can choose a current area.
    final currentStillAvailable = _selectedAreaId == null ||
        areas.any((area) => _metaInt(area['id']) == _selectedAreaId);
    setState(() {
      _customerAreas = areas;
      _customerAreasBranchId = branchId;
      if (!_isEditing && !currentStillAvailable) _selectedAreaId = null;
    });
  }

  Future<void> _manageCustomerAreas() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-customers')) {
      AppFeedback.warning(
        context,
        'You do not have permission to manage customer town / area values.',
      );
      return;
    }
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Town / Areas',
      singularLabel: 'Town / Area',
      icon: Icons.location_city_outlined,
      selectedId: _selectedAreaId,
      loadItems: () => _customerAreaService.getAreas(activeOnly: true),
      createItem: _customerAreaService.createArea,
      updateItem: _customerAreaService.updateArea,
      subtitle: 'Create, rename, or choose an area without leaving the sale.',
      selectedSubtitle: 'Selected for this sale',
    );
    if (!mounted || result == null) return;
    await _loadCustomerAreas();
    if (!mounted) return;
    if (result.selectedId != null &&
        _customerAreas.any((area) => _metaInt(area['id']) == result.selectedId)) {
      setState(() => _selectedAreaId = result.selectedId);
    } else if (result.selectedId == null) {
      setState(() => _selectedAreaId = null);
    }

    if (result.changed) {
      final branchId = int.tryParse(_effectiveBranchIdStr());
      final token = auth.token!;
      CatalogCacheService.instance
          .refresh(token: token, branchId: branchId)
          .then((_) => _loadCustomerAreas(preferCache: true));
    }
  }

  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<dynamic> _listValue(dynamic value) => value is List ? value : const [];

  double _editNum(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0.0;

  Future<void> _loadSaleForEdit() async {
    final saleId = widget.editSaleId;
    if (saleId == null) return;
    setState(() {
      _editLoading = true;
      _editLoadError = null;
    });
    try {
      final response = await _saleService.getSale(saleId, includeBalance: true);
      final sale = _mapValue(response['data']);
      if (sale.isEmpty) {
        throw const FormatException('The server returned an empty sale.');
      }

      final items = <Map<String, dynamic>>[];
      for (final raw in _listValue(sale['items'])) {
        final line = _mapValue(raw);
        final product = _mapValue(line['product']);
        final productId = int.tryParse(
              (line['product_id'] ?? product['id'] ?? '').toString(),
            ) ??
            0;
        if (productId <= 0) continue;
        final qty = _editNum(line['quantity']);
        final price = _editNum(line['price']);
        final discount = _editNum(line['discount']);
        final discountType =
            (line['discount_type'] ?? 'percentage').toString();
        final unitCost = _editNum(line['unit_cost']);
        items.add(<String, dynamic>{
          ...product,
          'sale_item_id': int.tryParse(line['id']?.toString() ?? ''),
          'product_id': productId,
          'name': (product['name'] ?? 'Product #$productId').toString(),
          'secondary_name': product['secondary_name'],
          'quantity': qty,
          'price': price,
          'discount_pct': discount,
          'discount_type': discountType,
          'total': _lineTotal(
            price: price,
            qty: qty,
            discPct: discount,
            discountType: discountType,
          ),
          SaleProfitCalculator.unitCostKey: unitCost,
          SaleProfitCalculator.estimatedKey: true,
          SaleProfitCalculator.sourceKey:
              'Posted cost snapshot; final amendment COGS is confirmed by the server',
        });
      }
      if (items.isEmpty) {
        throw const FormatException(
          'This invoice has no active sale items and cannot be amended here.',
        );
      }

      final customer = _mapValue(sale['customer']);
      final vendor = _mapValue(sale['vendor']);
      final salesman = _mapValue(sale['salesman']);
      final deliveryBoy = _mapValue(sale['delivery_boy']);
      final branch = _mapValue(sale['branch']);
      final meta = _mapValue(sale['meta']);
      final customerSnapshot = _mapValue(meta['customer_snapshot']);
      final customerId = int.tryParse(sale['customer_id']?.toString() ?? '');
      final vendorId = int.tryParse(sale['vendor_id']?.toString() ?? '');
      final salesmanId = int.tryParse(sale['salesman_id']?.toString() ?? '');
      final deliveryBoyId =
          int.tryParse(sale['delivery_boy_id']?.toString() ?? '');
      final saleSourceId =
          int.tryParse(sale['sale_source_id']?.toString() ?? '');
      final saleAreaId = int.tryParse(sale['area_id']?.toString() ?? '');

      discountController.text = _editNum(sale['discount']).toStringAsFixed(2);
      taxController.text = _editNum(sale['tax']).toStringAsFixed(2);
      shippingController.text = _editNum(sale['delivery']).toStringAsFixed(2);

      if (customerId != null) {
        customerNameController.text = [
          (customer['first_name'] ?? '').toString(),
          (customer['last_name'] ?? '').toString(),
        ].where((v) => v.trim().isNotEmpty).join(' ').trim();
        customerPhoneController.text = (customer['phone'] ?? '').toString();
        addressController.text = (customer['address'] ?? '').toString();
      } else {
        customerNameController.text =
            (customerSnapshot['name'] ?? 'Walk-in customer').toString();
        customerPhoneController.text =
            (customerSnapshot['phone'] ?? '').toString();
        addressController.text =
            (customerSnapshot['address'] ?? '').toString();
      }

      final selectedCustomerForEdit = customerId == null
          ? null
          : <String, dynamic>{
              ...customer,
              if (customerSnapshot.containsKey('phone_numbers'))
                'phone_numbers': customerSnapshot['phone_numbers'],
            };

      setState(() {
        _editSale = sale;
        _editRevision =
            int.tryParse(sale['revision_no']?.toString() ?? '') ?? 0;
        _originalTotal = _editNum(sale['total']);
        _existingNetPaid = _editNum(sale['net_paid']);
        _items = items;
        _originalItems = items
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _selectedCustomerId = customerId?.toString();
        _selectedCustomer = selectedCustomerForEdit;
        _selectedVendorId = vendorId;
        _selectedVendor = vendorId == null ? null : vendor;
        _selectedUserId = salesmanId;
        _selectedUser = salesmanId == null ? null : salesman;
        _selectedDeliveryBoyId = deliveryBoyId;
        _selectedDeliveryBoy = deliveryBoyId == null ? null : deliveryBoy;
        _selectedSaleSourceId = saleSourceId;
        _selectedAreaId = saleAreaId;
        _selectedBranchId = sale['branch_id']?.toString();
        _selectedBranch = branch.isEmpty ? null : branch;
        _customerLocked = true;
        _payments = const [];
      });

      // Sale sources are branch-owned. initState cannot load them for an
      // amendment because the invoice branch is not known until the sale has
      // been fetched above. Load them now, after both the branch and the saved
      // sale_source_id are established, so "Sale From" is auto-selected
      // deterministically instead of depending on the catalog-refresh race.
      await _loadSaleSources();
      await _loadCustomerAreas();
      if (!mounted) return;
      setState(() => _editLoading = false);
      _productSearchFocusNode.requestFocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _editLoading = false;
        _editLoadError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _editLoading = false;
        _editLoadError = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _resetAmendmentDraft() {
    if (!_isEditing || _editSale == null) return;
    final sale = _editSale!;
    setState(() {
      _items = _originalItems
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: true);
      discountController.text = _editNum(sale['discount']).toStringAsFixed(2);
      taxController.text = _editNum(sale['tax']).toStringAsFixed(2);
      shippingController.text = _editNum(sale['delivery']).toStringAsFixed(2);
      _selectedVendorId = int.tryParse(sale['vendor_id']?.toString() ?? '');
      _selectedVendor = _selectedVendorId == null
          ? null
          : _mapValue(sale['vendor']);
      _selectedUserId = int.tryParse(sale['salesman_id']?.toString() ?? '');
      _selectedUser = _selectedUserId == null
          ? null
          : _mapValue(sale['salesman']);
      _selectedDeliveryBoyId =
          int.tryParse(sale['delivery_boy_id']?.toString() ?? '');
      _selectedDeliveryBoy = _selectedDeliveryBoyId == null
          ? null
          : _mapValue(sale['delivery_boy']);
      _selectedSaleSourceId =
          int.tryParse(sale['sale_source_id']?.toString() ?? '');
    });
  }

  _AmendmentDiff _amendmentDiff({bool sourceChanged = false}) {
    final beforeById = <int, Map<String, dynamic>>{};
    for (final item in _originalItems) {
      final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
      if (id != null) beforeById[id] = item;
    }
    final afterIds = <int>{};
    var added = 0;
    var quantityChanged = 0;
    var priceChanged = 0;
    var discountChanged = 0;
    for (final item in _items) {
      final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
      if (id == null) {
        added++;
        continue;
      }
      afterIds.add(id);
      final old = beforeById[id];
      if (old == null) {
        added++;
        continue;
      }
      if ((_editNum(old['quantity']) - _editNum(item['quantity'])).abs() > .0004) {
        quantityChanged++;
      }
      if ((_editNum(old['price']) - _editNum(item['price'])).abs() > .0004) {
        priceChanged++;
      }
      if ((_editNum(old['discount_pct']) -
                  _editNum(item['discount_pct']))
              .abs() >
          .0004 ||
          (old['discount_type'] ?? 'percentage').toString() !=
              (item['discount_type'] ?? 'percentage').toString()) {
        discountChanged++;
      }
    }
    final removed = beforeById.keys.where((id) => !afterIds.contains(id)).length;
    return _AmendmentDiff(
      added: added,
      removed: removed,
      quantityChanged: quantityChanged,
      priceChanged: priceChanged,
      discountChanged: discountChanged,
      sourceChanged: sourceChanged,
    );
  }

  Future<void> _submitAmendment() async {
    if (_editSale == null || widget.editSaleId == null) {
      AppFeedback.error(context, 'The posted sale is not loaded yet.');
      return;
    }
    final invoiceBranchId = int.tryParse(_selectedBranchId ?? '');
    final workingBranchId = context.read<BranchProvider>().selectedBranchId;
    if (invoiceBranchId == null || workingBranchId != invoiceBranchId) {
      AppFeedback.warning(
        context,
        'This invoice belongs to Branch #${invoiceBranchId ?? '-'}.'
        ' Switch back to that branch before saving this amendment.',
      );
      return;
    }
    if (_items.isEmpty) {
      AppFeedback.warning(
        context,
        'A posted invoice must keep at least one item. Use the return/void workflow to reverse the entire invoice.',
      );
      return;
    }
    final quantityViolation = _firstQuantityViolation();
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return;
    }

    double subtotal = 0;
    for (final item in _items) {
      subtotal += _lineTotal(
        price: _editNum(item['price']),
        qty: _editNum(item['quantity']),
        discPct: _editNum(item['discount_pct']),
        discountType: (item['discount_type'] ?? 'percentage').toString(),
      );
    }
    final discount = _toDouble(discountController);
    final tax = _toDouble(taxController);
    final delivery = _toDouble(shippingController);
    final revisedTotal = subtotal - discount + tax + delivery;
    if (revisedTotal < -0.004) {
      AppFeedback.warning(
        context,
        'The revised invoice total cannot be negative. Use the return/refund workflow instead.',
      );
      return;
    }

    final sourceChanged =
        int.tryParse(_editSale!['sale_source_id']?.toString() ?? '') !=
            _selectedSaleSourceId;
    final diff = _amendmentDiff(sourceChanged: sourceChanged);
    final saleLevelChanged =
        (_editNum(_editSale!['discount']) - discount).abs() > .004 ||
            (_editNum(_editSale!['tax']) - tax).abs() > .004 ||
            (_editNum(_editSale!['delivery']) - delivery).abs() > .004 ||
            int.tryParse(_editSale!['vendor_id']?.toString() ?? '') !=
                _selectedVendorId ||
            int.tryParse(_editSale!['salesman_id']?.toString() ?? '') !=
                _selectedUserId ||
            int.tryParse(_editSale!['delivery_boy_id']?.toString() ?? '') !=
                _selectedDeliveryBoyId ||
            sourceChanged;
    if (!diff.hasChanges && !saleLevelChanged) {
      AppFeedback.info(context, 'There are no changes to save.');
      return;
    }

    final profit = SaleProfitCalculator.invoice(
      items: _items,
      invoiceDiscount: discount,
      shippingRevenue: delivery,
      tax: tax,
    );
    final pm = context.read<PaymentMethodProvider>();
    final paymentMethods = pm.activeMethods
        .map((m) => _AmendmentPaymentMethod(m.method, m.displayName))
        .toList(growable: false);
    final decision = await showDialog<_AmendmentReviewDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaleAmendmentReviewDialog(
        invoiceNo: (_editSale!['invoice_no'] ?? widget.editSaleId).toString(),
        revision: _editRevision,
        originalTotal: _originalTotal,
        revisedTotal: revisedTotal,
        netPaid: _existingNetPaid,
        customerAttached: _selectedCustomerId != null,
        deliverySale: _selectedDeliveryBoyId != null,
        diff: diff,
        profit: context.read<AuthProvider>().hasPermission('view-sale-profit')
            ? profit
            : null,
        paymentMethods: paymentMethods,
      ),
    );
    if (!mounted || decision == null) return;

    final payload = <String, dynamic>{
      'expected_revision': _editRevision,
      'reason': decision.reason,
      'items': _items.map((item) {
        final id = int.tryParse(item['sale_item_id']?.toString() ?? '');
        return <String, dynamic>{
          if (id != null) 'sale_item_id': id,
          'product_id': int.tryParse(item['product_id']?.toString() ?? '') ?? 0,
          'quantity': _editNum(item['quantity']),
          'price': _editNum(item['price']),
          'discount_pct': _editNum(item['discount_pct']),
          'discount_type':
              (item['discount_type'] ?? 'percentage').toString(),
        };
      }).toList(growable: false),
      'discount': discount,
      'tax': tax,
      'delivery': delivery,
      'vendor_id': _selectedVendorId,
      'salesman_id': _selectedUserId,
      'delivery_boy_id': _selectedDeliveryBoyId,
      'sale_source_id': _selectedSaleSourceId,
      if (decision.settlementAction != 'none')
        'settlement': <String, dynamic>{
          'action': decision.settlementAction,
          'amount': decision.settlementAmount,
          'method': decision.settlementMethod,
          if (decision.reference.trim().isNotEmpty)
            'reference': decision.reference.trim(),
          'note': 'Sale amendment revision ${_editRevision + 1}',
        },
    };

    setState(() => _submitting = true);
    Object? submitError;
    Map<String, dynamic>? response;
    try {
      try {
        response = await _saleService
            .amendSale(widget.editSaleId!, payload)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        submitError = e;
      }

      final creditIssue = submitError == null
          ? null
          : CreditLimitIssue.fromException(submitError!);
      if (creditIssue != null) {
        final auth = context.read<AuthProvider>();
        if (!creditIssue.canOverride ||
            !auth.hasPermission('override-party-credit-limit')) {
          if (mounted) AppFeedback.error(context, creditIssue.summary);
          return;
        }
        final overrideReason = await showCreditLimitOverrideDialog(
          context,
          creditIssue,
        );
        if (!mounted || overrideReason == null) return;
        payload['credit_limit_override'] = {'reason': overrideReason};
        submitError = null;
        try {
          response = await _saleService
              .amendSale(widget.editSaleId!, payload)
              .timeout(const Duration(seconds: 20));
        } catch (e) {
          submitError = e;
        }
      }

      if (submitError != null) {
        final e = submitError!;
        if (!mounted) return;
        if (e is ApiException && e.statusCode == 409) {
          AppFeedback.error(
            context,
            'This invoice was changed on another terminal. Your draft was not saved. Reload the invoice before applying it again.',
          );
        } else if (e is ApiException) {
          _applyServerLineErrors(e);
          AppFeedback.error(context, _describeRejection(e));
        } else {
          AppFeedback.error(
            context,
            'Sale amendment was not saved. Posted-sale editing requires an online server connection. $e',
          );
        }
        return;
      }

      if (!mounted) return;
      final amendment = _mapValue(_mapValue(response?['data'])['amendment']);
      final revision =
          amendment['revision_no']?.toString() ?? '${_editRevision + 1}';
      AppFeedback.success(
        context,
        'Sale amended successfully • Revision $revision. Original financial history was preserved.',
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  /// Seeds the product/customer instant-suggestion buckets from the local
  /// catalog cache so the pickers show data even offline / after a restart.
  void _hydrateOfflinePickers(int? branchIdInt) {
    ProductPickCache.hydrateFromCatalog(vendorId: _selectedVendorId, branchId: branchIdInt);
    CustomerPickCache.hydrateFromCatalog(branchId: branchIdInt);
  }

  Future<void> _openItemPickerOnFirstLoad() async {
    if (_didAutoOpenPicker || !mounted) return;
    _didAutoOpenPicker = true;
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted || _items.isNotEmpty) return;
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) return;
    await _addItemManual();
  }

  @override
  void dispose() {
    discountController.dispose();
    taxController.dispose();
    shippingController.dispose();
    cashReceivedController.dispose();
    saleReferenceController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _pageFocusNode.dispose();
    addressController.dispose();
    customerNameController.dispose();
    customerPhoneController.dispose();
    _customerFocusNode.dispose();
    _salesmanFocusNode.dispose();
    _deliveryBoyFocusNode.dispose();
    _vendorFocusNode.dispose();
    _productSearchFocusNode.dispose();
    _customerController.dispose();
    _salesmanController.dispose();
    _deliveryBoyController.dispose();
    _vendorController.dispose();
    _productSearchController.dispose();
    _walkInNameFocusNode.dispose();
    _walkInPhoneFocusNode.dispose();
    _walkInAddressFocusNode.dispose();
    _discountFocusNode.dispose();
    _taxFocusNode.dispose();
    _shippingFocusNode.dispose();
    _cashReceivedFocusNode.dispose();
    super.dispose();
  }

  // ---------------- Pickers ----------------
  // Future<void> _pickBranch() async {
  //   final token = Provider.of<AuthProvider>(context, listen: false).token!;
  //   final branch = await showModalBottomSheet<Map<String, dynamic>>(
  //     context: context,
  //     builder: (_) => BranchPickerSheet(token: token),
  //   );
  //   if (!mounted) return;
  //   if (branch != null) {
  //     setState(() {
  //       _selectedBranch = branch;
  //       _selectedBranchId = branch['id'].toString();
  //     });
  //   }
  // }

  /// Opens the full customer browse sheet and returns whatever was picked
  /// (null means "cleared / walk-in"). Used both as the manual "Select
  /// Customer" action and as the autocomplete field's "Browse all" fallback.
  Future<Map<String, dynamic>?> _openCustomerSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPickerSheet(token: token),
    );
  }

  void _applyCustomerSelection(Map<String, dynamic>? customer) {
    if (!mounted) return;
    if (customer == null) {
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _selectedAreaId = null;
        _customerLocked = false;

        // Option A: clear on unselect
        customerNameController.text = "";
        customerPhoneController.text = "";
        addressController.text = "";
      });
    } else {
      final address = (customer['address'] ?? "").toString();
      final name = (customer['first_name'] ?? "").toString();
      final phone = (customer['phone'] ?? "").toString();
      setState(() {
        _selectedCustomer = customer;
        _selectedCustomerId = customer['id'].toString();
        // Keep the customer's default id even if the area list is still
        // loading. Once reference data arrives, _loadCustomerAreas validates
        // that it is still an active value for this branch.
        _selectedAreaId = _metaInt(customer['area_id']);
        customerNameController.text = name;
        customerPhoneController.text = phone;
        addressController.text = address;

        _customerLocked = true; // lock editing when customer picked
      });
    }
    _restoreSaleScreenFocus();
  }

  Future<void> _pickCustomer() async {
    final customer = await _openCustomerSheet();
    _applyCustomerSelection(customer);
  }

  void _clearCustomerSelection() {
    setState(() {
      _selectedCustomer = null;
      _selectedCustomerId = null;
      _selectedAreaId = null;
      _customerLocked = false;
      customerNameController.text = "";
      customerPhoneController.text = "";
      addressController.text = "";
    });
  }

  Future<Map<String, dynamic>?> _openVendorSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VendorPickerSheet(token: token),
    );
  }

  void _applyVendorSelection(Map<String, dynamic>? vendor) {
    if (!mounted) return;
    setState(() {
      _selectedVendor = vendor;
      _selectedVendorId = _metaInt(vendor?['id']);
      if (!_isEditing) _items = []; // avoid cross-vendor mix on a new sale
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickVendor() async {
    if (!context.read<BranchFeatureProvider>().saleVendorEnabled) return;
    final vendor = await _openVendorSheet();
    _applyVendorSelection(vendor);
  }

  String _effectiveBranchIdStr() {
    // A posted invoice never changes branch. Keep all amendment pickers and
    // product lookups pinned to the invoice branch even if Master Admin
    // switches the app's working branch in another surface while this draft
    // is open. The backend will still reject Save until the user switches
    // back, so no cross-branch mutation can slip through.
    if (_isEditing) return _selectedBranchId ?? '';
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    return globalBranchId?.toString() ?? _selectedBranchId ?? '';
  }

  Future<Map<String, dynamic>?> _openUserSheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(token: token, branchId: _effectiveBranchIdStr()),
    );
  }

  void _applyUserSelection(Map<String, dynamic>? user) {
    if (!mounted) return;
    setState(() {
      _selectedUser = user;
      _selectedUserId = _metaInt(user?['id']);
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickUser() async {
    final user = await _openUserSheet();
    _applyUserSelection(user);
  }

  Future<Map<String, dynamic>?> _openDeliveryBoySheet() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UserPickerSheet(
        token: token,
        branchId: _effectiveBranchIdStr(),
        role: 'delivery',
        title: 'Select Delivery Boy',
        searchHint: 'Search delivery boy by name, email, phone…',
        allowQuickAdd: false,
      ),
    );
  }

  void _applyDeliveryBoySelection(Map<String, dynamic>? user) {
    if (!mounted) return;
    setState(() {
      _selectedDeliveryBoy = user;
      _selectedDeliveryBoyId = _metaInt(user?['id']);
    });
    _restoreSaleScreenFocus();
  }

  Future<void> _pickDeliveryBoy() async {
    if (!context.read<BranchFeatureProvider>().deliveryEnabled) return;
    final user = await _openDeliveryBoySheet();
    _applyDeliveryBoySelection(user);
  }

  // ---------------- Items ----------------

  /// Centralized single-product add for barcode, autocomplete, and product
  /// panel taps. If a compatible positive-qty row already exists it is
  /// incremented by 1; otherwise a new row is appended.
  ///
  /// "Compatible" means same [product_id] AND non-negative quantity so that
  /// deliberate inline-return rows (negative qty) are never merged into a
  /// normal sale line.
  ///
  /// Call inside setState — does NOT call setState itself.
  void _addOrIncrementProduct(Map<String, dynamic> product) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;
    final pickerAddQty =
        double.tryParse(product['_picker_add_qty']?.toString() ?? '');
    final addQty = pickerAddQty != null && pickerAddQty > 0 ? pickerAddQty : 1.0;

    final price = SalePricing.effectiveProductPrice(
      product,
      customerType: _selectedCustomerType,
    );
    final profitCostFields =
        SaleProfitCalculator.costFieldsFromProduct(product);

    final idx = _items.indexWhere((it) {
      final existingId =
          int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
      if (existingId != productId) return false;
      // Do not merge into inline-return (negative-qty) rows.
      final existingQty =
          double.tryParse(it['quantity']?.toString() ?? '') ?? 0.0;
      return existingQty >= 0;
    });

    if (idx != -1) {
      // Increment quantity while preserving edited price, discount, and type.
      final existingQty =
          double.tryParse(_items[idx]['quantity']?.toString() ?? '') ?? 0.0;
      final newQty = existingQty + addQty;
      final discPct =
          double.tryParse(_items[idx]['discount_pct']?.toString() ?? '') ?? 0.0;
      final rowDiscType =
          (_items[idx]['discount_type'] ?? 'percentage').toString();
      final rowPrice =
          double.tryParse(_items[idx]['price']?.toString() ?? '') ?? price;
      _items[idx]['quantity'] = newQty;
      _items[idx].addAll(profitCostFields);
      _items[idx]['product_vendor_id'] =
          int.tryParse(product['vendor_id']?.toString() ?? '');
      final productVendorName = (product['vendor_name'] ?? '').toString().trim();
      _items[idx]['product_vendor_name'] =
          productVendorName.isEmpty ? null : productVendorName;
      if ((product['secondary_name'] ?? '').toString().trim().isNotEmpty) {
        _items[idx]['secondary_name'] = product['secondary_name'];
      }
      _items[idx]['total'] =
          _lineTotal(price: rowPrice, qty: newQty, discPct: discPct, discountType: rowDiscType);
    } else {
      final scanDiscPct  = double.tryParse(product['discount']?.toString() ?? '') ?? 0.0;
      final scanDiscType = (product['discount_type'] ?? 'percentage').toString();
      _items.add({
        'product_id': productId,
        'product_vendor_id': int.tryParse(product['vendor_id']?.toString() ?? ''),
        'product_vendor_name': (product['vendor_name'] ?? '').toString().trim().isEmpty
            ? null
            : (product['vendor_name'] ?? '').toString().trim(),
        'name': product['name'],
        'secondary_name': product['secondary_name'],
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        ...profitCostFields,
        'quantity': addQty,
        'price': price,
        'discount_pct': scanDiscPct,
        'discount_type': scanDiscType,
        'total': _lineTotal(price: price, qty: addQty, discPct: scanDiscPct, discountType: scanDiscType),
        // Stamp the quantity contract onto the line — the product map this
        // came from (search hit, scan lookup, cache row) is not kept.
        ...QuantityRule.fromProduct(product).toRowFields(),
      });
    }
  }

  /// Sets a product's cart quantity to an explicit [qty] value (used only by
  /// the F2 multi-select picker where the user has intentionally specified the
  /// quantity). Preserves the existing row's price and discount when updating.
  ///
  /// For all single-product entry points (barcode, autocomplete, product-panel
  /// tap) use [_addOrIncrementProduct] instead.
  ///
  /// Call inside setState — does NOT call setState itself.
  void _applyPickedProduct(Map<String, dynamic> product, {double qty = 1.0}) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;

    final price = SalePricing.effectiveProductPrice(
      product,
      customerType: _selectedCustomerType,
    );
    final profitCostFields =
        SaleProfitCalculator.costFieldsFromProduct(product);

    final idx = _items.indexWhere(
      (it) => (int.tryParse(it["product_id"].toString()) ?? 0) == productId,
    );

    if (idx != -1) {
      _items[idx]["quantity"] = qty;
      _items[idx].addAll(profitCostFields);
      _items[idx]['product_vendor_id'] =
          int.tryParse(product['vendor_id']?.toString() ?? '');
      final productVendorName = (product['vendor_name'] ?? '').toString().trim();
      _items[idx]['product_vendor_name'] =
          productVendorName.isEmpty ? null : productVendorName;
      if ((product['secondary_name'] ?? '').toString().trim().isNotEmpty) {
        _items[idx]['secondary_name'] = product['secondary_name'];
      }
      final discPct =
          double.tryParse(_items[idx]["discount_pct"]?.toString() ?? '') ?? 0.0;
      final existingDiscType =
          (_items[idx]["discount_type"] ?? 'percentage').toString();
      final rowPrice =
          double.tryParse(_items[idx]["price"]?.toString() ?? '') ?? price;
      _items[idx]["total"] = _lineTotal(price: rowPrice, qty: qty, discPct: discPct, discountType: existingDiscType);
      // Refresh the rule too: the picker may know the unit for a line that was
      // added before the unit was known (e.g. from a stale cache row).
      _items[idx].addAll(QuantityRule.fromProduct(product).toRowFields());
    } else {
      final pickDiscPct  = double.tryParse(product['discount']?.toString() ?? '') ?? 0.0;
      final pickDiscType = (product['discount_type'] ?? 'percentage').toString();
      _items.add({
        "product_id": productId,
        "product_vendor_id": int.tryParse(product['vendor_id']?.toString() ?? ''),
        "product_vendor_name": (product['vendor_name'] ?? '').toString().trim().isEmpty
            ? null
            : (product['vendor_name'] ?? '').toString().trim(),
        "name": product['name'],
        "secondary_name": product['secondary_name'],
        "cost_price": product['cost_price'],
        "wholesale_price": product['wholesale_price'],
        ...profitCostFields,
        "quantity": qty,
        "price": price,
        "discount_pct": pickDiscPct,
        "discount_type": pickDiscType,
        "total": _lineTotal(price: price, qty: qty, discPct: pickDiscPct, discountType: pickDiscType),
        ...QuantityRule.fromProduct(product).toRowFields(),
      });
    }
  }

  Future<void> _addItemManual() async {
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    if (auth.isMasterAdmin && !branch.hasActiveBranch) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before selecting items.');
      return;
    }
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    // ✅ Already selected products in cart/items (for preselect)
    final alreadySelectedIds = _items
        .map((e) => int.tryParse(e["product_id"].toString()) ?? 0)
        .where((id) => id > 0)
        .toList();

    // ✅ Already selected qty map (id -> qty)
    final alreadySelectedQty = <int, double>{
      for (final it in _items)
        (int.tryParse(it["product_id"].toString()) ?? 0):
            (double.tryParse(it["quantity"].toString()) ?? 1.0),
    }..removeWhere((k, _) => k == 0);

    final picked = await ProductPickerGridSheet.openMulti(
      context,
      token: token,
      vendorId: _selectedVendorId,
      customerType: _selectedCustomerType,
      alreadySelectedIds: alreadySelectedIds,
      alreadySelectedQty: alreadySelectedQty,
      alreadySelectedProducts: _items.map((item) {
        return {
          'id': item['product_id'],
          'name': item['name'],
          'secondary_name': item['secondary_name'],
          'price': item['price'],
          'cost_price': item['cost_price'],
          'wholesale_price': item['wholesale_price'],
          SaleProfitCalculator.unitCostKey:
              item[SaleProfitCalculator.unitCostKey],
          SaleProfitCalculator.estimatedKey:
              item[SaleProfitCalculator.estimatedKey],
          SaleProfitCalculator.sourceKey:
              item[SaleProfitCalculator.sourceKey],
        };
      }).toList(),
    );

    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final x in picked) {
        final product = (x["product"] as Map?)?.cast<String, dynamic>();
        final qty = (x["qty"] as num?)?.toDouble() ?? 1.0;
        if (product == null) continue;
        _applyPickedProduct(product, qty: qty);
      }
    });
  }

  void _editItem(int index) {
    final item = _items[index];
    final qtyController = TextEditingController(
      text: item['quantity'].toString(),
    );
    final priceController = TextEditingController(
      text: item['price'].toString(),
    );

    final costPrice = item['cost_price'] ?? 0.0;
    final wholesalePrice = item['wholesale_price'] ?? 0.0;
    final rule = QuantityRule.fromProduct(item);

    bool showHidden = false;
    String? qtyError;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text("Edit ${item['name']}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: rule.allowDecimal,
                    signed: true,
                  ),
                  onChanged: (v) =>
                      setLocal(() => qtyError = rule.validateText(v)),
                  decoration: InputDecoration(
                    labelText: "Quantity",
                    helperText: rule.allowDecimal
                        ? null
                        : 'Whole numbers only${rule.unitName.isEmpty ? '' : ' (${rule.unitName})'}',
                    errorText: qtyError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Sale Price"),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: Icon(
                    showHidden ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(
                    showHidden ? "Hide Cost/Wholesale" : "Show Cost/Wholesale",
                  ),
                  onPressed: () => setLocal(() => showHidden = !showHidden),
                ),
                if (showHidden) ...[
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Cost Price: ${AppCurrency.format(costPrice)}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          "Wholesale Price: ${AppCurrency.format(wholesalePrice)}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  final error = rule.validateText(qtyController.text);
                  if (error != null) {
                    // Block rather than round: a rounded quantity would post
                    // stock and money the cashier never agreed to.
                    setLocal(() => qtyError = error);
                    return;
                  }
                  setState(() {
                    _items[index]['quantity'] =
                        double.tryParse(qtyController.text.trim()) ?? 1.0;
                    _items[index]['price'] =
                        double.tryParse(priceController.text) ?? 0.0;
                  });
                  Navigator.pop(context);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  SaleProfitSummary _currentProfitSummary() {
    // A linked return reverses the historical sale using the original item's
    // cost/discount/tax allocation on the backend. Do not mix it with the
    // live profit preview for newly sold items (which is based on today's
    // inventory carrying cost and the new invoice header values).
    final positiveItems = _items
        .where((item) => _metaNum(item['quantity']) > 0)
        .toList(growable: false);
    return SaleProfitCalculator.invoice(
      items: positiveItems,
      invoiceDiscount: _toDouble(discountController),
      shippingRevenue: _toDouble(shippingController),
      tax: _toDouble(taxController),
    );
  }

  void _showItemProfitInsight(int index) {
    if (!context.read<AuthProvider>().hasPermission('view-sale-profit')) return;
    if (index < 0 || index >= _items.length) return;
    if (_items[index]['original_sale_item_id'] != null) {
      AppFeedback.warning(
        context,
        'Return profit/cost is reversed from the original sale and is not editable in the live sale-profit preview.',
      );
      return;
    }
    final positiveIndex = _items
        .take(index)
        .where((item) => _metaNum(item['quantity']) > 0)
        .length;
    final summary = _currentProfitSummary();
    if (positiveIndex >= summary.lines.length) return;
    showSaleLineProfitDialog(context, summary.lines[positiveIndex]);
  }

  void _showInvoiceProfitDetails() {
    if (!context.read<AuthProvider>().hasPermission('view-sale-profit')) return;
    showSaleProfitDetailsDialog(context, _currentProfitSummary());
  }

  // ---------------- Barcode ----------------
  Future<void> _onBarcodeScanned(String code) async {
    if (code.isEmpty) return;

    // Try the live lookup first; if the server is unreachable, fall back to
    // the local catalog cache so scanning still works offline (handover doc
    // G1). getProductByBarcode returns null for "not found" and throws for a
    // network error — both fall through to the cache.
    Map<String, dynamic>? product;
    try {
      product = await _productService.getProductByBarcode(
        code,
        vendorId: _selectedVendorId,
      );
    } catch (_) {
      product = null;
    }
    product ??= await CatalogCacheService.instance.productByBarcode(
      code,
      branchId: int.tryParse(_effectiveBranchIdStr()),
      vendorId: _selectedVendorId,
    );
    if (product != null) {
      // Capture into a final local so Dart flow analysis narrows the type
      // inside the setState closure (local variable reassigned via ??= above
      // prevents automatic narrowing inside lambdas).
      final p = product;
      // Use the centralized merge method so repeated scans of the same
      // barcode increment the existing cart row instead of creating duplicates.
      setState(() => _addOrIncrementProduct(p));
    } else {
      if (!mounted) return;
      AppFeedback.warning(context, "Product not found: $code");
    }
    _barcodeController.clear();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  double _lineTotal({
    required double price,
    required double qty,
    required double discPct,
    String discountType = 'percentage',
  }) {
    final double t;
    if (discountType == 'fixed') {
      // discPct holds the fixed amount off per unit
      t = qty * (price - discPct);
    } else {
      final d = (discPct / 100.0).clamp(0.0, 100.0);
      t = qty * price * (1.0 - d);
    }
    return t.isFinite ? t : 0.0;
  }

  double _cartLineTotal(Map<String, dynamic> item) {
    final qty = _metaNum(item['quantity']);
    if (qty < 0 && item['original_sale_item_id'] != null) {
      return -_metaNum(item['return_credit']).abs();
    }
    return _lineTotal(
      price: _metaNum(item['price']),
      qty: qty,
      discPct: _metaNum(item['discount_pct']),
      discountType: (item['discount_type'] ?? 'percentage').toString(),
    );
  }

  double get _linkedReturnCredit => _items
      .where((i) => _metaNum(i['quantity']) < 0 && i['original_sale_item_id'] != null)
      .fold<double>(0, (sum, i) => sum + _metaNum(i['return_credit']).abs());

  double get _linkedReturnOriginalOutstanding {
    for (final item in _items) {
      if (_metaNum(item['quantity']) < 0 && item['original_sale_item_id'] != null) {
        return _metaNum(item['return_original_outstanding']);
      }
    }
    return 0;
  }

  Future<Map<String, String>?> _askReturnSource({
    String initialInvoice = '',
    String initialReason = '',
  }) {
    final seededInvoice = initialInvoice.trim().isNotEmpty
        ? initialInvoice.trim()
        : (widget.initialReturnInvoice ?? '').trim();
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReturnSourceDialog(
        initialInvoice: seededInvoice,
        initialReason: initialReason,
      ),
    );
  }

  Future<Map<String, dynamic>?> _chooseReturnSourceItem(List<dynamic> candidates) async {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1 && candidates.first is Map) {
      return Map<String, dynamic>.from(candidates.first as Map);
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select original sale line'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final row = Map<String, dynamic>.from(candidates[index] as Map);
              return ListTile(
                title: Text((row['product_name'] ?? 'Product').toString()),
                subtitle: Text(
                  'Sold ${row['sold_qty']} • Returned ${row['returned_qty']} • Returnable ${row['returnable_qty']}',
                ),
                trailing: Text(
                  AppCurrency.format(_metaNum(row['return_credit'])),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<bool> _linkReturnForRow(int index, double quantity) async {
    if (!mounted || index < 0 || index >= _items.length || quantity <= 0) return false;
    final current = Map<String, dynamic>.from(_items[index]);
    final productId = _metaInt(current['product_id']);
    if (productId == null || productId <= 0) return false;

    final wasLinked = current['original_sale_item_id'] != null;
    String invoice = (current['return_source_invoice'] ?? '').toString().trim();
    String reason = (current['return_reason'] ?? '').toString().trim();
    if (!wasLinked) {
      String defaultInvoice = (widget.initialReturnInvoice ?? '').trim();
      for (final row in _items) {
        if (row['original_sale_item_id'] != null) {
          defaultInvoice = (row['return_source_invoice'] ?? '').toString();
          break;
        }
      }
      final request = await _askReturnSource(initialInvoice: defaultInvoice);
      if (!mounted) return false;
      if (request == null) {
        setState(() {
          if (index < _items.length && _items[index]['original_sale_item_id'] == null) {
            _items[index]['quantity'] = quantity;
            _items[index]['total'] = _cartLineTotal(_items[index]);
          }
        });
        return false;
      }
      invoice = request['invoice']!;
      reason = request['reason']!;
    }

    for (int i = 0; i < _items.length; i++) {
      if (i == index) continue;
      final otherInvoice = (_items[i]['return_source_invoice'] ?? '').toString().trim();
      if (_items[i]['original_sale_item_id'] != null && otherInvoice.isNotEmpty && otherInvoice != invoice) {
        AppFeedback.warning(context, 'All returned items in one transaction must come from the same original invoice ($otherInvoice).');
        if (!wasLinked) setState(() => _items[index]['quantity'] = quantity);
        return false;
      }
    }

    try {
      final data = await _saleService.getReturnSource(
        invoice: invoice,
        productId: productId,
        quantity: quantity,
      );
      if (!mounted) return false;
      final candidates = data['items'] is List ? data['items'] as List : const <dynamic>[];
      Map<String, dynamic>? picked;
      if (wasLinked) {
        final existingId = _metaInt(current['original_sale_item_id']);
        for (final raw in candidates) {
          if (raw is Map && _metaInt(raw['sale_item_id']) == existingId) {
            picked = Map<String, dynamic>.from(raw);
            break;
          }
        }
      }
      picked ??= await _chooseReturnSourceItem(candidates);
      if (!mounted || picked == null) {
        if (!wasLinked) setState(() => _items[index]['quantity'] = quantity);
        return false;
      }
      final sale = data['sale'] is Map ? Map<String, dynamic>.from(data['sale'] as Map) : <String, dynamic>{};
      final sourceSaleId = _metaInt(sale['id']);
      if (sourceSaleId == null) throw Exception('Original sale could not be resolved.');

      final customer = sale['customer'];
      if (customer is Map) {
        _applyCustomerSelection(Map<String, dynamic>.from(customer));
      } else {
        _applyCustomerSelection(null);
      }

      final updated = Map<String, dynamic>.from(current)
        ..['original_sale_id'] = sourceSaleId
        ..['original_sale_item_id'] = _metaInt(picked['sale_item_id'])
        ..['return_source_invoice'] = (sale['invoice_no'] ?? invoice).toString()
        ..['return_reason'] = reason
        ..['returnable_quantity'] = _metaNum(picked['returnable_qty'])
        ..['return_original_outstanding'] = _metaNum(sale['outstanding'])
        ..['return_credit'] = _metaNum(picked['return_credit'])
        ..['return_merchandise_subtotal'] = _metaNum(picked['merchandise_subtotal'])
        ..['return_invoice_discount'] = _metaNum(picked['invoice_discount_allocated'])
        ..['return_tax'] = _metaNum(picked['tax_allocated'])
        ..['return_linked_quantity'] = quantity
        ..['price'] = _metaNum(picked['original_price'])
        ..['discount_pct'] = _metaNum(picked['line_discount'])
        ..['discount_type'] = (picked['discount_type'] ?? 'percentage').toString()
        ..['quantity'] = -quantity
        ..['total'] = -_metaNum(picked['return_credit']).abs();
      setState(() {
        _items[index] = updated;
        // Return linkage can materially change what is payable/refundable.
        // Stale split-tender amounts must never survive that recalculation.
        _payments = [];
        cashReceivedController.clear();
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = e is ApiException ? e.message : e.toString().replaceFirst('Exception: ', '');
      AppFeedback.error(context, message);
      setState(() {
        if (index >= _items.length) return;
        if (wasLinked) {
          final previous = _metaNum(current['return_linked_quantity']);
          _items[index] = current;
          if (previous > 0) _items[index]['quantity'] = -previous;
        } else {
          _items[index]['quantity'] = quantity;
          _items[index].remove('original_sale_id');
          _items[index].remove('original_sale_item_id');
        }
        _items[index]['total'] = _cartLineTotal(_items[index]);
      });
      return false;
    }
  }

  Widget _hiddenBarcodeField() {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: TextField(
          controller: _barcodeController,
          focusNode: _barcodeFocusNode,
          autofocus: false,
          onSubmitted: _onBarcodeScanned,
        ),
      ),
    );
  }


  double _metaNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _metaText(dynamic value) => (value ?? '').toString().trim();

  Map<String, dynamic>? _partySnapshot(
    Map<String, dynamic>? source, {
    dynamic id,
    String fallbackName = '',
  }) {
    if (source == null && id == null && fallbackName.trim().isEmpty) return null;

    dynamic read(String key) => source == null ? null : source[key];

    final firstName = _metaText(read('first_name'));
    final lastName = _metaText(read('last_name'));
    final directName = _metaText(read('name'));
    final fallback = fallbackName.trim();
    final combinedName = directName.isNotEmpty
        ? directName
        : [firstName, lastName].where((v) => v.isNotEmpty).join(' ').trim();

    final snapshot = <String, dynamic>{};
    final resolvedId = id ?? read('id');
    if (resolvedId != null) snapshot['id'] = resolvedId;

    final resolvedName = combinedName.isNotEmpty ? combinedName : fallback;
    if (resolvedName.isNotEmpty) snapshot['name'] = resolvedName;

    for (final key in const ['first_name', 'last_name', 'phone', 'mobile', 'email', 'address']) {
      final value = _metaText(read(key));
      if (value.isNotEmpty) snapshot[key] = value;
    }

    return snapshot.isEmpty ? null : snapshot;
  }

  Map<String, dynamic> _buildSaleMeta({
    required String? effectiveBranchId,
    required double subtotal,
    required double discount,
    required double tax,
    required double shipping,
    required double total,
    required double paid,
    required double balance,
    required double cashReceived,
    required double changeAmount,
    required List<Map<String, dynamic>> paymentsToSend,
  }) {
    final pmProvider = context.read<PaymentMethodProvider>();
    final typedPayments = paymentsToSend.map((payment) {
      final ref = _metaText(payment['reference']);
      final code =
          _metaText(payment['method']).isEmpty ? 'cash' : _metaText(payment['method']);
      return <String, dynamic>{
        'method': code,
        'label': pmProvider.displayNameFor(code),
        'amount': _metaNum(payment['amount']),
        if (ref.isNotEmpty) 'reference': ref,
      };
    }).toList(growable: false);

    final snapshotPrimaryPhone = _selectedCustomerId != null
        ? (_selectedCustomer?['phone'] ?? customerPhoneController.text)
            .toString()
            .trim()
        : customerPhoneController.text.trim();
    final snapshotSecondaryPhones = _selectedCustomerId != null
        ? _selectedCustomerSecondaryPhones
        : const <String>[];

    final customerSnapshot = <String, dynamic>{
      if (_selectedCustomerId != null) 'id': _selectedCustomerId,
      if ((_selectedCustomer?['customer_code'] ?? '').toString().trim().isNotEmpty)
        'customer_code': _selectedCustomer!['customer_code'],
      if (_selectedCustomer != null)
        'customer_type': SalePricing.normalizeCustomerType(
          _selectedCustomer!['customer_type'],
        ),
      'name': _selectedCustomer != null
          ? [
              _metaText(_selectedCustomer?['first_name']),
              _metaText(_selectedCustomer?['last_name']),
            ].where((v) => v.isNotEmpty).join(' ').trim()
          : (customerNameController.text.trim().isEmpty
              ? 'Walk-in customer'
              : customerNameController.text.trim()),
      'phone': snapshotPrimaryPhone,
      'phone_numbers': snapshotSecondaryPhones,
      'address': addressController.text.trim(),
      if (_selectedAreaId != null) 'area_id': _selectedAreaId,
      if (_selectedAreaName != null) 'area_name': _selectedAreaName,
      if (_selectedCustomer != null &&
          _selectedCustomer!.containsKey('credit_limit'))
        'credit_limit': _selectedCustomer!['credit_limit'],
      if (_selectedCustomer?['credit_limit_mode'] != null)
        'credit_limit_mode': _selectedCustomer!['credit_limit_mode'],
      if ((_selectedCustomer?['balance'] ??
              _selectedCustomer?['trade_balance']) !=
          null)
        'trade_balance': _selectedCustomer?['balance'] ??
            _selectedCustomer?['trade_balance'],
    };

    final meta = <String, dynamic>{
      'customer_snapshot': customerSnapshot,
      'print_customer_phone_numbers': snapshotSecondaryPhones.isNotEmpty,
      'branch_snapshot': {
        if (effectiveBranchId != null && effectiveBranchId.isNotEmpty)
          'id': effectiveBranchId,
        if (_selectedBranch != null) ...{
          if (_selectedBranch!['name'] != null) 'name': _selectedBranch!['name'],
          if (_selectedBranch!['location'] != null) 'location': _selectedBranch!['location'],
        },
      },
      'salesman_snapshot': _partySnapshot(
        _selectedUser,
        id: _selectedUserId,
        fallbackName: _metaText(_selectedUser?['name']),
      ),
      'delivery_boy_snapshot': _partySnapshot(
        _selectedDeliveryBoy,
        id: _selectedDeliveryBoyId,
        fallbackName: _metaText(_selectedDeliveryBoy?['name']),
      ),
      'vendor_snapshot': _partySnapshot(
        _selectedVendor,
        id: _selectedVendorId,
      ),
      if (_selectedSaleSourceId != null)
        'sale_source_snapshot': {
          'id': _selectedSaleSourceId,
          'name': (_selectedSaleSource?['name'] ?? 'Counter').toString(),
        },
      if (_selectedAreaId != null)
        'sale_area_snapshot': {
          'id': _selectedAreaId,
          if (_selectedAreaName != null) 'name': _selectedAreaName,
        },
      'totals_snapshot': {
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'delivery': shipping,
        'total': total,
        'paid': paid,
        'balance': balance,
      },
      'payments_snapshot': typedPayments,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
      'delivery': shipping,
      'sale_type': _selectedDeliveryBoyId != null ? 'delivery' : 'counter',
    };

    meta.removeWhere((_, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty));
    return meta;
  }

  double? _finiteCreditNumber(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  /// Applies a conservative device-side check only when an online submission
  /// could not be confirmed and the sale is about to enter the local queue.
  /// The backend remains authoritative and rechecks the actual party trade
  /// ledger during sync. No invoice allocation or paid/unpaid status is used.
  Future<_OfflineCreditDecision> _prepareOfflineCreditQueue({
    required Map<String, dynamic> payload,
    required int branchId,
    required double currentLedgerDelta,
  }) async {
    final customerId = int.tryParse(_selectedCustomerId ?? '');
    if (customerId == null || customerId <= 0 || currentLedgerDelta <= 0.004) {
      return const _OfflineCreditDecision.allow();
    }

    // A server-presented override may have been approved immediately before
    // the retry lost connectivity. Preserve that reason and idempotency key.
    final existingOverride = payload['credit_limit_override'];
    if (existingOverride is Map &&
        (existingOverride['reason']?.toString().trim().length ?? 0) >= 5) {
      return const _OfflineCreditDecision.allow(
        'This queued sale carries the authorized credit-limit override already approved online.',
      );
    }

    final customer = _selectedCustomer;
    final mode = (customer?['credit_limit_mode'] ?? 'block')
        .toString()
        .trim()
        .toLowerCase();
    final warningMode = mode == 'warning';
    final auth = context.read<AuthProvider>();
    final mayOverride =
        auth.hasPermission('override-party-credit-limit');

    Future<_OfflineCreditDecision> unknownDecision(String reason) async {
      final message =
          '$reason The authoritative customer trade balance will be checked when this sale synchronizes.';
      if (warningMode) {
        return _OfflineCreditDecision.allow('Credit warning: $message');
      }
      if (!mayOverride) {
        return _OfflineCreditDecision.deny(
          '$message An authorized credit-limit override is required before creating additional offline debt.',
        );
      }
      final overrideReason = await showOfflineCreditDataOverrideDialog(
        context,
        message: message,
      );
      if (overrideReason == null) {
        return const _OfflineCreditDecision.deny(
          'Offline sale cancelled because credit approval was not completed.',
        );
      }
      payload['credit_limit_override'] = {'reason': overrideReason};
      return const _OfflineCreditDecision.allow(
        'Queued with an authorized offline credit override. The server will validate it during synchronization.',
      );
    }

    if (customer == null || !customer.containsKey('credit_limit')) {
      return unknownDecision(
        'This customer was selected from data that does not contain a verified credit-control configuration.',
      );
    }

    // Explicit NULL is the production-compatible unlimited setting.
    if (customer['credit_limit'] == null) {
      return const _OfflineCreditDecision.allow();
    }
    final limit = _finiteCreditNumber(customer['credit_limit']);
    if (limit == null || limit < 0) {
      return unknownDecision(
        'The cached customer credit limit is invalid or unavailable.',
      );
    }

    final hasBalance = customer.containsKey('balance') ||
        customer.containsKey('trade_balance');
    final cachedBalance = _finiteCreditNumber(
      customer['balance'] ?? customer['trade_balance'],
    );
    if (!hasBalance || cachedBalance == null) {
      return unknownDecision(
        'No reliable cached customer trade balance is available while offline.',
      );
    }

    double pendingExposure;
    try {
      pendingExposure = await OfflineSalesQueueService.instance
          .pendingCustomerExposure(
        branchId: branchId,
        customerId: customerId,
      );
    } catch (_) {
      return unknownDecision(
        "The device could not verify this customer's existing unsynced exposure.",
      );
    }

    final balanceBefore = cachedBalance + pendingExposure;
    final projected = balanceBefore + currentLedgerDelta;
    if (projected <= limit + 0.004) {
      return const _OfflineCreditDecision.allow();
    }

    final issue = CreditLimitIssue(
      partyType: 'customer',
      partyId: customerId,
      limit: limit,
      balanceBefore: balanceBefore,
      projectedBalance: projected,
      exceededBy: projected - limit,
      mode: warningMode ? 'warning' : 'block',
      canOverride: mayOverride,
    );
    if (warningMode) {
      return _OfflineCreditDecision.allow(
        'Credit warning: ${issue.summary} The server will recheck the current party ledger during synchronization.',
      );
    }
    if (!mayOverride) {
      return _OfflineCreditDecision.deny(
        '${issue.summary} You do not have permission to approve this offline credit exposure.',
      );
    }

    final reason = await showCreditLimitOverrideDialog(context, issue);
    if (reason == null) {
      return const _OfflineCreditDecision.deny(
        'Offline sale cancelled because the credit-limit override was not approved.',
      );
    }
    payload['credit_limit_override'] = {'reason': reason};
    return _OfflineCreditDecision.allow(
      'Queued with an authorized offline credit override. ${issue.summary}',
    );
  }

  // ---------------- Submit ----------------
  /// The first cart line whose quantity breaks its unit's rule, described in
  /// a way that points at the line — or null when every line is acceptable.
  ///
  /// This mirrors the backend's own pre-write guard (units.FirstViolation), so
  /// a sale that could only come back as a 422 never leaves the device — which
  /// matters most when the device is offline and the rejection would otherwise
  /// not surface until sync.
  String? _firstQuantityViolation() {
    for (var i = 0; i < _items.length; i++) {
      final row = _items[i];
      final name = (row['name'] ?? 'item').toString();
      final qty = double.tryParse(row['quantity']?.toString() ?? '');
      if (qty == null) {
        return 'Line ${i + 1} ($name) has no valid quantity.';
      }
      final rule = QuantityRule.fromProduct(row);
      if (!rule.allows(qty)) {
        return 'Line ${i + 1} — $name: ${rule.message}';
      }
    }
    return null;
  }

  /// Reads a 422 bag and writes what it taught us back onto the cart.
  ///
  /// A `items.N.quantity` decimal rejection is the server stating that line
  /// N's unit does not allow a fraction — authoritative, and newer than
  /// whatever the line was carrying (a cache row from before the unit was
  /// changed, or no unit information at all). Recording it turns the field
  /// red and makes the client-side check catch the same mistake next time,
  /// instead of another round trip.
  void _applyServerLineErrors(ApiException e) {
    for (final lineError in parseValidationBag(e.body?['errors'])) {
      final rule = lineError.assertedRule;
      if (rule == null) continue;
      final index = lineError.index;
      if (index < 0 || index >= _items.length) continue;
      // Only what the server actually asserted: the rule, and the unit name
      // when it named one. The unit id is not in the message, and blanking a
      // known one would lose information.
      _items[index]['unit_allow_decimal'] = false;
      if (rule.unitName.isNotEmpty) _items[index]['unit_name'] = rule.unitName;
    }
  }

  /// Cashier-readable text for a rejection that will never succeed on retry.
  /// Field errors are listed with the cart line they belong to; anything else
  /// falls back to the server's own message.
  String _describeRejection(ApiException e) {
    final lines = <String>[];
    flattenBag(e.body?['errors']).forEach((key, message) {
      final index =
          key.startsWith('items.') ? int.tryParse(key.split('.')[1]) : null;
      if (index != null && index >= 0 && index < _items.length) {
        final name = (_items[index]['name'] ?? 'item').toString();
        lines.add('Line ${index + 1} — $name: $message');
      } else {
        lines.add(message);
      }
    });
    if (lines.isEmpty) return 'Sale not saved: ${e.message}';
    return 'Sale not saved — please correct and try again.\n${lines.join('\n')}';
  }

  Future<void> _submitSale({bool print = true}) async {
    if (_isEditing) {
      await _submitAmendment();
      return;
    }
    if (_items.isEmpty) {
      AppFeedback.warning(context, "Add at least 1 item before creating sale.");
      return;
    }

    // Quantity rules are checked before anything is built or sent. Offline,
    // this is the only defence — nothing will validate the sale until it
    // syncs, potentially hours later.
    final quantityViolation = _firstQuantityViolation();
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return;
    }

    if (_sendInvoiceOnWhatsApp) {
      try {
        WhatsAppInvoiceService.instance.normalizePhone(
          _whatsAppDestinationPhone(),
        );
      } on FormatException catch (e) {
        AppFeedback.warning(context, e.message.toString());
        return;
      }
    }

    final auth = context.read<AuthProvider>();
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final effectiveBranchId = globalBranchId?.toString() ?? _selectedBranchId;

    if (auth.isMasterAdmin && globalBranchId == null) {
      AppFeedback.warning(context, 'Please select a working branch from Branch Control before creating sale.');
      return;
    }
    final originBranchId = int.tryParse(effectiveBranchId ?? '');
    if (originBranchId == null || originBranchId <= 0) {
      AppFeedback.warning(
        context,
        'A valid working branch is required before creating a sale.',
      );
      return;
    }
    final originUserId = int.tryParse(auth.user?['id']?.toString() ?? '');
    double _rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

    final hasUnlinkedReturn = _items.any(
      (i) => _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] == null,
    );
    if (hasUnlinkedReturn) {
      AppFeedback.warning(
        context,
        'Every negative quantity must be linked to its original invoice before saving.',
      );
      return;
    }
    final linkedReturns = _items
        .where((i) => _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] != null)
        .toList();
    final linkedInvoiceIds = linkedReturns
        .map((i) => _metaInt(i['original_sale_id']))
        .whereType<int>()
        .toSet();
    if (linkedInvoiceIds.length > 1) {
      AppFeedback.warning(context, 'All returned items in one transaction must come from the same original invoice.');
      return;
    }

    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final qty = _rowNum(i['quantity']);
      if (qty <= 0) return sum;
      final price = _rowNum(i['price']);
      final disc = _rowNum(i['discount_pct']);
      final discType = (i['discount_type'] ?? 'percentage').toString();
      return sum + _lineTotal(price: price, qty: qty, discPct: disc, discountType: discType);
    });
    double discount = double.tryParse(discountController.text.trim()) ?? 0.0;
    double tax = double.tryParse(taxController.text.trim()) ?? 0.0;
    double shipping = double.tryParse(shippingController.text.trim()) ?? 0.0;
    if (subtotal <= .004 && linkedReturns.isNotEmpty &&
        (discount.abs() > .004 || tax.abs() > .004 || shipping.abs() > .004)) {
      AppFeedback.warning(
        context,
        'A return-only transaction cannot add a new invoice discount, tax, or delivery charge. Original delivery is non-refundable.',
      );
      return;
    }
    final saleTotal = subtotal - discount + tax + shipping;
    if (saleTotal < -0.004) {
      AppFeedback.warning(context, 'The new-sale total cannot be negative.');
      return;
    }
    final returnCredit = linkedReturns.fold<double>(
      0, (sum, i) => sum + _rowNum(i['return_credit']).abs(),
    );
    final originalOutstanding = linkedReturns.isEmpty
        ? 0.0
        : _rowNum(linkedReturns.first['return_original_outstanding']);
    final appliedToOriginal = returnCredit.clamp(0.0, originalOutstanding).toDouble();
    final afterOriginal = (returnCredit - appliedToOriginal).clamp(0.0, double.infinity).toDouble();
    final appliedToExchange = afterOriginal.clamp(0.0, saleTotal).toDouble();
    final refundDue = (afterOriginal - appliedToExchange).clamp(0.0, double.infinity).toDouble();
    final customerPays = (saleTotal - appliedToExchange).clamp(0.0, double.infinity).toDouble();
    // Customer-facing signed transaction total. Settlement is deliberately
    // separate: some return credit may first reduce the old invoice balance.
    final total = saleTotal - returnCredit;

    // Resolve the selected tender (falls back to the branch default drawer
    // method). Reference only applies to non-drawer methods (KNET/card/bank…).
    final pmProvider = context.read<PaymentMethodProvider>();
    final effectiveMethod =
        _saleMethod ?? pmProvider.defaultMethod?.method ?? 'cash';
    final isDrawerMethod =
        pmProvider.byCode(effectiveMethod)?.affectsCashDrawer ??
            (effectiveMethod == 'cash');
    final saleReference = saleReferenceController.text.trim();

    final List<Map<String, dynamic>> paymentsToSend = [];
    if (customerPays > 0 && _payments.isNotEmpty) {
      // Explicit split tender: send every row (method + amount + optional ref).
      for (final p in _payments) {
        final ref = (p['reference'] ?? '').toString().trim();
        paymentsToSend.add({
          "amount": _pmAmt(p['amount']).toStringAsFixed(2),
          "method": p['method'] ?? 'cash',
          if (ref.isNotEmpty) "reference": ref,
        });
      }
    } else if (_autoCashIfEmpty && customerPays > 0) {
      // Quick single tender via the selected method.
      paymentsToSend.add({
        "amount": customerPays.toStringAsFixed(2),
        "method": effectiveMethod,
        if (!isDrawerMethod && saleReference.isNotEmpty)
          "reference": saleReference,
      });
    }
    final Map<String, dynamic>? refundToSend =
        linkedReturns.isNotEmpty && _autoCashIfEmpty && refundDue > .004
        ? {
            'mode': 'auto',
            'method': effectiveMethod,
            if (!isDrawerMethod && saleReference.isNotEmpty)
              'reference': saleReference,
          }
        : null;

    final paid = paymentsToSend.fold<double>(
      0.0,
      (sum, payment) => sum + _metaNum(payment['amount']),
    );
    final balance = customerPays - paid;

    // Cash Received / Change apply to the CASH (drawer) portion only, and are
    // printed on the invoice (e.g. bill 1500, cash received 2000 → change 500).
    final cashDue = _saleCashDue(customerPays);
    final enteredCashReceived = _toDouble(cashReceivedController);
    final cashReceived =
        enteredCashReceived > 0 ? enteredCashReceived : cashDue;
    final changeAmount = cashDue > 0
        ? (cashReceived - cashDue).clamp(0.0, double.infinity).toDouble()
        : 0.0;

    setState(() => _submitting = true);

    // Every sale gets a client_ref, online or offline (handover doc §2.2) —
    // this is the idempotency key the backend uses to guarantee a synced
    // offline sale (or a retried/double-tapped submit) never creates a
    // duplicate row. occurred_at is the on-device timestamp captured right
    // now, at the moment "Save Sale" was pressed, so the sale still posts
    // and reports as having happened today even if it ends up queued and
    // synced later (§1.3).
    final clientRef = const Uuid().v4();
    final occurredAt = DateTime.now();

    // Generate a customer-friendly offline invoice reference.  This is
    // generated up-front for EVERY sale (online or offline) so:
    //   • The same reference is printed on the receipt and stored on the
    //     server record, enabling "find this receipt" searches later.
    //   • The UUID client_ref remains internal (idempotency only).
    //   • Online sales that succeed immediately also carry offline_invoice_no
    //     so that receipts and server records are always cross-searchable.
    final shiftProvider = context.read<RegisterShiftProvider>();
    final registerCode =
        shiftProvider.shift?['register']?['code']?.toString() ?? 'REG';
    final branchIdForSeq = originBranchId;

    String? offlineInvoiceNo;
    try {
      offlineInvoiceNo = await OfflineInvoiceSeqService.instance.next(
        branchId: branchIdForSeq,
        registerCode: registerCode,
        occurredAt: occurredAt,
      );
    } catch (e, s) {
      // Non-fatal: fall back to null — the sale can still proceed without it.
      debugPrint('offline_invoice_seq error: $e');
      debugPrintStack(stackTrace: s);
    }

    Map<String, dynamic>? res;
    var queuedOffline = false;

    try {
      final meta = _buildSaleMeta(
        effectiveBranchId: effectiveBranchId,
        subtotal: subtotal,
        discount: discount,
        tax: tax,
        shipping: shipping,
        total: saleTotal,
        paid: paid,
        balance: balance,
        cashReceived: cashReceived,
        changeAmount: changeAmount,
        paymentsToSend: paymentsToSend,
      );
      if (linkedReturns.isNotEmpty) {
        meta['return_preview'] = {
          'return_credit': returnCredit,
          'applied_to_original': appliedToOriginal,
          'applied_to_exchange': appliedToExchange,
          'refund_due': refundDue,
          'original_delivery_refund': 0,
        };
      }
      final payload = _saleService.buildSalePayload(
        branchId: effectiveBranchId,
        customerId: _selectedCustomerId != null
            ? int.tryParse(_selectedCustomerId!)
            : null,
        vendorId: _selectedVendorId,
        userId: _selectedUserId,
        deliveryBoyId: _selectedDeliveryBoyId,
        saleSourceId: _selectedSaleSourceId,
        areaId: _selectedAreaId,
        areaName: _selectedAreaName,
        saleType: _selectedDeliveryBoyId != null ? 'delivery' : null,
        items: _items,
        payments: paymentsToSend,
        refund: refundToSend,
        discount: discount,
        tax: tax,
        delivery: shipping,
        meta: meta,
        clientRef: clientRef,
        originBranchId: originBranchId,
        occurredAt: occurredAt,
        offlineInvoiceNo: offlineInvoiceNo,
      );

      String? queueReason;

      Object? submitError;
      try {
        res = await _saleService
            .createSaleFromPayload(payload)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        submitError = e;
      }

      // Credit control is party-ledger based. The server has already posted
      // the sale and any same-screen party receipt inside one transaction,
      // measured the resulting AR balance, and rolled everything back before
      // returning this 422. An authorized user may retry the SAME idempotency
      // reference once with an audited reason; no invoice allocation/status is
      // introduced by this flow.
      final firstCreditIssue = submitError == null
          ? null
          : CreditLimitIssue.fromException(submitError!);
      if (firstCreditIssue != null) {
        final auth = context.read<AuthProvider>();
        final mayOverride = firstCreditIssue.canOverride &&
            auth.hasPermission('override-party-credit-limit');
        if (!mayOverride) {
          if (!mounted) return;
          AppFeedback.error(context, firstCreditIssue.summary);
          return;
        }
        final reason = await showCreditLimitOverrideDialog(
          context,
          firstCreditIssue,
        );
        if (!mounted) return;
        if (reason == null) return;
        payload['credit_limit_override'] = {'reason': reason};
        try {
          res = await _saleService
              .createSaleFromPayload(payload)
              .timeout(const Duration(seconds: 15));
          submitError = null;
        } catch (e) {
          submitError = e;
        }
      }

      if (submitError != null) {
        final e = submitError!;
        // Linked returns are never queued offline: current returnable quantity,
        // old-invoice settlement and concurrent return locks must be verified
        // against the authoritative backend at posting time.
        if (linkedReturns.isNotEmpty &&
            (!(e is ApiException) || e.isRetryable || e.isAuthFailure || e.statusCode == 402 || isNetworkFailure(e))) {
          if (!mounted) return;
          AppFeedback.error(
            context,
            'Return/exchange requires a live CounterIQ connection. Nothing was queued or posted.',
          );
          return;
        }
        // A DETERMINISTIC rejection must not be queued. The queue's premise is
        // "this will work later"; re-POSTing an identical payload that the
        // server already refused on its merits will be refused identically.
        if (e is ApiException &&
            !e.isRetryable &&
            !e.isAuthFailure &&
            e.statusCode != 402) {
          _applyServerLineErrors(e);
          if (!mounted) return;
          setState(() {});
          final issue = CreditLimitIssue.fromException(e);
          AppFeedback.error(
            context,
            issue?.summary ?? _describeRejection(e),
          );
          return; // cart preserved; the outer finally clears _submitting
        }

        // Queue only failures that can validly succeed later: no connection,
        // retryable infrastructure, authentication expiry, or subscription
        // state. A party credit-limit rejection is deterministic and never
        // enters the background queue without an authorized override reason.
        queueReason = isNetworkFailure(e)
            ? 'Offline: could not reach the server ($e).'
            : 'Server responded with a retryable error, queued for review on sync: $e';

        final refundAmount = 0.0;
        final offlineCredit = await _prepareOfflineCreditQueue(
          payload: payload,
          branchId: originBranchId,
          currentLedgerDelta: total - paid + refundAmount,
        );
        if (!mounted) return;
        if (!offlineCredit.allowed) {
          AppFeedback.error(
            context,
            offlineCredit.message ??
                'This offline credit sale was not approved.',
          );
          return;
        }
        if (offlineCredit.message != null &&
            offlineCredit.message!.trim().isNotEmpty) {
          queueReason = '$queueReason ${offlineCredit.message}';
        }

        await OfflineSalesQueueService.instance.enqueue(
          clientRef: clientRef,
          originBranchId: originBranchId,
          originUserId: originUserId,
          payload: payload,
          occurredAt: occurredAt,
          offlineInvoiceNo: offlineInvoiceNo,
          initialError: queueReason,
        );
        queuedOffline = true;
        if (mounted) {
          // ignore: use_build_context_synchronously
          context.read<OfflineQueueProvider>().refresh();
        }
      }

      final creditLimitNotice = queuedOffline
          ? null
          : CreditLimitIssue.fromWarning(
              res?['data']?['credit_limit_warning'],
            );

      // receiptNo: prefer the server-confirmed invoice number for online
      // sales; use the customer-friendly offline reference for queued sales.
      // Never expose the UUID client_ref on a customer-facing receipt.
      final receiptNo = queuedOffline
          ? (offlineInvoiceNo ?? 'OFF-PENDING')
          : (res?['data']?['invoice_no'] ??
                  res?['data']?['sale']?['invoice_no'] ??
                  res?['data']?['id'] ??
                  'N/A')
              .toString();

      if (print) {
      final receiptSubtotal = subtotal - returnCredit;
      final receiptItems = _items.map((i) {
        final name = (i['name'] ?? '').toString();
        final price = double.tryParse(i['price']?.toString() ?? '') ?? 0.0;
        final qty = double.tryParse(i['quantity']?.toString() ?? '') ?? 0.0;
        final lineTotal =
            double.tryParse(i['total']?.toString() ?? '') ?? (price * qty);
        final gross = (price * qty).abs();
        final net = lineTotal.abs();
        final lineDiscount = gross > net ? gross - net : 0.0;
        final unitRaw = i['unit_name'] ?? i['unit_symbol'] ?? i['unit'];
        final unitName = unitRaw is Map
            ? (unitRaw['symbol'] ?? unitRaw['name'] ?? '').toString()
            : (unitRaw ?? '').toString();
        return SaleReceiptItem(
          name: name,
          secondaryName: (i['secondary_name'] ?? '').toString().trim().isEmpty
              ? null
              : (i['secondary_name'] ?? '').toString().trim(),
          price: price,
          qty: qty,
          total: lineTotal,
          unitName: unitName,
          discountAmount: lineDiscount,
          discountType: (i['discount_type'] ?? 'percentage').toString(),
          discountValue:
              double.tryParse(i['discount_pct']?.toString() ?? '') ?? 0.0,
        );
      }).toList();
      final printerConfig = context.read<PrinterConfigProvider>();

      if (!printerConfig.isConfigured) {
        try {
          final token = context.read<AuthProvider>().token;
          if (token != null) await printerConfig.refresh(token);
        } catch (e, s) {
          debugPrint('Printer config refresh failed: $e');
          debugPrintStack(stackTrace: s);
        }
      }

      final effectiveShopName = printerConfig.shopName.isNotEmpty ? printerConfig.shopName : 'My Shop';
      final effectiveShopAddress = printerConfig.shopAddress.isNotEmpty ? printerConfig.shopAddress : null;
      final effectiveShopPhone = printerConfig.shopPhone.isNotEmpty ? printerConfig.shopPhone : null;
      final mainTemplate = printerConfig.mainInvoiceTemplate;
      final whatsappTemplate = printerConfig.whatsappInvoiceTemplate;
      final whatsappPaperCode = printerConfig.whatsappPaperCode;
      final secondaryTemplate = printerConfig.secondaryInvoiceTemplate;
      final secondaryHeader = printerConfig.secondaryReceiptHeader.trim().isEmpty
          ? 'KITCHEN COPY'
          : printerConfig.secondaryReceiptHeader.trim();
      final footerLines = printerConfig.footerLines;
      final footerLineStyles = printerConfig.footerLineStyles;
      final printMeta = <String, dynamic>{
        ...meta,
        'item_discount_display': printerConfig.itemDiscountDisplay.value,
      };
      final receiptPrintTime = DateTime.now();

      Future<Uint8List> buildWhatsappPdf() {
        return ReceiptPreviewService.instance.buildReceiptPdf(
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: receiptPrintTime,
          items: receiptItems,
          subtotal: receiptSubtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          meta: printMeta,
          sections: whatsappTemplate.sections,
          paperWidth: whatsappPaperCode,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          invoiceHeading: printerConfig.invoiceHeading,
          showLogo: printerConfig.printLogoEnabled &&
              whatsappTemplate.isCustomerFacing,
          logoData: printerConfig.printLogoData,
          showQr: printerConfig.qrCodeEnabled &&
              whatsappTemplate.isCustomerFacing,
          qrUrl: printerConfig.qrCodeUrl,
          qrCaption: printerConfig.qrCodeCaption,
          template: whatsappTemplate,
        );
      }

      final mainRawNetworkWillPrint = printerConfig.isNetworkPrinter &&
          mainTemplate.supportsRawNetwork &&
          (printerConfig.networkIp ?? '').trim().isNotEmpty;
      final whatsappUsesDifferentPdf = whatsappTemplate != mainTemplate ||
          whatsappPaperCode != printerConfig.mainPaperCode;

      // Build an independently configured WhatsApp document while the physical
      // receipt is printing. Previously this second PDF was generated only
      // after printing completed, making WhatsApp feel unnecessarily slow.
      // When a local Primary print uses the exact same PDF we instead reuse the
      // bytes returned by LocalPrinterService and avoid the second render.
      Future<Uint8List?>? whatsappPdfFuture;
      Object? whatsappPdfError;
      StackTrace? whatsappPdfStackTrace;
      if (_sendInvoiceOnWhatsApp &&
          !queuedOffline &&
          (whatsappUsesDifferentPdf || mainRawNetworkWillPrint)) {
        final timing = Stopwatch()..start();
        whatsappPdfFuture = buildWhatsappPdf().then<Uint8List?>((bytes) {
          debugPrint(
            '[WHATSAPP-TIMING] PDF ready in ${timing.elapsedMilliseconds}ms bytes=${bytes.length}',
          );
          return bytes;
        }).catchError((Object error, StackTrace stackTrace) {
          // Capture the error now so an independently generated PDF cannot
          // become an unhandled asynchronous error while the printer is busy.
          whatsappPdfError = error;
          whatsappPdfStackTrace = stackTrace;
          return null;
        });
      }

      debugPrint('Active printer connection: ${printerConfig.activeConnection}, template: ${mainTemplate.value}');

      var printedToHardware = false;
      Uint8List? customerInvoicePdfBytes;
      if (printerConfig.isNetworkPrinter && mainTemplate.supportsRawNetwork && (printerConfig.networkIp ?? '').trim().isNotEmpty) {
        try {
          await ThermalPrinterService.instance.printSaleReceiptNetwork(
            printerIp: printerConfig.networkIp!.trim(),
            port: printerConfig.networkPort,
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: receiptPrintTime,
            items: receiptItems,
            subtotal: receiptSubtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: printMeta,
            sections: mainTemplate.sections,
            paperWidth: printerConfig.mainPaperCode,
            footerLines: footerLines,
            footerLineStyles: footerLineStyles,
            showLogo: printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
            logoData: printerConfig.printLogoData,
            showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
            qrUrl: printerConfig.qrCodeUrl,
            qrCaption: printerConfig.qrCodeCaption,
            template: mainTemplate,
          );
          printedToHardware = true;

          if (printerConfig.secondaryPrintEnabled && (printerConfig.secondaryNetworkIp ?? '').trim().isNotEmpty) {
            await ThermalPrinterService.instance.printSaleReceiptNetwork(
              printerIp: printerConfig.secondaryNetworkIp!.trim(),
              port: printerConfig.secondaryNetworkPort,
              shopName: effectiveShopName,
              shopAddress: effectiveShopAddress,
              shopPhone: effectiveShopPhone,
              receiptNo: receiptNo,
              dateTime: receiptPrintTime,
              items: receiptItems,
              subtotal: receiptSubtotal,
              discount: discount,
              tax: tax,
              grandTotal: total,
              cashReceived: cashReceived,
              changeAmount: changeAmount,
              meta: printMeta,
              sections: secondaryTemplate.sections,
              paperWidth: secondaryTemplate.paperWidthCode,
              footerLines: footerLines,
              footerLineStyles: footerLineStyles,
              receiptHeader: secondaryHeader,
              template: secondaryTemplate,
            );
          }
        } catch (e, s) {
          debugPrint('PRINT ERROR (network): $e');
          debugPrintStack(stackTrace: s);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      } else if (printerConfig.isLocalPrinter && (printerConfig.localPrinterName ?? '').trim().isNotEmpty) {
        try {
          customerInvoicePdfBytes =
              await LocalPrinterService.instance.printSaleReceipt(
            printerName: printerConfig.localPrinterName!.trim(),
            shopName: effectiveShopName,
            shopAddress: effectiveShopAddress,
            shopPhone: effectiveShopPhone,
            receiptNo: receiptNo,
            dateTime: receiptPrintTime,
            items: receiptItems,
            subtotal: receiptSubtotal,
            discount: discount,
            tax: tax,
            grandTotal: total,
            cashReceived: cashReceived,
            changeAmount: changeAmount,
            meta: printMeta,
            sections: mainTemplate.sections,
            paperWidth: printerConfig.mainPaperCode,
            footerLines: footerLines,
            footerLineStyles: footerLineStyles,
            invoiceHeading: printerConfig.invoiceHeading,
            showLogo: printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
            logoData: printerConfig.printLogoData,
            showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
            qrUrl: printerConfig.qrCodeUrl,
            qrCaption: printerConfig.qrCodeCaption,
            template: mainTemplate,
          );
          printedToHardware = true;

          if (printerConfig.secondaryPrintEnabled &&
              (printerConfig.secondaryLocalPrinterName ?? '').trim().isNotEmpty) {
            await LocalPrinterService.instance.printSaleReceipt(
              printerName: printerConfig.secondaryLocalPrinterName!.trim(),
              shopName: effectiveShopName,
              shopAddress: effectiveShopAddress,
              shopPhone: effectiveShopPhone,
              receiptNo: receiptNo,
              dateTime: receiptPrintTime,
              items: receiptItems,
              subtotal: receiptSubtotal,
              discount: discount,
              tax: tax,
              grandTotal: total,
              cashReceived: cashReceived,
              changeAmount: changeAmount,
              meta: printMeta,
              sections: secondaryTemplate.sections,
              paperWidth: secondaryTemplate.paperWidthCode,
              footerLines: footerLines,
              footerLineStyles: footerLineStyles,
              receiptHeader: secondaryHeader,
              template: secondaryTemplate,
              jobName: 'Secondary Copy $receiptNo',
            );
          }
        } catch (e, s) {
          debugPrint('PRINT ERROR (local): $e');
          debugPrintStack(stackTrace: s);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Sale created but printing failed: $e")),
            );
          }
        }
      }

      if (!printedToHardware) {
        customerInvoicePdfBytes =
            await ReceiptPreviewService.instance.previewReceipt(
          shopName: effectiveShopName,
          shopAddress: effectiveShopAddress,
          shopPhone: effectiveShopPhone,
          receiptNo: receiptNo,
          dateTime: receiptPrintTime,
          items: receiptItems,
          subtotal: receiptSubtotal,
          discount: discount,
          tax: tax,
          grandTotal: total,
          meta: printMeta,
          sections: mainTemplate.sections,
          paperWidth: printerConfig.mainPaperCode,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          invoiceHeading: printerConfig.invoiceHeading,
          showLogo:
              printerConfig.printLogoEnabled && mainTemplate.isCustomerFacing,
          logoData: printerConfig.printLogoData,
          showQr: printerConfig.qrCodeEnabled && mainTemplate.isCustomerFacing,
          qrUrl: printerConfig.qrCodeUrl,
          qrCaption: printerConfig.qrCodeCaption,
          template: mainTemplate,
        );
      }

      if (_sendInvoiceOnWhatsApp && !queuedOffline) {
        final whatsappFormat = printerConfig.whatsappInvoiceFormat;
        final customerSnapshotRaw = meta['customer_snapshot'];
        final customerSnapshot = customerSnapshotRaw is Map
            ? Map<String, dynamic>.from(customerSnapshotRaw)
            : const <String, dynamic>{};
        final rawCustomerBalance = res?['data']?['customer_balance'];
        final whatsappMessage = WhatsAppMessageTemplateService.render(
          template: printerConfig.whatsappMessageTemplate,
          showCustomerBalance: printerConfig.whatsappShowCustomerBalance,
          values: {
            'customer_name': _metaText(customerSnapshot['name']),
            'customer_code': _metaText(customerSnapshot['customer_code']),
            'invoice_no': receiptNo,
            'invoice_amount': total.toStringAsFixed(2),
            'amount_paid': paid.toStringAsFixed(2),
            'invoice_balance': balance.toStringAsFixed(2),
            'customer_balance': rawCustomerBalance == null
                ? ''
                : _metaNum(rawCustomerBalance).toStringAsFixed(2),
            'business_name': effectiveShopName,
            'date': '${occurredAt.day.toString().padLeft(2, '0')}/'
                '${occurredAt.month.toString().padLeft(2, '0')}/'
                '${occurredAt.year}',
            'currency': AppCurrency.currency,
            'attachment_format': whatsappFormat.label,
          },
        );
        final whatsappPhone = _whatsAppDestinationPhone();
        final reusablePrimaryPdf = whatsappTemplate == mainTemplate &&
                whatsappPaperCode == printerConfig.mainPaperCode
            ? customerInvoicePdfBytes
            : null;

        // Do not keep the cashier waiting for PDF/JPG conversion, disk IO or
        // clipboard work. The immutable sale/print values above are captured
        // by this task before _resetForNextSale() clears the workspace.
        unawaited(() async {
          try {
            final pdfTiming = Stopwatch()..start();
            Uint8List? pdfBytes = reusablePrimaryPdf;
            if (pdfBytes == null && whatsappPdfFuture != null) {
              pdfBytes = await whatsappPdfFuture;
              if (pdfBytes == null && whatsappPdfError != null) {
                Error.throwWithStackTrace(
                  whatsappPdfError!,
                  whatsappPdfStackTrace ?? StackTrace.current,
                );
              }
            }
            pdfBytes ??= await buildWhatsappPdf();
            debugPrint(
              '[WHATSAPP-TIMING] background PDF wait ${pdfTiming.elapsedMilliseconds}ms reused=${reusablePrimaryPdf != null}',
            );

            final prepareTiming = Stopwatch()..start();
            final prepared =
                await WhatsAppInvoiceService.instance.prepareAttachment(
              pdfBytes: pdfBytes,
              receiptNo: receiptNo,
              phone: whatsappPhone,
              format: whatsappFormat,
            );
            debugPrint(
              '[WHATSAPP-TIMING] background attachment ready in ${prepareTiming.elapsedMilliseconds}ms format=${whatsappFormat.value}',
            );
            if (!mounted) return;
            _addPendingWhatsAppTask(
              receiptNo: receiptNo,
              prepared: prepared,
              message: whatsappMessage,
            );
          } catch (e, st) {
            debugPrint('WHATSAPP INVOICE ERROR: $e');
            debugPrintStack(stackTrace: st);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Sale $receiptNo saved, but WhatsApp invoice preparation failed.',
                ),
                action: SnackBarAction(
                  label: 'Dismiss',
                  onPressed: () {},
                ),
              ),
            );
          }
        }());
      }
      } // if (print)

      if (!mounted) return;
      final whatsappWasRequested = _sendInvoiceOnWhatsApp && print;
      _resetForNextSale(keepInitialCustomer: widget.initialCustomer != null);
      if (queuedOffline) {
        AppFeedback.warning(
          context,
          "Offline — Pending Sync. Receipt: $receiptNo. ${queueReason ?? ''} Official invoice number will be assigned when synced.${whatsappWasRequested ? ' WhatsApp invoice was not prepared; send it after synchronization.' : ''}",
        );
      } else if (creditLimitNotice != null) {
        AppFeedback.warning(
          context,
          creditLimitNotice.overrideUsed
              ? 'Sale $receiptNo created with an authorized credit-limit override. ${creditLimitNotice.summary}'
              : 'Sale $receiptNo created with a credit-limit warning. ${creditLimitNotice.summary}',
        );
      } else {
        final postedReturn = res?['data']?['return'];
        if (postedReturn is Map) {
          final returned = _metaNum(postedReturn['return_credit']);
          final appliedOld = _metaNum(postedReturn['applied_to_original']);
          final appliedExchange = _metaNum(postedReturn['applied_to_exchange']);
          final refunded = _metaNum(postedReturn['refunded']);
          final creditLeft = _metaNum(postedReturn['customer_credit_left']);
          final postedReturnNo = (postedReturn['return_no'] ?? receiptNo).toString();
          final creditSuffix = creditLeft > .004
              ? ' • ${AppCurrency.format(creditLeft)} customer credit'
              : '';
          AppFeedback.success(
            context,
            'Return $postedReturnNo posted: '
            '${AppCurrency.format(returned)} credit • '
            '${AppCurrency.format(appliedOld)} old balance • '
            '${AppCurrency.format(appliedExchange)} exchange • '
            '${AppCurrency.format(refunded)} refunded$creditSuffix.',
          );
        } else {
          AppFeedback.success(
            context,
            "Sale $receiptNo created successfully. Ready for next sale.",
          );
        }
      }
      // Return focus to the product search panel so the cashier can start
      // the next sale immediately without touching the mouse.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _productSearchFocusNode.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, "Failed to create sale: $e");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _addPendingWhatsAppTask({
    required String receiptNo,
    required WhatsAppInvoicePreparation prepared,
    required String message,
  }) {
    if (!mounted) return;
    setState(() {
      _pendingWhatsAppTasks.insert(
        0,
        _PendingWhatsAppTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-${_postSaleTaskSequence++}',
          receiptNo: receiptNo,
          prepared: prepared,
          message: message,
        ),
      );
      // Keep a useful recent queue without allowing a busy shift to grow this
      // state forever. Older generated files remain on disk and can be resent
      // from the sale later.
      if (_pendingWhatsAppTasks.length > 8) {
        _pendingWhatsAppTasks.removeRange(8, _pendingWhatsAppTasks.length);
      }
    });
  }

  Future<void> _openPendingWhatsAppTask(_PendingWhatsAppTask task) async {
    if (task.opening) return;
    setState(() => task.opening = true);
    try {
      final copied = await WhatsAppInvoiceService.instance
          .copyFilesToClipboard(task.prepared.attachmentPaths);
      await WhatsAppInvoiceService.instance.openChat(
        phone: task.prepared.normalizedPhone,
        message: task.message,
      );
      if (!mounted) return;
      if (copied) {
        setState(
          () => _pendingWhatsAppTasks.removeWhere((t) => t.id == task.id),
        );
      } else {
        // Keep the task visible so the cashier still has a one-click folder
        // fallback instead of losing the generated invoice.
        setState(() => task.opening = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            copied
                ? '${task.receiptNo}: WhatsApp opened. Press Ctrl+V, then Send.'
                : '${task.receiptNo}: WhatsApp opened. Clipboard copy failed; use the folder button on the ready task to attach the ${task.prepared.attachmentDescription}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => task.opening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open WhatsApp for ${task.receiptNo}: $e')),
      );
    }
  }

  void _dismissPendingWhatsAppTask(_PendingWhatsAppTask task) {
    setState(() => _pendingWhatsAppTasks.removeWhere((t) => t.id == task.id));
  }

  Widget _buildPostSaleTaskPanel() {
    if (_pendingWhatsAppTasks.isEmpty) return const SizedBox.shrink();
    final visible = _pendingWhatsAppTasks.take(3).toList(growable: false);
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
              child: Row(
                children: [
                  const Icon(Icons.chat_rounded, size: 17, color: Color(0xFF128C7E)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _pendingWhatsAppTasks.length == 1
                          ? 'WhatsApp invoice ready'
                          : '${_pendingWhatsAppTasks.length} WhatsApp invoices ready',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  if (_pendingWhatsAppTasks.length > 3)
                    Text(
                      '+${_pendingWhatsAppTasks.length - 3} more',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            ...visible.map(
              (task) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.receiptNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+${task.prepared.normalizedPhone} • ${task.prepared.attachmentDescription}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: task.opening
                          ? null
                          : () => _openPendingWhatsAppTask(task),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      ),
                      icon: task.opening
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text('Open', style: TextStyle(fontSize: 10.5)),
                    ),
                    IconButton(
                      tooltip: 'Open attachment folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: task.opening
                          ? null
                          : () => WhatsAppInvoiceService.instance
                              .openInvoiceFolder(task.prepared.primaryPath),
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      visualDensity: VisualDensity.compact,
                      onPressed: task.opening
                          ? null
                          : () => _dismissPendingWhatsAppTask(task),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetForNextSale({bool keepInitialCustomer = false}) {
    setState(() {
      _items = [];
      _payments = [];
      discountController.text = '0';
      taxController.text = '0';
      shippingController.text = '0';
      cashReceivedController.clear();
      saleReferenceController.clear();
      _saleMethod = null;
      _selectedVendor = null;
      _selectedVendorId = null;
      _selectedUser = null;
      _selectedUserId = null;
      _selectedDeliveryBoy = null;
      _selectedDeliveryBoyId = null;
      _autoCashIfEmpty = true;
      _sendInvoiceOnWhatsApp = false;
      _showProfitInsight = false;

      if (!keepInitialCustomer) {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _selectedAreaId = null;
        _customerLocked = false;
        customerNameController.clear();
        customerPhoneController.clear();
        addressController.clear();
      }
    });
  }

  Future<List<ProductRef>> _queryProducts(String q) async {
    try {
      final res = await _productService.getProducts(
        page: 1,
        search: q,
        vendorId: _selectedVendorId,
      );
      final data = res['data'];
      List list = const [];

      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map && first['products'] is List) {
          list = first['products'] as List;
        }
      }

      double _tp(Map m) {
        for (final k in [
          'tp',
          'sell_price',
          'price',
          'unit_price',
          'default_price',
        ]) {
          final v = m[k];
          if (v != null) {
            final n = double.tryParse(v.toString());
            if (n != null) return n;
          }
        }
        return 0.0;
      }

      double? _stock(Map m) {
        final raw = m['branch_stock'] ?? m['stock'] ?? m['quantity_in_stock'];
        if (raw == null) return null;
        if (raw is Map) {
          final qty = raw['quantity'] ?? raw['qty'] ?? raw['in_stock'];
          return double.tryParse(qty?.toString() ?? '');
        }
        return double.tryParse(raw.toString());
      }

      return list
          .map<ProductRef>((raw) {
            final m = raw as Map<String, dynamic>;
            return ProductRef(
              id: _metaInt(m['id'] ?? m['product_id']) ?? 0,
              name: (m['name'] ?? m['title'] ?? 'Unnamed').toString(),
              tp: _tp(m),
              sku: (m['sku'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['sku'].toString().trim(),
              barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                  ? null
                  : m['barcode'].toString().trim(),
              stock: _stock(m),
              raw: m,
            );
          })
          .toList(growable: false);
    } catch (_) {
      // Offline / server-unreachable fallback: search the local SQLite catalog
      // so the product autocomplete keeps working with no connectivity.
      // Uses the same CatalogCacheService that the barcode scanner already falls
      // back to, giving the cashier a consistent offline experience.
      try {
        final branchIdInt = int.tryParse(_effectiveBranchIdStr());
        final offlineRows = await CatalogCacheService.instance.searchProducts(
          q,
          branchId: branchIdInt,
          vendorId: _selectedVendorId,
          limit: 50,
        );
        return offlineRows.map<ProductRef>((m) {
          double tp = 0;
          for (final k in const ['price', 'tp', 'sell_price', 'unit_price']) {
            final v = m[k];
            if (v != null) {
              final n = double.tryParse(v.toString());
              if (n != null) {
                tp = n;
                break;
              }
            }
          }
          return ProductRef(
            id: _metaInt(m['id']) ?? 0,
            name: (m['name'] ?? 'Unnamed').toString(),
            tp: tp,
            sku: (m['sku'] ?? '').toString().trim().isEmpty
                ? null
                : m['sku'].toString().trim(),
            barcode: (m['barcode'] ?? '').toString().trim().isEmpty
                ? null
                : m['barcode'].toString().trim(),
            stock: null, // branch_stock not stored in the SQLite cache shape
            raw: m,
          );
        }).toList(growable: false);
      } catch (_) {
        return const <ProductRef>[];
      }
    }
  }

  // helpers
  double _toDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0.0;
  String _money(num v) => v.toStringAsFixed(2);
  Color _balanceColor(double balance) {
    if (balance > 0) return Colors.red;
    if (balance < 0) return Colors.orange;
    return Colors.green;
  }


  static SingleActivator _ctrl(LogicalKeyboardKey key) => SingleActivator(key, control: true);
  static SingleActivator _cmd(LogicalKeyboardKey key) => SingleActivator(key, meta: true);
  static SingleActivator _ctrlShift(LogicalKeyboardKey key) => SingleActivator(key, control: true, shift: true);
  static SingleActivator _cmdShift(LogicalKeyboardKey key) => SingleActivator(key, meta: true, shift: true);

  void _focusBarcodeScanner() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  /// Focus [node] and select all text in [ctrl] so typing replaces the current
  /// value. Used for numeric fields (discount, tax, cash received).
  void _focusAndSelectAll(FocusNode node, TextEditingController ctrl) {
    node.requestFocus();
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
  }

  /// After an autocomplete dropdown closes (selection or clear), focus drifts
  /// out of the Create Sale shortcut scope.  Schedule a post-frame callback to
  /// return focus to the page node so local shortcuts (F2, Ctrl+Enter, etc.)
  /// work again immediately without requiring a manual click.
  void _restoreSaleScreenFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      _pageFocusNode.requestFocus();
    });
  }

  // ── Derived cart ID set for the product panel in-cart badges ────────────
  Set<int> get _cartProductIds {
    return _items
        .map((i) => int.tryParse(i['product_id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toSet();
  }

  Map<int, double> get _cartProductQuantities {
    final result = <int, double>{};
    for (final item in _items) {
      final id = int.tryParse(item['product_id']?.toString() ?? '') ?? 0;
      final qty = double.tryParse(item['quantity']?.toString() ?? '') ?? 0.0;
      if (id <= 0 || qty <= 0) continue;
      result[id] = (result[id] ?? 0) + qty;
    }
    return result;
  }

  // ── Split-tender helpers ────────────────────────────────────────────────
  double _pmAmt(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  bool _methodIsDrawer(String? code) {
    final pm = context.read<PaymentMethodProvider>();
    return pm.byCode(code ?? '')?.affectsCashDrawer ??
        (code == null || code == 'cash');
  }

  /// Total tendered: explicit split rows if any, else the auto-cash full amount.
  double _salePaid(double total) {
    if (_payments.isNotEmpty) {
      return _payments.fold<double>(0.0, (s, p) => s + _pmAmt(p['amount']));
    }
    if (_autoCashIfEmpty && total > 0) return total;
    return 0.0;
  }

  /// Cash (drawer) portion due — drives the Cash Received / Change fields and
  /// what gets printed on the invoice.
  double _saleCashDue(double total) {
    if (_payments.isNotEmpty) {
      return _payments
          .where((p) => _methodIsDrawer(p['method']?.toString()))
          .fold<double>(0.0, (s, p) => s + _pmAmt(p['amount']));
    }
    if (_autoCashIfEmpty && total > 0) {
      final def = context.read<PaymentMethodProvider>().defaultMethod;
      final code = _saleMethod ?? def?.method;
      return _methodIsDrawer(code) ? total : 0.0;
    }
    return 0.0;
  }

  Future<void> _addSalePaymentDialog(double total) async {
    final pm = context.read<PaymentMethodProvider>();
    var methods = pm.activeMethods;
    if (methods.isEmpty) {
      await pm.reload();
      methods = pm.activeMethods;
    }
    if (methods.isEmpty) {
      if (mounted) {
        AppFeedback.error(context, 'No payment methods configured for this branch.');
      }
      return;
    }

    final remaining = total - _salePaid(total);
    final amountCtl = TextEditingController(
        text: remaining > 0 ? remaining.toStringAsFixed(2) : '');
    final refCtl = TextEditingController();
    String method = (pm.defaultMethod ?? methods.first).method;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final selected = pm.byCode(method);
          final showReference = selected != null && !selected.affectsCashDrawer;
          return AlertDialog(
            title: const Text('Add Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: methods
                      .map((m) => DropdownMenuItem(
                            value: m.method,
                            child: Text(m.displayName),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => method = v ?? method),
                ),
                if (showReference) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtl,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
                      hintText: 'Txn / approval / cheque no…',
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountCtl.text.trim()) ?? 0.0;
                  if (amount <= 0) return;
                  final ref = refCtl.text.trim();
                  setState(() => _payments.add({
                        'amount': amount,
                        'method': method,
                        if (ref.isNotEmpty) 'reference': ref,
                      }));
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAll = context.watch<BranchProvider>().isAll;
    final auth = context.watch<AuthProvider>();
    final token = auth.token!;
    final activeBranchId = context.watch<BranchProvider>().selectedBranchId;
    if (!_isEditing &&
        activeBranchId != _saleSourcesBranchId &&
        !_saleSourcesReloadScheduled) {
      _saleSourcesReloadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _saleSourcesReloadScheduled = false;
        if (!mounted) return;
        await _loadSaleSources();
      });
    }
    if (!_isEditing &&
        activeBranchId != _customerAreasBranchId &&
        !_customerAreasReloadScheduled) {
      _customerAreasReloadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _customerAreasReloadScheduled = false;
        if (!mounted) return;
        await _loadCustomerAreas();
      });
    }

    if (_isEditing && _editLoading) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Column(
          children: [
            const SaleStatusBar(light: true, showBackButton: true),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Loading posted invoice…',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.navy,
                          ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'The latest revision, payments and current invoice items are being loaded.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_isEditing && _editLoadError != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Column(
          children: [
            const SaleStatusBar(light: true, showBackButton: true),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: EnterprisePanel(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 34, color: AppTheme.danger),
                        const SizedBox(height: 12),
                        const Text(
                          'Unable to load posted sale',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.navy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _editLoadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadSaleForEdit,
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Feature flags — watched so the UI reacts when settings change.
    final featureProvider = context.watch<BranchFeatureProvider>();
    final deliveryEnabled = featureProvider.deliveryEnabled;
    final saleVendorEnabled = featureProvider.saleVendorEnabled;

    // Clear forbidden state when a flag is turned off while screen is open.
    // Runs in the build phase via post-frame to avoid calling setState mid-build.
    if (!_isEditing && !deliveryEnabled && (_selectedDeliveryBoyId != null || _selectedDeliveryBoy != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedDeliveryBoy = null;
            _selectedDeliveryBoyId = null;
          });
        }
      });
    }
    if (!_isEditing && !saleVendorEnabled && (_selectedVendorId != null || _selectedVendor != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedVendor = null;
            _selectedVendorId = null;
            // Do NOT clear items — vendor change only affects product filtering,
            // not already-added items.
          });
        }
      });
    }

    double rowNum(v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    final subtotal = _items.fold<double>(0.0, (sum, i) {
      final qty = rowNum(i['quantity']);
      if (qty <= 0) return sum;
      final price = rowNum(i['price']);
      final disc = rowNum(i['discount_pct']);
      final discType = (i['discount_type'] ?? 'percentage').toString();
      return sum + _lineTotal(price: price, qty: qty, discPct: disc, discountType: discType);
    });
    final discount = _toDouble(discountController);
    final tax = _toDouble(taxController);
    final shipping = _toDouble(shippingController);
    final saleTotal = subtotal - discount + tax + shipping;
    final returnCredit = _linkedReturnCredit;
    final appliedOld = returnCredit.clamp(0.0, _linkedReturnOriginalOutstanding).toDouble();
    final afterOld = (returnCredit - appliedOld).clamp(0.0, double.infinity).toDouble();
    final appliedExchange = afterOld.clamp(0.0, saleTotal.clamp(0.0, double.infinity)).toDouble();
    final refundDue = (afterOld - appliedExchange).clamp(0.0, double.infinity).toDouble();
    final customerPays = (saleTotal - appliedExchange).clamp(0.0, double.infinity).toDouble();
    // Signed checkout amount: positive means collect from customer; negative
    // means refundable/credit value remains after settling old AR + exchange.
    final total = customerPays > .004 ? customerPays : -refundDue;

    // Change is computed against the CASH (drawer) portion only — a split of
    // 1000 cash + 500 bank on a 1500 bill has no change; 2000 cash on a 1500
    // bill shows 500 change and prints it on the invoice.
    final cashDue = _saleCashDue(total);
    final enteredCashReceived = _toDouble(cashReceivedController);
    final effectiveCashReceived =
        enteredCashReceived > 0 ? enteredCashReceived : cashDue;
    final changeAmount = cashDue > 0
        ? (effectiveCashReceived - cashDue).clamp(0.0, double.infinity).toDouble()
        : 0.0;

    // ── Focus + shortcut scope ──────────────────────────────────────────────
    // CallbackShortcuts must be an ANCESTOR of Focus(_pageFocusNode) so that
    // the local bindings fire when _pageFocusNode holds focus (e.g. after
    // clicking blank space). In the old layout _pageFocusNode was the parent
    // of CallbackShortcuts — making it invisible to the local handler, so
    // key events fell through to the global AppKeyboardShortcuts (where F2
    // opens a new Create Sale screen instead of the product picker here).
    //
    // onTap instead of onTapDown: by the time onTap fires, any inner widget
    // that was tapped (TextField, button) has already called requestFocus().
    // We only take focus when no text-editing widget currently holds it, so
    // TextFields stay interactive and shortcuts are never swallowed.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final pf = FocusManager.instance.primaryFocus;
        final ctx = pf?.context;
        final isEditingText = ctx != null &&
            ctx.findAncestorWidgetOfExactType<EditableText>() != null;
        if (!isEditingText) {
          _pageFocusNode.requestFocus();
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f2): () => _addItemManual(),
            _ctrl(LogicalKeyboardKey.keyI): () => _addItemManual(),
            _cmd(LogicalKeyboardKey.keyI): () => _addItemManual(),
            if (!_isEditing) ...{
              const SingleActivator(LogicalKeyboardKey.f3): () => _pickCustomer(),
              _ctrlShift(LogicalKeyboardKey.keyC): () => _pickCustomer(),
              _cmdShift(LogicalKeyboardKey.keyC): () => _pickCustomer(),
            },
            // Delivery shortcuts — only active when delivery module is enabled.
            if (deliveryEnabled) ...{
              const SingleActivator(LogicalKeyboardKey.f4): () => _pickDeliveryBoy(),
              _ctrlShift(LogicalKeyboardKey.keyD): () => _pickDeliveryBoy(),
              _cmdShift(LogicalKeyboardKey.keyD): () => _pickDeliveryBoy(),
              _ctrlShift(LogicalKeyboardKey.keyB): () {
                _deliveryBoyController.clear();
                _deliveryBoyFocusNode.requestFocus();
              },
            },
            const SingleActivator(LogicalKeyboardKey.f9): _focusBarcodeScanner,
            _ctrl(LogicalKeyboardKey.enter): () => _submitSale(),
            _cmd(LogicalKeyboardKey.enter): () => _submitSale(),
            _ctrl(LogicalKeyboardKey.numpadEnter): () => _submitSale(),
            _cmd(LogicalKeyboardKey.numpadEnter): () => _submitSale(),
            _ctrl(LogicalKeyboardKey.slash): () =>
                showAppShortcutGuide(context, includeSaleCreate: true),
            _cmd(LogicalKeyboardKey.slash): () =>
                showAppShortcutGuide(context, includeSaleCreate: true),
            if (!_isEditing)
              _ctrlShift(LogicalKeyboardKey.keyU): () {
                _customerController.clear();
                _customerFocusNode.requestFocus();
              },
            _ctrlShift(LogicalKeyboardKey.keyS): () {
              _salesmanController.clear();
              _salesmanFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyP): () {
              _productSearchFocusNode.requestFocus();
            },
            // Vendor focus shortcuts — only when sale vendor is enabled.
            if (saleVendorEnabled) ...{
              _ctrlShift(LogicalKeyboardKey.keyV): () {
                _vendorController.clear();
                _vendorFocusNode.requestFocus();
              },
              _cmdShift(LogicalKeyboardKey.keyV): () {
                _vendorController.clear();
                _vendorFocusNode.requestFocus();
              },
            },
            _ctrlShift(LogicalKeyboardKey.keyN): () {
              _walkInNameFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyH): () {
              _walkInPhoneFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyA): () {
              _walkInAddressFocusNode.requestFocus();
            },
            _ctrlShift(LogicalKeyboardKey.keyR): () {
              _focusAndSelectAll(_cashReceivedFocusNode, cashReceivedController);
            },
            _cmdShift(LogicalKeyboardKey.keyR): () {
              _focusAndSelectAll(_cashReceivedFocusNode, cashReceivedController);
            },
            _ctrlShift(LogicalKeyboardKey.keyG): () {
              _focusAndSelectAll(_discountFocusNode, discountController);
            },
            _ctrlShift(LogicalKeyboardKey.keyT): () {
              _focusAndSelectAll(_taxFocusNode, taxController);
            },
            _ctrlShift(LogicalKeyboardKey.keyS): () {
              _focusAndSelectAll(_shippingFocusNode, shippingController);
            },
          },
          child: Focus(
            focusNode: _pageFocusNode,
            autofocus: true,
            skipTraversal: true,
            child: Scaffold(
              backgroundColor: AppTheme.bg,
              body: Form(
              key: _formKey,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Light status bar (30 px) ──────────────────────
                      const SaleStatusBar(light: true, showBackButton: true),
                      if (_isEditing) _buildAmendmentHeader(total),

                      // ── 2-panel workspace ─────────────────────────────
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LEFT 57% – cart workspace
                            Expanded(
                              flex: 57,
                              child: _buildCartWorkspace(
                                token: token,
                                isAll: isAll,
                                subtotal: subtotal,
                                deliveryEnabled: deliveryEnabled,
                                saleVendorEnabled: saleVendorEnabled,
                                canViewProfit:
                                    auth.hasPermission('view-sale-profit'),
                              ),
                            ),

                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppTheme.border,
                            ),

                            // RIGHT 43% – product browser with own search bar
                            Expanded(
                              flex: 43,
                              child: SaleProductPanel(
                                key: ValueKey(_selectedVendorId),
                                token: token,
                                vendorId: _selectedVendorId,
                                branchId: int.tryParse(_effectiveBranchIdStr()),
                                customerType: _selectedCustomerType,
                                cartProductIds: _cartProductIds,
                                cartProductQuantities: _cartProductQuantities,
                                canCreateVariant:
                                    auth.hasPermission('manage-products'),
                                onProductTapped: (p) =>
                                    setState(() => _addOrIncrementProduct(p)),
                                onOpenModal: _addItemManual,
                                showSearchBar: true,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Split-tender summary (visible when >1 tender entered)
                      if (_payments.isNotEmpty) _buildSplitStrip(total),

                      // ── Fixed bottom action bar ───────────────────────
                      _buildBottomBar(
                        total: total,
                        changeAmount: changeAmount,
                      ),
                    ],
                  ),

                  // Hidden 1×1 barcode TextField — offset matches light bar (30 px)
                  Positioned(
                    left: 0,
                    top: 30,
                    child: _hiddenBarcodeField(),
                  ),

                  // Non-modal post-sale task surface. It never requests focus,
                  // so barcode scanning/typing for the next invoice continues
                  // uninterrupted while WhatsApp attachments finish.
                  if (_pendingWhatsAppTasks.isNotEmpty)
                    Positioned(
                      right: 12,
                      bottom: 76,
                      child: _buildPostSaleTaskPanel(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Cart workspace (left 57%) ────────────────────────────────────────────
  Widget _buildCartWorkspace({
    required String token,
    required bool isAll,
    required double subtotal,
    required bool deliveryEnabled,
    required bool saleVendorEnabled,
    required bool canViewProfit,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. FIXED — party selectors (Customer, Salesman, Delivery Boy, Vendor)
          PartySectionCard(
            isAll: isAll,
            selectedCustomer: _selectedCustomer,
            selectedUser: _selectedUser,
            selectedDeliveryBoy: _selectedDeliveryBoy,
            selectedBranch: _selectedBranch,
            selectedVendor: _selectedVendor,
            saleSources: _saleSources,
            selectedSaleSourceId: _selectedSaleSourceId,
            onSaleSourceChanged: (value) =>
                setState(() => _selectedSaleSourceId = value),
            canManageSaleSources:
                context.watch<AuthProvider>().hasPermission('manage-sale-sources'),
            onManageSaleSources: _manageSaleSources,
            branchId: _effectiveBranchIdStr(),
            token: token,
            showDeliveryBoy:
                deliveryEnabled || (_isEditing && _selectedDeliveryBoyId != null),
            showVendor:
                saleVendorEnabled || (_isEditing && _selectedVendorId != null),
            customerLocked: _isEditing,
            customerLockMessage:
                'Customer identity is locked on posted invoices. Use the dedicated customer-transfer workflow when an AR party genuinely needs correction.',
            onPickCustomer: _pickCustomer,
            onPickUser: _pickUser,
            onPickDeliveryBoy: _pickDeliveryBoy,
            onPickVendor: _pickVendor,
            onClearVendor: () => setState(() {
              _selectedVendor = null;
              _selectedVendorId = null;
              if (!_isEditing) _items = [];
            }),
            onBrowseCustomerSheet: _openCustomerSheet,
            onApplyCustomer: _applyCustomerSelection,
            onBrowseUserSheet: _openUserSheet,
            onApplyUser: _applyUserSelection,
            onBrowseDeliveryBoySheet: _openDeliveryBoySheet,
            onApplyDeliveryBoy: _applyDeliveryBoySelection,
            onBrowseVendorSheet: _openVendorSheet,
            onApplyVendor: _applyVendorSelection,
            customerFocusNode: _customerFocusNode,
            salesmanFocusNode: _salesmanFocusNode,
            deliveryBoyFocusNode: _deliveryBoyFocusNode,
            vendorFocusNode: _vendorFocusNode,
            customerController: _customerController,
            salesmanController: _salesmanController,
            deliveryBoyController: _deliveryBoyController,
            vendorController: _vendorController,
          ),

          if ((widget.initialReturnInvoice ?? '').trim().isNotEmpty)
            _buildReturnContextBanner(),

          // 2. FIXED — walk-in/customer snapshot fields are immutable once the
          // invoice is posted. Customer identity is already shown above in the
          // locked party field, so hiding these edit-only inputs avoids a
          // misleading control that would not be persisted by an amendment.
          if (!_isEditing) _buildWalkInCompact(),

          const Divider(height: 1, thickness: 1, color: AppTheme.border),

          // 3. FIXED — product autocomplete + scanner + F2
          _buildInputRow(),

          // 4. FIXED — cart table column headers
          _buildCartTableHeader(),

          // 5. INDEPENDENTLY SCROLLABLE — cart item rows
          Expanded(
            child: ItemsTable(
              compact: true,
              items: _items,
              onQueryProducts: _queryProducts,
              onAddItem: _addItemManual,
              onItemsChanged: (next) => setState(() => _items = next),
              onReturnLinkRequested: _isEditing ? null : _linkReturnForRow,
              onProfitInsight:
                  canViewProfit ? _showItemProfitInsight : null,
            ),
          ),

          // 6. FIXED — subtotal + editable discount/tax
          const Divider(height: 1, thickness: 1, color: AppTheme.border),
          _buildSummaryRow(
            subtotal: subtotal,
            canViewProfit: canViewProfit,
          ),
        ],
      ),
    );
  }

  Widget _buildReturnContextBanner() {
    final invoice = (widget.initialReturnInvoice ?? '').trim();
    if (_isEditing || invoice.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(.08),
        border: const Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_return_outlined,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Return / Exchange for $invoice • Enter a negative quantity on the item being returned. Original delivery is non-refundable.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fixed cart table column header row ─────────────────────────────────
  Widget _buildCartTableHeader() {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: Text('Product', style: style)),
          Expanded(
            flex: 2,
            child: Text('T.P', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Disc (%)', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Text('Qty', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Text('Total', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 28),
        ],
      ),
    );
  }

  // ── Compact walk-in section (two rows: name+phone | address) ────────────
  Widget _buildWalkInCompact() {
    final inputDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: label + name + phone + clear
          Row(
            children: [
              const Text(
                'Walk-in',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Focus: Ctrl+Shift+N',
                  child: SizedBox(
                    height: 40,
                    child: TextFormField(
                      controller: customerNameController,
                      focusNode: _walkInNameFocusNode,
                      decoration: inputDecoration.copyWith(
                        hintText: 'Customer name',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Focus: Ctrl+Shift+H',
                child: SizedBox(
                  width: 120,
                  height: 40,
                  child: TextFormField(
                    controller: customerPhoneController,
                    focusNode: _walkInPhoneFocusNode,
                    keyboardType: TextInputType.phone,
                    decoration: inputDecoration.copyWith(hintText: 'Phone'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_selectedCustomerId != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: _clearCustomerSelection,
                  borderRadius: BorderRadius.circular(4),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          // Row 2: address + optional WhatsApp invoice destination
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Focus: Ctrl+Shift+A',
                  child: SizedBox(
                    height: 40,
                    child: TextFormField(
                      controller: addressController,
                      focusNode: _walkInAddressFocusNode,
                      decoration: inputDecoration.copyWith(
                        hintText: 'Address (optional)',
                        prefixIcon: const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              // The WhatsApp invoice toggle is only shown when the branch has
              // the whatsapp_invoice addon active. When the addon is off the
              // toggle is hidden and _sendInvoiceOnWhatsApp stays false, so the
              // normal thermal/PDF printing path is completely unaffected.
              if (context.watch<AuthProvider>().hasAddon('whatsapp_invoice')) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Prepare this receipt for WhatsApp after the sale is saved. Registered customers always use their primary phone.',
                  child: InkWell(
                    onTap: _submitting
                        ? null
                        : () => setState(() {
                              _sendInvoiceOnWhatsApp =
                                  !_sendInvoiceOnWhatsApp;
                            }),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _sendInvoiceOnWhatsApp,
                          onChanged: _submitting
                              ? null
                              : (value) => setState(() {
                                    _sendInvoiceOnWhatsApp = value ?? false;
                                  }),
                          visualDensity: VisualDensity.compact,
                        ),
                        const Text(
                          'WhatsApp invoice',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ], // end whatsapp_invoice addon gate
              if (_sendInvoiceOnWhatsApp) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(maxWidth: 230),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(6),
                    color: AppTheme.surfaceSoft,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_rounded,
                        size: 14,
                        color: Color(0xFF128C7E),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _whatsAppDestinationPhone().isEmpty
                              ? 'Primary phone required'
                              : 'To: ${_whatsAppDestinationPhone()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: DropdownButtonFormField<int>(
                    value: _areaById(_selectedAreaId) == null
                        ? null
                        : _selectedAreaId,
                    isExpanded: true,
                    decoration: inputDecoration.copyWith(
                      labelText: 'Town / Area',
                      hintText: 'Select sale area',
                      prefixIcon: const Icon(
                        Icons.location_city_outlined,
                        size: 15,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    items: _customerAreas
                        .where(_areaActive)
                        .map(
                          (area) => DropdownMenuItem<int>(
                            value: _metaInt(area['id']),
                            child: Text(
                              (area['name'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .where((item) => item.value != null)
                        .toList(growable: false),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _selectedAreaId = value),
                  ),
                ),
              ),
              if (_selectedAreaId != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Clear sale area',
                  child: SizedBox(
                    width: 38,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _selectedAreaId = null),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppTheme.border),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
                ),
              ],
              if (context.read<AuthProvider>().hasPermission('manage-customers')) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Create or rename Town / Area',
                  child: SizedBox(
                    width: 38,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _manageCustomerAreas,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppTheme.border),
                      ),
                      child: const Icon(Icons.tune_rounded, size: 17),
                    ),
                  ),
                ),
              ],
              if (_selectedCustomerId != null &&
                  _metaInt(_selectedCustomer?['area_id']) != null &&
                  _selectedAreaId != _metaInt(_selectedCustomer?['area_id'])) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message:
                      'This changes only this sale. The customer default area is not modified.',
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
          if (_selectedCustomerId != null &&
              _selectedCustomerSecondaryPhones.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.print_outlined,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Invoice phones:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedCustomerSecondaryPhones.join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Input row: product autocomplete + scanner + F2 ─────────────────────
  Widget _buildInputRow() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Row(
        children: [
          // Product autocomplete — adds to cart on selection
          Expanded(
            child: _CartProductSearch(
              focusNode: _productSearchFocusNode,
              controller: _productSearchController,
              onQuery: _queryProducts,
              onSelected: (ref) {
                // Route through the centralized merge/increment method for
                // both raw-data-available and raw-data-missing cases so that
                // selecting the same product twice always increments the
                // existing row rather than appending a new one.
                final productMap = ref.raw ??
                    <String, dynamic>{
                      'id': ref.id,
                      'name': ref.name,
                      'price': ref.tp,
                    };
                setState(() => _addOrIncrementProduct(productMap));
              },
            ),
          ),
          const SizedBox(width: 6),

          // Scanner toggle (F9)
          Tooltip(
            message: 'Focus barcode scanner  (F9)',
            child: InkWell(
              onTap: _focusBarcodeScanner,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _scannerEnabled
                      ? AppTheme.success.withOpacity(.10)
                      : AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _scannerEnabled
                        ? AppTheme.success.withOpacity(.40)
                        : AppTheme.border,
                  ),
                ),
                child: Icon(
                  _scannerEnabled
                      ? Icons.check_circle_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 16,
                  color:
                      _scannerEnabled ? AppTheme.success : AppTheme.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // F2 / Add Items (opens full modal picker for multi-select)
          Tooltip(
            message: 'Add items  (F2)',
            child: OutlinedButton.icon(
              onPressed: _addItemManual,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('F2', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary row: item count + subtotal + editable discount/tax ─────────
  Widget _buildSummaryRow({
    required double subtotal,
    required bool canViewProfit,
  }) {
    final profitSummary = _currentProfitSummary();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              // Item count + subtotal (read-only)
              Text(
                '${_items.length} item${_items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Sub: ${AppCurrency.format(subtotal)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (canViewProfit) ...[
                const SizedBox(width: 5),
                Tooltip(
                  message: _showProfitInsight
                      ? 'Hide profit insight'
                      : 'Show profit insight',
                  child: Material(
                    color: _showProfitInsight
                        ? AppTheme.primary.withOpacity(.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () => setState(
                        () => _showProfitInsight = !_showProfitInsight,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          _showProfitInsight
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 15,
                          color: _showProfitInsight
                              ? AppTheme.primary
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),

              // Order Discount (editable inline)
              const Text(
                'Disc(-):',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Focus: Ctrl+Shift+G',
                child: SizedBox(
                  width: 70,
                  height: 36,
                  child: TextField(
                    controller: discountController,
                    focusNode: _discountFocusNode,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Order Tax (editable inline)
              const Text(
                'Tax(+):',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Focus: Ctrl+Shift+T',
                child: SizedBox(
                  width: 70,
                  height: 36,
                  child: TextField(
                    controller: taxController,
                    focusNode: _taxFocusNode,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Shipping Charges (editable inline)
              const Text(
                'Ship(+):',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Shipping Charges — Focus: Ctrl+Shift+S',
                child: SizedBox(
                  width: 70,
                  height: 36,
                  child: TextField(
                    controller: shippingController,
                    focusNode: _shippingFocusNode,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_linkedReturnCredit > .004)
          Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment_return_outlined, size: 15, color: AppTheme.warning),
                const SizedBox(width: 6),
                Text(
                  'Return credit ${AppCurrency.format(_linkedReturnCredit)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.navy),
                ),
                const SizedBox(width: 12),
                Text(
                  'Old invoice outstanding ${AppCurrency.format(_linkedReturnOriginalOutstanding)}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                const Text(
                  'Original delivery refund: 0',
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: canViewProfit && _showProfitInsight
              ? SaleProfitStrip(
                  key: const ValueKey('sale-profit-strip'),
                  summary: profitSummary,
                  onDetails: _showInvoiceProfitDetails,
                )
              : const SizedBox.shrink(
                  key: ValueKey('sale-profit-strip-hidden'),
                ),
        ),
      ],
    );
  }

  // ── Split-tender summary strip ──────────────────────────────────────────
  Widget _buildSplitStrip(double total) {
    final pm = context.read<PaymentMethodProvider>();
    final paid = _salePaid(total);
    final balance = total - paid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _payments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final p = _payments[i];
                  final name = pm.displayNameFor(p['method']?.toString());
                  final amt = AppCurrency.format(_pmAmt(p['amount']));
                  final ref = (p['reference'] ?? '').toString().trim();
                  return InputChip(
                    label: Text(ref.isEmpty ? '$name  $amt' : '$name  $amt · $ref'),
                    onDeleted: () => setState(() => _payments.removeAt(i)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('Paid ${AppCurrency.format(paid)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 10),
          Text(
            'Balance ${AppCurrency.format(balance)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: balance.abs() < 0.005 ? AppTheme.success : AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmendmentHeader(double revisedTotal) {
    final sale = _editSale ?? const <String, dynamic>{};
    final invoice = (sale['invoice_no'] ?? widget.editSaleId ?? '').toString();
    final difference = revisedTotal - _originalTotal;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.09),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.primary.withOpacity(.18)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note_rounded, size: 15, color: AppTheme.primary),
                SizedBox(width: 4),
                Text(
                  'AUDITED EDIT',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            invoice.isEmpty ? 'Posted sale' : invoice,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Revision #$_editRevision',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _AmendmentHeaderMetric(
            label: 'Original',
            value: AppCurrency.format(_originalTotal),
          ),
          const SizedBox(width: 18),
          _AmendmentHeaderMetric(
            label: 'Revised',
            value: AppCurrency.format(revisedTotal),
          ),
          const SizedBox(width: 18),
          _AmendmentHeaderMetric(
            label: 'Difference',
            value:
                '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
            valueColor: difference.abs() <= .004
                ? AppTheme.textMuted
                : difference > 0
                    ? AppTheme.warning
                    : AppTheme.success,
          ),
          const SizedBox(width: 12),
          const Tooltip(
            message:
                'Posted-sale amendments require the server and are committed atomically with stock, COGS, ledger and audit history.',
            child: Icon(Icons.cloud_done_outlined, size: 16, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildAmendmentBottomBar(double total) {
    final difference = total - _originalTotal;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_edu_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posted invoice amendment',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Original financial documents stay preserved',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          _AmendmentBottomMetric(
            label: 'Original',
            value: AppCurrency.format(_originalTotal),
          ),
          const SizedBox(width: 18),
          _AmendmentBottomMetric(
            label: 'Revised',
            value: AppCurrency.format(total),
          ),
          const SizedBox(width: 18),
          _AmendmentBottomMetric(
            label: 'Difference',
            value: '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
            valueColor: difference.abs() <= .004
                ? AppTheme.textMuted
                : difference > 0
                    ? AppTheme.warning
                    : AppTheme.success,
          ),
          const SizedBox(width: 18),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _resetAmendmentDraft,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Reset Changes'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _submitting ? null : _submitAmendment,
            icon: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(_submitting ? 'Saving…' : 'Review Changes  Ctrl+↵'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fixed bottom action bar ──────────────────────────────────────────────
  Widget _buildBottomBar({
    required double total,
    required double changeAmount,
  }) {
    if (_isEditing) return _buildAmendmentBottomBar(total);
    final pm = context.watch<PaymentMethodProvider>();
    final methods = pm.activeMethods;
    final currentMethod = _saleMethod ?? pm.defaultMethod?.method;
    final hasSplit = _payments.isNotEmpty;
    // Show Cash Received/Change whenever a physical-cash portion exists.
    final showCashFields = _saleCashDue(total) > 0;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Auto Cash toggle
          const Text(
            'Auto Cash',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.8,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _autoCashIfEmpty,
              onChanged: (v) => setState(() => _autoCashIfEmpty = v),
            ),
          ),
          const SizedBox(width: 8),

          // Payment method selector (single-tender only; hidden when splitting)
          if (methods.isNotEmpty && !hasSplit)
            SizedBox(
              width: 128,
              height: 44,
              child: DropdownButtonFormField<String>(
                value: currentMethod,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
                items: methods
                    .map((m) => DropdownMenuItem(
                          value: m.method,
                          child: Text(m.displayName, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _saleMethod = v),
              ),
            ),
          const SizedBox(width: 8),

          // Cash Received + Change apply only to physical drawer cash.
          if (showCashFields) ...[
            Tooltip(
              message: 'Focus: Ctrl+Shift+R',
              child: SizedBox(
                width: 110,
                height: 44,
                child: TextField(
                  controller: cashReceivedController,
                  focusNode: _cashReceivedFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'Cash Recv.',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppCurrency.format(changeAmount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: changeAmount > 0 ? AppTheme.success : AppTheme.navy,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ] else if (!hasSplit)
            // Non-drawer tender (KNET/card/bank/cheque): optional reference.
            SizedBox(
              width: 150,
              height: 44,
              child: TextField(
                controller: saleReferenceController,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  hintText: 'Txn / approval',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(width: 8),
          // Split tender — add another payment row (e.g. 1000 cash + 500 bank).
          OutlinedButton.icon(
            onPressed: total > .004 ? () => _addSalePaymentDialog(total) : null,
            icon: const Icon(Icons.call_split_rounded, size: 16),
            label: Text(hasSplit ? 'Add (${_payments.length})' : 'Split'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          const Spacer(),

          // Total payable
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total < -0.004 ? 'Refund / Credit Due' : 'Total Payable',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                AppCurrency.format(total.abs()),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: total < -0.004 ? AppTheme.warning : AppTheme.navy,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Clear cart
          OutlinedButton(
            onPressed: () => _resetForNextSale(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: AppTheme.danger),
              foregroundColor: AppTheme.danger,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),

          // Save without print
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _submitSale(print: false),
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: AppTheme.primary.withOpacity(.5)),
                foregroundColor: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Save + Print (Ctrl+↵)
          SizedBox(
            height: 38,
            child: FilledButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _submitSale(print: true),
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded, size: 15),
              label: Text(
                _submitting ? 'Saving…' : 'Create & Print  Ctrl+↵',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _SaleWorkspaceHeader extends StatelessWidget {
  final String customerLabel;
  final int itemCount;
  final String total;
  final String balance;
  final VoidCallback onAddItems;

  const _SaleWorkspaceHeader({
    required this.customerLabel,
    required this.itemCount,
    required this.total,
    required this.balance,
    required this.onAddItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final title = Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.point_of_sale_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Sale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      customerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          );
          final stats = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlainStat(label: 'Items', value: itemCount.toString()),
              _PlainStat(label: 'Total', value: total),
              _PlainStat(label: 'Balance', value: balance),
            ],
          );
          final button = FilledButton.icon(
            onPressed: onAddItems,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Items'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 12),
                stats,
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              stats,
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _PlainStat extends StatelessWidget {
  final String label;
  final String value;

  const _PlainStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}


// ── Cart product autocomplete (Point 1) ────────────────────────────────────
// Overlay-based dropdown; adds product to cart on selection.
class _CartProductSearch extends StatefulWidget {
  final FocusNode focusNode;
  final TextEditingController controller;
  final Future<List<ProductRef>> Function(String q) onQuery;
  final void Function(ProductRef ref) onSelected;

  const _CartProductSearch({
    required this.focusNode,
    required this.controller,
    required this.onQuery,
    required this.onSelected,
  });

  @override
  State<_CartProductSearch> createState() => _CartProductSearchState();
}

class _CartProductSearchState extends State<_CartProductSearch> {
  final LayerLink _layerLink = LayerLink();

  /// Binds the field and its dropdown into one tap region so a click on the
  /// dropdown is not treated as a tap outside this widget. See the
  /// TextFieldTapRegion note in _buildDropdown for the other half of the fix.
  final Object _tapGroup = Object();
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  List<ProductRef> _suggestions = [];
  int _highlightIndex = -1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    final q = widget.controller.text.trim();
    if (q.isEmpty) {
      _debounce?.cancel();
      _removeOverlay();
      if (mounted) {
        setState(() {
          _suggestions = [];
          _highlightIndex = -1;
          _loading = false;
        });
      }
      return;
    }
    // Show loading immediately, debounce the actual fetch.
    if (mounted) setState(() => _loading = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final results = await widget.onQuery(q);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _highlightIndex = results.isNotEmpty ? 0 : -1;
      _loading = false;
    });
    if (results.isEmpty) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    // Refresh in place rather than tearing down and re-inserting: destroying
    // the entry mid-gesture cancels a click that is already in progress.
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _buildDropdown());
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectIndex(int i) {
    if (i < 0 || i >= _suggestions.length) return;
    final ref = _suggestions[i];
    widget.controller.clear();
    _removeOverlay();
    setState(() {
      _suggestions = [];
      _highlightIndex = -1;
    });
    widget.onSelected(ref);
  }

  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _highlightIndex =
          (_highlightIndex + delta).clamp(0, _suggestions.length - 1);
    });
    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildDropdown() {
    // TextFieldTapRegion == TapRegion(groupId: EditableText). On desktop,
    // EditableText's default onTapOutside unfocuses the field on pointer-DOWN
    // for any tap outside its own group. This dropdown lives in the root
    // Overlay, so it counted as "outside": the field blurred, _onFocusChanged
    // tore the overlay down, and the tap died before pointer-UP reached the
    // row — which is why only Enter could select. Joining the EditableText
    // group is the only thing that prevents that blur. The inner TapRegion
    // keeps our own outside-tap dismissal working.
    return TextFieldTapRegion(
      child: TapRegion(
      groupId: _tapGroup,
      child: CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      offset: const Offset(0, 38),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 420,
          child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, i) {
                final ref = _suggestions[i];
                final highlighted = i == _highlightIndex;
                final sub = [
                  if (ref.sku != null && ref.sku!.isNotEmpty)
                    'SKU: ${ref.sku}',
                  if (ref.barcode != null && ref.barcode!.isNotEmpty)
                    ref.barcode!,
                ].join('  ');
                return GestureDetector(
                  onTap: () => _selectIndex(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: highlighted
                          ? AppTheme.primarySoft
                          : Colors.transparent,
                      border: const Border(
                        bottom: BorderSide(color: AppTheme.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ref.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: highlighted
                                      ? AppTheme.primary
                                      : AppTheme.navy,
                                ),
                              ),
                              if (sub.isNotEmpty)
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppCurrency.format(ref.tp),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                            if (ref.stock != null)
                              Text(
                                'Stock: ${ref.stock!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
    ),
    ),
  );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) => _removeOverlay(),
      child: CompositedTransformTarget(
      link: _layerLink,
      // Focus wraps the TextField so onKeyEvent fires while the TextField has focus.
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveHighlight(1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveHighlight(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (_highlightIndex >= 0) {
              _selectIndex(_highlightIndex);
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _removeOverlay();
            setState(() {
              _suggestions = [];
              _highlightIndex = -1;
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            decoration: InputDecoration(
              hintText: 'Search product… (name / SKU / barcode)',
              prefixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    )
                  : const Icon(Icons.search, size: 16),
              suffixIcon: widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        widget.controller.clear();
                        _removeOverlay();
                        setState(() {
                          _suggestions = [];
                          _highlightIndex = -1;
                        });
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: AppTheme.surfaceSoft,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
      ),
    );
  }
}

class _CreateSaleBottomBar extends StatelessWidget {
  final int itemCount;
  final String total;
  final String paid;
  final String balance;
  final bool submitting;
  final VoidCallback onSubmit;

  const _CreateSaleBottomBar({
    required this.itemCount,
    required this.total,
    required this.paid,
    required this.balance,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.navy.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EnterpriseStatPill(label: 'Items', value: itemCount.toString(), icon: Icons.inventory_2_outlined, color: AppTheme.primary),
              EnterpriseStatPill(label: 'Total', value: total, icon: Icons.payments_outlined, color: AppTheme.success),
              EnterpriseStatPill(label: 'Balance', value: balance, icon: Icons.account_balance_wallet_outlined, color: AppTheme.warning),
            ],
          );
          final button = SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_rounded),
              label: Text(submitting ? 'Saving...' : 'Save Sale  Ctrl+Enter'),
            ),
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 10),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _AmendmentDiff {
  final int added;
  final int removed;
  final int quantityChanged;
  final int priceChanged;
  final int discountChanged;
  final bool sourceChanged;

  const _AmendmentDiff({
    required this.added,
    required this.removed,
    required this.quantityChanged,
    required this.priceChanged,
    required this.discountChanged,
    required this.sourceChanged,
  });

  bool get hasChanges =>
      added > 0 ||
      removed > 0 ||
      quantityChanged > 0 ||
      priceChanged > 0 ||
      discountChanged > 0 ||
      sourceChanged;
}

class _AmendmentPaymentMethod {
  final String code;
  final String label;

  const _AmendmentPaymentMethod(this.code, this.label);
}

class _AmendmentReviewDecision {
  final String reason;
  final String settlementAction;
  final String settlementMethod;
  final double settlementAmount;
  final String reference;

  const _AmendmentReviewDecision({
    required this.reason,
    required this.settlementAction,
    required this.settlementMethod,
    required this.settlementAmount,
    required this.reference,
  });
}

class _SaleAmendmentReviewDialog extends StatefulWidget {
  final String invoiceNo;
  final int revision;
  final double originalTotal;
  final double revisedTotal;
  final double netPaid;
  final bool customerAttached;
  final bool deliverySale;
  final _AmendmentDiff diff;
  final SaleProfitSummary? profit;
  final List<_AmendmentPaymentMethod> paymentMethods;

  const _SaleAmendmentReviewDialog({
    required this.invoiceNo,
    required this.revision,
    required this.originalTotal,
    required this.revisedTotal,
    required this.netPaid,
    required this.customerAttached,
    required this.deliverySale,
    required this.diff,
    required this.profit,
    required this.paymentMethods,
  });

  @override
  State<_SaleAmendmentReviewDialog> createState() =>
      _SaleAmendmentReviewDialogState();
}

class _SaleAmendmentReviewDialogState
    extends State<_SaleAmendmentReviewDialog> {
  final _reasonController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  String _action = 'none';
  late String _method;
  String? _error;

  double get _balance => widget.revisedTotal - widget.netPaid;
  double get _requiredAmount => _balance.abs();

  @override
  void initState() {
    super.initState();
    _method = widget.paymentMethods.isNotEmpty
        ? widget.paymentMethods.first.code
        : 'cash';
    if (!widget.customerAttached && _requiredAmount > .004) {
      _action = _balance > 0 ? 'collect' : 'refund';
    }
    _amountController.text = _requiredAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  String _settlementLabel(String action) {
    if (_balance > .004) {
      return action == 'collect'
          ? 'Collect now'
          : widget.customerAttached
              ? 'Leave as customer balance'
              : 'Must collect now';
    }
    if (_balance < -.004) {
      return action == 'refund'
          ? 'Refund now'
          : widget.customerAttached
              ? 'Keep as customer credit'
              : 'Must refund now';
    }
    return 'No settlement required';
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Enter a clear amendment reason (at least 5 characters).');
      return;
    }
    var amount = 0.0;
    if (_action != 'none') {
      amount = double.tryParse(_amountController.text.trim()) ?? 0;
      if (amount < .01) {
        setState(() => _error = 'Enter a valid settlement amount.');
        return;
      }
      if (!widget.customerAttached && (amount - _requiredAmount).abs() > .004) {
        setState(() => _error =
            'A walk-in invoice must be settled exactly (${AppCurrency.format(_requiredAmount)}).');
        return;
      }
      if (amount > _requiredAmount + .004) {
        setState(() => _error =
            'Settlement cannot exceed ${AppCurrency.format(_requiredAmount)}.');
        return;
      }
    }
    Navigator.of(context).pop(
      _AmendmentReviewDecision(
        reason: reason,
        settlementAction: _action,
        settlementMethod: _method,
        settlementAmount: amount,
        reference: _referenceController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final difference = widget.revisedTotal - widget.originalTotal;
    final hasBalance = _requiredAmount > .004;
    final settlementOptions = <DropdownMenuItem<String>>[
      if (widget.customerAttached || !hasBalance)
        DropdownMenuItem(
          value: 'none',
          child: Text(_settlementLabel('none')),
        ),
      if (_balance > .004)
        DropdownMenuItem(
          value: 'collect',
          child: Text(_settlementLabel('collect')),
        ),
      if (_balance < -.004)
        DropdownMenuItem(
          value: 'refund',
          child: Text(_settlementLabel('refund')),
        ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Sale Amendment',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppTheme.navy,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text(
                          '${widget.invoiceNo}  •  Revision ${widget.revision} → ${widget.revision + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ReviewMetric(
                          label: 'Original Total',
                          value: AppCurrency.format(widget.originalTotal),
                        ),
                        _ReviewMetric(
                          label: 'Revised Total',
                          value: AppCurrency.format(widget.revisedTotal),
                        ),
                        _ReviewMetric(
                          label: 'Difference',
                          value:
                              '${difference > .004 ? '+' : ''}${AppCurrency.format(difference)}',
                          valueColor: difference.abs() <= .004
                              ? AppTheme.textMuted
                              : difference > 0
                                  ? AppTheme.warning
                                  : AppTheme.success,
                        ),
                        _ReviewMetric(
                          label: 'Already Settled',
                          value: AppCurrency.format(widget.netPaid),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.compare_arrows_rounded,
                      title: 'Changes in this revision',
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ChangeChip(
                          icon: Icons.add_circle_outline,
                          label: '${widget.diff.added} added',
                          active: widget.diff.added > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.remove_circle_outline,
                          label: '${widget.diff.removed} removed',
                          active: widget.diff.removed > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.exposure_outlined,
                          label: '${widget.diff.quantityChanged} quantity',
                          active: widget.diff.quantityChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.price_change_outlined,
                          label: '${widget.diff.priceChanged} price',
                          active: widget.diff.priceChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.percent_rounded,
                          label: '${widget.diff.discountChanged} discount',
                          active: widget.diff.discountChanged > 0,
                        ),
                        _ChangeChip(
                          icon: Icons.hub_outlined,
                          label: 'Sale From changed',
                          active: widget.diff.sourceChanged,
                        ),
                      ],
                    ),
                    if (widget.profit != null) ...[
                      const SizedBox(height: 18),
                      const _ReviewSectionTitle(
                        icon: Icons.insights_outlined,
                        title: 'Revised profit insight',
                      ),
                      const SizedBox(height: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceSoft,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'Net Sales',
                                value: AppCurrency.format(
                                  widget.profit!.netSalesBeforeTax,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'COGS',
                                value: AppCurrency.format(
                                  widget.profit!.costOfGoods,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: widget.profit!.grossProfit < 0
                                    ? 'Loss'
                                    : 'Gross Profit',
                                value: AppCurrency.format(
                                  widget.profit!.grossProfit,
                                ),
                                valueColor: widget.profit!.grossProfit < 0
                                    ? AppTheme.danger
                                    : AppTheme.success,
                              ),
                            ),
                            Expanded(
                              child: _InlineReviewValue(
                                label: 'Margin',
                                value: widget.profit!.marginPercent == null
                                    ? '—'
                                    : '${widget.profit!.marginPercent!.toStringAsFixed(1)}%',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Settlement after amendment',
                    ),
                    const SizedBox(height: 9),
                    if (widget.deliverySale) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.delivery_dining_outlined,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _action == 'collect'
                                    ? 'This delivery collection will be assigned to the selected rider’s custody (1210), exactly like a normal paid delivery sale. It will not be added to the cashier drawer.'
                                    : _action == 'refund'
                                        ? 'This refund is paid from the selected payment account. Existing rider custody is preserved because already-collected rider money is a separate historical financial movement.'
                                        : 'Changing the invoice does not rewrite historical rider custody. Only actual new collections or refunds move money.',
                                style: const TextStyle(
                                  color: AppTheme.navy,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<String>(
                        value: _action,
                        decoration: InputDecoration(
                          labelText: _balance > .004
                              ? 'Revised balance due: ${AppCurrency.format(_balance)}'
                              : _balance < -.004
                                  ? 'Customer credit: ${AppCurrency.format(-_balance)}'
                                  : 'Invoice is exactly settled',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: settlementOptions,
                        onChanged: hasBalance && widget.customerAttached
                            ? (value) {
                                if (value == null) return;
                                setState(() {
                                  _action = value;
                                  _amountController.text =
                                      _requiredAmount.toStringAsFixed(2);
                                });
                              }
                            : null,
                      ),
                      if (_action != 'none') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _amountController,
                                readOnly: !widget.customerAttached,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: _action == 'refund'
                                      ? 'Refund Amount'
                                      : 'Collection Amount',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _method,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Method',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: widget.paymentMethods.isEmpty
                                    ? const [
                                        DropdownMenuItem(
                                          value: 'cash',
                                          child: Text('Cash'),
                                        ),
                                      ]
                                    : widget.paymentMethods
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m.code,
                                            child: Text(
                                              m.label,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _method = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _referenceController,
                                decoration: const InputDecoration(
                                  labelText: 'Reference (optional)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    const SizedBox(height: 18),
                    const _ReviewSectionTitle(
                      icon: Icons.description_outlined,
                      title: 'Amendment reason',
                    ),
                    const SizedBox(height: 9),
                    TextField(
                      controller: _reasonController,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText:
                            'Required — e.g. Customer changed size before delivery',
                        border: OutlineInputBorder(),
                        helperText:
                            'This reason becomes part of the permanent invoice audit trail.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Stock, COGS, AR, tax and ledger deltas commit together. If any validation fails, nothing is changed.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                    label: const Text('Save Amendment'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReviewMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 166,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _ReviewSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

class _ChangeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ChangeChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(.08) : AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppTheme.primary.withOpacity(.20) : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppTheme.primary : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.navy : AppTheme.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _InlineReviewValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InlineReviewValue({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _AmendmentHeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _AmendmentHeaderMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _AmendmentBottomMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _AmendmentBottomMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppTheme.navy,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _ReturnSourceDialog extends StatefulWidget {
  final String initialInvoice;
  final String initialReason;

  const _ReturnSourceDialog({
    required this.initialInvoice,
    required this.initialReason,
  });

  @override
  State<_ReturnSourceDialog> createState() => _ReturnSourceDialogState();
}

class _ReturnSourceDialogState extends State<_ReturnSourceDialog> {
  static const _reasons = <String>[
    'Customer changed mind',
    'Wrong item',
    'Wrong size / variant',
    'Damaged / defective',
    'Quality issue',
    'Duplicate purchase',
    'Other',
  ];

  late final TextEditingController _invoiceController;
  late final TextEditingController _otherController;
  late String _reason;

  @override
  void initState() {
    super.initState();
    _invoiceController = TextEditingController(text: widget.initialInvoice);
    _otherController = TextEditingController();
    _reason = _reasons.contains(widget.initialReason)
        ? widget.initialReason
        : (widget.initialReason.trim().isNotEmpty ? 'Other' : _reasons.first);
    if (_reason == 'Other' &&
        widget.initialReason.trim().isNotEmpty &&
        widget.initialReason != 'Other') {
      _otherController.text = widget.initialReason;
    }
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  void _submit() {
    final invoice = _invoiceController.text.trim();
    final reason = _reason == 'Other'
        ? _otherController.text.trim()
        : _reason;
    if (invoice.isEmpty || reason.isEmpty) {
      AppFeedback.warning(
        context,
        'Original invoice and return reason are required.',
      );
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'invoice': invoice,
      'reason': reason,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment_return_outlined),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Link return to original invoice',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _invoiceController,
                autofocus: widget.initialInvoice.trim().isEmpty,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Original invoice *',
                  hintText: 'Invoice no. / offline receipt no.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _reason,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Return reason *',
                  border: OutlineInputBorder(),
                ),
                items: _reasons
                    .map(
                      (reason) => DropdownMenuItem<String>(
                        value: reason,
                        child: Text(reason),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(
                  () => _reason = value ?? _reasons.first,
                ),
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otherController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Reason details *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text(
                  'Stock is restored automatically. CounterIQ calculates the refundable merchandise, original invoice discount and tax from the original invoice. Original delivery is never refunded.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text('Find original item'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
