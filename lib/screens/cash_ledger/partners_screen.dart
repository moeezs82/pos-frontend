import 'package:enterprise_pos/api/partner_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_ledger_create_screen.dart' show kOwnerEquityPermission;
import 'package:enterprise_pos/screens/reports/enterprise_reports_workspace_screen.dart';
import 'package:enterprise_pos/services/app_navigator.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Business partners / co-owners of the active branch (add-on `owner_equity`).
///
/// Partners are never deleted — deactivate instead, so historical capital and
/// drawings keep their owner. Active ownership cannot exceed 100% (enforced by
/// the backend; the error is shown as returned).
class PartnersScreen extends StatefulWidget {
  /// Embedded mode (inside the Cash Ledger workspace): shows a Back button that
  /// calls this instead of relying on a pushed route.
  final VoidCallback? onBack;

  const PartnersScreen({super.key, this.onBack});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  late final PartnerService _api;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _partners = [];
  num _activeTotal = 0;

  @override
  void initState() {
    super.initState();
    _api = PartnerService(token: context.read<AuthProvider>().token ?? '');
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.list();
      if (!mounted) return;
      setState(() {
        _partners = List<Map<String, dynamic>>.from(
          (data['partners'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _activeTotal = num.tryParse('${data['active_ownership_percent_total'] ?? 0}') ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _errorText(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _edit([Map<String, dynamic>? partner]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PartnerDialog(api: _api, partner: partner, errorText: _errorText),
    );
    if (saved == true) _fetch();
  }

  Future<void> _toggleActive(Map<String, dynamic> partner) async {
    final active = partner['status'] == 'active';
    try {
      await _api.update((partner['id'] as num).toInt(), {'status': active ? 'inactive' : 'active'});
      _fetch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.hasPermission(kOwnerEquityPermission);
    final canReport = auth.hasPermission('view-reports');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.onBack == null,
        leading: widget.onBack == null
            ? null
            : IconButton(tooltip: 'Back to Owner Equity', icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack),
        title: const Text('Partners'),
        actions: [
          if (canReport)
            TextButton.icon(
              // Reports open as a shell workspace (sidebar stays visible).
              onPressed: () => PosNavigation.openSingleton(
                routeId: PosRouteIds.report('partner-statement'),
                builder: (_) => const EnterpriseReportsWorkspaceScreen(initialReportKey: 'partner-statement'),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Partner Statement'),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Partner'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      Text(
                        'Active ownership allocated: ${_activeTotal.toStringAsFixed(2)}% of 100%. '
                        'Profit share in reports and profit allocation use these percentages.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      // Profit allocation (phase 7) is refused by the backend
                      // unless active partners add up to exactly 100%.
                      if (_partners.isNotEmpty && (_activeTotal - 100).abs() >= 0.005) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.warning.withValues(alpha: .45)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Active partners add up to ${_activeTotal.toStringAsFixed(2)}%, not 100%. '
                                  'Profit cannot be allocated to partners until the active percentages total exactly 100%.',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_partners.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(child: Text('No partners yet. Without partners, owner capital and drawings stay single-owner.')),
                        ),
                      ..._partners.map((p) {
                        final active = p['status'] == 'active';
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: (active ? AppTheme.success : Colors.grey).withValues(alpha: .15),
                              child: Icon(Icons.handshake_rounded, color: active ? AppTheme.success : Colors.grey),
                            ),
                            title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              '${p['ownership_percent']}%',
                              if ((p['phone'] ?? '').toString().isNotEmpty) '${p['phone']}',
                              if (!active) 'Inactive',
                            ].join(' • ')),
                            trailing: canManage
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded), onPressed: () => _edit(p)),
                                    IconButton(
                                      tooltip: active ? 'Deactivate' : 'Reactivate',
                                      icon: Icon(active ? Icons.block_rounded : Icons.check_circle_outline_rounded),
                                      onPressed: () => _toggleActive(p),
                                    ),
                                  ])
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class _PartnerDialog extends StatefulWidget {
  final PartnerService api;
  final Map<String, dynamic>? partner;
  final String Function(Object) errorText;

  const _PartnerDialog({required this.api, required this.partner, required this.errorText});

  @override
  State<_PartnerDialog> createState() => _PartnerDialogState();
}

class _PartnerDialogState extends State<_PartnerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pct;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.partner;
    _name = TextEditingController(text: p?['name']?.toString() ?? '');
    _pct = TextEditingController(text: p?['ownership_percent']?.toString() ?? '');
    _phone = TextEditingController(text: p?['phone']?.toString() ?? '');
    _notes = TextEditingController(text: p?['notes']?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _pct.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final pct = double.parse(_pct.text.trim());
    try {
      if (widget.partner == null) {
        await widget.api.create(name: _name.text.trim(), ownershipPercent: pct, phone: _phone.text, notes: _notes.text);
      } else {
        await widget.api.update((widget.partner!['id'] as num).toInt(), {
          'name': _name.text.trim(),
          'ownership_percent': pct,
          'phone': _phone.text.trim(),
          'notes': _notes.text.trim(),
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = widget.errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.partner == null ? 'Add Partner' : 'Edit Partner'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _pct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Ownership % *', helperText: 'Active partners together cannot exceed 100%.'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number';
                  if (n < 0 || n > 100) return 'Between 0 and 100';
                  return null;
                },
              ),
              TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
              TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
