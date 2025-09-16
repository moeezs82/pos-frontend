import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  const ProductFormScreen({super.key, this.product});

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
  final _costPriceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _discountController = TextEditingController();

  bool _isActive = true;
  bool _taxInclusive = false;
  bool _loading = false;

  int? _selectedCategoryId;
  int? _selectedBrandId;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _brands = [];
  List<Map<String, dynamic>> _branches = [];
  final Map<int, TextEditingController> _branchStockControllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      final p = widget.product!;
      _skuController.text = p['sku'] ?? '';
      _barcodeController.text = p['barcode'] ?? '';
      _nameController.text = p['name'] ?? '';
      _descController.text = p['description'] ?? '';
      _priceController.text = p['price']?.toString() ?? '';
      _costPriceController.text = p['cost_price']?.toString() ?? '';
      _wholesalePriceController.text = p['wholesale_price']?.toString() ?? '';
      _taxRateController.text = p['tax_rate']?.toString() ?? '';
      _discountController.text = p['discount']?.toString() ?? '';
      // 🔑 FIX: cast int(0/1) to bool
      _isActive = p['is_active'] == 1 || p['is_active'] == true;
      _taxInclusive = p['tax_inclusive'] == 1 || p['tax_inclusive'] == true;
      _selectedCategoryId = p['category_id'];
      _selectedBrandId = p['brand_id'];
    }
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token!;
    try {
      final cats = await ApiService.getCategories(token);
      final brands = await ApiService.getBrands(token);
      final branches = await ApiService.getBranches(token);

      setState(() {
        _categories = cats;
        _brands = brands;
        _branches = branches;

        // preload stock if editing
        if (widget.product != null && widget.product!['stocks'] != null) {
          for (final b in branches) {
            final stock = (widget.product!['stocks'] as List).firstWhere(
              (s) => s['branch_id'] == b['id'],
              orElse: () => {"quantity": 0},
            );
            _branchStockControllers[b['id']] = TextEditingController(
              text: stock['quantity'].toString(),
            );
          }
        } else {
          for (final b in branches) {
            _branchStockControllers[b['id']] = TextEditingController(text: "0");
          }
        }
      });
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    }
  }

  String _generateBarcode() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return "BC$millis";
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
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final newBranch = await ApiService.createBranch(auth.token!, result);
      setState(() {
        _branches.add(newBranch);
        _branchStockControllers[newBranch['id']] = TextEditingController(
          text: "0",
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final branchStocks = _branches.map((b) {
      final qty =
          double.tryParse(_branchStockControllers[b['id']]?.text ?? "0") ?? 0.0;
      return {"branch_id": b['id'], "quantity": qty};
    }).toList();

    final payload = {
      "sku": _skuController.text,
      "barcode": _barcodeController.text,
      "name": _nameController.text,
      "description": _descController.text,
      "price": double.tryParse(_priceController.text) ?? 0.0,
      "cost_price": double.tryParse(_costPriceController.text) ?? 0.0,
      "wholesale_price": double.tryParse(_wholesalePriceController.text) ?? 0.0,
      "tax_rate": double.tryParse(_taxRateController.text) ?? 0.0,
      "tax_inclusive": _taxInclusive,
      "discount": double.tryParse(_discountController.text) ?? 0.0,
      "category_id": _selectedCategoryId,
      "brand_id": _selectedBrandId,
      "is_active": _isActive,
      "branch_stocks": branchStocks,
    };

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final token = auth.token!;
      if (widget.product == null) {
        await ApiService.createProduct(token, payload);
      } else {
        await ApiService.updateProduct(token, widget.product!['id'], payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
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
    final isEdit = widget.product != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? "Edit Product" : "Add Product")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _skuController,
                decoration: const InputDecoration(
                  labelText: "SKU",
                  border: OutlineInputBorder(),
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

              // Category dropdown + add
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue:
                          _selectedCategoryId != null &&
                              _categories.any(
                                (c) => c['id'] == _selectedCategoryId,
                              )
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
                        final auth = Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        );
                        final newCat = await ApiService.createCategory(
                          auth.token!,
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

              // Brand dropdown + add
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue:
                          _selectedBrandId != null &&
                              _brands.any((b) => b['id'] == _selectedBrandId)
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
                        final auth = Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        );
                        final newBrand = await ApiService.createBrand(
                          auth.token!,
                          name,
                        );
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Branch Stocks",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (!isEdit) // ➡️ Only show add button in create mode
                    IconButton(
                      icon: const Icon(Icons.add_business, color: Colors.green),
                      onPressed: _addBranch,
                    ),
                ],
              ),

              // 📍 Show different layouts based on create/edit
              if (isEdit)
                // 🔹 VIEW ONLY when editing
                Column(
                  children: (widget.product?['stocks'] as List<dynamic>? ?? [])
                      .map((stock) {
                        final branch =
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
                            title: Text(branch),
                            trailing: Text(
                              "Qty: $qty",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                )
              else
                // 🔹 EDITABLE when creating
                Column(
                  children: _branches.map((b) {
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
                        icon: Icon(isEdit ? Icons.save : Icons.add),
                        label: Text(
                          isEdit ? "Update Product" : "Create Product",
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
