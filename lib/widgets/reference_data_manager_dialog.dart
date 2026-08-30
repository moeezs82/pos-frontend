import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

/// Result returned by an inline reference-data manager.
///
/// [selectedId] is the value the product form should keep selected after it
/// reloads its dropdown. It can be null when the operator clears the selection
/// or deletes the currently-selected item.
class ReferenceManagerResult {
  final int? selectedId;
  final bool changed;

  const ReferenceManagerResult({
    required this.selectedId,
    required this.changed,
  });
}

typedef NamedReferenceLoader = Future<List<Map<String, dynamic>>> Function();
typedef NamedReferenceCreate = Future<Map<String, dynamic>> Function(String name);
typedef NamedReferenceUpdate = Future<Map<String, dynamic>> Function(
  int id,
  String name,
);
typedef NamedReferenceDelete = Future<void> Function(int id);

Future<ReferenceManagerResult?> showNamedReferenceManagerDialog({
  required BuildContext context,
  required String title,
  required String singularLabel,
  required IconData icon,
  required int? selectedId,
  required NamedReferenceLoader loadItems,
  required NamedReferenceCreate createItem,
  required NamedReferenceUpdate updateItem,
  NamedReferenceDelete? deleteItem,
  bool allowClearSelection = true,
  String? subtitle,
  String selectedSubtitle = 'Selected for this product',
}) {
  return showDialog<ReferenceManagerResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NamedReferenceManagerDialog(
      title: title,
      singularLabel: singularLabel,
      icon: icon,
      selectedId: selectedId,
      loadItems: loadItems,
      createItem: createItem,
      updateItem: updateItem,
      deleteItem: deleteItem,
      allowClearSelection: allowClearSelection,
      subtitle: subtitle,
      selectedSubtitle: selectedSubtitle,
    ),
  );
}

class _NamedReferenceManagerDialog extends StatefulWidget {
  final String title;
  final String singularLabel;
  final IconData icon;
  final int? selectedId;
  final NamedReferenceLoader loadItems;
  final NamedReferenceCreate createItem;
  final NamedReferenceUpdate updateItem;
  final NamedReferenceDelete? deleteItem;
  final bool allowClearSelection;
  final String? subtitle;
  final String selectedSubtitle;

  const _NamedReferenceManagerDialog({
    required this.title,
    required this.singularLabel,
    required this.icon,
    required this.selectedId,
    required this.loadItems,
    required this.createItem,
    required this.updateItem,
    required this.deleteItem,
    required this.allowClearSelection,
    required this.subtitle,
    required this.selectedSubtitle,
  });

  @override
  State<_NamedReferenceManagerDialog> createState() =>
      _NamedReferenceManagerDialogState();
}

