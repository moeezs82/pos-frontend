import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/fixed_asset_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Writes need this permission (backend enforces it); reading only needs
/// view-cashbook or view-reports.
const kFixedAssetsPermission = 'manage-fixed-assets';

String _errorText(Object e) {
  if (e is ApiException) {
    final errs = e.body?['errors'];
    if (errs is Map && errs.isNotEmpty) {
      final first = errs.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }
    if (e.message.trim().isNotEmpty) return e.message;
  }
  return e.toString().replaceFirst('Exception: ', '');
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
num _num(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;

/// Fixed Assets workspace (add-on `fixed_assets`): asset register with book
/// values, registering a purchase, monthly straight-line depreciation runs and
/// disposals. Every action posts to the ledger; undo actions post mirror
/// entries dated like the original.
class FixedAssetsScreen extends StatefulWidget {
  const FixedAssetsScreen({super.key});

  @override
  State<FixedAssetsScreen> createState() => _FixedAssetsScreenState();
}

class _FixedAssetsScreenState extends State<FixedAssetsScreen> {
  late final FixedAssetService _api;
  final _money = const AppMoneyFormatter();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  String _status = 'active';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _api = FixedAssetService(token: context.read<AuthProvider>().token ?? '');
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.list(status: _status == 'all' ? null : _status, search: _searchCtrl.text);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from((data['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _summary = Map<String, dynamic>.from(data['summary'] ?? const {});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  void _openReport(String key) => PosNavigation.openSingleton(
        routeId: PosRouteIds.report(key),
        builder: (_) => EnterpriseReportsWorkspaceScreen(initialReportKey: key),
      );

  Future<void> _addAsset() async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _AssetFormDialog(api: _api));
    if (saved == true) _fetch();
  }

  Future<void> _runDepreciation() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _DepreciationRunDialog(api: _api));
    if (changed == true) _fetch();
  }

  Future<void> _openAsset(Map<String, dynamic> a) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AssetDetailDialog(api: _api, assetId: (a['id'] as num).toInt()),
    );
    if (changed == true) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.hasPermission(kFixedAssetsPermission);
    final canReport = auth.hasPermission('view-reports');

    return EnterprisePage(
      title: 'Fixed Assets',
      subtitle: 'Asset register, monthly straight-line depreciation and disposals.',
      icon: Icons.precision_manufacturing_outlined,
      actions: [
        if (canManage)
          FilledButton.icon(onPressed: _addAsset, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add Asset')),
        if (canManage)
          OutlinedButton.icon(onPressed: _runDepreciation, icon: const Icon(Icons.event_repeat_rounded, size: 18), label: const Text('Run Depreciation')),
        if (canReport)
          OutlinedButton.icon(onPressed: () => _openReport('asset-register'), icon: const Icon(Icons.list_alt_rounded, size: 18), label: const Text('Asset Register')),
        if (canReport)
          OutlinedButton.icon(onPressed: () => _openReport('depreciation-schedule'), icon: const Icon(Icons.timeline_rounded, size: 18), label: const Text('Schedule')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(label: 'Active assets', value: '${_summary['active_assets'] ?? 0}', icon: Icons.inventory_2_outlined, color: AppTheme.info),
              _StatCard(label: 'Cost', value: _money.format(_num(_summary['cost'])), icon: Icons.payments_outlined, color: AppTheme.teal),
              _StatCard(label: 'Accumulated depreciation', value: _money.format(_num(_summary['accumulated_depreciation'])), icon: Icons.trending_down_rounded, color: AppTheme.warning),
              _StatCard(label: 'Book value', value: _money.format(_num(_summary['book_value'])), icon: Icons.account_balance_rounded, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'disposed', label: Text('Disposed')),
                  ButtonSegment(value: 'void', label: Text('Void')),
                  ButtonSegment(value: 'all', label: Text('All')),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  setState(() => _status = s.first);
                  _fetch();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, code or category', isDense: true),
                  onSubmitted: (_) => _fetch(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ]),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No fixed assets here yet.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final a = _items[i];
          final code = (a['asset_code'] ?? '').toString();
          return ListTile(
            onTap: () => _openAsset(a),
            leading: const Icon(Icons.precision_manufacturing_outlined),
            title: Text('${a['name']}${code.isEmpty ? '' : '  ·  $code'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Bought ${a['purchase_date']} · ${a['useful_life_months']} months · '
                '${_money.format(_num(a['monthly_depreciation']))}/month${(a['category'] ?? '').toString().isEmpty ? '' : ' · ${a['category']}'}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money.format(_num(a['book_value'])), style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('cost ${_money.format(_num(a['cost']))}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
                  ],
                ),
                const SizedBox(width: 10),
                _StatusChip(status: '${a['status']}'),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Add asset ────────────────────────────────────────────────────────────────

class _AssetFormDialog extends StatefulWidget {
  final FixedAssetService api;
  const _AssetFormDialog({required this.api});

  @override
  State<_AssetFormDialog> createState() => _AssetFormDialogState();
}

class _AssetFormDialogState extends State<_AssetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _category = TextEditingController();
  final _cost = TextEditingController();
  final _salvage = TextEditingController(text: '0');
  final _life = TextEditingController(text: '60');
  final _notes = TextEditingController();
  DateTime _purchaseDate = DateTime.now();
  String _funding = 'cash';
  String _method = 'cash';
  Map<String, dynamic>? _vendor;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _category, _cost, _salvage, _life, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickVendor() async {
    final token = context.read<AuthProvider>().token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * .86, child: VendorPickerSheet(token: token)),
    );
    if (picked != null) setState(() => _vendor = picked);
  }

  String _vendorName(Map<String, dynamic> v) {
    final n = '${v['first_name'] ?? ''} ${v['last_name'] ?? ''}'.trim();
    return n.isNotEmpty ? n : (v['company_name'] ?? 'Vendor #${v['id']}').toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_funding == 'vendor' && _vendor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select the vendor.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.create({
        'name': _name.text.trim(),
        if (_code.text.trim().isNotEmpty) 'asset_code': _code.text.trim(),
        if (_category.text.trim().isNotEmpty) 'category': _category.text.trim(),
        'purchase_date': _ymd(_purchaseDate),
        'cost': double.parse(_cost.text.trim()),
        'salvage_value': double.tryParse(_salvage.text.trim()) ?? 0,
        'useful_life_months': int.parse(_life.text.trim()),
        'funding': _funding,
        if (_funding == 'cash') 'payment_method': _method,
        if (_funding == 'vendor') 'vendor_id': _vendor!['id'],
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = context.watch<PaymentMethodProvider>().activeMethods;
    String? positive(String? v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : 'Enter an amount above 0';
    return AlertDialog(
      title: const Text('Add Fixed Asset'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name *'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
                Row(children: [
                  Expanded(child: TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Asset code'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Category'))),
                ]),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _purchaseDate, firstDate: DateTime(2000), lastDate: DateTime.now());
                    if (d != null) setState(() => _purchaseDate = d);
                  },
                  child: InputDecorator(decoration: const InputDecoration(labelText: 'Purchase date'), child: Text(_ymd(_purchaseDate))),
                ),
                Row(children: [
                  Expanded(child: TextFormField(controller: _cost, decoration: const InputDecoration(labelText: 'Cost *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: positive)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _salvage, decoration: const InputDecoration(labelText: 'Salvage value'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _life,
                      decoration: const InputDecoration(labelText: 'Useful life (months) *'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim()) ?? 0;
                        return n < 1 || n > 600 ? '1–600' : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('Paid now'), icon: Icon(Icons.payments_outlined)),
                    ButtonSegment(value: 'vendor', label: Text('On credit (vendor)'), icon: Icon(Icons.storefront_outlined)),
                  ],
                  selected: {_funding},
                  onSelectionChanged: (s) => setState(() => _funding = s.first),
                ),
                const SizedBox(height: 10),
                if (_funding == 'cash')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: methods
                        .map((m) => ChoiceChip(
                              selected: _method == m.method,
                              avatar: Icon(m.icon, size: 18),
                              label: Text(m.displayName),
                              onSelected: (_) => setState(() => _method = m.method),
                            ))
                        .toList(),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(_vendor == null ? 'No vendor selected' : _vendorName(_vendor!)),
                    subtitle: const Text('Posted to Accounts Payable; pay it later through vendor payments.'),
                    trailing: OutlinedButton(onPressed: _pickVendor, child: const Text('Choose')),
                  ),
                TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
                const SizedBox(height: 8),
                const Text(
                  'Straight-line, monthly. The purchase month is depreciated in full; the disposal month is not.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Register Asset')),
      ],
    );
  }
}

