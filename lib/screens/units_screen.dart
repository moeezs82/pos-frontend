import 'package:flutter/material.dart';

import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';

/// Units of measure.
///
/// A unit answers one operational question: may a product measured in it be
/// sold or purchased in fractions? "Kilogram" yes, "Piece" no. That flag is the
/// reason this screen exists — the name alone would not be worth managing.
///
/// Turning Allow Decimal OFF is the one destructive-feeling action here. The
/// backend refuses it while products on that unit still hold fractional stock,
/// because otherwise the branch would be stuck: the leftover 0.5 could never be
/// sold, since 0.5 would no longer be a legal quantity. That 422 is surfaced
/// verbatim rather than swallowed — it names the offending products.
class UnitsScreen extends StatefulWidget {
  final String token;

  const UnitsScreen({super.key, required this.token});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  late final UnitService _service = UnitService(token: widget.token);

  List<ProductUnit> _units = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final units = await _service.list();
      if (!mounted) return;
      setState(() {
        _units = units;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _readableError(e);
        _loading = false;
      });
    }
  }

  /// Pulls the useful sentence out of an API failure.
  ///
  /// The backend returns a 422 whose message explains a real business rule —
  /// fractional stock blocking a change, or a unit still in use. Showing a
  /// generic "something went wrong" would hide exactly the information the
  /// operator needs to act on.
  String _readableError(Object e) {
    final raw = e.toString();
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
  }

  Future<void> _create() async {
    final result = await showDialog<_UnitDraft>(
      context: context,
      builder: (_) => const _UnitDialog(),
    );
    if (result == null) return;
    try {
      await _service.create(
        name: result.name,
        shortName: result.shortName,
        allowDecimal: result.allowDecimal,
        isActive: result.isActive,
      );
      _toast('Unit "${result.name}" created.');
      await _load();
    } catch (e) {
      _toast(_readableError(e), error: true);
    }
  }

  Future<void> _edit(ProductUnit unit) async {
    final result = await showDialog<_UnitDraft>(
      context: context,
      builder: (_) => _UnitDialog(existing: unit),
    );
    if (result == null) return;
    try {
      await _service.update(
        unit.id,
        name: result.name,
        shortName: result.shortName,
        allowDecimal: result.allowDecimal,
        isActive: result.isActive,
      );
      _toast('Unit "${result.name}" updated.');
      await _load();
    } catch (e) {
      // Most likely the fractional-stock guard. Its message names the
      // products, so show it long enough to read.
      _toast(_readableError(e), error: true);
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.delete(unit.id);
      _toast('Unit "${unit.name}" deleted.');
      await _load();
    } catch (e) {
      _toast(_readableError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Units'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Add unit'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not load units',
        detail: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_units.isEmpty) {
      return const _Message(
        icon: Icons.straighten,
        title: 'No units yet',
        detail:
            'Add a unit like Piece or Kilogram, then assign it to your products. '
            'The unit decides whether that product can be sold in decimal quantities.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _units.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = _units[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: u.allowDecimal
                  ? Colors.teal.withOpacity(.15)
                  : Colors.blueGrey.withOpacity(.15),
              child: Icon(
                u.allowDecimal ? Icons.scale : Icons.tag,
                size: 18,
                color: u.allowDecimal ? Colors.teal : Colors.blueGrey,
              ),
            ),
            title: Row(
              children: [
                Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis)),
                if (u.shortName != null) ...[
                  const SizedBox(width: 6),
                  Text('(${u.shortName})',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
                if (!u.isActive) ...[
                  const SizedBox(width: 8),
                  const _Chip(text: 'Inactive', color: Colors.grey),
                ],
              ],
            ),
            // The whole point of the screen, stated plainly rather than as a
            // bare "allow_decimal: true".
            subtitle: Text(
              u.allowDecimal
                  ? 'Decimal quantities allowed — e.g. 1.5'
                  : 'Whole quantities only — e.g. 1, 2, -1',
              style: TextStyle(
                fontSize: 12,
                color: u.allowDecimal ? Colors.teal.shade700 : Colors.blueGrey.shade700,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _edit(u),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                  onPressed: () => _delete(u),
                ),
              ],
            ),
            onTap: () => _edit(u),
          );
        },
      ),
    );
  }
}

/// What the dialog hands back. A plain value object so the screen owns all the
/// API calls and error handling in one place.
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

class _UnitDialog extends StatefulWidget {
  final ProductUnit? existing;

  const _UnitDialog({this.existing});

  @override
  State<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<_UnitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _shortName =
      TextEditingController(text: widget.existing?.shortName ?? '');

  late bool _allowDecimal = widget.existing?.allowDecimal ?? false;
  late bool _isActive = widget.existing?.isActive ?? true;

  bool get _isEdit => widget.existing != null;

  /// True when the user is turning decimals OFF on an existing unit — the one
  /// change the backend can refuse.
  bool get _isDisablingDecimals =>
      _isEdit && widget.existing!.allowDecimal && !_allowDecimal;

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit unit' : 'Add unit'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Piece, Kilogram, Litre…',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shortName,
                decoration: const InputDecoration(
                  labelText: 'Short name (optional)',
                  hintText: 'pc, kg, L',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v != null && v.trim().length > 50)
                    ? 'Keep the short name under 50 characters.'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowDecimal,
                onChanged: (v) => setState(() => _allowDecimal = v),
                title: const Text('Allow Decimal'),
                subtitle: Text(
                  _allowDecimal
                      ? 'Quantities like 1.5 are allowed.'
                      : 'Only whole quantities: 1, 2, -1. 1.5 will be rejected.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              // Warn BEFORE the request, so the operator understands the 422 if
              // it comes back rather than reading it as a bug.
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
                    'If any product using this unit currently has fractional '
                    'stock, this change will be refused. Existing sales and '
                    'purchases are never modified.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive units stay on existing products but are hidden when '
                  'choosing a unit.',
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
            final short = _shortName.text.trim();
            Navigator.pop(
              context,
              _UnitDraft(
                name: _name.text.trim(),
                shortName: short.isEmpty ? null : short,
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

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;

  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
