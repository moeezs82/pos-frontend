import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/partner_service.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Reassign unassigned owner capital to a partner (phase 7a).
///
/// Capital recorded before any partner existed is not tagged to anyone. This
/// moves it to a partner with no cash movement (DR 3000 untagged / CR 3000
/// partner). The backend re-checks the partner, the available amount and the
/// period lock; this dialog only pre-fills and shows the result.
///
/// Returns `true` from [showDialog] after a successful reassignment.
class CapitalReassignDialog extends StatefulWidget {
  final CashLedgerService service;
  final PartnerService partners;

  /// Unassigned capital available today (pre-fills the amount).
  final num unassigned;

  const CapitalReassignDialog({super.key, required this.service, required this.partners, required this.unassigned});

  @override
  State<CapitalReassignDialog> createState() => _CapitalReassignDialogState();
}

class _CapitalReassignDialogState extends State<CapitalReassignDialog> {
  final _formKey = GlobalKey<FormState>();
  final _money = const AppMoneyFormatter();
  late final TextEditingController _amount;
  final _note = TextEditingController();

  bool _loadingPartners = true;
  List<Map<String, dynamic>> _activePartners = const [];
  int? _partnerId;

  /// Null = today (the server default). Set only when the user back-dates.
  DateTime? _backDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.unassigned.toStringAsFixed(2));
    _loadPartners();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    try {
      final data = await widget.partners.list(activeOnly: true);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(
        (data['partners'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      setState(() {
        _activePartners = rows;
        if (rows.length == 1) _partnerId = (rows.first['id'] as num).toInt();
        _loadingPartners = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPartners = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _backDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _backDate = picked);
  }

  String _friendlyError(Object e) {
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

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amount = double.parse(_amount.text.trim());
      await widget.service.reassignCapital(
        partnerId: _partnerId!,
        amount: amount.toStringAsFixed(2),
        entryDate: _backDate == null ? null : _fmtDate(_backDate!),
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final noPartners = !_loadingPartners && _activePartners.isEmpty;
    return AlertDialog(
      title: const Text('Reassign capital to partner'),
      content: SizedBox(
        width: 440,
        child: _loadingPartners
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unassigned capital: ${_money.format(widget.unassigned)}. '
                        'This moves it to a partner\'s capital. No cash moves and total equity does not change.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      if (noPartners)
                        const Text(
                          'There are no active partners. Add the partner first (Owner Equity → Partners).',
                          style: TextStyle(color: AppTheme.danger),
                        )
                      else ...[
                        DropdownButtonFormField<int>(
                          initialValue: _partnerId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Partner *'),
                          items: _activePartners
                              .map((p) => DropdownMenuItem<int>(
                                    value: (p['id'] as num).toInt(),
                                    child: Text('${p['name']} (${p['ownership_percent']}%)', overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: _saving ? null : (v) => setState(() => _partnerId = v),
                          validator: (v) => v == null ? 'Select the partner' : null,
                        ),
                        TextFormField(
                          controller: _amount,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Amount *'),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null) return 'Enter a number';
                            if (n <= 0) return 'Must be greater than 0';
                            if (n > widget.unassigned + 0.005) return 'Cannot exceed ${_money.format(widget.unassigned)}';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _backDate == null ? 'Date: today' : 'Date: ${_fmtDate(_backDate!)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _saving ? null : _pickDate,
                              icon: const Icon(Icons.event_rounded, size: 18),
                              label: Text(_backDate == null ? 'Back-date' : 'Change'),
                            ),
                            if (_backDate != null)
                              IconButton(
                                tooltip: 'Use today',
                                onPressed: _saving ? null : () => setState(() => _backDate = null),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                          ],
                        ),
                        Text(
                          'Today changes partner statements from today on. Back-dating to the original capital date also '
                          'corrects earlier statements, but cannot be inside a locked period.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                        ),
                        TextFormField(
                          controller: _note,
                          enabled: !_saving,
                          maxLength: 2000,
                          decoration: const InputDecoration(labelText: 'Note', counterText: ''),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving || _loadingPartners || noPartners ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Reassign'),
        ),
      ],
    );
  }
}
