import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/partner_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum OwnerEntryKind { capital, drawings }

/// Dedicated in-shell form for owner capital (CAPITAL_IN) and owner drawings
/// (OWNER_DRAWINGS). Hosted inside Cash Ledger → Owner Equity so the desktop
/// sidebar stays visible; it never pushes or pops a route.
///
/// Posting rules (enforced by the backend, previewed here):
///   capital  → DR cash/payment account, CR 3000 Owner's Capital
///   drawings → DR 3010 Owner's Drawings, CR cash/payment account
class OwnerEntryForm extends StatefulWidget {
  final OwnerEntryKind kind;

  /// Current lifetime figures from the Owner Equity summary, used for the
  /// "now → after this entry" projection. Keys: capital_contributed,
  /// drawings, net_owner_equity.
  final Map<String, dynamic> summary;

  /// `true` after a successful save, `false` on cancel.
  final ValueChanged<bool> onClose;

  const OwnerEntryForm({super.key, required this.kind, required this.summary, required this.onClose});

  @override
  State<OwnerEntryForm> createState() => _OwnerEntryFormState();
}

class _OwnerEntryFormState extends State<OwnerEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _money = const AppMoneyFormatter();

  late final CashLedgerService _ledger;
  late final PartnerService _partnersApi;

  DateTime _date = DateTime.now();
  String _method = 'cash';
  bool _allowNegativeCash = false;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _partners = const [];
  bool _partnersLoaded = false;
  int? _partnerId;

  bool get _isCapital => widget.kind == OwnerEntryKind.capital;
  String get _category => _isCapital ? 'CAPITAL_IN' : 'OWNER_DRAWINGS';
  Color get _accent => _isCapital ? AppTheme.success : AppTheme.warning;
  bool get _partnerRequired => _partners.length > 1;
  double get _amount => double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token ?? '';
    _ledger = CashLedgerService(token: token);
    _partnersApi = PartnerService(token: token);
    _amountCtrl.addListener(() => setState(() {}));
    _loadPartners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    try {
      final data = await _partnersApi.list(activeOnly: true);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(
        (data['partners'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      setState(() {
        _partners = rows;
        _partnersLoaded = true;
        if (rows.length == 1) _partnerId = (rows.first['id'] as num).toInt();
      });
    } catch (_) {
      // Partners are optional; without them the entry is single-owner.
      if (mounted) setState(() => _partnersLoaded = true);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
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
    if (_saving) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _ledger.createEntry(
        category: _category,
        amount: _amount.toStringAsFixed(2),
        txnDate: _fmtDate(_date),
        method: _method,
        referenceName: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        allowNegativeCash: _allowNegativeCash,
        partnerId: _partnerId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isCapital ? 'Owner capital recorded.' : 'Owner drawings recorded.')),
      );
      widget.onClose(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  num _summaryNum(String key) => num.tryParse('${widget.summary[key] ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1100;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        ...posSaveShortcuts(_submit),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_saving) widget.onClose(false);
        },
      },
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                      const SizedBox(height: 16),
                    ],
                    wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: _buildEntryColumn()),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _buildEffectColumn()),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildEntryColumn(),
                              const SizedBox(height: 16),
                              _buildEffectColumn(),
                            ],
                          ),
                    const SizedBox(height: 16),
                    _buildActions(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return EnterprisePanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Owner Equity (Esc)',
            onPressed: _saving ? null : () => widget.onClose(false),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 6),
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(color: _accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Icon(_isCapital ? Icons.account_balance_rounded : Icons.person_remove_alt_1_rounded, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCapital ? 'Record Owner Capital' : 'Record Owner Drawings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.2),
                ),
                const SizedBox(height: 2),
                Text(
                  _isCapital
                      ? 'Money the owner puts into the business. It increases owner equity — it is not sales income.'
                      : 'Money the owner takes out for personal use. It reduces owner equity — it is not a business expense.',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Badge(
            label: _isCapital ? 'Cash In' : 'Cash Out',
            icon: _isCapital ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: _accent,
          ),
        ],
      ),
    );
  }

  Widget _buildEntryColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseSectionHeader(
                title: 'Entry details',
                subtitle: 'Amount, date and who this belongs to.',
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.3),
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.payments_rounded, color: _accent),
                ),
                validator: (_) => _amount <= 0 ? 'Enter an amount greater than zero' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_rounded)),
                        child: Text(_fmtDate(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  if (_partners.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(child: _buildPartnerField()),
                  ],
                ],
              ),
              if (!_partnersLoaded) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _referenceCtrl,
                decoration: InputDecoration(
                  labelText: _partnerId != null ? 'Reference (optional)' : 'Owner / reference name *',
                  hintText: _isCapital ? 'e.g. Owner investment, bank transfer ref' : 'e.g. Personal withdrawal',
                  prefixIcon: const Icon(Icons.badge_rounded),
                ),
                validator: (v) => (_partnerId == null && (v == null || v.trim().isEmpty))
                    ? 'Enter the owner name or a reference'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnterpriseSectionHeader(
                title: _isCapital ? 'Received into' : 'Paid from',
                subtitle: 'The drawer or account the money moves through.',
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.teal,
              ),
              const SizedBox(height: 14),
              Builder(builder: (context) {
                final methods = context.watch<PaymentMethodProvider>().activeMethods;
                if (methods.isEmpty) {
                  return const Text('No payment methods configured for this branch.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
                }
                return Wrap(
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
                );
              }),
              if (!_isCapital && context.watch<PaymentMethodProvider>().affectsCashDrawer(_method)) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowNegativeCash,
                  onChanged: (v) => setState(() => _allowNegativeCash = v),
                  title: const Text('Allow negative cash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: const Text('Override the cash-on-hand check (needs approval permission).',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPartnerField() {
    return DropdownButtonFormField<int>(
      initialValue: _partnerId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _partnerRequired ? 'Partner *' : 'Partner',
        prefixIcon: const Icon(Icons.handshake_rounded),
      ),
      items: _partners
          .map((p) => DropdownMenuItem<int>(
                value: (p['id'] as num).toInt(),
                child: Text('${p['name']}  ·  ${p['ownership_percent']}%', overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() => _partnerId = v),
      validator: (v) => _partnerRequired && v == null ? 'Select the partner' : null,
    );
  }

  Widget _buildEffectColumn() {
    final methodName = context.watch<PaymentMethodProvider>().displayNameFor(_method);
    final amount = _amount;
    final equityAccount = _isCapital ? "3000 · Owner's Capital" : "3010 · Owner's Drawings";
    final debit = _isCapital ? methodName : equityAccount;
    final credit = _isCapital ? equityAccount : methodName;

    final capitalNow = _summaryNum('capital_contributed');
    final drawingsNow = _summaryNum('drawings');
    final netNow = _summaryNum('net_owner_equity');
    final netAfter = _isCapital ? netNow + amount : netNow - amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseSectionHeader(
                title: 'Accounting effect',
                subtitle: 'The journal entry this will post.',
                icon: Icons.account_tree_rounded,
                color: AppTheme.info,
              ),
              const SizedBox(height: 14),
              _JournalLine(side: 'DR', account: debit, amount: _money.format(amount), color: AppTheme.info),
              const SizedBox(height: 8),
              _JournalLine(side: 'CR', account: credit, amount: _money.format(amount), color: AppTheme.purple),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.surfaceSoft, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isCapital
                            ? 'Not income: excluded from Profit & Loss. Shows under Equity on the Balance Sheet.'
                            : 'Not an expense: excluded from Profit & Loss and the expense report. Reduces Equity on the Balance Sheet.',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseSectionHeader(
                title: 'Owner equity',
                subtitle: 'Current position and the result after saving.',
                icon: Icons.savings_rounded,
                color: AppTheme.success,
              ),
              const SizedBox(height: 14),
              _ValueRow(label: 'Capital contributed', value: _money.format(capitalNow + (_isCapital ? amount : 0))),
              _ValueRow(label: 'Owner drawings', value: _money.format(drawingsNow + (_isCapital ? 0 : amount))),
              const Divider(height: 22),
              _ValueRow(label: 'Net owner equity now', value: _money.format(netNow), muted: true),
              _ValueRow(
                label: 'After this entry',
                value: _money.format(netAfter),
                emphasize: true,
                color: netAfter < 0 ? AppTheme.danger : _accent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return EnterprisePanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.keyboard_rounded, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Ctrl+S to save · Esc to go back', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ),
          OutlinedButton(
            onPressed: _saving ? null : () => widget.onClose(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_isCapital ? 'Save Capital' : 'Save Drawings'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Badge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _JournalLine extends StatelessWidget {
  final String side;
  final String account;
  final String amount;
  final Color color;

  const _JournalLine({required this.side, required this.account, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
            child: Text(side, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(account, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  final bool emphasize;
  final Color? color;

  const _ValueRow({required this.label, required this.value, this.muted = false, this.emphasize = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  color: muted ? AppTheme.textMuted : null,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                )),
          ),
          Text(value,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                fontSize: emphasize ? 17 : 14,
                color: color ?? (muted ? AppTheme.textMuted : null),
              )),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600))),
          IconButton(onPressed: onDismiss, icon: const Icon(Icons.close_rounded, size: 18), color: AppTheme.danger),
        ],
      ),
    );
  }
}