class _NamedReferenceManagerDialogState
    extends State<_NamedReferenceManagerDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  int? _selectedId;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _searchCtrl.addListener(_refreshFilter);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_refreshFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refreshFilter() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await widget.loadItems();
      items.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_selectedId != null &&
            !_items.any((item) => _idOf(item['id']) == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _readableError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameEditDialog(label: widget.singularLabel),
    );
    if (name == null) return;

    setState(() => _busy = true);
    try {
      final created = await widget.createItem(name);
      final id = _idOf(created['id']);
      if (!mounted) return;
      _changed = true;
      if (id != null) _selectedId = id;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final id = _idOf(item['id']);
    if (id == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameEditDialog(
        label: widget.singularLabel,
        initialValue: (item['name'] ?? '').toString(),
      ),
    );
    if (name == null) return;

    setState(() => _busy = true);
    try {
      await widget.updateItem(id, name);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = _idOf(item['id']);
    if (id == null) return;
    final name = (item['name'] ?? widget.singularLabel).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          'This removes the ${widget.singularLabel.toLowerCase()} from this branch. '
          'If it is still used by products, the server may refuse the deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final deleteItem = widget.deleteItem;
      if (deleteItem == null) return;
      await deleteItem(id);
      _changed = true;
      if (_selectedId == id) _selectedId = null;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((item) =>
            (item['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ManagerHeader(
              icon: widget.icon,
              title: widget.title,
              subtitle: widget.subtitle ??
                  (widget.deleteItem == null
                      ? 'Create, rename, or choose without leaving this form.'
                      : 'Create, rename, delete, or choose without leaving the product form.'),
              onClose: _busy
                  ? null
                  : () => Navigator.pop(
                        context,
                        ReferenceManagerResult(
                          selectedId: _selectedId,
                          changed: _changed,
                        ),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        hintText: 'Search ${widget.title.toLowerCase()}…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ManagerError(message: _error!, onRetry: _load)
                      : items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  _items.isEmpty
                                      ? 'No ${widget.title.toLowerCase()} yet.'
                                      : 'No matches found.',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final item = items[index];
                                final id = _idOf(item['id']);
                                final selected = id != null && id == _selectedId;
                                return ListTile(
                                  enabled: !_busy,
                                  leading: CircleAvatar(
                                    radius: 17,
                                    backgroundColor: selected
                                        ? AppTheme.primarySoft
                                        : AppTheme.surfaceSoft,
                                    child: Icon(
                                      selected
                                          ? Icons.check_rounded
                                          : widget.icon,
                                      size: 17,
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                  title: Text(
                                    (item['name'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: selected
                                      ? Text(widget.selectedSubtitle)
                                      : null,
                                  onTap: id == null || _busy
                                      ? null
                                      : () => setState(() => _selectedId = id),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rename',
                                        onPressed: _busy ? null : () => _edit(item),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                      ),
                                      if (widget.deleteItem != null)
                                        IconButton(
                                          tooltip: 'Delete',
                                          onPressed: _busy ? null : () => _delete(item),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: AppTheme.danger,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                children: [
                  if (widget.allowClearSelection)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _selectedId = null),
                      icon: const Icon(Icons.clear_rounded, size: 17),
                      label: const Text('Clear selection'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(
                              context,
                              ReferenceManagerResult(
                                selectedId: _selectedId,
                                changed: _changed,
                              ),
                            ),
                    child: const Text('Done'),
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

Future<ReferenceManagerResult?> showUnitManagerDialog({
  required BuildContext context,
  required UnitService service,
  required int? selectedId,
  bool allowClearSelection = true,
}) {
  return showDialog<ReferenceManagerResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UnitManagerDialog(
      service: service,
      selectedId: selectedId,
      allowClearSelection: allowClearSelection,
    ),
  );
}

class _UnitManagerDialog extends StatefulWidget {
  final UnitService service;
  final int? selectedId;
  final bool allowClearSelection;

  const _UnitManagerDialog({
    required this.service,
    required this.selectedId,
    required this.allowClearSelection,
  });

  @override
  State<_UnitManagerDialog> createState() => _UnitManagerDialogState();
}

class _UnitManagerDialogState extends State<_UnitManagerDialog> {
  final _searchCtrl = TextEditingController();
  List<ProductUnit> _units = [];
  int? _selectedId;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _searchCtrl.addListener(_refreshFilter);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_refreshFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refreshFilter() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final units = await widget.service.list();
      units.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _units = units;
        if (_selectedId != null && !_units.any((u) => u.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = _readableError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final draft = await showDialog<_UnitDraft>(
      context: context,
      builder: (_) => const _UnitEditDialog(),
    );
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      final created = await widget.service.create(
        name: draft.name,
        shortName: draft.shortName,
        allowDecimal: draft.allowDecimal,
        isActive: draft.isActive,
      );
      _changed = true;
      _selectedId = created.id;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(ProductUnit unit) async {
    final draft = await showDialog<_UnitDraft>(
      context: context,
      builder: (_) => _UnitEditDialog(existing: unit),
    );
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.update(
        unit.id,
        name: draft.name,
        shortName: draft.shortName,
        clearShortName: draft.shortName == null && unit.shortName != null,
        allowDecimal: draft.allowDecimal,
        isActive: draft.isActive,
      );
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProductUnit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${unit.name}"?'),
        content: const Text(
          'Products already assigned to this unit will block the delete. '
          'Existing sales and purchases are never changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.service.delete(unit.id);
      _changed = true;
      if (_selectedId == unit.id) _selectedId = null;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ProductUnit> get _filteredUnits {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _units;
    return _units
        .where((u) =>
            u.name.toLowerCase().contains(q) ||
            (u.shortName ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final units = _filteredUnits;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ManagerHeader(
              icon: Icons.straighten_rounded,
              title: 'Manage Units',
              subtitle: 'Units control whether product quantities can use decimals.',
              onClose: _busy
                  ? null
                  : () => Navigator.pop(
                        context,
                        ReferenceManagerResult(
                          selectedId: _selectedId,
                          changed: _changed,
                        ),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        hintText: 'Search units…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add Unit'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ManagerError(message: _error!, onRetry: _load)
                      : units.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  'No units found.',
                                  style: TextStyle(color: AppTheme.textMuted),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: units.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final unit = units[index];
                                final selected = unit.id == _selectedId;
                                final canSelect =
                                    unit.isActive || unit.id == widget.selectedId;
                                return ListTile(
                                  enabled: !_busy && canSelect,
                                  onTap: _busy || !canSelect
                                      ? null
                                      : () => setState(() => _selectedId = unit.id),
                                  leading: CircleAvatar(
                                    radius: 17,
                                    backgroundColor: selected
                                        ? AppTheme.primarySoft
                                        : AppTheme.surfaceSoft,
                                    child: Icon(
                                      selected
                                          ? Icons.check_rounded
                                          : (unit.allowDecimal
                                              ? Icons.scale_rounded
                                              : Icons.tag_rounded),
                                      size: 17,
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          unit.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if ((unit.shortName ?? '').isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${unit.shortName})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                      if (!unit.isActive) ...[
                                        const SizedBox(width: 8),
                                        const _StatusChip('Inactive'),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    !unit.isActive && !canSelect
                                        ? 'Inactive · available for management only'
                                        : unit.allowDecimal
                                            ? 'Decimal quantities allowed'
                                            : 'Whole quantities only',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit unit',
                                        onPressed: _busy ? null : () => _edit(unit),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete unit',
                                        onPressed: _busy ? null : () => _delete(unit),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Row(
                children: [
                  if (widget.allowClearSelection)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _selectedId = null),
                      icon: const Icon(Icons.clear_rounded, size: 17),
                      label: const Text('Clear selection'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(
                              context,
                              ReferenceManagerResult(
                                selectedId: _selectedId,
                                changed: _changed,
                              ),
                            ),
                    child: const Text('Done'),
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

class _NameEditDialog extends StatefulWidget {
  final String label;
  final String initialValue;

  const _NameEditDialog({
    required this.label,
    this.initialValue = '',
  });

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialValue.isNotEmpty;
    return AlertDialog(
      title: Text('${editing ? 'Rename' : 'Add'} ${widget.label}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: '${widget.label} Name',
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return 'Name is required.';
            if (text.runes.length > 255) return 'Keep the name under 255 characters.';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _controller.text.trim());
  }
}

class _UnitDraft {
  final String name;
  final String? shortName;
  final bool allowDecimal;
  final bool isActive;

  const _UnitDraft({
    required this.name,
    this.shortName,
    required this.allowDecimal,
    required this.isActive,
  });
}

class _UnitEditDialog extends StatefulWidget {
  final ProductUnit? existing;

  const _UnitEditDialog({this.existing});

  @override
  State<_UnitEditDialog> createState() => _UnitEditDialogState();
}

class _UnitEditDialogState extends State<_UnitEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _shortNameCtrl =
      TextEditingController(text: widget.existing?.shortName ?? '');
  late bool _allowDecimal = widget.existing?.allowDecimal ?? false;
  late bool _isActive = widget.existing?.isActive ?? true;

  bool get _isEdit => widget.existing != null;
  bool get _isDisablingDecimals =>
      _isEdit && widget.existing!.allowDecimal && !_allowDecimal;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Unit' : 'Add Unit'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Piece, Kilogram, Litre…',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Name is required.';
                  if (text.runes.length > 255) {
                    return 'Keep the name under 255 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Short name (optional)',
                  hintText: 'pc, kg, L',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().runes.length > 50
                    ? 'Keep the short name under 50 characters.'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowDecimal,
                onChanged: (value) => setState(() => _allowDecimal = value),
                title: const Text('Allow Decimal'),
                subtitle: Text(
                  _allowDecimal
                      ? 'Quantities like 1.5 are allowed.'
                      : 'Only whole quantities such as 1, 2, or -1 are allowed.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_isDisablingDecimals)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(.4)),
                  ),
                  child: const Text(
                    'If products using this unit currently have fractional stock, '
                    'the server will refuse this change so existing stock cannot become unsellable.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive units remain on existing products but are hidden for new selections.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final shortName = _shortNameCtrl.text.trim();
            Navigator.pop(
              context,
              _UnitDraft(
                name: _nameCtrl.text.trim(),
                shortName: shortName.isEmpty ? null : shortName,
                allowDecimal: _allowDecimal,
                isActive: _isActive,
              ),
            );
          },
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _ManagerHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  const _ManagerHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 11),
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
                    color: Colors.white.withOpacity(.62),
                    fontSize: 11,
                  ),
                ),
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
}

class _ManagerError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ManagerError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 34, color: AppTheme.danger),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;

  const _StatusChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.textMuted.withOpacity(.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
      ),
    );
  }
}

int? _idOf(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _readableError(Object e) =>
    e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
