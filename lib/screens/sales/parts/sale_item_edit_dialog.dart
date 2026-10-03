import 'dart:math' as math;
import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:flutter/material.dart';

class SaleItemEditDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isEditing;
  final String? customerType;

  const SaleItemEditDialog({
    super.key,
    required this.item,
    required this.isEditing,
    this.customerType,
  });

  @override
  State<SaleItemEditDialog> createState() => _SaleItemEditDialogState();
}

class _SaleItemEditDialogState extends State<SaleItemEditDialog> {
  late final QuantityRule _rule;
  late final ProductPackaging? _existingSnapshot;
  late final int? _existingPackageId;
  late final bool _isExistingPostedPackage;
  late final List<ProductPackaging> _active;
  late final Map<String, ProductPackaging?> _options;
  late String _selectedKey;

  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  late final TextEditingController _discountController;
  late String _discountType;

  late final double _costPrice;
  late final double _wholesalePrice;
  bool _showHidden = false;
  String? _qtyError;
  String? _priceError;
  String? _discountError;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _rule = QuantityRule.fromProduct(item);
    _existingSnapshot = _snapshotPackaging(item);
    _existingPackageId = _metaInt(item['packaging_id']);
    _isExistingPostedPackage = widget.isEditing &&
        item['sale_item_id'] != null &&
        _existingPackageId != null;

    _active = _activePackagings(item);
    _options = <String, ProductPackaging?>{'base': null};
    if (_existingSnapshot != null) {
      _options['snapshot'] = _existingSnapshot;
    }
    for (final package in _active) {
      if (_existingPackageId != null && package.id == _existingPackageId) {
        continue;
      }
      _options['package:${package.id}'] = package;
    }

    _selectedKey = _existingSnapshot != null ? 'snapshot' : 'base';
    final initialQty = _existingSnapshot == null
        ? _metaNum(item['quantity'])
        : (_metaNullableNum(item['packaging_quantity']) ??
            (_metaNum(item['quantity']) / _existingSnapshot.baseQuantity));
    final initialPrice = _existingSnapshot == null
        ? _metaNum(item['price'])
        : (_metaNullableNum(item['packaging_unit_price']) ??
            (_metaNum(item['price']) * _existingSnapshot.baseQuantity));

    _qtyController = TextEditingController(text: _compactNumber(initialQty));
    _priceController = TextEditingController(text: _compactNumber(initialPrice));

    _discountType = (item['discount_type'] ?? 'percentage').toString();
    final initialDiscount =
        _discountType == 'fixed' && _existingSnapshot != null
            ? (_metaNullableNum(item['packaging_discount_snapshot']) ??
                _metaNum(item['discount_pct']) * _existingSnapshot.baseQuantity)
            : _metaNum(item['discount_pct']);
    _discountController =
        TextEditingController(text: _compactNumber(initialDiscount));

