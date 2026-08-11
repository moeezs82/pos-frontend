import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
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
  final _taxRateCtrl = TextEditingController(text: '0');

  // Defaults are create-screen helpers only. They prefill a newly-added
  // variant and are never stored independently from the child products.
  final _defaultRetailCtrl = TextEditingController();
  final _defaultWholesaleCtrl = TextEditingController();
  final _defaultCostCtrl = TextEditingController();
  final _defaultReorderCtrl = TextEditingController(text: '0');

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
  late CommonService _commonService;
  late UnitService _unitService;

  bool get _isEdit => widget.group != null;

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
    _commonService = CommonService(token: token);
    _unitService = UnitService(token: token);

    if (widget.group != null) {
      final g = widget.group!;
      _nameCtrl.text = (g['name'] ?? '').toString();
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
    _loadRefData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taxRateCtrl.dispose();
    _defaultRetailCtrl.dispose();
    _defaultWholesaleCtrl.dispose();
    _defaultCostCtrl.dispose();
    _defaultReorderCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() => _loading = true);
    try {
      final cats = await _commonService.getCategories();
      final brands = await _commonService.getBrands();
      final units = await _unitService.list();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _brands = brands;
        _units = units
            .where((u) => u.isActive || u.id == _selectedUnitId)
            .toList();
        if (_selectedUnitId == null && !_isEdit && _units.isNotEmpty) {
          final piece =
              _units.where((u) => u.name.toLowerCase() == 'piece').toList();
          _selectedUnitId = piece.isNotEmpty ? piece.first.id : _units.first.id;
        }
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
        retailPrice: _parseDouble(_defaultRetailCtrl.text),
        wholesalePrice: _parseDouble(_defaultWholesaleCtrl.text),
        costPrice: _parseDouble(_defaultCostCtrl.text),
        reorderLevel: _parseInt(_defaultReorderCtrl.text),
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
        selectedUnitLabel: _selectedUnit?.label,
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
          isActive: _isActive,
          categoryId: _selectedCategoryId,
          brandId: _selectedBrandId,
          unitId: _selectedUnitId,
          vendorId: _selectedVendorId,
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
              sku: v.sku,
              barcode: v.barcode,
              price: v.retailPrice,
              costPrice: v.costPrice,
              wholesalePrice: v.wholesalePrice,
              stock: v.openingStock,
              reorderLevel: v.reorderLevel,
              taxRate: taxRate,
              taxInclusive: _taxInclusive,
              discountType: _discountType,
            ),
          )
          .toList();

      await _groupService.createVariableProduct(
        name: _nameCtrl.text.trim(),
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

      if (mounted) {
        AppFeedback.success(
          context,
          'Created ${_nameCtrl.text.trim()} with ${variants.length} variant${variants.length == 1 ? '' : 's'}.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                width: width,
                child: _dropdownField(
                  label: 'Category',
                  icon: Icons.category_outlined,
                  value: _validMapSelection(_categories, _selectedCategoryId),
                  items: _categories,
                  onChanged: (value) =>
                      setState(() => _selectedCategoryId = value),
                ),
              ),
              SizedBox(
                width: width,
                child: _dropdownField(
                  label: 'Brand',
                  icon: Icons.branding_watermark_outlined,
                  value: _validMapSelection(_brands, _selectedBrandId),
                  items: _brands,
                  onChanged: (value) =>
                      setState(() => _selectedBrandId = value),
                ),
              ),
              SizedBox(
                width: width,
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
                          u.allowDecimal ? '${u.name} · decimals allowed' : u.name,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedUnitId = value),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
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
                child:
                    _numberField(_defaultWholesaleCtrl, 'Default Wholesale'),
              ),
              SizedBox(
                width: width,
                child: _numberField(_defaultCostCtrl, 'Default Cost'),
              ),
              SizedBox(
                width: width,
                child:
                    _numberField(_defaultReorderCtrl, 'Default Reorder Level'),
              ),
            ],
          );
        },
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
            DataColumn(label: _TableHeading('SIZE')),
            DataColumn(label: _TableHeading('COLOR')),
            DataColumn(label: _TableHeading('SKU')),
            DataColumn(label: _TableHeading('BARCODE')),
            DataColumn(label: _TableHeading('RETAIL'), numeric: true),
            DataColumn(label: _TableHeading('WHOLESALE'), numeric: true),
            DataColumn(label: _TableHeading('COST'), numeric: true),
            DataColumn(label: _TableHeading('OPENING'), numeric: true),
            DataColumn(label: _TableHeading('REORDER'), numeric: true),
            DataColumn(label: _TableHeading('ACTIONS')),
          ],
          rows: List<DataRow>.generate(_variants.length, (index) {
            final v = _variants[index];
            return DataRow(
              cells: [
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
  final String? selectedUnitLabel;
  final ProductGroupService groupService;
  final _VariantDraftValidator validateDraft;

  const _VariantEditorDialog({
    required this.seed,
    required this.editingIndex,
    required this.allowAddAnother,
    required this.groupName,
    required this.selectedUnitLabel,
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
  late final TextEditingController _skuCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _retailCtrl;
  late final TextEditingController _wholesaleCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _reorderCtrl;

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
  }

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _retailCtrl.dispose();
    _wholesaleCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _reorderCtrl.dispose();
    super.dispose();
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
      sku: _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      retailPrice: _parseDouble(_retailCtrl.text),
      wholesalePrice: _parseDouble(_wholesaleCtrl.text),
      costPrice: _parseDouble(_costCtrl.text),
      openingStock: _parseDouble(_stockCtrl.text),
      reorderLevel: _parseInt(_reorderCtrl.text),
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
                      const SizedBox(height: 22),
                      _sectionTitle('Opening Inventory'),
                      const SizedBox(height: 10),
                      _field(
                        _stockCtrl,
                        'Opening Stock',
                        numeric: true,
                        hint: widget.selectedUnitLabel == null
                            ? '0'
                            : 'Quantity in ${widget.selectedUnitLabel}',
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
  String sku;
  String barcode;
  double retailPrice;
  double wholesalePrice;
  double costPrice;
  double openingStock;
  int reorderLevel;

  _VariantDraft({
    required this.id,
    this.size = '',
    this.color = '',
    this.sku = '',
    this.barcode = '',
    this.retailPrice = 0,
    this.wholesalePrice = 0,
    this.costPrice = 0,
    this.openingStock = 0,
    this.reorderLevel = 0,
  });

  _VariantDraft copy() => _VariantDraft(
        id: id,
        size: size,
        color: color,
        sku: sku,
        barcode: barcode,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
        costPrice: costPrice,
        openingStock: openingStock,
        reorderLevel: reorderLevel,
      );

  _VariantDraft copyForNext({required int id}) => _VariantDraft(
        id: id,
        retailPrice: retailPrice,
        wholesalePrice: wholesalePrice,
        costPrice: costPrice,
        reorderLevel: reorderLevel,
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
