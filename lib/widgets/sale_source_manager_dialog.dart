import 'package:enterprise_pos/api/sale_source_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

class SaleSourceManagerResult {
  final int? selectedId;
  final bool changed;

  const SaleSourceManagerResult({required this.selectedId, required this.changed});
}

Future<SaleSourceManagerResult?> showSaleSourceManagerDialog({
  required BuildContext context,
  required SaleSourceService service,
  required int? selectedId,
}) {
  return showDialog<SaleSourceManagerResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SaleSourceManagerDialog(
      service: service,
      selectedId: selectedId,
    ),
  );
}

class _SaleSourceManagerDialog extends StatefulWidget {
  final SaleSourceService service;
  final int? selectedId;

  const _SaleSourceManagerDialog({required this.service, required this.selectedId});

  @override
  State<_SaleSourceManagerDialog> createState() => _SaleSourceManagerDialogState();
}

class _SaleSourceManagerDialogState extends State<_SaleSourceManagerDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  int? _selectedId;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _search.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final list = await widget.service.getSaleSources();
      if (!mounted) return;
      final sorted = [...list]..sort(_compareItems);
      setState(() => _items = sorted);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = await _nameDialog('Add Sale Source');
    if (name == null) return;
    setState(() => _busy = true);
    try {
      final created = await widget.service.createSaleSource(name: name);
      _changed = true;
      _selectedId = _id(created['id']) ?? _selectedId;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Map<String, dynamic> item) async {
    final id = _id(item['id']);
    if (id == null) return;
    final name = await _nameDialog(
      'Rename Sale Source',
      initial: (item['name'] ?? '').toString(),
    );
    if (name == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.updateSaleSource(id, name: name);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> item, bool value) async {
    final id = _id(item['id']);
    if (id == null) return;
    if ((item['code'] ?? '').toString() == 'counter' && !value) {
      AppFeedback.warning(context, 'Counter is the default source and must remain active.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.updateSaleSource(id, isActive: value);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(Map<String, dynamic> item, int direction) async {
    if (_search.text.trim().isNotEmpty) return;
    final sorted = [..._items]..sort(_compareItems);
    final id = _id(item['id']);
    if (id == null) return;
    final index = sorted.indexWhere((e) => _id(e['id']) == id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= sorted.length) return;

    final other = sorted[targetIndex];
    final otherId = _id(other['id']);
    if (otherId == null) return;
    var currentOrder = _order(item);
    var otherOrder = _order(other);
    if (currentOrder == otherOrder) {
      // Normalize the two positions locally without touching unrelated rows.
      currentOrder = index * 10 + 10;
      otherOrder = targetIndex * 10 + 10;
    }

    setState(() => _busy = true);
    try {
      await widget.service.updateSaleSource(id, sortOrder: otherOrder);
      await widget.service.updateSaleSource(otherId, sortOrder: currentOrder);
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.error(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _compareItems(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byOrder = _order(a).compareTo(_order(b));
    if (byOrder != 0) return byOrder;
    return (a['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase());
  }

  int _order(Map<String, dynamic> item) =>
      int.tryParse(item['sort_order']?.toString() ?? '') ?? 0;

  Future<String?> _nameDialog(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Source name',
            hintText: 'e.g. Instagram',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final value = ctrl.text.trim();
            if (value.isNotEmpty) Navigator.pop(ctx, value);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = ctrl.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((e) =>
      (e['name'] ?? '').toString().toLowerCase().contains(q) ||
      (e['code'] ?? '').toString().toLowerCase().contains(q)
    ).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.hub_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sale Sources', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.navy)),
                    SizedBox(height: 2),
                    Text('Add future sales channels without changing the software.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                )),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.pop(context, SaleSourceManagerResult(selectedId: _selectedId, changed: _changed)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: _search,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'Search sale sources…',
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Source'),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                          ]),
                        ))
                      : rows.isEmpty
                          ? const Center(child: Text('No sale sources found.', style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final item = rows[index];
                                final id = _id(item['id']);
                                final active = _bool(item['is_active']);
                                final selected = id != null && id == _selectedId;
                                final isCounter = (item['code'] ?? '').toString() == 'counter';
                                return ListTile(
                                  enabled: !_busy,
                                  selected: selected,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: selected ? AppTheme.primarySoft : AppTheme.surfaceSoft,
                                    child: Icon(selected ? Icons.check_rounded : Icons.hub_outlined, size: 18, color: selected ? AppTheme.primary : AppTheme.textMuted),
                                  ),
                                  title: Row(children: [
                                    Flexible(child: Text((item['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                                    if (!active) ...[
                                      const SizedBox(width: 8),
                                      const _StatusPill(text: 'Inactive'),
                                    ],
                                  ]),
                                  subtitle: Text(isCounter ? 'System default' : 'Available as a Sale From channel', style: const TextStyle(fontSize: 11.5)),
                                  onTap: id == null || !active ? null : () => setState(() => _selectedId = id),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (_search.text.trim().isEmpty) ...[
                                      IconButton(
                                        tooltip: 'Move up',
                                        onPressed: _busy || index == 0 ? null : () => _move(item, -1),
                                        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 19),
                                      ),
                                      IconButton(
                                        tooltip: 'Move down',
                                        onPressed: _busy || index == rows.length - 1 ? null : () => _move(item, 1),
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                                      ),
                                    ],
                                    IconButton(
                                      tooltip: 'Rename',
                                      onPressed: _busy ? null : () => _rename(item),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                    ),
                                    Tooltip(
                                      message: isCounter ? 'Counter must remain active' : (active ? 'Deactivate for new sales' : 'Reactivate'),
                                      child: Switch.adaptive(
                                        value: active,
                                        onChanged: _busy || isCounter ? null : (v) => _toggle(item, v),
                                      ),
                                    ),
                                  ]),
                                );
                              },
                            ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(children: [
                const Expanded(child: Text('Inactive sources remain on historical invoices and reports.', style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted))),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, SaleSourceManagerResult(selectedId: _selectedId, changed: _changed)),
                  child: const Text('Done'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  int? _id(dynamic value) => value is int ? value : int.tryParse(value?.toString() ?? '');
  bool _bool(dynamic value) => value == true || value == 1 || value?.toString().toLowerCase() == 'true';
  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');
}

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
    child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
  );
}
