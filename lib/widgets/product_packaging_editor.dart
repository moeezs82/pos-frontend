import 'package:flutter/material.dart';
import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/models/product_unit.dart';

/// Catalog editor for product-specific package conversions.
///
/// Important: this edits metadata only. Inventory remains in the product's
/// canonical base unit and transaction screens will consume these definitions
/// in a later phase.
class ProductPackagingEditor extends StatelessWidget {
  final List<ProductPackaging> packagings;
  final ProductUnit? baseUnit;
  final double baseRetailPrice;
  final double baseWholesalePrice;
  final bool enabled;
  final ValueChanged<List<ProductPackaging>> onChanged;
  final Future<ProductUnit?> Function()? onRequestBaseUnit;
  final String title;

  const ProductPackagingEditor({
    super.key,
    required this.packagings,
    required this.baseUnit,
    required this.baseRetailPrice,
    required this.baseWholesalePrice,
    required this.onChanged,
    this.onRequestBaseUnit,
    this.enabled = true,
    this.title = 'Packaging',
  });

  @override
  Widget build(BuildContext context) {
    final unitLabel = _unitLabel(baseUnit);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: enabled ? () => _openEditor(context) : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Packaging'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            baseUnit == null
                ? 'Select a base unit first. Stock will always remain in the base unit.'
                : 'Base unit: $unitLabel. Every package converts directly to $unitLabel; inventory remains in $unitLabel.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (packagings.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'No packaging configured. The product continues to use only its base unit.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ...List.generate(packagings.length, (index) {
              final item = packagings[index];
              return Padding(
                padding: EdgeInsets.only(
                    bottom: index == packagings.length - 1 ? 0 : 8),
                child: _PackagingTile(
                  item: item,
                  unitLabel: unitLabel,
                  baseRetailPrice: baseRetailPrice,
                  baseWholesalePrice: baseWholesalePrice,
                  enabled: enabled,
                  onEdit: () => _openEditor(context, index: index),
                  onToggle: () => _toggle(index),
                  onRemoveNew: item.id == null ? () => _removeNew(index) : null,
                ),
              );
            }),
        ],
      ),
    );
  }

  void _toggle(int index) {
    final next = packagings.map((e) => e.copy()).toList();
    next[index] = next[index].copyWith(isActive: !next[index].isActive);
    onChanged(next);
  }

  void _removeNew(int index) {
    final next = packagings.map((e) => e.copy()).toList()..removeAt(index);
    onChanged(next);
  }

  Future<void> _openEditor(BuildContext context, {int? index}) async {
    var resolvedBaseUnit = baseUnit;

    // A legacy/simple product can legitimately reach edit mode without a
    // base unit selected. Packaging cannot be defined safely until that unit
    // is explicit, so let the parent resolve it and then continue straight
    // into the packaging dialog instead of making the Add Packaging button
    // appear broken. Nothing is silently assumed here.
    if (resolvedBaseUnit == null && onRequestBaseUnit != null) {
      resolvedBaseUnit = await onRequestBaseUnit!();
      if (!context.mounted) return;
    }

    if (resolvedBaseUnit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a base unit before adding packaging.')),
      );
      return;
    }

    final result = await showDialog<ProductPackaging>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PackagingDialog(
        initial: index == null ? null : packagings[index],
        baseUnit: resolvedBaseUnit!,
        baseRetailPrice: baseRetailPrice,
        baseWholesalePrice: baseWholesalePrice,
        existingNames: {
          for (var i = 0; i < packagings.length; i++)
            if (i != index) packagings[i].name.trim().toLowerCase(),
        },
      ),
    );
    if (result == null) return;
    final next = packagings.map((e) => e.copy()).toList();
    if (index == null) {
      next.add(result.copyWith(sortOrder: next.length));
    } else {
      next[index] = result.copyWith(sortOrder: index);
    }
    onChanged(next);
  }

  static String _unitLabel(ProductUnit? unit) {
    if (unit == null) return 'base units';
    final label = unit.label.trim();
    return label.isEmpty ? unit.name : label;
  }
}

class _PackagingTile extends StatelessWidget {
  final ProductPackaging item;
  final String unitLabel;
  final double baseRetailPrice;
  final double baseWholesalePrice;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onRemoveNew;

