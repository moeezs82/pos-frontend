import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/models/product_packaging.dart';
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
import 'package:enterprise_pos/services/product_stock.dart';
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
import 'package:intl/intl.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';

// local widgets split into small files
import 'package:enterprise_pos/screens/sales/services/sale_checkout_totals.dart';
import 'package:enterprise_pos/screens/sales/services/sale_product_query_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_submission_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_mutator.dart';
import 'package:enterprise_pos/screens/sales/services/sale_customer_lookup_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_reference_data_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_unit_conversion_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_return_service.dart';
import 'package:enterprise_pos/screens/sales/services/sales_order_submitter.dart';
import 'package:enterprise_pos/screens/sales/services/sale_picker_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_amendment_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_validator.dart';
import 'package:enterprise_pos/screens/sales/services/sale_meta_builder.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_cart_widgets.dart';
import 'package:enterprise_pos/screens/sales/services/sale_offline_credit_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_receipt_dispatcher.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_keyboard_shortcuts.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_action_bars.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_summary_row.dart';
import 'package:enterprise_pos/screens/sales/parts/cart_product_search.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_amendment_dialog.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_item_edit_dialog.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_party_section.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_post_task_panel.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_return_source_dialog.dart';
import 'package:enterprise_pos/screens/sales/parts/sale_walk_in_section.dart';


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

  /// When supplied, this screen becomes the conversion editor for an approved
  /// sales order. Create mode is unchanged. Final submit posts to
  /// POST /sales-orders/{id}/convert instead of POST /sales, so the backend
  /// links the sale and flips the order status in one guarded operation.
  final SalesOrderPrefill? salesOrderPrefill;

  /// When true, this screen operates as a Sales Order quotation and booking form.
  /// Submissions create or update a sales order instead of posting to /sales.
  final bool isSalesOrder;

  /// When editing an existing Sales Order.
  final SalesOrder? editSalesOrder;

  const CreateSaleScreen({
    super.key,
    this.initialCustomer,
    this.initialReturnInvoice,
    this.editSaleId,
    this.salesOrderPrefill,
    this.isSalesOrder = false,
    this.editSalesOrder,
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
  DateTime? _salesOrderDeliveryDate;
  final TextEditingController _salesOrderNotesController = TextEditingController();

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
  Future<bool>? _walkInPhoneLookupFuture;
  String? _lastWalkInPhoneLookupKey;

  // barcode (kept intact)
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _scannerEnabled = false;
  bool _showProfitInsight = false;
  bool _itemEditorOpen = false;

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
  final SalePostTaskManager _postTaskManager = SalePostTaskManager();

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

    // Seed lightweight reference data from the local catalog first. The
    // catalog refresh below is coordinated/TTL-protected, so reopening Sale
    // Create no longer triggers duplicate live reference + catalog requests.
    unawaited(_loadSaleSources(preferCache: true));
    unawaited(_loadCustomerAreas(preferCache: true));

    // Warm only role/vendor pickers that are not already backed by the local
    // catalog replica. Customer/product pickers are hydrated from SQLite below
    // and fall back to live search on demand.
    final branchId = context.read<BranchProvider>().selectedBranchId?.toString();
    final features = context.read<BranchFeatureProvider>();
    PartyPrefetch.warmSalesmen(token, branchId: branchId);
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
    _walkInPhoneFocusNode.addListener(_handleWalkInPhoneFocusChange);

    if (widget.isSalesOrder) {
      if (widget.editSalesOrder != null) {
        final prefill =
            SalesOrderSubmitter.parseOrder(widget.editSalesOrder!);
        _selectedCustomerId = prefill.customerId;
        _selectedCustomer = prefill.customer;
        customerNameController.text = prefill.customerName;
        customerPhoneController.text = prefill.customerPhone;
        addressController.text = prefill.customerAddress;
        _customerLocked = prefill.customerId != null;
        if (prefill.salesmanId != null) {
          _selectedUserId = prefill.salesmanId;
        }
        if (prefill.salesman != null) {
          _selectedUser = prefill.salesman;
        }
        _items = prefill.items;
        if (prefill.discount != null) {
          discountController.text = prefill.discount!;
        }
        if (prefill.tax != null) {
          taxController.text = prefill.tax!;
        }
        if (prefill.notes != null) {
          _salesOrderNotesController.text = prefill.notes!;
        }
        _salesOrderDeliveryDate = prefill.deliveryDate;
      } else {
        // New Sales Order: Default salesman to current logged in user
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final auth = context.read<AuthProvider>();
          final currentUserId = int.tryParse(auth.user?['id']?.toString() ?? '');
          if (currentUserId != null && currentUserId > 0) {
            setState(() {
              _selectedUserId = currentUserId;
              _selectedUser = auth.user;
            });
          }
        });
        if (widget.initialCustomer != null) {
          final customer = widget.initialCustomer!;
          _selectedCustomer = customer;
          _selectedCustomerId = customer['id']?.toString();
          customerNameController.text = (customer['first_name'] ?? customer['name'] ?? '').toString();
          customerPhoneController.text = (customer['phone'] ?? '').toString();
          addressController.text = (customer['address'] ?? '').toString();
          _customerLocked = _selectedCustomerId != null;
        }
      }
    } else if (!_isEditing && widget.salesOrderPrefill != null) {
      final prefill =
          SalesOrderSubmitter.parsePrefill(widget.salesOrderPrefill!);
      _selectedCustomerId = prefill.customerId;
      _selectedCustomer = prefill.customer;
      customerNameController.text = prefill.customerName;
      customerPhoneController.text = prefill.customerPhone;
      addressController.text = prefill.customerAddress;
      _customerLocked = prefill.customerId != null;
      if (prefill.salesmanId != null) {
        _selectedUserId = prefill.salesmanId;
      }
      if (prefill.salesman != null) {
        _selectedUser = prefill.salesman;
      }
      _items = prefill.items;
      if (prefill.discount != null) {
        discountController.text = prefill.discount!;
      }
      if (prefill.tax != null) {
        taxController.text = prefill.tax!;
      }
    } else if (!_isEditing && widget.initialCustomer != null) {
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
        if (!_isEditing) _selectedSaleSourceId = null;
        _saleSourcesBranchId = branchId;
      });
    }
    final result = await SaleReferenceDataService.loadSaleSources(
      service: _saleSourceService,
      branchId: branchId,
      currentSelectedId: _selectedSaleSourceId,
      isEditing: _isEditing,
      preferCache: preferCache,
    );
    if (!mounted) return;
    setState(() {
      _saleSources = result.sources;
      _saleSourcesBranchId = branchId;
      _selectedSaleSourceId = result.selectedId;
    });
  }

  Map<String, dynamic>? get _selectedSaleSource =>
      SaleReferenceDataService.findSourceById(_saleSources, _selectedSaleSourceId);

  Future<void> _manageSaleSources() async {
    final token = context.read<AuthProvider>().token!;
    final newId = await SaleReferenceDataService.manageSaleSources(
      context: context,
      service: _saleSourceService,
      selectedId: _selectedSaleSourceId,
      effectiveBranchId: _effectiveBranchIdStr(),
      token: token,
      onReload: _loadSaleSources,
    );
    if (!mounted || newId == null) return;
    setState(() => _selectedSaleSourceId = newId);
  }

  String? get _selectedAreaName =>
      SaleReferenceDataService.areaNameById(_customerAreas, _selectedAreaId);

  Future<void> _loadCustomerAreas({bool preferCache = false}) async {
    final branchId = int.tryParse(_effectiveBranchIdStr());
    if (branchId != null && _customerAreasBranchId != branchId && mounted) {
      setState(() {
        _customerAreas = const [];
        if (!_isEditing) _selectedAreaId = null;
        _customerAreasBranchId = branchId;
      });
    }
    final result = await SaleReferenceDataService.loadCustomerAreas(
      service: _customerAreaService,
      branchId: branchId,
      currentSelectedId: _selectedAreaId,
      isEditing: _isEditing,
      preferCache: preferCache,
    );
    if (!mounted) return;
    setState(() {
      _customerAreas = result.areas;
      _customerAreasBranchId = branchId;
      _selectedAreaId = result.selectedId;
    });
  }

  Future<void> _manageCustomerAreas() async {
    final auth = context.read<AuthProvider>();
    final newId = await SaleReferenceDataService.manageCustomerAreas(
      context: context,
      service: _customerAreaService,
      selectedId: _selectedAreaId,
      effectiveBranchId: _effectiveBranchIdStr(),
      token: auth.token!,
      hasPermission: auth.hasPermission('manage-customers'),
      onReload: _loadCustomerAreas,
    );
    if (!mounted) return;
    if (newId != null &&
        _customerAreas.any((area) => _metaInt(area['id']) == newId)) {
      setState(() => _selectedAreaId = newId);
    } else if (newId == null) {
      setState(() => _selectedAreaId = null);
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

      final loaded = SaleAmendmentService.parseLoadedSale(
        sale: sale,
        lineTotalCalculator: ({
          required price,
          required qty,
          required discPct,
          required discountType,
          required extraDiscount,
        }) =>
            _lineTotal(
          price: price,
          qty: qty,
          discPct: discPct,
          discountType: discountType,
          extraDiscount: extraDiscount,
        ),
      );

      discountController.text = loaded.discount.toStringAsFixed(2);
      taxController.text = loaded.tax.toStringAsFixed(2);
      shippingController.text = loaded.delivery.toStringAsFixed(2);
      customerNameController.text = loaded.customerName;
      customerPhoneController.text = loaded.customerPhone;
      addressController.text = loaded.customerAddress;

      setState(() {
        _editSale = sale;
        _editRevision = loaded.revision;
        _originalTotal = loaded.originalTotal;
        _existingNetPaid = loaded.existingNetPaid;
        _items = loaded.items;
        _originalItems = loaded.items
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _selectedCustomerId = loaded.customerId?.toString();
        _selectedCustomer = loaded.customer;
        _selectedVendorId = loaded.vendorId;
        _selectedVendor = loaded.vendor;
        _selectedUserId = loaded.salesmanId;
        _selectedUser = loaded.salesman;
        _selectedDeliveryBoyId = loaded.deliveryBoyId;
        _selectedDeliveryBoy = loaded.deliveryBoy;
        _selectedSaleSourceId = loaded.saleSourceId;
        _selectedAreaId = loaded.areaId;
        _selectedBranchId = loaded.branchId;
        _selectedBranch = loaded.branch;
        _customerLocked = true;
        _payments = const [];
      });

      // Sale sources are branch-owned. Load them after both branch and saleSourceId are known.
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
    final reset = SaleAmendmentService.computeResetValues(
      sale: _editSale!,
      originalItems: _originalItems,
    );
    setState(() {
      _items = reset.items;
      discountController.text = reset.discount;
      taxController.text = reset.tax;
      shippingController.text = reset.delivery;
      _selectedVendorId = reset.vendorId;
      _selectedVendor = reset.vendor;
      _selectedUserId = reset.userId;
      _selectedUser = reset.user;
      _selectedDeliveryBoyId = reset.deliveryBoyId;
      _selectedDeliveryBoy = reset.deliveryBoy;
      _selectedSaleSourceId = reset.saleSourceId;
    });
  }

  Future<void> _submitAmendment() async {
    final success = await SaleAmendmentService.executeAmendment(
      context: context,
      saleService: _saleService,
      editSaleId: widget.editSaleId,
      editSale: _editSale,
      editRevision: _editRevision,
      originalTotal: _originalTotal,
      existingNetPaid: _existingNetPaid,
      selectedBranchId: _selectedBranchId,
      selectedSaleSourceId: _selectedSaleSourceId,
      selectedVendorId: _selectedVendorId,
      selectedUserId: _selectedUserId,
      selectedDeliveryBoyId: _selectedDeliveryBoyId,
      selectedCustomerId: _selectedCustomerId,
      items: _items,
      originalItems: _originalItems,
      discount: _toDouble(discountController),
      tax: _toDouble(taxController),
      delivery: _toDouble(shippingController),
      lineTotalCalculator: _cartLineTotal,
      onSubmittingChanged: (submitting) {
        if (mounted) setState(() => _submitting = submitting);
      },
    );
    if (success && mounted) {
      Navigator.of(context).pop(true);
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
    _salesOrderNotesController.dispose();
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
    _walkInPhoneFocusNode.removeListener(_handleWalkInPhoneFocusChange);
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

  void _handleWalkInPhoneFocusChange() {
    if (_walkInPhoneFocusNode.hasFocus || _selectedCustomerId != null || _isEditing) {
      return;
    }
    unawaited(_resolveWalkInCustomerByPhone());
  }

  Future<bool> _resolveWalkInCustomerByPhone({bool force = false}) async {
    if (_isEditing || _selectedCustomerId != null) return true;

    final phone = customerPhoneController.text.trim();
    if (phone.isEmpty) return true;
    final key = CustomerPhoneUtils.compareKey(phone);
    if (key.isEmpty) return true;

    // If focus-loss already started a lookup, Save must wait for it instead of
    // racing ahead. Otherwise the late response could select the old customer
    // after _resetForNextSale() has already cleared the completed transaction.
    final inFlight = _walkInPhoneLookupFuture;
    if (inFlight != null) {
      final ok = await inFlight;
      if (!mounted || !ok || _selectedCustomerId != null) return ok;
      final currentKey = CustomerPhoneUtils.compareKey(
        customerPhoneController.text.trim(),
      );
      if (currentKey != key) {
        return _resolveWalkInCustomerByPhone(force: force);
      }
    }

    if (!force && _lastWalkInPhoneLookupKey == key) return true;

    final lookup = _performWalkInCustomerLookup(phone, key);
    _walkInPhoneLookupFuture = lookup;
    try {
      return await lookup;
    } finally {
      if (identical(_walkInPhoneLookupFuture, lookup)) {
        _walkInPhoneLookupFuture = null;
      }
    }
  }

  Future<bool> _performWalkInCustomerLookup(String phone, String key) {
    return SaleCustomerLookupService.performLookup(
      context: context,
      saleService: _saleService,
      phone: phone,
      key: key,
      isCurrentPhoneValid: () =>
          _selectedCustomerId == null &&
          CustomerPhoneUtils.compareKey(customerPhoneController.text.trim()) ==
              key,
      onCustomerMatched: (customer) {
        _lastWalkInPhoneLookupKey = key;
        _applyCustomerSelection(customer);
      },
    );
  }

  /// Opens the full customer browse sheet and returns whatever was picked
  /// (null means "cleared / walk-in"). Used both as the manual "Select
  /// Customer" action and as the autocomplete field's "Browse all" fallback.
  Future<Map<String, dynamic>?> _openCustomerSheet() {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return SalePickerService.openCustomerSheet(context, token: token);
  }

  void _applyCustomerSelection(Map<String, dynamic>? customer) {
    if (!mounted) return;
    if (customer == null) {
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _selectedAreaId = null;
        _customerLocked = false;
        _lastWalkInPhoneLookupKey = null;

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
        _lastWalkInPhoneLookupKey = CustomerPhoneUtils.compareKey(phone);
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
      _lastWalkInPhoneLookupKey = null;
      customerNameController.text = "";
      customerPhoneController.text = "";
      addressController.text = "";
    });
  }

  Future<Map<String, dynamic>?> _openVendorSheet() {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return SalePickerService.openVendorSheet(context, token: token);
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

  Future<Map<String, dynamic>?> _openUserSheet() {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return SalePickerService.openUserSheet(
      context,
      token: token,
      branchId: _effectiveBranchIdStr(),
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

  Future<Map<String, dynamic>?> _openDeliveryBoySheet() {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    return SalePickerService.openDeliveryBoySheet(
      context,
      token: token,
      branchId: _effectiveBranchIdStr(),
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
    SaleCartMutator.addOrIncrementProduct(
      items: _items,
      product: product,
      customerType: _selectedCustomerType,
    );
  }

  /// Call inside setState — does NOT call setState itself.
  void _applyPickedProduct(Map<String, dynamic> product, {double qty = 1.0}) {
    SaleCartMutator.applyPickedProduct(
      items: _items,
      product: product,
      qty: qty,
      customerType: _selectedCustomerType,
    );
  }

  Future<void> _addItemManual() async {
    final auth = context.read<AuthProvider>();
    final branch = context.read<BranchProvider>();
    final picked = await SalePickerService.openMultiProductPicker(
      context: context,
      token: auth.token!,
      items: _items,
      vendorId: _selectedVendorId,
      customerType: _selectedCustomerType,
      isMasterAdmin: auth.isMasterAdmin,
      hasActiveBranch: branch.hasActiveBranch,
    );

    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      for (final x in picked) {
        final product = (x["product"] as Map?)?.cast<String, dynamic>();
        final qty = (x["qty"] as num?)?.toDouble() ?? 1.0;
        if (product == null) continue;
        _applyPickedProduct(product, qty: qty);
      }
    });
  }

  void _changeSellingUnitQuick(int index, int? packagingId) {
    final next = SaleUnitConversionService.changeSellingUnitQuick(
      context: context,
      items: _items,
      index: index,
      packagingId: packagingId,
      isEditing: _isEditing,
      customerType: _selectedCustomerType,
      onEditDeferred: _editItem,
      calculateCartLineTotal: _cartLineTotal,
    );
    if (next != null) {
      setState(() => _items[index] = next);
    }
  }

  Future<void> _editItem(int index) async {
    if (!mounted || index < 0 || index >= _items.length || _itemEditorOpen) {
      return;
    }
    _itemEditorOpen = true;
    try {
      final updatedRow = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SaleItemEditDialog(
          item: _items[index],
          isEditing: _isEditing,
          customerType: _selectedCustomerType,
        ),
      );
      if (updatedRow != null && mounted) {
        setState(() {
          updatedRow['total'] = _cartLineTotal(updatedRow);
          _items[index] = updatedRow;
        });
      }
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _itemEditorOpen = false;
      });
    }
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

    final product = await SaleProductQueryService.lookupByBarcode(
      productService: _productService,
      barcode: code,
      vendorId: _selectedVendorId,
      branchId: int.tryParse(_effectiveBranchIdStr()),
    );
    if (product != null) {
      setState(() => _addOrIncrementProduct(product));
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
    double extraDiscount = 0,
    String discountType = 'percentage',
  }) {
    return SaleCartMutator.lineTotal(
      price: price,
      qty: qty,
      discPct: discPct,
      extraDiscount: extraDiscount,
      discountType: discountType,
    );
  }

  double _cartLineTotal(Map<String, dynamic> item) {
    return SaleCartMutator.cartLineTotal(item);
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

  Future<bool> _linkReturnForRow(
    int index,
    double quantity,
    double? packagingQuantity,
  ) {
    return SaleReturnService.linkReturnForRow(
      context: context,
      saleService: _saleService,
      items: _items,
      index: index,
      quantity: quantity,
      packagingQuantity: packagingQuantity,
      initialReturnInvoice: widget.initialReturnInvoice,
      onCustomerSelected: _applyCustomerSelection,
      onRowUpdated: (updated) {
        setState(() => _items[index] = updated);
      },
      onResetPayments: () {
        setState(() {
          _payments = [];
          cashReceivedController.clear();
        });
      },
      onRowRestore: (restored) {
        setState(() {
          _items[index] = restored;
          _items[index]['total'] = _cartLineTotal(_items[index]);
        });
      },
    );
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

  Future<void> _submitSalesOrder({required bool submitForApproval}) async {
    final success = await SalesOrderSubmitter.executeSalesOrderSubmit(
      context: context,
      selectedCustomerId: _selectedCustomerId,
      customerPhone: customerPhoneController.text,
      onResolveCustomerByPhone: () =>
          _resolveWalkInCustomerByPhone(force: true),
      customerFocusNode: _customerFocusNode,
      items: _items,
      editSalesOrder: widget.editSalesOrder,
      onSubmittingChanged: (submitting) {
        if (mounted) setState(() => _submitting = submitting);
      },
      auth: context.read<AuthProvider>(),
      selectedUserId: _selectedUserId,
      discount: double.tryParse(discountController.text.trim()) ?? 0.0,
      tax: double.tryParse(taxController.text.trim()) ?? 0.0,
      deliveryDate: _salesOrderDeliveryDate,
      notes: _salesOrderNotesController.text,
      submitForApproval: submitForApproval,
    );
    if (!mounted) return;
    if (success) {
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
      } else {
        _resetForNextSale();
      }
    }
  }

  Future<void> _submitSale({bool print = true}) async {
    if (widget.isSalesOrder) {
      await _submitSalesOrder(submitForApproval: true);
      return;
    }
    if (_isEditing) {
      await _submitAmendment();
      return;
    }

    final auth = context.read<AuthProvider>();
    final globalBranchId = context.read<BranchProvider>().selectedBranchId;
    final effectiveBranchId = globalBranchId?.toString() ?? _selectedBranchId;
    final originBranchId = int.tryParse(effectiveBranchId ?? '') ?? 0;

    final discount = _toDouble(discountController);
    final tax = _toDouble(taxController);
    final shipping = _toDouble(shippingController);

    final pmProvider = context.read<PaymentMethodProvider>();
    final effectiveMethod =
        _saleMethod ?? pmProvider.defaultMethod?.method ?? 'cash';
    final isDrawerMethod =
        pmProvider.byCode(effectiveMethod)?.affectsCashDrawer ??
            (effectiveMethod == 'cash');

    final totals = SaleCheckoutTotals.calculate(
      items: _items,
      lineTotalCalculator: _cartLineTotal,
      discount: discount,
      tax: tax,
      shipping: shipping,
      splitPayments: _payments,
      autoCashIfEmpty: _autoCashIfEmpty,
      effectiveMethod: effectiveMethod,
      isDrawerMethod: isDrawerMethod,
      saleReference: saleReferenceController.text,
      enteredCashReceived: _toDouble(cashReceivedController),
    );

    final valid = SaleSubmissionService.validatePreflight(
      context: context,
      items: _items,
      sendInvoiceOnWhatsApp: _sendInvoiceOnWhatsApp,
      whatsAppPhone: _whatsAppDestinationPhone(),
      isMasterAdmin: auth.isMasterAdmin,
      globalBranchId: globalBranchId,
      originBranchId: originBranchId,
      subtotal: totals.subtotal,
      discount: totals.discount,
      tax: totals.tax,
      shipping: totals.shipping,
      saleTotal: totals.saleTotal,
    );
    if (!valid) return;

    if (_selectedCustomerId == null && customerPhoneController.text.trim().isNotEmpty) {
      final canContinue = await _resolveWalkInCustomerByPhone(force: true);
      if (!canContinue || !mounted) return;
    }

    setState(() => _submitting = true);

    try {
      final shiftProvider = context.read<RegisterShiftProvider>();
      final registerCode =
          shiftProvider.shift?['register']?['code']?.toString() ?? 'REG';
      final originUserId = int.tryParse(auth.user?['id']?.toString() ?? '');

      await SaleSubmissionService.executeSubmitSale(
        context: context,
        saleService: _saleService,
        auth: auth,
        items: _items,
        totals: totals,
        printReceipt: print,
        sendInvoiceOnWhatsApp: _sendInvoiceOnWhatsApp,
        whatsAppPhone: _whatsAppDestinationPhone(),
        effectiveBranchId: effectiveBranchId!,
        originBranchId: originBranchId,
        originUserId: originUserId,
        registerCode: registerCode,
        selectedCustomer: _selectedCustomer,
        selectedCustomerId: _selectedCustomerId,
        selectedCustomerSecondaryPhones: _selectedCustomerSecondaryPhones,
        walkInCustomerName: customerNameController.text,
        walkInPhone: customerPhoneController.text,
        walkInAddress: addressController.text,
        selectedAreaId: _selectedAreaId,
        selectedAreaName: _selectedAreaName,
        selectedUser: _selectedUser,
        selectedUserId: _selectedUserId,
        selectedDeliveryBoy: _selectedDeliveryBoy,
        selectedDeliveryBoyId: _selectedDeliveryBoyId,
        selectedVendor: _selectedVendor,
        selectedVendorId: _selectedVendorId,
        selectedSaleSourceId: _selectedSaleSourceId,
        selectedSaleSourceName: _selectedSaleSource?['name']?.toString(),
        selectedBranch: _selectedBranch,
        effectiveMethod: effectiveMethod,
        salesOrderPrefill: widget.salesOrderPrefill,
        lineTotalFallback: _cartLineTotal,
        onAddPendingWhatsAppTask: ({
          required String receiptNo,
          required WhatsAppInvoicePreparation prepared,
          required String message,
        }) {
          _addPendingWhatsAppTask(
            receiptNo: receiptNo,
            prepared: prepared,
            message: message,
          );
        },
        onResetSale: ({required bool keepInitialCustomer}) {
          _resetForNextSale(keepInitialCustomer: keepInitialCustomer);
        },
        keepInitialCustomer: widget.initialCustomer != null,
        onFocusProductSearch: () {
          if (mounted) _productSearchFocusNode.requestFocus();
        },
      );
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
      _postTaskManager.addTask(
        receiptNo: receiptNo,
        prepared: prepared,
        message: message,
      );
    });
  }

  Future<void> _openPendingWhatsAppTask(PendingWhatsAppTask task) async {
    await _postTaskManager.openTask(
      context,
      task,
      notify: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _dismissPendingWhatsAppTask(PendingWhatsAppTask task) {
    setState(() => _postTaskManager.dismissTask(task));
  }

  Widget _buildPostSaleTaskPanel() {
    return SalePostTaskPanel(
      tasks: _postTaskManager.tasks,
      onOpenTask: _openPendingWhatsAppTask,
      onDismissTask: _dismissPendingWhatsAppTask,
      onOpenFolder: (path) =>
          WhatsAppInvoiceService.instance.openInvoiceFolder(path),
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
        _lastWalkInPhoneLookupKey = null;
        customerNameController.clear();
        customerPhoneController.clear();
        addressController.clear();
      }

      if (widget.isSalesOrder) {
        _salesOrderNotesController.clear();
        _salesOrderDeliveryDate = null;
        final auth = context.read<AuthProvider>();
        final currentUserId = int.tryParse(auth.user?['id']?.toString() ?? '');
        if (currentUserId != null && currentUserId > 0) {
          _selectedUserId = currentUserId;
          _selectedUser = auth.user;
        }
      }
    });
  }

  Future<List<ProductRef>> _queryProducts(String q) {
    return SaleProductQueryService.queryProducts(
      productService: _productService,
      query: q,
      vendorId: _selectedVendorId,
      branchId: int.tryParse(_effectiveBranchIdStr()),
    );
  }

  // helpers
  double _toDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0.0;

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
    final payment = await showSaleAddPaymentDialog(
      context: context,
      total: total,
      alreadyPaid: _salePaid(total),
      pm: context.read<PaymentMethodProvider>(),
    );
    if (payment != null && mounted) {
      setState(() => _payments.add(payment));
    }
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

    final pmProvider = context.read<PaymentMethodProvider>();
    final effectiveMethod =
        _saleMethod ?? pmProvider.defaultMethod?.method ?? 'cash';
    final isDrawerMethod =
        pmProvider.byCode(effectiveMethod)?.affectsCashDrawer ??
            (effectiveMethod == 'cash');

    final checkoutTotals = SaleCheckoutTotals.calculate(
      items: _items,
      lineTotalCalculator: _cartLineTotal,
      discount: _toDouble(discountController),
      tax: _toDouble(taxController),
      shipping: _toDouble(shippingController),
      splitPayments: _payments,
      autoCashIfEmpty: _autoCashIfEmpty,
      effectiveMethod: effectiveMethod,
      isDrawerMethod: isDrawerMethod,
      saleReference: saleReferenceController.text,
      enteredCashReceived: _toDouble(cashReceivedController),
    );
    final subtotal = checkoutTotals.subtotal;
    final total = checkoutTotals.signedTotal;
    final changeAmount = checkoutTotals.changeAmount;

    // ── Focus + shortcut scope ──────────────────────────────────────────────
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
        bindings: SaleShortcutBindings.buildBindings(
          context: context,
          isEditing: _isEditing,
          isSalesOrder: widget.isSalesOrder,
          deliveryEnabled: deliveryEnabled,
          saleVendorEnabled: saleVendorEnabled,
          onAddItemManual: _addItemManual,
          onPickCustomer: _pickCustomer,
          onPickDeliveryBoy: _pickDeliveryBoy,
          onDeliveryBoyFocus: () {
            _deliveryBoyController.clear();
            _deliveryBoyFocusNode.requestFocus();
          },
          onFocusBarcodeScanner: _focusBarcodeScanner,
          onSubmitPrimary: () => widget.isSalesOrder
              ? _submitSalesOrder(submitForApproval: true)
              : _submitSale(),
          onSubmitDraft: widget.isSalesOrder
              ? () => _submitSalesOrder(submitForApproval: false)
              : null,
          onCustomerFocus: () {
            _customerController.clear();
            _customerFocusNode.requestFocus();
          },
          onSalesmanFocus: () {
            _salesmanController.clear();
            _salesmanFocusNode.requestFocus();
          },
          onProductSearchFocus: () => _productSearchFocusNode.requestFocus(),
          onVendorFocus: () {
            _vendorController.clear();
            _vendorFocusNode.requestFocus();
          },
          onWalkInNameFocus: () => _walkInNameFocusNode.requestFocus(),
          onWalkInPhoneFocus: () => _walkInPhoneFocusNode.requestFocus(),
          onWalkInAddressFocus: () => _walkInAddressFocusNode.requestFocus(),
          onCashReceivedFocus: () => _focusAndSelectAll(
            _cashReceivedFocusNode,
            cashReceivedController,
          ),
          onDiscountFocus: () => _focusAndSelectAll(
            _discountFocusNode,
            discountController,
          ),
          onTaxFocus: () => _focusAndSelectAll(
            _taxFocusNode,
            taxController,
          ),
          onShippingFocus: () => _focusAndSelectAll(
            _shippingFocusNode,
            shippingController,
          ),
        ),
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
                      if (widget.salesOrderPrefill != null) _buildSalesOrderConversionHeader(),
                      if (widget.isSalesOrder) _buildSalesOrderHeader(),

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
                  if (_postTaskManager.tasks.isNotEmpty)
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
                !widget.isSalesOrder && (deliveryEnabled || (_isEditing && _selectedDeliveryBoyId != null)),
            showVendor:
                !widget.isSalesOrder && (saleVendorEnabled || (_isEditing && _selectedVendorId != null)),
            customerLocked: _isEditing || (widget.isSalesOrder && widget.editSalesOrder != null),
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
            compact: true,
          ),

          if ((widget.initialReturnInvoice ?? '').trim().isNotEmpty && !_isEditing)
            SaleReturnContextBanner(
              returnInvoice: widget.initialReturnInvoice!,
            ),

          // 2. FIXED — walk-in/customer snapshot fields are immutable once the
          // invoice is posted. Customer identity is already shown above in the
          // locked party field, so hiding these edit-only inputs avoids a
          // misleading control that would not be persisted by an amendment.
          if (!_isEditing) _buildWalkInCompact(),

          const Divider(height: 1, thickness: 1, color: AppTheme.border),

          // 3. FIXED — product autocomplete + scanner + F2
          SaleCartInputRow(
            searchFocusNode: _productSearchFocusNode,
            searchController: _productSearchController,
            onQueryProducts: _queryProducts,
            onProductSelected: (ref) {
              final productMap = ref.raw ??
                  <String, dynamic>{
                    'id': ref.id,
                    'name': ref.name,
                    'price': ref.tp,
                  };
              setState(() => _addOrIncrementProduct(productMap));
            },
            onFocusScanner: _focusBarcodeScanner,
            scannerEnabled: _scannerEnabled,
            onAddItemsManual: _addItemManual,
          ),

          // 4. FIXED — cart table column headers
          const SaleCartTableHeader(),

          // 5. INDEPENDENTLY SCROLLABLE — cart item rows
          Expanded(
            child: ItemsTable(
              compact: true,
              items: _items,
              onQueryProducts: _queryProducts,
              onAddItem: _addItemManual,
              onItemsChanged: (next) => setState(() => _items = next),
              onEditSellingUnit: _editItem,
              onSellingUnitChanged: _changeSellingUnitQuick,
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

  Widget _buildWalkInCompact() {
    return SaleWalkInSection(
      nameController: customerNameController,
      nameFocusNode: _walkInNameFocusNode,
      phoneController: customerPhoneController,
      phoneFocusNode: _walkInPhoneFocusNode,
      onPhoneEditingComplete: () {
        unawaited(_resolveWalkInCustomerByPhone());
        _walkInAddressFocusNode.requestFocus();
      },
      addressController: addressController,
      addressFocusNode: _walkInAddressFocusNode,
      selectedCustomerId: _selectedCustomerId,
      selectedCustomer: _selectedCustomer,
      selectedCustomerSecondaryPhones: _selectedCustomerSecondaryPhones,
      onClearCustomer: _clearCustomerSelection,
      sendInvoiceOnWhatsApp: _sendInvoiceOnWhatsApp,
      onWhatsAppChanged: (v) => setState(() => _sendInvoiceOnWhatsApp = v),
      whatsAppDestinationPhone: _whatsAppDestinationPhone(),
      customerAreas: _customerAreas,
      selectedAreaId: _selectedAreaId,
      onAreaChanged: (v) => setState(() => _selectedAreaId = v),
      onClearArea: () => setState(() => _selectedAreaId = null),
      onManageCustomerAreas: _manageCustomerAreas,
      submitting: _submitting,
    );
  }

  // ── Summary row: item count + subtotal + editable discount/tax ─────────
  Widget _buildSummaryRow({
    required double subtotal,
    required bool canViewProfit,
  }) {
    return SaleSummaryRow(
      itemCount: _items.length,
      subtotal: subtotal,
      canViewProfit: canViewProfit,
      showProfitInsight: _showProfitInsight,
      onToggleProfitInsight: () =>
          setState(() => _showProfitInsight = !_showProfitInsight),
      discountController: discountController,
      discountFocusNode: _discountFocusNode,
      taxController: taxController,
      taxFocusNode: _taxFocusNode,
      shippingController: shippingController,
      shippingFocusNode: _shippingFocusNode,
      linkedReturnCredit: _linkedReturnCredit,
      linkedReturnOriginalOutstanding: _linkedReturnOriginalOutstanding,
      profitSummary: _currentProfitSummary(),
      onProfitDetails: _showInvoiceProfitDetails,
    );
  }

  // ── Split-tender summary strip ──────────────────────────────────────────
  Widget _buildSplitStrip(double total) {
    final pm = context.read<PaymentMethodProvider>();
    final paid = _salePaid(total);
    final balance = total - paid;
    return SaleSplitTenderStrip(
      payments: _payments,
      paid: paid,
      balance: balance,
      displayNameFor: pm.displayNameFor,
      onRemovePayment: (i) => setState(() => _payments.removeAt(i)),
    );
  }

  Widget _buildSalesOrderConversionHeader() {
    final order = widget.salesOrderPrefill?.order;
    return SaleSalesOrderConversionHeader(
      orderNumber: order?.orderNumber ?? 'Order',
    );
  }

  Widget _buildSalesOrderHeader() {
    return SaleSalesOrderHeader(
      editSalesOrder: widget.editSalesOrder,
      deliveryDate: _salesOrderDeliveryDate,
      onDeliveryDateChanged: (picked) =>
          setState(() => _salesOrderDeliveryDate = picked),
      notesController: _salesOrderNotesController,
    );
  }

  Widget _buildAmendmentHeader(double revisedTotal) {
    final sale = _editSale ?? const <String, dynamic>{};
    return SaleAmendmentHeader(
      invoiceNo: (sale['invoice_no'] ?? widget.editSaleId ?? '').toString(),
      revision: _editRevision,
      originalTotal: _originalTotal,
      revisedTotal: revisedTotal,
    );
  }

  Widget _buildAmendmentBottomBar(double total) {
    return SaleAmendmentBottomBar(
      originalTotal: _originalTotal,
      total: total,
      submitting: _submitting,
      onReset: _resetAmendmentDraft,
      onSubmit: _submitAmendment,
    );
  }

  Widget _buildSalesOrderBottomBar(double total) {
    return SaleSalesOrderBottomBar(
      editSalesOrder: widget.editSalesOrder,
      itemCount: _items.length,
      total: total,
      submitting: _submitting,
      onClear: _resetForNextSale,
      onSaveDraft: () => _submitSalesOrder(submitForApproval: false),
      onSubmitForApproval: () => _submitSalesOrder(submitForApproval: true),
    );
  }

  // ── Fixed bottom action bar ──────────────────────────────────────────────
  Widget _buildBottomBar({
    required double total,
    required double changeAmount,
  }) {
    if (_isEditing) return _buildAmendmentBottomBar(total);
    if (widget.isSalesOrder) return _buildSalesOrderBottomBar(total);
    final pm = context.watch<PaymentMethodProvider>();
    return SaleStandardBottomBar(
      autoCashIfEmpty: _autoCashIfEmpty,
      onAutoCashChanged: (v) => setState(() => _autoCashIfEmpty = v),
      methods: pm.activeMethods,
      currentMethod: _saleMethod ?? pm.defaultMethod?.method,
      onMethodChanged: (v) => setState(() => _saleMethod = v),
      hasSplit: _payments.isNotEmpty,
      showCashFields: _saleCashDue(total) > 0,
      cashReceivedController: cashReceivedController,
      cashReceivedFocusNode: _cashReceivedFocusNode,
      changeAmount: changeAmount,
      saleReferenceController: saleReferenceController,
      total: total,
      splitPaymentsCount: _payments.length,
      onAddSplitPayment: () => _addSalePaymentDialog(total),
      onClear: () => _resetForNextSale(),
      submitting: _submitting,
      onSaveOnly: () => _submitSale(print: false),
      onSaveAndPrint: () => _submitSale(print: true),
    );
  }

}
