import 'dart:io';

import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/product_packaging_editor.dart';
import 'package:enterprise_pos/widgets/reference_data_manager_dialog.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Creates or edits a variable-product family.
///
/// Important UX rule: a variant is added explicitly, one row at a time. The
/// screen never generates a Cartesian size × color matrix because real stock
/// often contains only a subset of possible combinations.
class VariableProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? group;
  final int? vendorId;

  const VariableProductFormScreen({super.key, this.group, this.vendorId});

  @override
  State<VariableProductFormScreen> createState() =>
      _VariableProductFormScreenState();
}

class _VariableProductFormScreenState extends State<VariableProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _secondaryNameCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController(text: '0');

  // Defaults are create-screen helpers only. They prefill a newly-added
  // variant and are never stored independently from the child products.
  final _defaultRetailCtrl = TextEditingController();
  final _defaultWholesaleCtrl = TextEditingController();
  final _defaultCostCtrl = TextEditingController();
  final _defaultReorderCtrl = TextEditingController(text: '0');
  List<ProductPackaging> _defaultPackagings = [];

  bool _isActive = true;
  bool _taxInclusive = false;
  final String _discountType = 'percentage';

  int? _selectedCategoryId;
  int? _selectedBrandId;
  int? _selectedUnitId;
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _brands = [];
  List<ProductUnit> _units = [];

  final List<_VariantDraft> _variants = [];
  int _nextVariantId = 1;

  bool _loading = false;
  bool _saving = false;
  bool _bulkSkuBusy = false;
  bool _bulkBarcodeBusy = false;

  late ProductGroupService _groupService;
  late ProductService _productService;
  late CommonService _commonService;
  late UnitService _unitService;

  bool get _isEdit => widget.group != null;
  bool get _groupHasPackagings =>
      ProductUnit.parseBool(widget.group?['has_packagings'], false);

  ProductUnit? get _selectedUnit {
    if (_selectedUnitId == null) return null;
    for (final unit in _units) {
      if (unit.id == _selectedUnitId) return unit;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _groupService = ProductGroupService(token: token);
    _productService = ProductService(token: token);
    _commonService = CommonService(token: token);
    _unitService = UnitService(token: token);

    if (widget.group != null) {
      final g = widget.group!;
      _nameCtrl.text = (g['name'] ?? '').toString();
      _secondaryNameCtrl.text = (g['secondary_name'] ?? '').toString();
      _isActive = g['is_active'] == 1 || g['is_active'] == true;
      _taxInclusive =
          g['tax_inclusive'] == 1 || g['tax_inclusive'] == true;
      _taxRateCtrl.text = (g['tax_rate'] ?? '0').toString();
      _selectedCategoryId = _asInt(g['category_id']);
      _selectedBrandId = _asInt(g['brand_id']);
      _selectedUnitId = _asInt(g['unit_id']);
      _selectedVendorId = _asInt(g['vendor_id']);
    }
    if (widget.vendorId != null) _selectedVendorId = widget.vendorId;
    _defaultRetailCtrl.addListener(_onDefaultPackagePriceChanged);
    _defaultWholesaleCtrl.addListener(_onDefaultPackagePriceChanged);
    _loadRefData();
  }

  void _onDefaultPackagePriceChanged() {
    if (mounted && _defaultPackagings.isNotEmpty) setState(() {});
  }

  @override
  void dispose() {
    _defaultRetailCtrl.removeListener(_onDefaultPackagePriceChanged);
    _defaultWholesaleCtrl.removeListener(_onDefaultPackagePriceChanged);
    _nameCtrl.dispose();
    _secondaryNameCtrl.dispose();
    _taxRateCtrl.dispose();
    _defaultRetailCtrl.dispose();
    _defaultWholesaleCtrl.dispose();
    _defaultCostCtrl.dispose();
    _defaultReorderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() => _loading = true);
    // Reference permissions are independent. Load them independently so a 403
    // for units cannot wipe categories/brands (and vice versa).
    await Future.wait([
      _loadCategories(),
      _loadBrands(),
      _loadUnits(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _commonService.getCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  Future<void> _loadBrands() async {
    try {
      final brands = await _commonService.getBrands();
      if (!mounted) return;
      setState(() => _brands = brands);
    } catch (e) {
      debugPrint('Error loading brands: $e');
    }
  }

  Future<void> _loadUnits() async {
    try {
      final units = await _unitService.list();
      if (!mounted) return;
      setState(() {
        _units = units
            .where((u) => u.isActive || (_isEdit && u.id == _selectedUnitId))
            .toList();
        if (!_units.any((u) => u.id == _selectedUnitId)) {
          _selectedUnitId = null;
        }
        if (_selectedUnitId == null && !_isEdit && _units.isNotEmpty) {
          final piece =
              _units.where((u) => u.name.toLowerCase() == 'piece').toList();
          _selectedUnitId = piece.isNotEmpty ? piece.first.id : _units.first.id;
        }
      });
    } catch (e) {
      debugPrint('Error loading units: $e');
    }
  }

  Future<void> _manageCategories() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-categories')) return;
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Manage Categories',
      singularLabel: 'Category',
      icon: Icons.category_outlined,
      selectedId: _selectedCategoryId,
      loadItems: _commonService.getCategories,
      createItem: _commonService.createCategory,
      updateItem: _commonService.updateCategory,
      deleteItem: _commonService.deleteCategory,
      // Group update treats an omitted nullable FK as "leave unchanged".
      // Do not offer Clear while editing until the backend clear contract is
      // unambiguous; create mode may still leave the field unset.
      allowClearSelection: !_isEdit,
    );
    if (result == null || !mounted) return;
    await _loadCategories();
    if (!mounted) return;
    setState(() {
      _selectedCategoryId =
          _categories.any((c) => _asInt(c['id']) == result.selectedId)
              ? result.selectedId
              : null;
    });
  }

  Future<void> _manageBrands() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-brands')) return;
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Manage Brands',
      singularLabel: 'Brand',
      icon: Icons.branding_watermark_outlined,
      selectedId: _selectedBrandId,
      loadItems: _commonService.getBrands,
      createItem: _commonService.createBrand,
      updateItem: _commonService.updateBrand,
      deleteItem: _commonService.deleteBrand,
      allowClearSelection: !_isEdit,
    );
    if (result == null || !mounted) return;
    await _loadBrands();
    if (!mounted) return;
    setState(() {
      _selectedBrandId = _brands.any((b) => _asInt(b['id']) == result.selectedId)
          ? result.selectedId
          : null;
    });
  }

  Future<void> _applyUnitChange(int? nextUnitId) async {
    if (nextUnitId == _selectedUnitId) return;
    if (_isEdit && _groupHasPackagings) {
      if (mounted) {
        AppFeedback.warning(
          context,
          'Base unit is locked because one or more variants already have packaging conversions.',
        );
      }
      return;
    }

    final hasUnsavedPackaging = _defaultPackagings.isNotEmpty ||
        _variants.any((v) => v.packagings.isNotEmpty);
    if (hasUnsavedPackaging) {
      final clear = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Change base unit?'),
              content: const Text(
                'Packaging conversions are defined against the current base unit. Changing the unit will clear the configured packaging on new variants so it cannot be reinterpreted incorrectly.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Clear Packaging & Change'),
                ),
              ],
            ),
          ) ??
          false;
      if (!clear || !mounted) return;
    }

    setState(() {
      _selectedUnitId = nextUnitId;
      _defaultPackagings = [];
      for (final variant in _variants) {
        variant.packagings = [];
      }
    });
  }

  Future<void> _manageUnits() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-units')) return;
    if (_isEdit && _groupHasPackagings) {
      AppFeedback.warning(
        context,
        'Base unit is locked because this family already has packaging conversions.',
      );
      return;
    }
    final result = await showUnitManagerDialog(
      context: context,
      service: _unitService,
      selectedId: _selectedUnitId,
      allowClearSelection: !_isEdit,
    );
    if (result == null || !mounted) return;
    final next = result.selectedId;
    await _loadUnits();
    if (!mounted) return;
    if (next == null || _units.any((u) => u.id == next)) {
      await _applyUnitChange(next);
    }
  }

  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: token),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedVendor = picked;
        _selectedVendorId = _asInt(picked['id']);
      });
    }
  }

  _VariantDraft _newVariantSeed() => _VariantDraft(
        id: _nextVariantId++,
        secondaryName: _secondaryNameCtrl.text.trim(),
        retailPrice: _parseDouble(_defaultRetailCtrl.text),
        wholesalePrice: _parseDouble(_defaultWholesaleCtrl.text),
        costPrice: _parseDouble(_defaultCostCtrl.text),
        reorderLevel: _parseInt(_defaultReorderCtrl.text),
        packagings: _defaultPackagings.map((p) => p.copy()).toList(),
      );

  Future<void> _addVariantFlow() async {
    _VariantDraft? seed;
    var addAnother = true;

    while (mounted && addAnother) {
      final result = await _showVariantDialog(seed: seed ?? _newVariantSeed());
      if (result == null) return;

      setState(() => _variants.add(result.variant));
      addAnother = result.addAnother;
      if (addAnother) {
        seed = result.variant.copyForNext(id: _nextVariantId++);
        // showDialog completes when pop begins, while the old DialogRoute can
        // still be reversing. Let that route fully leave the overlay before
        // pushing the next variant editor.
        await Future<void>.delayed(kThemeAnimationDuration);
        if (!mounted) return;
      }
    }
  }

  Future<void> _editVariant(int index) async {
    final current = _variants[index];
    final result = await _showVariantDialog(
      seed: current.copy(),
      editingIndex: index,
      allowAddAnother: false,
    );
    if (result != null && mounted) {
      setState(() => _variants[index] = result.variant);
    }
  }

  void _removeVariant(int index) {
    setState(() => _variants.removeAt(index));
  }

  Future<_VariantDialogResult?> _showVariantDialog({
    required _VariantDraft seed,
    int? editingIndex,
    bool allowAddAnother = true,
  }) {
    return showDialog<_VariantDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VariantEditorDialog(
        seed: seed,
        editingIndex: editingIndex,
        allowAddAnother: allowAddAnother,
        groupName: _nameCtrl.text.trim(),
        selectedUnit: _selectedUnit,
        groupService: _groupService,
        validateDraft: (draft) => _variantValidationMessage(
          draft,
          excludingIndex: editingIndex,
        ),
      ),
    );
  }

  String? _variantValidationMessage(
    _VariantDraft draft, {
    int? excludingIndex,
  }) {
    if (draft.size.trim().isEmpty && draft.color.trim().isEmpty) {
      return 'Enter at least a size or a color.';
    }
    if (draft.sku.trim().isEmpty) return 'SKU is required for every variant.';
    if (draft.retailPrice <= 0) return 'Retail price must be greater than 0.';
    if (draft.wholesalePrice < 0 || draft.costPrice < 0) {
      return 'Price and cost values cannot be negative.';
    }
    if (draft.discount < 0) return 'Discount cannot be negative.';
    if (draft.discountType == 'percentage' && draft.discount > 100) {
      return 'Percentage discount cannot exceed 100%.';
    }
    if (draft.discountType == 'fixed' && draft.discount > draft.retailPrice) {
      return 'Fixed discount cannot exceed the retail price.';
    }
    if (draft.openingStock < 0) return 'Opening stock cannot be negative.';
    if (draft.reorderLevel < 0) return 'Reorder level cannot be negative.';
    if (draft.openingStock > 0 && draft.costPrice <= 0) {
      return 'Opening stock requires a cost / opening cost greater than 0.';
    }

    final unit = _selectedUnit;
    if (unit != null && !unit.allowDecimal &&
        !QuantityRule.isWhole(draft.openingStock)) {
      return 'Decimal opening stock is not allowed for unit "${unit.name}".';
    }

    final sizeKey = draft.size.trim().toLowerCase();
    final colorKey = draft.color.trim().toLowerCase();
    final skuKey = draft.sku.trim().toLowerCase();
    final barcodeKey = draft.barcode.trim().toLowerCase();

    for (var i = 0; i < _variants.length; i++) {
      if (i == excludingIndex) continue;
      final other = _variants[i];
      if (other.size.trim().toLowerCase() == sizeKey &&
          other.color.trim().toLowerCase() == colorKey) {
        return 'This size/color combination is already added.';
      }
      if (other.sku.trim().toLowerCase() == skuKey) {
        return 'SKU "${draft.sku}" is already used by another variant.';
      }
      if (barcodeKey.isNotEmpty &&
          other.barcode.trim().toLowerCase() == barcodeKey) {
        return 'Barcode "${draft.barcode}" is already used by another variant.';
      }
    }
    return null;
  }

  Future<void> _generateMissingSkus() async {
    if (_variants.isEmpty) return;
    if (_nameCtrl.text.trim().isEmpty) {
      AppFeedback.warning(context, 'Enter the product name first.');
      return;
    }
    setState(() => _bulkSkuBusy = true);
    try {
      for (final variant in _variants) {
        if (variant.sku.trim().isNotEmpty) continue;
        variant.sku = await _groupService.generateSKU(
          groupName: _nameCtrl.text.trim(),
          size: variant.size,
          color: variant.color,
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'SKU generation failed: $e');
    } finally {
      if (mounted) setState(() => _bulkSkuBusy = false);
    }
  }

  Future<void> _generateMissingBarcodes() async {
    if (_variants.isEmpty) return;
    setState(() => _bulkBarcodeBusy = true);
    try {
      final seen = _variants
          .map((v) => v.barcode.trim())
          .where((v) => v.isNotEmpty)
          .toSet();
      for (final variant in _variants) {
        if (variant.barcode.trim().isNotEmpty) continue;
        var barcode = '';
        for (var attempt = 0; attempt < 4; attempt++) {
          barcode = await _groupService.generateBarcode();
          if (!seen.contains(barcode)) break;
        }
        variant.barcode = barcode;
        seen.add(barcode);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Barcode generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _bulkBarcodeBusy = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_isEdit) {
      if (_variants.isEmpty) {
        AppFeedback.error(context, 'Add at least one variant before saving.');
        return;
      }
      for (var i = 0; i < _variants.length; i++) {
        final error = _variantValidationMessage(_variants[i], excludingIndex: i);
        if (error != null) {
          AppFeedback.error(context, 'Variant ${i + 1}: $error');
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final taxRate = _parseDouble(_taxRateCtrl.text);
      if (_isEdit) {
        await _groupService.updateGroup(
          _asInt(widget.group!['id'])!,
          name: _nameCtrl.text.trim(),
          secondaryName: _secondaryNameCtrl.text.trim(),
          isActive: _isActive,
          // Update sends every shared family FK explicitly. Zero is the
          // backend's clear sentinel, so choosing "None" really clears the
          // group and all existing variants instead of silently omitting it.
          categoryId: _selectedCategoryId ?? 0,
          brandId: _selectedBrandId ?? 0,
          unitId: _selectedUnitId ?? 0,
          vendorId: _selectedVendorId ?? 0,
          taxRate: taxRate,
          taxInclusive: _taxInclusive,
        );
        if (mounted) {
          AppFeedback.success(context, 'Variable product updated.');
          Navigator.pop(context, true);
        }
        return;
      }

      final variants = _variants
          .map(
            (v) => VariantInput(
              size: v.size,
              color: v.color,
              secondaryName: v.secondaryName,
              sku: v.sku,
              barcode: v.barcode,
              price: v.retailPrice,
              costPrice: v.costPrice,
              wholesalePrice: v.wholesalePrice,
              stock: v.openingStock,
              reorderLevel: v.reorderLevel,
              taxRate: taxRate,
              taxInclusive: _taxInclusive,
              discount: v.discount,
              discountType: v.discountType,
              packagings: v.packagings,
            ),
          )
          .toList();

      final created = await _groupService.createVariableProduct(
        name: _nameCtrl.text.trim(),
        secondaryName: _secondaryNameCtrl.text.trim(),
        isActive: _isActive,
        categoryId: _selectedCategoryId,
        brandId: _selectedBrandId,
        unitId: _selectedUnitId,
        vendorId: _selectedVendorId,
        taxRate: taxRate,
        taxInclusive: _taxInclusive,
        discountType: _discountType,
        variants: variants,
      );

      // Variant creation is atomic on the backend, while images use the
      // existing multipart product endpoint. Match returned products by the
      // required unique SKU (not list order) before uploading each image.
      final failedImages = await _uploadCreatedVariantImages(created);

      if (mounted) {
        if (failedImages > 0) {
          AppFeedback.warning(
            context,
            'Product created successfully, but $failedImages variant image${failedImages == 1 ? '' : 's'} could not be uploaded. Open the product family and retry the image from Edit Variant.',
          );
        } else {
          AppFeedback.success(
            context,
            'Created ${_nameCtrl.text.trim()} with ${variants.length} variant${variants.length == 1 ? '' : 's'}.',
          );
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<int> _uploadCreatedVariantImages(Map<String, dynamic> created) async {
    final rawProducts = created['products'];
    if (rawProducts is! List) {
      return _variants.where((v) => v.imagePath != null).length;
    }

    final productIdBySku = <String, int>{};
    for (final raw in rawProducts) {
      if (raw is! Map) continue;
      final sku = (raw['sku'] ?? '').toString().trim();
      final id = _asInt(raw['id']);
      if (sku.isNotEmpty && id != null) productIdBySku[sku] = id;
    }

    var failed = 0;
    for (final variant in _variants) {
      final imagePath = variant.imagePath;
      if (imagePath == null || imagePath.isEmpty) continue;
      final productId = productIdBySku[variant.sku.trim()];
      if (productId == null) {
        failed++;
        continue;
      }
      try {
        await _productService.updateProduct(
          productId,
          const <String, dynamic>{},
          imagePath: imagePath,
        );
      } catch (e) {
        debugPrint('Variant image upload failed for ${variant.sku}: $e');
        failed++;
      }
    }
    return failed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Product Family' : 'Add Variable Product'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: Text(_isEdit ? 'Save Changes' : 'Create Product'),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPageIntro(),
                        const SizedBox(height: 18),
                        _buildGeneralCard(),
                        if (!_isEdit) ...[
                          const SizedBox(height: 18),
                          _buildDefaultsCard(),
                          const SizedBox(height: 18),
                          _buildVariantsCard(),
                        ],
                        const SizedBox(height: 22),
                        _buildFooterActions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPageIntro() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.style_rounded, color: AppTheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Edit product family' : 'Create a variable product',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'Update the shared name and catalog settings. Existing variants are managed from the product detail screen.'
                    : 'Set the shared product information once, then add only the variants you actually stock.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralCard() {
    final auth = context.watch<AuthProvider>();
    final canManageCategories = auth.hasPermission('manage-categories');
    final canManageBrands = auth.hasPermission('manage-brands');
    final canManageUnits = auth.hasPermission('manage-units');

    return _sectionCard(
      title: 'General Information',
      subtitle: 'Shared by every variant in this product family.',
      icon: Icons.inventory_2_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 760;
          final width = twoColumns
              ? (constraints.maxWidth - 14) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: constraints.maxWidth,
                child: TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration('Product / Group Name *',
                      icon: Icons.label_outline_rounded),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Product name is required'
                      : null,
                ),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: TextFormField(
                  controller: _secondaryNameCtrl,
                  decoration: _inputDecoration(
                    'Secondary Name',
                    icon: Icons.translate_rounded,
                  ).copyWith(
                    hintText: 'Optional alternate or local-language family name',
                  ),
                ),
              ),
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: _dropdownField(
                        label: 'Category',
                        icon: Icons.category_outlined,
                        value: _validMapSelection(_categories, _selectedCategoryId),
                        items: _categories,
                        onChanged: (value) =>
                            setState(() => _selectedCategoryId = value),
                      ),
                    ),
                    if (canManageCategories) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Manage categories',
                        onPressed: _saving ? null : _manageCategories,
                        icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: _dropdownField(
                        label: 'Brand',
                        icon: Icons.branding_watermark_outlined,
                        value: _validMapSelection(_brands, _selectedBrandId),
                        items: _brands,
                        onChanged: (value) =>
                            setState(() => _selectedBrandId = value),
                      ),
                    ),
                    if (canManageBrands) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Manage brands',
                        onPressed: _saving ? null : _manageBrands,
                        icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _units.any((u) => u.id == _selectedUnitId)
                            ? _selectedUnitId
                            : null,
                        decoration: _inputDecoration('Unit of Measure',
                            icon: Icons.straighten_outlined),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('None'),
                          ),
                          ..._units.map(
                            (u) => DropdownMenuItem<int?>(
                              value: u.id,
                              child: Text(
                                u.allowDecimal
                                    ? '${u.name} · decimals allowed'
                                    : u.name,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (_isEdit && _groupHasPackagings)
                            ? null
                            : (value) => _applyUnitChange(value),
                      ),
                    ),
                    if (canManageUnits) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Manage units',
                        onPressed: (_saving || (_isEdit && _groupHasPackagings))
                            ? null
                            : _manageUnits,
                        icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: width, child: _vendorField()),
              SizedBox(
                width: width,
                child: TextFormField(
                  controller: _taxRateCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDecoration('Tax Rate (%)',
                      icon: Icons.percent_rounded),
                  validator: (value) {
                    final n = _parseDouble(value ?? '');
                    return n < 0 ? 'Tax rate cannot be negative' : null;
                  },
                ),
              ),
              SizedBox(
                width: width,
                child: _toggleTile(
                  title: 'Tax Inclusive',
                  subtitle: 'Selling prices already include tax',
                  icon: Icons.receipt_long_outlined,
                  value: _taxInclusive,
                  onChanged: (value) => setState(() => _taxInclusive = value),
                ),
              ),
              SizedBox(
                width: width,
                child: _toggleTile(
                  title: 'Active',
                  subtitle: _isActive
                      ? 'Available to operational product screens'
                      : 'Hidden from active product selection',
                  icon: Icons.power_settings_new_rounded,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  activeColor: AppTheme.success,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDefaultsCard() {
    return _sectionCard(
      title: 'Defaults for New Variants',
      subtitle:
          'Optional shortcuts. These values prefill Add Variant and can still be changed per variant.',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _numberField(_defaultRetailCtrl, 'Default Retail'),
                  ),
                  SizedBox(
                    width: width,
                    child: _numberField(
                        _defaultWholesaleCtrl, 'Default Wholesale'),
                  ),
                  SizedBox(
                    width: width,
                    child: _numberField(_defaultCostCtrl, 'Default Cost'),
                  ),
                  SizedBox(
                    width: width,
                    child: _numberField(
                        _defaultReorderCtrl, 'Default Reorder Level'),
                  ),
                ],
              );
            },
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 14),
            ProductPackagingEditor(
              title: 'Default Packaging for New Variants',
              packagings: _defaultPackagings,
              baseUnit: _selectedUnit,
              baseRetailPrice: _parseDouble(_defaultRetailCtrl.text),
              baseWholesalePrice: _parseDouble(_defaultWholesaleCtrl.text),
              enabled: !_saving,
              onChanged: (items) =>
                  setState(() => _defaultPackagings = items),
            ),
            if (_variants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            for (final variant in _variants) {
                              variant.packagings = _defaultPackagings
                                  .map((p) => p.copy())
                                  .toList();
                            }
                          });
                          AppFeedback.success(
                            context,
                            'Packaging defaults applied to current variants.',
                          );
                        },
                  icon: const Icon(Icons.copy_all_outlined, size: 17),
                  label: const Text('Apply Packaging to Current Variants'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildVariantsCard() {
    return _sectionCard(
      title: 'Variants',
      subtitle:
          'Each row is one real sellable SKU with independent price, barcode and opening stock.',
      icon: Icons.view_list_rounded,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: _variants.isEmpty || _bulkSkuBusy
                ? null
                : _generateMissingSkus,
            icon: _bulkSkuBusy
                ? const _ButtonSpinner()
                : const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Generate Missing SKUs'),
          ),
          OutlinedButton.icon(
            onPressed: _variants.isEmpty || _bulkBarcodeBusy
                ? null
                : _generateMissingBarcodes,
            icon: _bulkBarcodeBusy
                ? const _ButtonSpinner()
                : const Icon(Icons.qr_code_2_rounded, size: 17),
            label: const Text('Generate Missing Barcodes'),
          ),
          FilledButton.icon(
            onPressed: _addVariantFlow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Variant'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
      child: _variants.isEmpty ? _buildVariantEmptyState() : _buildVariantTable(),
    );
  }

  Widget _buildVariantEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.add_box_outlined,
                color: AppTheme.primary, size: 26),
          ),
          const SizedBox(height: 14),
          const Text(
            'No variants added',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Add exactly the size/color combinations you sell. CounterIQ will not create unwanted combinations.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addVariantFlow,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Add First Variant'),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 42,
          dataRowHeight: 54,
          horizontalMargin: 16,
          columnSpacing: 26,
          headingRowColor:
              MaterialStateProperty.all(const Color(0xFFF3F6FA)),
          columns: const [
            DataColumn(label: _TableHeading('IMAGE')),
            DataColumn(label: _TableHeading('SIZE')),
            DataColumn(label: _TableHeading('COLOR')),
            DataColumn(label: _TableHeading('SKU')),
            DataColumn(label: _TableHeading('BARCODE')),
            DataColumn(label: _TableHeading('RETAIL'), numeric: true),
            DataColumn(label: _TableHeading('WHOLESALE'), numeric: true),
            DataColumn(label: _TableHeading('COST'), numeric: true),
            DataColumn(label: _TableHeading('DISCOUNT')),
            DataColumn(label: _TableHeading('OPENING'), numeric: true),
            DataColumn(label: _TableHeading('REORDER'), numeric: true),
            DataColumn(label: _TableHeading('ACTIONS')),
          ],
          rows: List<DataRow>.generate(_variants.length, (index) {
            final v = _variants[index];
            return DataRow(
              cells: [
                DataCell(_draftImageThumb(v.imagePath)),
                DataCell(_tableText(v.size.isEmpty ? '—' : v.size,
                    strong: true)),
                DataCell(_tableText(v.color.isEmpty ? '—' : v.color,
                    strong: true)),
                DataCell(_tableText(v.sku, monospace: true)),
                DataCell(_tableText(
                    v.barcode.isEmpty ? '—' : v.barcode,
                    monospace: true)),
                DataCell(_tableText(_fmtMoney(v.retailPrice), strong: true)),
                DataCell(_tableText(_fmtMoney(v.wholesalePrice))),
                DataCell(_tableText(_fmtMoney(v.costPrice))),
                DataCell(_tableText(_discountLabel(v.discount, v.discountType))),
                DataCell(_tableText(_fmtQty(v.openingStock))),
                DataCell(_tableText(v.reorderLevel.toString())),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit variant',
                        onPressed: () => _editVariant(index),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppTheme.primary,
                      ),
                      IconButton(
                        tooltip: 'Remove variant',
                        onPressed: () => _removeVariant(index),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: AppTheme.danger,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _draftImageThumb(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Icon(Icons.image_outlined, size: 17, color: AppTheme.textMuted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.file(
        File(path),
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 38,
          height: 38,
          color: AppTheme.surfaceSoft,
          child: const Icon(Icons.broken_image_outlined,
              size: 17, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  String _discountLabel(double value, String type) {
    if (value <= 0) return '—';
    if (type == 'fixed') return '${_fmtMoney(value)} fixed';
    return '${_fmtQty(value)}%';
  }

  Widget _buildFooterActions() {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded, size: 17),
          label: const Text('Cancel'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const _ButtonSpinner()
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isEdit ? 'Save Changes' : 'Create Variable Product'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 14),
                  Flexible(child: trailing),
                ],
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _vendorField() {
    final label = _selectedVendor != null
        ? _vendorDisplayName(_selectedVendor!)
        : _selectedVendorId != null
            ? 'Vendor #$_selectedVendorId'
            : 'None selected';

    return InkWell(
      onTap: _pickVendor,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration:
            _inputDecoration('Vendor / Supplier', icon: Icons.storefront_outlined),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedVendorId == null
                      ? AppTheme.textMuted
                      : AppTheme.navy,
                ),
              ),
            ),
            if (_selectedVendorId != null)
              IconButton(
                tooltip: 'Clear vendor',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => setState(() {
                  _selectedVendor = null;
                  _selectedVendorId = null;
                }),
                icon: const Icon(Icons.close_rounded, size: 16),
              )
            else
              const Icon(Icons.unfold_more_rounded,
                  size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color activeColor = AppTheme.primary,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? activeColor : AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy)),
                Text(subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required IconData icon,
    required int? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int?>(
      value: value,
      decoration: _inputDecoration(label, icon: icon),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('None')),
        ...items.map(
          (item) => DropdownMenuItem<int?>(
            value: _asInt(item['id']),
            child: Text((item['name'] ?? '').toString()),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDecoration(label),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) return null;
        final n = double.tryParse(value!.trim());
        if (n == null) return 'Enter a valid number';
        if (n < 0) return 'Cannot be negative';
        return null;
      },
    );
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFFCFDFE),
      isDense: true,
    );
  }

  Widget _dialogHeader(String title, String subtitle,
      {required VoidCallback onClose}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 14, 18),
      decoration: const BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.style_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.62), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _dialogSectionTitle(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.75,
          fontWeight: FontWeight.w800,
          color: AppTheme.textMuted,
        ),
      );

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool numeric = false,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        isDense: true,
      ),
    );
  }

  Widget _tableText(String value,
      {bool strong = false, bool monospace = false}) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: AppTheme.navy,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        fontFamily: monospace ? 'monospace' : null,
      ),
    );
  }

  int? _validMapSelection(List<Map<String, dynamic>> items, int? value) {
    if (value == null) return null;
    return items.any((item) => _asInt(item['id']) == value) ? value : null;
  }

  static String _vendorDisplayName(Map<String, dynamic> vendor) {
    final company = (vendor['company_name'] ?? '').toString().trim();
    final first = (vendor['first_name'] ?? '').toString().trim();
    final last = (vendor['last_name'] ?? '').toString().trim();
    if (company.isNotEmpty) return company;
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Vendor #${vendor['id']}' : full;
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double _parseDouble(String value) =>
      double.tryParse(value.trim()) ?? 0.0;

  static int _parseInt(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    return parsed.round();
  }

  static String _numberText(num value) {
    if (value == 0) return '';
    if (value.toDouble() == value.toDouble().truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _fmtMoney(double value) => value.toStringAsFixed(2);

  static String _fmtQty(double value) {
    if (QuantityRule.isWhole(value)) return value.toInt().toString();
    var text = value.toStringAsFixed(4);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
  }
}

typedef _VariantDraftValidator = String? Function(_VariantDraft draft);

/// Owns all variant-editor controllers inside the dialog route.
///
/// This is intentionally a dedicated StatefulWidget instead of creating and
/// disposing TextEditingControllers around showDialog(). A dialog Future can
/// complete before the route has finished its reverse transition; disposing
/// controllers from the caller at that point can tear down dependencies while
/// TextFormFields are still mounted on Windows.
class _VariantEditorDialog extends StatefulWidget {
  final _VariantDraft seed;
  final int? editingIndex;
  final bool allowAddAnother;
  final String groupName;
  final ProductUnit? selectedUnit;
  final ProductGroupService groupService;
  final _VariantDraftValidator validateDraft;

  const _VariantEditorDialog({
    required this.seed,
    required this.editingIndex,
    required this.allowAddAnother,
    required this.groupName,
    required this.selectedUnit,
    required this.groupService,
    required this.validateDraft,
  });

  @override
  State<_VariantEditorDialog> createState() => _VariantEditorDialogState();
}

class _VariantEditorDialogState extends State<_VariantEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _sizeCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _secondaryNameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _retailCtrl;
  late final TextEditingController _wholesaleCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _reorderCtrl;
  late final TextEditingController _discountCtrl;
  late String _discountType;
  String? _imagePath;
  late List<ProductPackaging> _packagings;

  bool _skuBusy = false;
  bool _barcodeBusy = false;
  bool _submitting = false;

  bool get _isEditing => widget.editingIndex != null;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _sizeCtrl = TextEditingController(text: seed.size);
    _colorCtrl = TextEditingController(text: seed.color);
    _secondaryNameCtrl = TextEditingController(text: seed.secondaryName);
    _skuCtrl = TextEditingController(text: seed.sku);
    _barcodeCtrl = TextEditingController(text: seed.barcode);
    _retailCtrl = TextEditingController(text: _numberText(seed.retailPrice));
    _wholesaleCtrl =
        TextEditingController(text: _numberText(seed.wholesalePrice));
    _costCtrl = TextEditingController(text: _numberText(seed.costPrice));
    _stockCtrl = TextEditingController(text: _numberText(seed.openingStock));
    _reorderCtrl = TextEditingController(
      text: seed.reorderLevel == 0 ? '0' : seed.reorderLevel.toString(),
    );
    _discountCtrl = TextEditingController(text: _numberText(seed.discount));
    _discountType = seed.discountType == 'fixed' ? 'fixed' : 'percentage';
    _imagePath = seed.imagePath;
    _packagings = seed.packagings.map((p) => p.copy()).toList();
    _retailCtrl.addListener(_onPackagePriceChanged);
    _wholesaleCtrl.addListener(_onPackagePriceChanged);
  }

  void _onPackagePriceChanged() {
    if (mounted && _packagings.isNotEmpty) setState(() {});
  }

  @override
  void dispose() {
    _retailCtrl.removeListener(_onPackagePriceChanged);
    _wholesaleCtrl.removeListener(_onPackagePriceChanged);
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    _secondaryNameCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _retailCtrl.dispose();
    _wholesaleCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _reorderCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_submitting) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024) {
      if (mounted) {
        AppFeedback.error(context, 'Product images must be 2 MB or smaller.');
      }
      return;
    }
    if (mounted) setState(() => _imagePath = file.path);
  }

  Widget _buildImagePicker() {
    final path = _imagePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: path == null || path.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 34, color: AppTheme.textMuted),
                      SizedBox(height: 6),
                      Text(
                        'No variant image selected',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.textMuted),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          tooltip: 'Remove image',
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _imagePath = null),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _submitting ? null : _pickImage,
            icon: const Icon(Icons.image_outlined, size: 17),
            label: Text(path == null || path.isEmpty
                ? 'Choose Image'
                : 'Replace Image'),
          ),
        ),
        const Text(
          'JPG, PNG, or WebP · maximum 2 MB',
          style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Future<void> _generateSku() async {
    if (_skuBusy || _submitting) return;
    if (widget.groupName.isEmpty) {
      AppFeedback.warning(context, 'Enter the product name first.');
      return;
    }

    setState(() => _skuBusy = true);
    try {
      final sku = await widget.groupService.generateSKU(
        groupName: widget.groupName,
        size: _sizeCtrl.text.trim(),
        color: _colorCtrl.text.trim(),
      );
      if (!mounted) return;
      _skuCtrl.text = sku;
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'SKU generation failed: $e');
    } finally {
      if (mounted) setState(() => _skuBusy = false);
    }
  }

  Future<void> _generateBarcode() async {
    if (_barcodeBusy || _submitting) return;
    setState(() => _barcodeBusy = true);
    try {
      final barcode = await widget.groupService.generateBarcode();
      if (!mounted) return;
      _barcodeCtrl.text = barcode;
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Barcode generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _barcodeBusy = false);
    }
  }

  void _submit(bool addAnother) {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final draft = _VariantDraft(
      id: widget.seed.id,
      size: _sizeCtrl.text.trim(),
      color: _colorCtrl.text.trim(),
      secondaryName: _secondaryNameCtrl.text.trim(),
      sku: _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      retailPrice: _parseDouble(_retailCtrl.text),
      wholesalePrice: _parseDouble(_wholesaleCtrl.text),
      costPrice: _parseDouble(_costCtrl.text),
      discount: _parseDouble(_discountCtrl.text),
      discountType: _discountType,
      openingStock: _parseDouble(_stockCtrl.text),
      reorderLevel: _parseInt(_reorderCtrl.text),
      imagePath: _imagePath,
      packagings: _packagings.map((p) => p.copy()).toList(),
    );

    final error = widget.validateDraft(draft);
    if (error != null) {
      AppFeedback.error(context, error);
      return;
    }

    // Prevent double-clicks while the route begins its pop transition. The
    // dialog owns its controllers, so they remain valid until State.dispose().
    setState(() => _submitting = true);
    Navigator.of(context).pop(
      _VariantDialogResult(
        variant: draft,
        addAnother: widget.allowAddAnother && addAnother,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              _isEditing ? 'Edit Variant' : 'Add Variant',
              _isEditing
                  ? 'Update this variant before saving the product.'
                  : 'Add only the size/color combination you actually stock.',
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Variation'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _sizeCtrl,
                              'Size',
                              hint: 'e.g. S, M, XL, 42',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _colorCtrl,
                              'Color',
                              hint: 'e.g. Black, Blue',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _secondaryNameCtrl,
                        'Secondary Name',
                        hint: 'Optional local-language name for this variant',
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('Product Image'),
                      const SizedBox(height: 10),
                      _buildImagePicker(),
                      const SizedBox(height: 22),
                      _sectionTitle('Identification'),
                      const SizedBox(height: 10),
                      _field(
                        _skuCtrl,
                        'SKU *',
                        hint: 'Enter or generate a SKU',
                        validator: (value) =>
                            (value?.trim().isEmpty ?? true)
                                ? 'SKU is required'
                                : null,
                        suffix: _skuBusy
                            ? const _SmallSpinner()
                            : IconButton(
                                tooltip: 'Generate SKU',
                                onPressed: _submitting ? null : _generateSku,
                                icon: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 18,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _barcodeCtrl,
                        'Barcode',
                        hint: 'Manufacturer barcode or generate one',
                        suffix: _barcodeBusy
                            ? const _SmallSpinner()
                            : IconButton(
                                tooltip: 'Generate barcode',
                                onPressed:
                                    _submitting ? null : _generateBarcode,
                                icon: const Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 19,
                                ),
                              ),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('Pricing'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _retailCtrl,
                              'Retail Price *',
                              numeric: true,
                              validator: (value) =>
                                  _parseDouble(value ?? '') <= 0
                                      ? 'Must be greater than 0'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _wholesaleCtrl,
                              'Wholesale Price',
                              numeric: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _costCtrl,
                              'Cost / Opening Cost',
                              numeric: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              _reorderCtrl,
                              'Reorder Level',
                              numeric: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _discountCtrl,
                              _discountType == 'fixed'
                                  ? 'Discount (Fixed Amount)'
                                  : 'Discount (%)',
                              numeric: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _discountType,
                              decoration: InputDecoration(
                                labelText: 'Discount Type',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide:
                                      const BorderSide(color: AppTheme.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: const BorderSide(
                                      color: AppTheme.primary, width: 1.5),
                                ),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'percentage',
                                  child: Text('Percentage (%)'),
                                ),
                                DropdownMenuItem(
                                  value: 'fixed',
                                  child: Text('Fixed Amount'),
                                ),
                              ],
                              onChanged: _submitting
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() => _discountType = value);
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('Packaging'),
                      const SizedBox(height: 10),
                      ProductPackagingEditor(
                        packagings: _packagings,
                        baseUnit: widget.selectedUnit,
                        baseRetailPrice: _parseDouble(_retailCtrl.text),
                        baseWholesalePrice: _parseDouble(_wholesaleCtrl.text),
                        enabled: !_submitting,
                        onChanged: (items) =>
                            setState(() => _packagings = items),
                      ),
                      const SizedBox(height: 22),
                      _sectionTitle('Opening Inventory'),
                      const SizedBox(height: 10),
                      _field(
                        _stockCtrl,
                        'Opening Stock',
                        numeric: true,
                        hint: widget.selectedUnit == null
                            ? '0'
                            : 'Quantity in ${widget.selectedUnit!.label}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Opening stock is posted through CounterIQ inventory accounting. '
                        'Later stock changes should use purchases or stock adjustments.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppTheme.textMuted.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  if (widget.allowAddAnother && !_isEditing) ...[
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _submit(true),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Save & Add Another'),
                    ),
                    const SizedBox(width: 10),
                  ],
                  FilledButton.icon(
                    onPressed: _submitting ? null : () => _submit(false),
                    icon: Icon(
                      _isEditing ? Icons.save_rounded : Icons.check_rounded,
                      size: 17,
                    ),
                    label: Text(_isEditing ? 'Save Variant' : 'Add Variant'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 14, 18),
      decoration: const BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.style_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.75,
          fontWeight: FontWeight.w800,
          color: AppTheme.textMuted,
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool numeric = false,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
        isDense: true,
      ),
    );
  }

  static double _parseDouble(String value) =>
      double.tryParse(value.trim()) ?? 0.0;

  static int _parseInt(String value) {
    final parsed = double.tryParse(value.trim()) ?? 0;
    return parsed.round();
  }

  static String _numberText(num value) {
    if (value == 0) return '';
    if (value.toDouble() == value.toDouble().truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

class _VariantDraft {
  final int id;
  String size;
  String color;
  String secondaryName;
  String sku;
  String barcode;
  double retailPrice;
  double wholesalePrice;
  double costPrice;
  double discount;
  String discountType;
  double openingStock;
  int reorderLevel;
  String? imagePath;
  List<ProductPackaging> packagings;

  _VariantDraft({
    required this.id,
    this.size = '',
    this.color = '',
    this.secondaryName = '',
    this.sku = '',
    this.barcode = '',
    this.retailPrice = 0,
    this.wholesalePrice = 0,
    this.costPrice = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.openingStock = 0,
    this.reorderLevel = 0,
    this.imagePath,
    List<ProductPackaging>? packagings,
  }) : packagings =
            packagings?.map((p) => p.copy()).toList() ?? <ProductPackaging>[];

  _VariantDraft copy() => _VariantDraft(
        id: id,
        size: size,
        color: color,
        secondaryName: secondaryName,
        sku: sku,
        barcode: barcode,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
        costPrice: costPrice,
        discount: discount,
        discountType: discountType,
        openingStock: openingStock,
        reorderLevel: reorderLevel,
        imagePath: imagePath,
        packagings: packagings,
      );

  _VariantDraft copyForNext({required int id}) => _VariantDraft(
        id: id,
        secondaryName: secondaryName,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
        costPrice: costPrice,
        discount: discount,
        discountType: discountType,
        reorderLevel: reorderLevel,
        packagings: packagings,
        // Never copy an image into the next variant automatically; colors and
        // sizes often have different product photos.
        imagePath: null,
      );
}

class _VariantDialogResult {
  final _VariantDraft variant;
  final bool addAnother;

  const _VariantDialogResult({
    required this.variant,
    required this.addAnother,
  });
}

class _TableHeading extends StatelessWidget {
  final String label;

  const _TableHeading(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.55,
          color: AppTheme.textMuted,
        ),
      );
}

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(13),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.8),
        ),
      );
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.8),
      );
}
