import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/product_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SeasonsScreen extends StatefulWidget {
  const SeasonsScreen({super.key});

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  IntelligenceService? _service;
  IntelligenceEnvelope? _data;
  Object? _error;
  bool _loading = false;

  IntelligenceService _api() => _service ??= IntelligenceService(token: context.read<AuthProvider>().token!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final envelope = await _api().seasons();
      if (mounted) {
        setState(() => _data = envelope);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Business Seasons'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add season'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? IntelligenceError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(),
    );
  }

  Widget _body() {
    final rows = asMapList(_data!.result);
    final dated = rows.where((r) => r['recurrence'] == 'dated').length;
    final annual = rows.where((r) => r['recurrence'] == 'annual_fixed').length;
    final missingYear = rows.where((r) => r['missing_current_year'] == true).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const IntelligencePageHeader(
          title: 'Business Seasons',
          subtitle: 'Maintain owner-declared seasonal demand calendars such as Ramadan, Eid, summer and wedding season so replenishment can explain why demand may rise.',
        ),
        const SizedBox(height: 16),
        IntelligenceMetaBar(computedAt: _data!.computedAt, stale: _data!.stale, refreshing: _loading, onRefresh: _load),
        const SizedBox(height: 16),
        const IntelligenceInfoBanner(
          icon: Icons.event_repeat_rounded,
          title: 'Why this matters',
          message: 'The calendar explains why demand may change, while your own history measures what actually changed. CounterIQ never guesses religious dates, so year-specific dates must be entered intentionally when needed.',
          color: AppTheme.purple,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            MetricCard(title: 'Configured seasons', value: '${rows.length}', caption: 'All active business seasons in this branch context.', icon: Icons.event_note_rounded, color: AppTheme.purple),
            MetricCard(title: 'Annual fixed', value: '$annual', caption: 'Recurring month/day seasons used every year.', icon: Icons.repeat_rounded, color: AppTheme.info),
            MetricCard(title: 'Declared dates', value: '$dated', caption: 'Year-specific date ranges entered manually.', icon: Icons.date_range_rounded, color: AppTheme.warning),
            MetricCard(title: 'Need current-year dates', value: '$missingYear', caption: 'Dated seasons that are missing the current year.', icon: Icons.warning_amber_rounded, color: AppTheme.danger),
          ],
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const IntelligenceEmptyState(
            title: 'No business seasons configured yet',
            subtitle: 'Add seasons such as Ramadan, Eid, summer or wedding season so replenishment can describe demand context more clearly.',
            icon: Icons.event_busy_outlined,
          )
        else
          IntelligenceSectionCard(
            padding: const EdgeInsets.all(12),
            child: Column(children: rows.map(_seasonCard).toList()),
          ),
      ],
    );
  }

  Widget _seasonCard(Map<String, dynamic> row) {
    final recurrence = row['recurrence']?.toString() ?? 'annual_fixed';
    final bool missingCurrentYear = row['missing_current_year'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (missingCurrentYear ? AppTheme.warning : AppTheme.purple).withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(missingCurrentYear ? Icons.warning_amber_rounded : Icons.event_repeat_rounded, color: missingCurrentYear ? AppTheme.warning : AppTheme.purple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(row['name']?.toString() ?? 'Season', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                    _modePill(recurrence),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_subtitle(row), style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
                if ((row['notes']?.toString() ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(row['notes'].toString(), style: const TextStyle(fontSize: 12.5, color: AppTheme.navy, height: 1.35)),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _edit(existing: row);
              if (value == 'tag') _tag(row);
              if (value == 'delete') _delete(row);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'tag', child: Text('Add product / brand / category tag')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modePill(String recurrence) {
    final bool dated = recurrence == 'dated';
    final color = dated ? AppTheme.warning : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Text(dated ? 'Declared dates' : 'Annual fixed', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }

  String _subtitle(Map<String, dynamic> row) {
    if (row['recurrence'] == 'dated') {
      final warning = row['missing_current_year'] == true ? ' • current-year dates missing' : '';
      return '${row['starts_on'] ?? '—'} → ${row['ends_on'] ?? '—'} • ${row['occurrence_year'] ?? '—'}$warning';
    }
    return '${row['start_month']}/${row['start_day']} → ${row['end_month']}/${row['end_day']} • annual fixed';
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing == null ? '' : (existing['name']?.toString() ?? ''));
    final notes = TextEditingController(text: existing == null ? '' : (existing['notes']?.toString() ?? ''));
    String recurrence = existing == null ? 'annual_fixed' : (existing['recurrence']?.toString() ?? 'annual_fixed');
    final start = TextEditingController(
      text: recurrence == 'dated'
          ? (existing == null ? '' : (existing['starts_on']?.toString() ?? ''))
          : '${existing == null ? '' : (existing['start_month'] ?? '')}/${existing == null ? '' : (existing['start_day'] ?? '')}',
    );
    final end = TextEditingController(
      text: recurrence == 'dated'
          ? (existing == null ? '' : (existing['ends_on']?.toString() ?? ''))
          : '${existing == null ? '' : (existing['end_month'] ?? '')}/${existing == null ? '' : (existing['end_day'] ?? '')}',
    );
    final year = TextEditingController(
      text: existing == null ? DateTime.now().year.toString() : (existing['occurrence_year']?.toString() ?? DateTime.now().year.toString()),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add business season' : 'Edit business season'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: recurrence,
                    decoration: const InputDecoration(labelText: 'Date type'),
                    items: const [
                      DropdownMenuItem(value: 'annual_fixed', child: Text('Annual fixed (month/day)')),
                      DropdownMenuItem(value: 'dated', child: Text('Declared dates (year-specific)')),
                    ],
                    onChanged: (value) => setLocal(() => recurrence = value ?? recurrence),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: start, decoration: InputDecoration(labelText: recurrence == 'dated' ? 'Starts on (YYYY-MM-DD)' : 'Starts (MM/DD)')),
                  const SizedBox(height: 10),
                  TextField(controller: end, decoration: InputDecoration(labelText: recurrence == 'dated' ? 'Ends on (YYYY-MM-DD)' : 'Ends (MM/DD)')),
                  if (recurrence == 'dated') ...[
                    const SizedBox(height: 10),
                    TextField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Occurrence year')),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                try {
                  final body = <String, dynamic>{
                    'name': name.text.trim(),
                    'recurrence': recurrence,
                    'is_active': true,
                    'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                  };
                  if (recurrence == 'dated') {
                    body['starts_on'] = start.text.trim();
                    body['ends_on'] = end.text.trim();
                    body['occurrence_year'] = int.parse(year.text.trim());
                  } else {
                    final startParts = start.text.split('/');
                    final endParts = end.text.split('/');
                    body['start_month'] = int.parse(startParts[0]);
                    body['start_day'] = int.parse(startParts[1]);
                    body['end_month'] = int.parse(endParts[0]);
                    body['end_day'] = int.parse(endParts[1]);
                  }
                  Navigator.pop(ctx, body);
                } catch (_) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please check the date format before saving.')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    notes.dispose();
    start.dispose();
    end.dispose();
    year.dispose();

    if (result == null) return;

    try {
      if (existing == null) {
        await _api().createSeason(result);
      } else {
        await _api().updateSeason((existing['id'] as num).toInt(), result);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _tag(Map<String, dynamic> row) async {
    String scope = 'product';
    Map<String, dynamic>? selected;

    Future<void> pickForScope(StateSetter setLocal) async {
      final token = context.read<AuthProvider>().token!;
      Map<String, dynamic>? picked;
      if (scope == 'product') {
        picked = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProductPickerSheet(token: token),
        );
      } else {
        final common = CommonService(token: token);
        final items = scope == 'brand' ? await common.getBrands() : await common.getCategories();
        if (!mounted) return;
        picked = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => _ReferencePickerDialog(
            title: scope == 'brand' ? 'Select brand' : 'Select category',
            items: items,
          ),
        );
      }
      if (picked != null) setLocal(() => selected = picked);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Apply ${row['name']} to…'),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose what this season applies to. CounterIQ will use the tag only as seasonal context for matching products.',
                  style: TextStyle(color: AppTheme.textMuted, height: 1.35),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: scope,
                  decoration: const InputDecoration(labelText: 'Apply season to'),
                  items: const [
                    DropdownMenuItem(value: 'product', child: Text('A specific product')),
                    DropdownMenuItem(value: 'brand', child: Text('All products in a brand')),
                    DropdownMenuItem(value: 'category', child: Text('All products in a category')),
                  ],
                  onChanged: (value) {
                    setLocal(() {
                      scope = value ?? scope;
                      selected = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => pickForScope(setLocal),
                  icon: const Icon(Icons.search_rounded),
                  label: Text(selected == null ? 'Choose ${scope == 'product' ? 'product' : scope}' : 'Change selection'),
                ),
                if (selected != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      selected!['name']?.toString() ?? selected!['title']?.toString() ?? 'Selected item #${selected!['id']}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Add season tag'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selected == null) return;
    final rawId = selected!['id'];
    if (rawId is! num) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The selected item does not contain a valid ID.')));
      }
      return;
    }

    try {
      await _api().addSeasonTag((row['id'] as num).toInt(), scope: scope, scopeId: rawId.toInt());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row['name']} now applies to ${selected!['name'] ?? selected!['title'] ?? 'the selected item'}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete season?'),
        content: Text('Delete ${row['name']} and its tags?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api().deleteSeason((row['id'] as num).toInt());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
        }
      }
    }
  }
}


class _ReferencePickerDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const _ReferencePickerDialog({required this.title, required this.items});

  @override
  State<_ReferencePickerDialog> createState() => _ReferencePickerDialogState();
}

class _ReferencePickerDialogState extends State<_ReferencePickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final visible = widget.items.where((item) {
      if (q.isEmpty) return true;
      return (item['name']?.toString() ?? '').toLowerCase().contains(q);
    }).toList(growable: false);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No matching items found.', style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = visible[index];
                        return ListTile(
                          title: Text(item['name']?.toString() ?? 'Unnamed'),
                          subtitle: Text('ID ${item['id'] ?? '—'}'),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
