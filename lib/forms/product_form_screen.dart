import 'dart:math';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/branch_provider.dart';

class ProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final int? vendorId;

  const ProductFormScreen({super.key, this.product, this.vendorId});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _discountController = TextEditingController();

  bool _isActive = true;
  bool _taxInclusive = false;
  bool _loading = false;

  int? _selectedCategoryId;
  int? _selectedBrandId;

  // Optional vendor
  Map<String, dynamic>? _selectedVendor;
  int? _selectedVendorId;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _brands = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _visibleBranches = [];

  final Map<int, TextEditingController> _branchStockControllers = {};

  late ProductService _productService;
  late CommonService _commonService;

  bool get _isEdit => widget.product != null;

  // ---- Branch helpers (use BranchProvider API you already have) ----
  bool _isAllBranchesSelected(BranchProvider bp) => bp.isAll;
  int? _activeBranchId(BranchProvider bp) => bp.selectedBranchId;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _productService = ProductService(token: token);
    _commonService = CommonService(token: token);

    if (widget.product != null) {
      final p = widget.product!;
      _skuController.text = p['sku'] ?? _generateSKU();
      _barcodeController.text = p['barcode'] ?? _generateBarcode();
      _nameController.text = p['name'] ?? '';
      _descController.text = p['description'] ?? '';
      _priceController.text = p['price']?.toString() ?? '';
      _costPriceController.text = p['cost_price']?.toString() ?? '';
      _wholesalePriceController.text = p['wholesale_price']?.toString() ?? '';
      _taxRateController.text = p['tax_rate']?.toString() ?? '';
      _discountController.text = p['discount']?.toString() ?? '';
      _isActive = p['is_active'] == 1 || p['is_active'] == true;
      _taxInclusive = p['tax_inclusive'] == 1 || p['tax_inclusive'] == true;
      _selectedCategoryId = p['category_id'];
      _selectedBrandId = p['brand_id'];

      // Prefill vendor from product if present
      _selectedVendorId = p['vendor_id'] is int ? p['vendor_id'] as int : null;
      if (p['vendor'] is Map<String, dynamic>) {
        _selectedVendor = {
          'id': p['vendor']['id'],
          'first_name': p['vendor']['first_name'],
        };
        _selectedVendorId = _selectedVendor?['id'] as int?;
      }
    }

    // If a vendorId is passed to the screen, lock it in:
    if (widget.vendorId != null) {
      _selectedVendorId = widget.vendorId;
      // Optional: if you have vendor details, set a name; fallback to id-only label
      _selectedVendor = {
        'id': widget.vendorId,
        'first_name': 'Vendor #${widget.vendorId}',
      };
    }

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final cats = await _commonService.getCategories();
      final brands = await _commonService.getBrands();
      final branches = await _commonService.getBranches();

      final bp = Provider.of<BranchProvider>(context, listen: false);
      final showAll = _isAllBranchesSelected(bp);
      final activeId = _activeBranchId(bp);

      final visible = showAll
          ? branches
          : branches.where((b) => b['id'] == activeId).toList();

      setState(() {
        _categories = cats;
        _brands = brands;
        _branches = branches;
        _visibleBranches = visible;

        // controllers for visible branches only
        if (widget.product != null && widget.product!['stocks'] != null) {
          for (final b in _visibleBranches) {
            final stock = (widget.product!['stocks'] as List).firstWhere(
              (s) => s['branch_id'] == b['id'],
              orElse: () => {"quantity": 0},
            );
            _branchStockControllers[b['id']] = TextEditingController(
              text: (stock['quantity'] ?? 0).toString(),
            );
          }
        } else {
          for (final b in _visibleBranches) {
            _branchStockControllers[b['id']] = TextEditingController(text: "0");
          }
        }
      });
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    }
  }

  String _generateSKU() {
    final ts = DateTime.now().millisecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final r = Random()
        .nextInt(36 * 36 * 36)
        .toRadixString(36)
        .padLeft(3, '0')
        .toUpperCase();
    return "SKU-$ts$r";
  }

  String _generateBarcode() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return "$millis";
  }

  Future<String?> _showAddDialog(String type) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add $type"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: "$type Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _addBranch() async {
    // Only meaningful when "All Branches" is selected (button is hidden otherwise)
    final nameController = TextEditingController();
    final locController = TextEditingController();
    final phoneController = TextEditingController();
    bool isActive = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Branch"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: locController,
              decoration: const InputDecoration(labelText: "Location"),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: "Phone"),
            ),
            SwitchListTile(
              title: const Text("Active"),
              value: isActive,
              onChanged: (v) => isActive = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              "name": nameController.text,
              "location": locController.text,
              "phone": phoneController.text,
              "is_active": isActive,
            }),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result != null) {
      final newBranch = await _commonService.createBranch(result);
      setState(() {
        _branches.add(newBranch);
        final bp = Provider.of<BranchProvider>(context, listen: false);
        if (_isAllBranchesSelected(bp)) {
          _visibleBranches.add(newBranch);
          _branchStockControllers[newBranch['id']] = TextEditingController(
            text: "0",
          );
        }
      });
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
    if (picked != null) {
      setState(() {
        _selectedVendor = picked;
        _selectedVendorId = picked['id'] as int?;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final branchStocks = _visibleBranches.map((b) {
      final qty =
          double.tryParse(_branchStockControllers[b['id']]?.text ?? "0") ?? 0.0;
      return {"branch_id": b['id'], "quantity": qty};
    }).toList();

    final payload = {
      "sku": _skuController.text,
      "barcode": _barcodeController.text,
      "name": _nameController.text,
      "description": _descController.text,
      "stock": double.tryParse(_stockController.text)??0,
      "price": double.tryParse(_priceController.text) ?? 0.0,
      "cost_price": double.tryParse(_costPriceController.text) ?? 0.0,
      "wholesale_price": double.tryParse(_wholesalePriceController.text) ?? 0.0,
      "tax_rate": double.tryParse(_taxRateController.text) ?? 0.0,
      "tax_inclusive": _taxInclusive,
      "discount": double.tryParse(_discountController.text) ?? 0.0,
      "category_id": _selectedCategoryId,
      "brand_id": _selectedBrandId,
      "vendor_id": _selectedVendorId, // optional
      "is_active": _isActive,
      "branch_stocks": branchStocks,
    };

    try {
      if (widget.product == null) {
        final product = await _productService.createProduct(payload);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Product created successfully")),
        );
        Navigator.pop(context, product);
      } else {
        await _productService.updateProduct(widget.product!['id'], payload);
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bp = Provider.of<BranchProvider>(context); // listen for UI toggles
    final showAll = _isAllBranchesSelected(bp);
    final activeId = _activeBranchId(bp);

    final fixedVendorId = widget.vendorId; // lock if provided to screen
    final productVendorId =
        widget.product?['vendor_id']; // vendor from existing product
    final showReadOnly =
        _isEdit || fixedVendorId != null; // read-only on edit OR when locked
    final effectiveVendorId =
        fixedVendorId ?? productVendorId ?? _selectedVendorId;
    final effectiveVendorName =
        _selectedVendor?['first_name'] ??
        widget.product?['vendor']?['first_name'] ??
        (effectiveVendorId != null
            ? 'Vendor #$effectiveVendorId'
            : 'None selected');

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? "Edit Product" : "Add Product")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _skuController,
                decoration: InputDecoration(
                  labelText: "SKU",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code),
                    onPressed: () =>
                        setState(() => _skuController.text = _generateSKU()),
                  ),
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: "Barcode",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code),
                    onPressed: () => setState(
                      () => _barcodeController.text = _generateBarcode(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Name",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Description",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Category
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value:
                          (_selectedCategoryId != null &&
                              _categories.any(
                                (c) => c['id'] == _selectedCategoryId,
                              ))
                          ? _selectedCategoryId
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Category",
                        border: OutlineInputBorder(),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(c['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCategoryId = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () async {
                      final name = await _showAddDialog("Category");
                      if (name != null && name.isNotEmpty) {
                        final newCat = await _commonService.createCategory(
                          name,
                        );
                        setState(() {
                          _categories.add(newCat);
                          _selectedCategoryId = newCat['id'];
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Brand
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value:
                          (_selectedBrandId != null &&
                              _brands.any((b) => b['id'] == _selectedBrandId))
                          ? _selectedBrandId
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Brand",
                        border: OutlineInputBorder(),
                      ),
                      items: _brands
                          .map(
                            (b) => DropdownMenuItem<int>(
                              value: b['id'],
                              child: Text(b['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedBrandId = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () async {
                      final name = await _showAddDialog("Brand");
                      if (name != null && name.isNotEmpty) {
                        final newBrand = await _commonService.createBrand(name);
                        setState(() {
                          _brands.add(newBrand);
                          _selectedBrandId = newBrand['id'];
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vendor (optional)
              // --- Vendor UI ---
              if (showReadOnly) ...[
                // Read-only tile, no picker, no clear
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text("Vendor"),
                  subtitle: Text("Vendor Selected"),
                  trailing: const Icon(Icons.lock),
                ),
              ] else ...[
                // Picker visible only on create AND when no fixed vendorId is passed
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text("Vendor (optional)"),
                  subtitle: Text(
                    _selectedVendor?['first_name']?.toString() ?? 'None selected',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedVendorId != null)
                        IconButton(
                          tooltip: "Clear",
                          onPressed: () => setState(() {
                            _selectedVendor = null;
                            _selectedVendorId = null;
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.store),
                        label: Text(
                          _selectedVendorId == null ? "Pick" : "Change",
                        ),
                        onPressed: _pickVendor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Opening Stock",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Price",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Cost Price",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wholesalePriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Wholesale Price",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Tax Rate (%)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text("Tax Inclusive"),
                value: _taxInclusive,
                onChanged: (v) => setState(() => _taxInclusive = v),
              ),
              TextFormField(
                controller: _discountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Discount (%)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Branch Stocks
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Branch Stocks",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (!_isEdit && showAll)
                    IconButton(
                      icon: const Icon(Icons.add_business, color: Colors.green),
                      onPressed: _addBranch,
                    ),
                ],
              ),

              if (_isEdit)
                Column(
                  children: (() {
                    final stocks =
                        (widget.product?['stocks'] as List<dynamic>? ?? []);
                    final filtered = showAll
                        ? stocks
                        : stocks
                              .where((s) => s['branch_id'] == activeId)
                              .toList();
                    return filtered.map((stock) {
                      final branchName =
                          stock['branch']?['name'] ??
                          "Branch ${stock['branch_id']}";
                      final qty = stock['quantity'] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          title: Text(branchName),
                          trailing: Text(
                            "Qty: $qty",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }).toList();
                  })(),
                )
              else
                Column(
                  children: _visibleBranches.map((b) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextFormField(
                        controller: _branchStockControllers[b['id']],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: "${b['name']} Stock",
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 24),

              SwitchListTile(
                title: const Text("Active"),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        icon: Icon(_isEdit ? Icons.save : Icons.add),
                        label: Text(
                          _isEdit ? "Update Product" : "Create Product",
                        ),
                        onPressed: _save,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