// ── Asset detail: history, dispose, undo ─────────────────────────────────────

class _AssetDetailDialog extends StatefulWidget {
  final FixedAssetService api;
  final int assetId;
  const _AssetDetailDialog({required this.api, required this.assetId});

  @override
  State<_AssetDetailDialog> createState() => _AssetDetailDialogState();
}

class _AssetDetailDialogState extends State<_AssetDetailDialog> {
  final _money = const AppMoneyFormatter();
  Map<String, dynamic>? _asset;
  List<Map<String, dynamic>> _deps = [];
  String? _error;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.show(widget.assetId);
      if (!mounted) return;
      setState(() {
        _asset = Map<String, dynamic>.from(data['asset'] ?? {});
        _deps = List<Map<String, dynamic>>.from((data['depreciations'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    }
  }

  Future<void> _act(Future<void> Function() fn, String done) async {
    setState(() => _busy = true);
    try {
      await fn();
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirm')),
          ],
        ),
      ) ==
      true;

  Future<void> _dispose() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DisposeDialog(bookValue: _num(_asset!['book_value'])));
    if (result == null) return;
    await _act(
      () => widget.api.dispose(widget.assetId,
          date: result['date'] as String, proceeds: result['proceeds'] as double, paymentMethod: result['method'] as String?, note: result['note'] as String?),
      'Asset disposed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().hasPermission(kFixedAssetsPermission);
    final a = _asset;
    return AlertDialog(
      title: Text(a == null ? 'Fixed Asset' : '${a['name']}'),
      content: SizedBox(
        width: 560,
        child: _error != null
            ? Text(_error!)
            : a == null
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [_StatusChip(status: '${a['status']}'), const SizedBox(width: 8), Text('${a['asset_code'] ?? ''}')]),
                        const SizedBox(height: 10),
                        _kv('Purchased', '${a['purchase_date']} · ${a['funding'] == 'vendor' ? 'on credit (vendor)' : 'paid via ${a['payment_method'] ?? 'cash'}'}'),
                        _kv('Cost', _money.format(_num(a['cost']))),
                        _kv('Salvage value', _money.format(_num(a['salvage_value']))),
                        _kv('Useful life', '${a['useful_life_months']} months from ${a['depreciation_start_date']}'),
                        _kv('Monthly depreciation', _money.format(_num(a['monthly_depreciation']))),
                        _kv('Accumulated depreciation', _money.format(_num(a['accumulated_depreciation']))),
                        _kv('Book value', _money.format(_num(a['book_value']))),
                        if (a['disposal_date'] != null) ...[
                          _kv('Disposed', '${a['disposal_date']} for ${_money.format(_num(a['disposal_proceeds']))}'),
                          _kv(_num(a['disposal_gain_loss']) >= 0 ? 'Gain' : 'Loss', _money.format(_num(a['disposal_gain_loss']).abs())),
                        ],
                        const Divider(height: 24),
                        const Text('Depreciation history', style: TextStyle(fontWeight: FontWeight.w800)),
                        if (_deps.isEmpty)
                          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Nothing posted yet.', style: TextStyle(color: AppTheme.textMuted)))
                        else
                          ..._deps.map((d) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${d['period']}'),
                                subtitle: d['status'] == 'reversed' ? const Text('reversed') : null,
                                trailing: Text(_money.format(_num(d['amount'])),
                                    style: TextStyle(decoration: d['status'] == 'reversed' ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w700)),
                              )),
                      ],
                    ),
                  ),
      ),
      actions: [
        if (canManage && a != null && a['status'] == 'active') ...[
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (await _confirm('Void asset?', 'Reverses the purchase entry on its original date. Only possible while no depreciation is posted.')) {
                      await _act(() => widget.api.voidAsset(widget.assetId), 'Asset voided.');
                    }
                  },
            child: const Text('Void Purchase'),
          ),
          FilledButton.tonal(onPressed: _busy ? null : _dispose, child: const Text('Dispose / Sell')),
        ],
        if (canManage && a != null && a['status'] == 'disposed')
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (await _confirm('Reverse disposal?', 'Reverses the disposal entry on its original date and makes the asset active again.')) {
                      await _act(() => widget.api.voidDisposal(widget.assetId), 'Disposal reversed.');
                    }
                  },
            child: const Text('Reverse Disposal'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Close')),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 190, child: Text(k, style: const TextStyle(color: AppTheme.textMuted))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

class _DisposeDialog extends StatefulWidget {
  final num bookValue;
  const _DisposeDialog({required this.bookValue});

  @override
  State<_DisposeDialog> createState() => _DisposeDialogState();
}

class _DisposeDialogState extends State<_DisposeDialog> {
  final _money = const AppMoneyFormatter();
  final _proceeds = TextEditingController(text: '0');
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'cash';

  @override
  void dispose() {
    _proceeds.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final methods = context.watch<PaymentMethodProvider>().activeMethods;
    final proceeds = double.tryParse(_proceeds.text.trim()) ?? 0;
    final diff = proceeds - widget.bookValue;
    return AlertDialog(
      title: const Text('Dispose / Sell Asset'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Disposal date'), child: Text(_ymd(_date))),
            ),
            TextField(
              controller: _proceeds,
              decoration: const InputDecoration(labelText: 'Sale proceeds (0 for a write-off)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            if (proceeds > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: methods
                    .map((m) => ChoiceChip(selected: _method == m.method, label: Text(m.displayName), onSelected: (_) => setState(() => _method = m.method)))
                    .toList(),
              ),
            ],
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: 10),
            Text(
              'Book value ${_money.format(widget.bookValue)} → ${diff >= 0 ? 'gain' : 'loss'} of ${_money.format(diff.abs())}. '
              'Depreciation must be posted through the month before the disposal date.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: proceeds < 0
              ? null
              : () => Navigator.pop(context, {
                    'date': _ymd(_date),
                    'proceeds': proceeds,
                    'method': proceeds > 0 ? _method : null,
                    'note': _note.text,
                  }),
          child: const Text('Dispose'),
        ),
      ],
    );
  }
}