    _costPrice = _metaNum(item['cost_price']);
    _wholesalePrice = _metaNum(item['wholesale_price']);
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  static int? _metaInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString().trim());
  }

  static double _metaNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim()) ?? 0.0;
  }

  static double? _metaNullableNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static double _roundTo(double value, int scale) {
    final factor = math.pow(10, scale).toDouble();
    return (value * factor).roundToDouble() / factor;
  }

  static String _compactNumber(num value, {int scale = 4}) {
    final doubleValue = value.toDouble();
    final rounded = _roundTo(doubleValue, scale);
    if ((rounded - rounded.roundToDouble()).abs() < 0.000001) {
      return rounded.round().toString();
    }
    var text = rounded.toStringAsFixed(scale);
    while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static ProductPackaging? _snapshotPackaging(Map<String, dynamic> item) {
    final id = _metaInt(item['packaging_id']);
    final factor = _metaNullableNum(item['packaging_factor_snapshot']);
    if (id == null || factor == null || factor <= 0) return null;
    final productId = _metaInt(item['product_id']) ?? 0;
    return ProductPackaging(
      id: id,
      productId: productId,
      name: (item['packaging_name_snapshot'] ?? 'Pack').toString(),
      shortName: item['packaging_short_name_snapshot']?.toString(),
      baseQuantity: factor,
      sellingPrice: _metaNullableNum(item['packaging_unit_price']),
      costPrice: _metaNullableNum(item['cost_price']),
      wholesalePrice: _metaNullableNum(item['wholesale_price']),
      isActive: true,
      isDefault: false,
    );
  }

  static List<ProductPackaging> _activePackagings(Map<String, dynamic> item) {
    final raw = item['packagings'] ?? item['product_packagings'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ProductPackaging.fromJson(Map<String, dynamic>.from(m)))
        .where((p) => p.isActive)
        .toList(growable: false);
  }

  static String _packagingDisplayLabel(
    ProductPackaging package,
    QuantityRule rule,
  ) {
    final qty = _compactNumber(package.baseQuantity);
    final unit = rule.unitName.trim().isEmpty ? 'units' : rule.unitName.trim();
    final name = (package.shortName ?? package.name).trim();
    return '$name ($qty $unit)';
  }

  void _selectSellingUnit(String? nextKey) {
    if (nextKey == null || nextKey == _selectedKey) return;
    final currentPackaging = _options[_selectedKey];
    final enteredQty = double.tryParse(_qtyController.text.trim()) ?? 0;
    final currentBaseQty = currentPackaging == null
        ? enteredQty
        : enteredQty * currentPackaging.baseQuantity;
    final next = _options[nextKey];

    setState(() {
      _selectedKey = nextKey;
      _qtyError = null;
      _priceError = null;
      _discountError = null;

      if (_isExistingPostedPackage) {
        _qtyController.text = _compactNumber(
          next == null
              ? _roundTo(currentBaseQty, 3)
              : _roundTo(currentBaseQty / next.baseQuantity, 4),
        );
        if (_discountType == 'fixed') {
          final enteredDiscount =
              double.tryParse(_discountController.text.trim()) ?? 0;
          final baseDiscount = currentPackaging == null
              ? enteredDiscount
              : enteredDiscount / currentPackaging.baseQuantity;
          _discountController.text = _compactNumber(
            next == null ? baseDiscount : baseDiscount * next.baseQuantity,
          );
        }
      } else {
        _qtyController.text = _compactNumber(enteredQty);
      }

      if (next == null) {
        _priceController.text = _compactNumber(
          SalePricing.effectiveProductPrice(
            widget.item,
            customerType: widget.customerType,
          ),
        );
      } else {
        _priceController.text = _compactNumber(
          SalePricing.effectivePackagingPrice(
            widget.item,
            next,
            customerType: widget.customerType,
          ),
        );
      }
    });
  }

  void _onSave() {
    final qty = double.tryParse(_qtyController.text.trim());
    final price = double.tryParse(_priceController.text.trim());
    final discount = double.tryParse(_discountController.text.trim());
    final package = _options[_selectedKey];
    final unitLabel = _rule.unitName.trim().isEmpty ? 'Base Unit' : _rule.unitName.trim();

    if (qty == null) {
      setState(() => _qtyError = 'Enter a valid quantity.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _priceError = price == null
          ? 'Enter a valid sale price.'
          : 'Sale price cannot be negative.');
      return;
    }
    if (discount == null ||
        discount < 0 ||
        (_discountType == 'percentage' && discount > 100) ||
        (_discountType == 'fixed' && discount > price + .0004)) {
      setState(() {
        if (discount == null) {
          _discountError = 'Enter a valid discount.';
        } else if (discount < 0) {
          _discountError = 'Discount cannot be negative.';
        } else if (_discountType == 'percentage') {
          _discountError = 'Percentage discount cannot exceed 100%.';
        } else {
          _discountError = 'Fixed discount cannot exceed the sale price.';
        }
      });
      return;
    }

    final row = Map<String, dynamic>.from(widget.item);

    if (package == null) {
      final error = _rule.validateText(_qtyController.text);
      if (error != null) {
        setState(() => _qtyError = error);
        return;
      }
      row['quantity'] = qty;
      row['price'] = price;
      row['discount_type'] = _discountType;
      row['discount_pct'] = discount;
      row.remove('packaging_id');
      row.remove('packaging_name_snapshot');
      row.remove('packaging_short_name_snapshot');
      row.remove('packaging_factor_snapshot');
      row.remove('packaging_quantity');
      row.remove('packaging_unit_price');
      row.remove('packaging_discount_snapshot');
      Navigator.pop(context, row);
      return;
    }

    if (qty <= 0 || !QuantityRule.isWhole(qty)) {
      setState(() => _qtyError = qty <= 0
          ? 'Package quantity must be greater than zero.'
          : 'Package quantity must be a whole number. Use $unitLabel for loose quantity.');
      return;
    }
    final baseQty = _roundTo(qty * package.baseQuantity, 3);
    if (!_rule.allows(baseQty)) {
      setState(() => _qtyError = _rule.message);
      return;
    }

    row['discount_type'] = _discountType;
    final packageFixedDiscount = _discountType == 'fixed' ? discount : null;
    row['quantity'] = baseQty;
    row['price'] = _roundTo(price / package.baseQuantity, 4);
    if (_discountType == 'fixed') {
      row['discount_pct'] = _roundTo(
        (packageFixedDiscount ?? 0) / package.baseQuantity,
        4,
      );
      row['packaging_discount_snapshot'] =
          _roundTo(packageFixedDiscount ?? 0, 4);
    } else {
      row.remove('packaging_discount_snapshot');
    }
    row['packaging_id'] = package.id;
    row['packaging_name_snapshot'] = package.name;
    if ((package.shortName ?? '').trim().isEmpty) {
      row.remove('packaging_short_name_snapshot');
    } else {
      row['packaging_short_name_snapshot'] = package.shortName!.trim();
    }
    row['packaging_factor_snapshot'] = package.baseQuantity;
    row['packaging_quantity'] = qty;
    row['packaging_unit_price'] = price;

    Navigator.pop(context, row);
  }

  @override
  Widget build(BuildContext context) {
    final selectedPackaging = _options[_selectedKey];
    final packageMode = selectedPackaging != null;
    final unitLabel = _rule.unitName.trim().isEmpty ? 'Base Unit' : _rule.unitName.trim();
    final dialogContentWidth = (MediaQuery.sizeOf(context).width - 96)
        .clamp(320.0, 560.0)
        .toDouble();

    return AlertDialog(
      title: Text("Edit ${widget.item['name']}"),
      content: SizedBox(
        width: dialogContentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Selling Unit',
                  helperText: 'Select the selling unit for this line.',
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _options.entries.map((entry) {
                    final package = entry.value;
                    final historical =
                        entry.key == 'snapshot' && _isExistingPostedPackage;
                    final label = package == null
                        ? unitLabel
                        : '${_packagingDisplayLabel(package, _rule)}${historical ? ' • invoice snapshot' : ''}';
                    return ChoiceChip(
                      label: Text(label),
                      selected: _selectedKey == entry.key,
                      onSelected: (selected) {
                        if (!selected) return;
                        _selectSellingUnit(entry.key);
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
              if (_isExistingPostedPackage) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'This posted line keeps its original package conversion. If the current package changed, add it as a new line instead.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _qtyController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: !packageMode && _rule.allowDecimal,
                  signed: !packageMode,
                ),
                onChanged: (v) {
                  setState(() {
                    final parsed = double.tryParse(v.trim());
                    if (v.trim().isEmpty) {
                      _qtyError = null;
                    } else if (parsed == null) {
                      _qtyError = 'Enter a valid quantity.';
                    } else if (packageMode) {
                      _qtyError = parsed <= 0
                          ? 'Package quantity must be greater than zero.'
                          : (!QuantityRule.isWhole(parsed)
                              ? 'Package quantity must be a whole number. Use $unitLabel for loose quantity.'
                              : (_rule.allows(parsed * selectedPackaging!.baseQuantity)
                                  ? null
                                  : _rule.message));
                    } else {
                      _qtyError = _rule.validateText(v);
                    }
                  });
                },
                decoration: InputDecoration(
                  labelText: packageMode
                      ? '${selectedPackaging!.shortName ?? selectedPackaging.name} Quantity'
                      : 'Quantity',
                  helperText: packageMode
                      ? 'Whole packages only • ${_packagingDisplayLabel(selectedPackaging!, _rule)}'
                      : (_rule.allowDecimal
                          ? null
                          : 'Whole numbers only${_rule.unitName.isEmpty ? '' : ' (${_rule.unitName})'}'),
                  errorText: _qtyError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => setState(() {
                  final parsed = double.tryParse(v.trim());
                  _priceError = v.trim().isEmpty || parsed == null
                      ? 'Enter a valid sale price.'
                      : (parsed < 0 ? 'Sale price cannot be negative.' : null);
                }),
                decoration: InputDecoration(
                  labelText: packageMode
                      ? 'Price per ${selectedPackaging!.shortName ?? selectedPackaging.name}'
                      : 'Sale Price per $unitLabel',
                  errorText: _priceError,
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  Widget buildDiscountField() => TextField(
                        controller: _discountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (v) => setState(() {
                          final parsed = double.tryParse(v.trim());
                          final currentPrice =
                              double.tryParse(_priceController.text.trim()) ?? 0;
                          if (v.trim().isEmpty || parsed == null) {
                            _discountError = 'Enter a valid discount.';
                          } else if (parsed < 0) {
                            _discountError = 'Discount cannot be negative.';
                          } else if (_discountType == 'percentage' &&
                              parsed > 100) {
                            _discountError =
                                'Percentage discount cannot exceed 100%.';
                          } else if (_discountType == 'fixed' &&
                              parsed > currentPrice + 0.0004) {
                            _discountError =
                                'Fixed discount cannot exceed the sale price.';
                          } else {
                            _discountError = null;
                          }
                        }),
                        decoration: InputDecoration(
                          labelText: _discountType == 'fixed'
                              ? (packageMode
                                  ? 'Discount per ${selectedPackaging!.shortName ?? selectedPackaging.name}'
                                  : 'Discount per $unitLabel')
                              : 'Discount %',
                          errorText: _discountError,
                        ),
                      );

                  Widget buildDiscountTypeField() => InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Discount Type',
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const <MapEntry<String, String>>[
                            MapEntry('percentage', 'Percentage'),
                            MapEntry('fixed', 'Fixed'),
                          ].map((option) {
                            final value = option.key;
                            return ChoiceChip(
                              label: Text(option.value),
                              selected: _discountType == value,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() {
                                  _discountType = value;
                                  final parsed = double.tryParse(
                                        _discountController.text.trim(),
                                      ) ??
                                      0;
                                  final currentPrice = double.tryParse(
                                        _priceController.text.trim(),
                                      ) ??
                                      0;
                                  if ((value == 'percentage' && parsed > 100) ||
                                      (value == 'fixed' &&
                                          parsed > currentPrice + 0.0004)) {
                                    _discountController.text = '0';
                                  }
                                  _discountError = null;
                                });
                              },
                            );
                          }).toList(growable: false),
                        ),
                      );

                  if (dialogContentWidth < 430) {
                    return Column(
                      children: [
                        buildDiscountField(),
                        const SizedBox(height: 12),
                        buildDiscountTypeField(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: buildDiscountField()),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: buildDiscountTypeField()),
                    ],
                  );
                },
              ),
              if (packageMode) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Stock / COGS equivalent: ${_compactNumber(_roundTo((double.tryParse(_qtyController.text.trim()) ?? 0) * selectedPackaging!.baseQuantity, 3))} $unitLabel',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                icon: Icon(
                  _showHidden ? Icons.visibility_off : Icons.visibility,
                ),
                label: Text(
                  _showHidden ? 'Hide Cost/Wholesale' : 'Show Cost/Wholesale',
                ),
                onPressed: () => setState(() => _showHidden = !_showHidden),
              ),
              if (_showHidden) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Base Cost: ${AppCurrency.format(_costPrice)} / $unitLabel',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(
                        'Base Wholesale: ${AppCurrency.format(_wholesalePrice)} / $unitLabel',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