  const _PackagingTile({
    required this.item,
    required this.unitLabel,
    required this.baseRetailPrice,
    required this.baseWholesalePrice,
    required this.enabled,
    required this.onEdit,
    required this.onToggle,
    this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    final retailAuto = item.retailPrice == null;
    final wholesaleAuto = item.wholesalePrice == null;
    final retail = item.effectiveRetailPrice(baseRetailPrice);
    final wholesale = item.effectiveWholesalePrice(baseWholesalePrice);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
        color: item.isActive
            ? null
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .35),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (item.shortName?.isNotEmpty == true)
                      Text('(${item.shortName})',
                          style: Theme.of(context).textTheme.bodySmall),
                    _StatusChip(active: item.isActive),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '1 ${item.name} = ${_qty(item.baseQuantity)} $unitLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 18,
                  runSpacing: 4,
                  children: [
                    Text(
                        'Retail: ${retailAuto ? 'Auto ' : ''}${_money(retail)}'),
                    Text(
                        'Wholesale: ${wholesaleAuto ? 'Auto ' : ''}${_money(wholesale)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            enabled: enabled,
            tooltip: 'Packaging actions',
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'toggle') onToggle();
              if (value == 'remove' && onRemoveNew != null) onRemoveNew!();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(item.isActive ? 'Deactivate' : 'Reactivate'),
              ),
              if (onRemoveNew != null)
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;
  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: active
            ? Colors.green.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? Colors.green.shade700 : null,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _PackagingDialog extends StatefulWidget {
  final ProductPackaging? initial;
  final ProductUnit baseUnit;
  final double baseRetailPrice;
  final double baseWholesalePrice;
  final Set<String> existingNames;

  const _PackagingDialog({
    this.initial,
    required this.baseUnit,
    required this.baseRetailPrice,
    required this.baseWholesalePrice,
    required this.existingNames,
  });

  @override
  State<_PackagingDialog> createState() => _PackagingDialogState();
}

class _PackagingDialogState extends State<_PackagingDialog> {
  static const _presets = <String>[
    'Box',
    'Carton',
    'Pack',
    'Case',
    'Tray',
    'Bundle',
    'Dozen',
    'Pallet',
    'Sack',
    'Roll',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _shortName;
  late final TextEditingController _baseQuantity;
  late final TextEditingController _retail;
  late final TextEditingController _wholesale;
  late bool _overrideRetail;
  late bool _overrideWholesale;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _shortName = TextEditingController(text: p?.shortName ?? '');
    _baseQuantity = TextEditingController(
        text: p == null ? '' : _qty(p.baseQuantity));
    _retail = TextEditingController(
        text: p?.retailPrice == null ? '' : _money(p!.retailPrice!));
    _wholesale = TextEditingController(
        text: p?.wholesalePrice == null ? '' : _money(p!.wholesalePrice!));
    _overrideRetail = p?.retailPrice != null;
    _overrideWholesale = p?.wholesalePrice != null;
    _active = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    _baseQuantity.dispose();
    _retail.dispose();
    _wholesale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.baseUnit.label;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Packaging' : 'Edit Packaging'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick names', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _presets
                      .map((name) => ActionChip(
                            label: Text(name),
                            onPressed: () => setState(() => _name.text = name),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Packaging name *',
                          hintText: 'e.g. Box or Carton',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateName,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _shortName,
                        decoration: const InputDecoration(
                          labelText: 'Short name',
                          hintText: 'e.g. Ctn',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v?.trim().length ?? 0) > 30
                            ? 'Maximum 30 characters.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _baseQuantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Base quantity *',
                    helperText: 'How many $unit are inside one ${_name.text.trim().isEmpty ? 'package' : _name.text.trim()}?',
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validateBaseQuantity,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                _PriceOverrideField(
                  title: 'Retail package price',
                  isOverride: _overrideRetail,
                  controller: _retail,
                  autoValue: widget.baseRetailPrice * (_parsedQty ?? 0),
                  onToggle: (value) => setState(() => _overrideRetail = value),
                ),
                const SizedBox(height: 12),
                _PriceOverrideField(
                  title: 'Wholesale package price',
                  isOverride: _overrideWholesale,
                  controller: _wholesale,
                  autoValue: widget.baseWholesalePrice * (_parsedQty ?? 0),
                  onToggle: (value) => setState(() => _overrideWholesale = value),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Inactive packaging stays in history but is not offered for new transactions.',
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save Packaging'),
        ),
      ],
    );
  }

  double? get _parsedQty => double.tryParse(_baseQuantity.text.trim());

  String? _validateName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Packaging name is required.';
    if (text.length > 120) return 'Maximum 120 characters.';
    final key = text.toLowerCase();
    if (widget.existingNames.contains(key)) return 'This packaging name already exists.';
    final baseName = widget.baseUnit.name.trim().toLowerCase();
    final baseShort = widget.baseUnit.shortName?.trim().toLowerCase() ?? '';
    if (key == baseName || (baseShort.isNotEmpty && key == baseShort)) {
      return 'Use a name different from the base unit.';
    }
    return null;
  }

  String? _validateBaseQuantity(String? value) {
    final q = double.tryParse(value?.trim() ?? '');
    if (q == null || !q.isFinite || q <= 0) return 'Enter a quantity greater than 0.';
    if (!widget.baseUnit.allowDecimal && !QuantityRule.isWhole(q)) {
      return '${widget.baseUnit.name} only allows whole quantities.';
    }
    return null;
  }

  double? _validatedOverride(TextEditingController controller, String label) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label must be greater than 0.')),
      );
      return null;
    }
    return value;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    double? retail;
    double? wholesale;
    if (_overrideRetail) {
      retail = _validatedOverride(_retail, 'Retail package price');
      if (retail == null) return;
    }
    if (_overrideWholesale) {
      wholesale = _validatedOverride(_wholesale, 'Wholesale package price');
      if (wholesale == null) return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(ProductPackaging(
      id: initial?.id,
      name: _name.text.trim(),
      shortName: _shortName.text.trim().isEmpty ? null : _shortName.text.trim(),
      baseQuantity: _parsedQty!,
      retailPrice: retail,
      wholesalePrice: wholesale,
      isActive: _active,
      sortOrder: initial?.sortOrder ?? 0,
    ));
  }
}

class _PriceOverrideField extends StatelessWidget {
  final String title;
  final bool isOverride;
  final TextEditingController controller;
  final double autoValue;
  final ValueChanged<bool> onToggle;

  const _PriceOverrideField({
    required this.title,
    required this.isOverride,
    required this.controller,
    required this.autoValue,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Auto')),
                ButtonSegment(value: true, label: Text('Override')),
              ],
              selected: {isOverride},
              onSelectionChanged: (v) => onToggle(v.first),
              showSelectedIcon: false,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isOverride)
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Package price',
              border: OutlineInputBorder(),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Auto = base price x package quantity = ${_money(autoValue)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

String _qty(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String _money(double value) {
  if (!value.isFinite) return '0';
  return value.toStringAsFixed(2);
}