// ── Depreciation run ─────────────────────────────────────────────────────────

class _DepreciationRunDialog extends StatefulWidget {
  final FixedAssetService api;
  const _DepreciationRunDialog({required this.api});

  @override
  State<_DepreciationRunDialog> createState() => _DepreciationRunDialogState();
}

class _DepreciationRunDialogState extends State<_DepreciationRunDialog> {
  final _money = const AppMoneyFormatter();
  late String _period;
  late final List<String> _periods;
  Map<String, dynamic>? _preview;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to last month: the current month is usually not over yet.
    _periods = List.generate(36, (i) => _ym(DateTime(now.year, now.month - i, 1)));
    _period = _periods[1];
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.previewDepreciation(_period);
      if (mounted) setState(() => _preview = data);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _do(Future<Map<String, dynamic>> Function() fn, String done) async {
    setState(() => _busy = true);
    try {
      await fn();
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _loadPreview();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = List<Map<String, dynamic>>.from((_preview?['lines'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final summary = Map<String, dynamic>.from(_preview?['summary'] ?? const {});
    return AlertDialog(
      title: const Text('Run Depreciation'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Post depreciation through'),
              items: _periods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _period = v);
                      _loadPreview();
                    },
            ),
            const SizedBox(height: 8),
            const Text(
              'Every missing month up to this one is posted (one entry per asset per month, dated the month end). Running again posts nothing new.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
            if (_busy && _preview == null) const LinearProgressIndicator(),
            if (_preview != null) ...[
              Text('${summary['entries'] ?? 0} entr${summary['entries'] == 1 ? 'y' : 'ies'} for ${summary['assets'] ?? 0} asset(s), total ${_money.format(_num(summary['total']))}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: lines
                      .map((l) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${l['name']}${(l['asset_code'] ?? '').toString().isEmpty ? '' : ' (${l['asset_code']})'}'),
                            subtitle: Text('${l['period']} · dated ${l['entry_date']}'),
                            trailing: Text(_money.format(_num(l['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _do(() => widget.api.reverseDepreciation(_period), 'Depreciation for $_period reversed.'),
          child: Text('Reverse $_period'),
        ),
        TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Close')),
        FilledButton(
          onPressed: _busy || lines.isEmpty ? null : () => _do(() => widget.api.runDepreciation(_period), 'Depreciation posted through $_period.'),
          child: const Text('Post Depreciation'),
        ),
      ],
    );
  }
}

// ── small widgets ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppTheme.success,
      'disposed' => AppTheme.warning,
      _ => AppTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
