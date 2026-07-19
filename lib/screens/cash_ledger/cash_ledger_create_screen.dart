import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/account_service.dart';
import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/user_picker_sheet.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Metadata for each cash-ledger category, kept in one place so the form and
/// the list screen render them consistently.
class CashLedgerCategoryMeta {
  final String value; // backend enum
  final String label;
  final String direction; // in | out
  final IconData icon;
  final Color color;
  final String hint;

  const CashLedgerCategoryMeta({
    required this.value,
    required this.label,
    required this.direction,
    required this.icon,
    required this.color,
    required this.hint,
  });

  bool get isInflow => direction == 'in';

  static const all = <CashLedgerCategoryMeta>[
    CashLedgerCategoryMeta(
      value: 'QAMETI_COLLECTION',
      label: 'Qameti Collection',
      direction: 'in',
      icon: Icons.savings_rounded,
      color: AppTheme.success,
      hint: 'Cash received as your committee/Qameti payout.',
    ),
    CashLedgerCategoryMeta(
      value: 'LOAN_RECOVERED',
      label: 'Loan Recovered',
      direction: 'in',
      icon: Icons.call_received_rounded,
      color: AppTheme.success,
      hint: 'Cash received back from someone you lent to.',
    ),
    CashLedgerCategoryMeta(
      value: 'QAMETI_PAYMENT',
      label: 'Qameti Payment',
      direction: 'out',
      icon: Icons.savings_outlined,
      color: AppTheme.warning,
      hint: 'Cash paid as your committee/Qameti installment.',
    ),
    CashLedgerCategoryMeta(
      value: 'LOAN_GIVEN',
      label: 'Loan Given',
      direction: 'out',
      icon: Icons.call_made_rounded,
      color: AppTheme.danger,
      hint: 'Cash lent out to a person or party.',
    ),
    CashLedgerCategoryMeta(
      value: 'OTHER_EXPENSE',
      label: 'Other Expense',
      direction: 'out',
      icon: Icons.receipt_long_rounded,
      color: AppTheme.danger,
      hint: 'Miscellaneous non-business cash expense.',
    ),
  ];

  static CashLedgerCategoryMeta byValue(String value) =>
      all.firstWhere((c) => c.value == value, orElse: () => all.first);
}

class CashLedgerCreateScreen extends StatefulWidget {
  /// Optionally pre-select a category when launched from a shortcut.
  final String? initialCategory;
  const CashLedgerCreateScreen({super.key, this.initialCategory});

  @override
  State<CashLedgerCreateScreen> createState() => _CashLedgerCreateScreenState();
}

class _CashLedgerCreateScreenState extends State<CashLedgerCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();

  late final CashLedgerService _service;
  late final AccountService _accountsApi;

  bool _saving = false;

  late String _category;
  String _method = 'cash';
  DateTime _txnDate = DateTime.now();
  bool _allowNegativeCash = false;

  String _partyKind = 'none'; // none|customer|vendor|user
  Map<String, dynamic>? _selectedParty;

  // Expense-account selector state (only used when category == OTHER_EXPENSE).
  static const _defaultExpenseCode = '5300';
  List<Map<String, dynamic>> _expenseAccounts = [];
  String? _expenseAccountCode;
  bool _expenseLoading = false;
  bool _expenseLoadedOnce = false;
  String? _expenseError; // non-null => load failed (distinct from "empty")

  bool get _expenseSelectionReady =>
      !_isExpense || (!_expenseLoading && _expenseError == null && _expenseAccountCode != null);

  bool get _isExpense => _category == 'OTHER_EXPENSE';

  CashLedgerCategoryMeta get _meta => CashLedgerCategoryMeta.byValue(_category);

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? CashLedgerCategoryMeta.all.first.value;
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _accountsApi = AccountService(token: token);
    if (_isExpense) _loadExpenseAccounts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  /// Load the eligible EXPENSE accounts from the dedicated operational endpoint.
  /// Never swallows failures into an empty list: an error is surfaced with a
  /// Retry action so we don't claim "no accounts exist" when the call failed.
  Future<void> _loadExpenseAccounts({bool force = false}) async {
    if (_expenseLoading) return;
    if (_expenseLoadedOnce && !force && _expenseError == null) return;
    setState(() {
      _expenseLoading = true;
      _expenseError = null;
    });
    try {
      final items = await _accountsApi.getExpenseOptions();
      if (!mounted) return;
      setState(() {
        _expenseAccounts = items;
        _expenseLoadedOnce = true;
        final codes = items
            .map((a) => a['code']?.toString())
            .whereType<String>()
            .toSet();
        // Drop a previously-selected code that is no longer eligible.
        if (_expenseAccountCode != null && !codes.contains(_expenseAccountCode)) {
          _expenseAccountCode = null;
        }
        // Default to 5300 only if it is actually eligible and returned.
        _expenseAccountCode ??= codes.contains(_defaultExpenseCode)
            ? _defaultExpenseCode
            : (items.isNotEmpty ? items.first['code']?.toString() : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _expenseError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _expenseLoading = false);
    }
  }

  /// State-aware expense-account picker: loading, load-error+retry, a genuine
  /// empty state, or the dropdown. Never renders an empty dropdown for a failed
  /// or in-flight load.
  Widget _buildExpenseSelector() {
    if (_expenseLoading && _expenseAccounts.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Expense account *',
          prefixIcon: Icon(Icons.account_tree_rounded),
        ),
        child: Row(
          children: const [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading expense accounts…'),
          ],
        ),
      );
    }

    if (_expenseError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.danger.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.danger.withOpacity(.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not load expense accounts. $_expenseError',
                style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _expenseLoading ? null : () => _loadExpenseAccounts(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_expenseAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.textMuted, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No eligible expense accounts are configured. Ask an administrator to add an active expense account in the Chart of Accounts.',
                style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: () => _loadExpenseAccounts(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reload'),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: _expenseAccountCode,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Expense account *',
        prefixIcon: Icon(Icons.account_tree_rounded),
      ),
      items: _expenseAccounts
          .map((a) => DropdownMenuItem<String>(
                value: a['code']?.toString(),
                child: Text('${a['code']} · ${a['name']}',
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() => _expenseAccountCode = v),
      validator: (v) => (_isExpense && (v == null || v.isEmpty))
          ? 'Select an expense account'
          : null,
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  /// Ctrl+1..Ctrl+5 jump straight to a category by its position in the
  /// chip list, mirroring the type-to-select pattern used elsewhere.
  void _selectCategoryByIndex(int index) {
    final all = CashLedgerCategoryMeta.all;
    if (index < 0 || index >= all.length) return;
    _applyCategory(all[index].value);
  }

  static bool _isLoanValue(String v) => v == 'LOAN_GIVEN' || v == 'LOAN_RECOVERED';
  bool get _isLoan => _isLoanValue(_category);

  /// Change category and clear incompatible counterparty state so no stale
  /// party/ID is ever submitted. Only loan entries carry a (borrower) party;
  /// Qameti and Expense never attach a commercial party.
  void _applyCategory(String value) {
    setState(() {
      _category = value;
      if (_isLoanValue(value)) {
        if (_partyKind == 'none') _partyKind = 'customer';
      } else {
        _partyKind = 'none';
      }
      _selectedParty = null;
      // Expense account only applies to OTHER_EXPENSE; clear when leaving.
      if (value != 'OTHER_EXPENSE') {
        _expenseAccountCode = null;
      }
    });
    if (value == 'OTHER_EXPENSE') _loadExpenseAccounts();
  }

  /// F3 / Ctrl+Shift+P only does something once a party kind other than
  /// "none" is selected — otherwise there's nothing to pick.
  void _pickPartyShortcut() {
    if (_partyKind == 'none') return;
    _pickParty();
  }

  String _partyName(Map<String, dynamic>? party) {
    if (party == null) return 'No party selected';
    final first = (party['first_name'] ?? '').toString().trim();
    final last = (party['last_name'] ?? '').toString().trim();
    final name = (party['name'] ?? party['business_name'] ?? party['company_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : (name.isNotEmpty ? name : 'Party #${party["id"]}');
  }

  String? get _partyId {
    if (_partyKind == 'none' || _selectedParty == null) return null;
    return _selectedParty!['id']?.toString();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _txnDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked != null) setState(() => _txnDate = picked);
  }

  Future<void> _pickParty() async {
    final token = context.read<AuthProvider>().token!;
    final height = MediaQuery.of(context).size.height * .86;
    Widget? sheet;
    if (_partyKind == 'customer') {
      sheet = CustomerPickerSheet(token: token);
    } else if (_partyKind == 'vendor') {
      sheet = VendorPickerSheet(token: token);
    } else if (_partyKind == 'user') {
      sheet = UserPickerSheet(token: token, title: 'Select User');
    }
    if (sheet == null) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(height: height, child: sheet),
    );
    if (picked != null) setState(() => _selectedParty = picked);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Surface the backend's useful validation detail (e.g. "Insufficient cash on
  /// hand. Available: 500.00, requested: 600.00.") instead of a generic message.
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
    if (!_formKey.currentState!.validate()) return;

    // Expense entries require a real, eligible account. Guard here too so the
    // Ctrl+Enter shortcut can't post with a missing/failed-to-load account.
    if (_isExpense && !_expenseSelectionReady) {
      _showMessage(_expenseError != null
          ? 'Fix the expense account load error before saving.'
          : 'Select an expense account before saving.');
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      _showMessage('Amount must be greater than zero.');
      return;
    }

    // Only loan entries carry a (borrower) party. For Qameti/Expense we never
    // send a commercial party — the backend rejects it defensively too.
    final hasParty = _isLoan && _partyKind != 'none' && _selectedParty != null;
    if (_isLoan && _selectedParty == null) {
      _showMessage('Please select the borrower from the list.');
      return;
    }
    if (!hasParty && _referenceCtrl.text.trim().isEmpty) {
      _showMessage('Enter a reference / payee name.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.createEntry(
        category: _category,
        amount: amount.toStringAsFixed(2),
        txnDate: _fmtDate(_txnDate),
        method: _method,
        partyKind: hasParty ? _partyKind : null,
        partyId: hasParty ? _partyId : null,
        referenceName: _referenceCtrl.text.trim().isNotEmpty ? _referenceCtrl.text.trim() : null,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
        allowNegativeCash: _allowNegativeCash,
        expenseAccountCode: _isExpense ? _expenseAccountCode : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_meta.label} recorded successfully.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;

    return Focus(
      autofocus: true,
      skipTraversal: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          ...posSaveShortcuts(() {
            if (!_saving) _submit();
          }),
          posCtrl(LogicalKeyboardKey.digit1): () => _selectCategoryByIndex(0),
          posCtrl(LogicalKeyboardKey.digit2): () => _selectCategoryByIndex(1),
          posCtrl(LogicalKeyboardKey.digit3): () => _selectCategoryByIndex(2),
          posCtrl(LogicalKeyboardKey.digit4): () => _selectCategoryByIndex(3),
          posCtrl(LogicalKeyboardKey.digit5): () => _selectCategoryByIndex(4),
          posCtrl(LogicalKeyboardKey.numpad1): () => _selectCategoryByIndex(0),
          posCtrl(LogicalKeyboardKey.numpad2): () => _selectCategoryByIndex(1),
          posCtrl(LogicalKeyboardKey.numpad3): () => _selectCategoryByIndex(2),
          posCtrl(LogicalKeyboardKey.numpad4): () => _selectCategoryByIndex(3),
          posCtrl(LogicalKeyboardKey.numpad5): () => _selectCategoryByIndex(4),
          const SingleActivator(LogicalKeyboardKey.f3): _pickPartyShortcut,
          posCtrlShift(LogicalKeyboardKey.keyP): _pickPartyShortcut,
          posCmdShift(LogicalKeyboardKey.keyP): _pickPartyShortcut,
          posCtrl(LogicalKeyboardKey.keyD): () => _pickDate(),
          posCmd(LogicalKeyboardKey.keyD): () => _pickDate(),
          posCtrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.cashLedgerCreate),
          posCmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.cashLedgerCreate),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_saving) Navigator.pop(context);
          },
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Cash Ledger Entry'),
            actions: [
              IconButton(
                tooltip: 'Keyboard shortcuts',
                onPressed: () => showAppShortcutGuide(context, extra: PosShortcutCatalog.cashLedgerCreate),
                icon: const Icon(Icons.keyboard_rounded),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _buildMainPanel()),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: _buildPartyPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          _buildMainPanel(),
                          const SizedBox(height: 16),
                          _buildPartyPanel(),
                        ],
                      ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: (_saving || !_expenseSelectionReady) ? null : _submit,
                    icon: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save Entry  Ctrl+Enter'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnterpriseSectionHeader(
            title: 'Entry type',
            subtitle: 'Qameti, personal/party loans and other non-sales cash movements.',
            icon: Icons.swap_vert_rounded,
            color: _meta.color,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CashLedgerCategoryMeta.all.map((c) {
              final selected = _category == c.value;
              return ChoiceChip(
                selected: selected,
                avatar: Icon(c.icon, size: 18, color: selected ? c.color : AppTheme.textMuted),
                label: Text(c.label),
                onSelected: (_) => _applyCategory(c.value),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          _DirectionBanner(meta: _meta),
          const SizedBox(height: 18),
          TextFormField(
            controller: _amountCtrl,
            focusNode: _amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixIcon: Icon(Icons.payments_rounded),
              hintText: '0.00',
            ),
            validator: (value) {
              final amount = double.tryParse((value ?? '').replaceAll(',', '')) ?? 0;
              return amount <= 0 ? 'Enter a valid amount' : null;
            },
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Transaction date',
                prefixIcon: Icon(Icons.calendar_today_rounded),
              ),
              child: Text(_fmtDate(_txnDate), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          if (_isExpense) ...[
            const SizedBox(height: 14),
            _buildExpenseSelector(),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _referenceCtrl,
            decoration: InputDecoration(
              labelText: _isExpense
                  ? 'Payee / reference *'
                  : (_partyKind == 'none' ? 'Reference name *' : 'Reference / note name'),
              prefixIcon: const Icon(Icons.badge_rounded),
              hintText: _partyKind == 'none'
                  ? 'Who the money went to / came from (required)'
                  : 'Optional label',
            ),
            validator: (value) {
              if (_partyKind == 'none' && (value == null || value.trim().isEmpty)) {
                return 'Required when no party is linked';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _noteCtrl,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
              hintText: 'Example: committee #3 installment, lent for medical, etc.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyPanel() {
    return Column(
      children: [
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnterpriseSectionHeader(
                title: 'Cash source',
                subtitle: 'Which drawer/account the money moves through.',
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.teal,
              ),
              const SizedBox(height: 14),
              Builder(builder: (context) {
                final methods =
                    context.watch<PaymentMethodProvider>().activeMethods;
                if (methods.isEmpty) {
                  return const Text(
                    'No payment methods configured for this branch.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: methods.map((m) {
                    final selected = _method == m.method;
                    return ChoiceChip(
                      selected: selected,
                      avatar: Icon(m.icon, size: 18),
                      label: Text(m.displayName),
                      onSelected: (_) => setState(() => _method = m.method),
                    );
                  }).toList(),
                );
              }),
              if (!_meta.isInflow &&
                  (context.watch<PaymentMethodProvider>().affectsCashDrawer(_method))) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowNegativeCash,
                  onChanged: (v) => setState(() => _allowNegativeCash = v),
                  title: const Text('Allow negative cash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                  subtitle: const Text('Override the cash-on-hand safety check.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        // Counterparty is a BORROWER and only applies to loan entries. Qameti
        // and Other Expense never link a commercial party (they use the
        // reference / payee field), so this whole panel is hidden for them.
        if (_isLoan) ...[
        const SizedBox(height: 16),
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnterpriseSectionHeader(
                title: 'Borrower',
                subtitle: 'Who received / is repaying the loan. Required for loan entries.',
                icon: Icons.groups_2_rounded,
                color: AppTheme.warning,
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'customer', label: Text('Customer'), icon: Icon(Icons.person_rounded)),
                  ButtonSegment(value: 'vendor', label: Text('Vendor'), icon: Icon(Icons.storefront_rounded)),
                  ButtonSegment(value: 'user', label: Text('User'), icon: Icon(Icons.badge_rounded)),
                ],
                selected: {_partyKind == 'none' ? 'customer' : _partyKind},
                onSelectionChanged: (set) {
                  setState(() {
                    _partyKind = set.first;
                    _selectedParty = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(.1),
                      child: Icon(
                        _partyKind == 'vendor'
                            ? Icons.storefront_rounded
                            : _partyKind == 'customer'
                                ? Icons.person_rounded
                                : _partyKind == 'user'
                                    ? Icons.badge_rounded
                                    : Icons.receipt_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _partyKind == 'none' ? 'Unlinked entry' : _partyName(_selectedParty),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _partyKind == 'none'
                                ? 'Use the reference name field instead.'
                                : _selectedParty == null
                                    ? 'Select $_partyKind from the list.'
                                    : ((_selectedParty!['phone'] ?? _selectedParty!['email'] ?? '').toString()),
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (_partyKind != 'none')
                      IconButton.filledTonal(
                        onPressed: _pickParty,
                        icon: const Icon(Icons.search_rounded),
                        tooltip: 'Select $_partyKind',
                      ),
                  ],
                ),
              ),
              if (_partyKind != 'none') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickParty,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: Text('Choose ${_partyKind[0].toUpperCase()}${_partyKind.substring(1)}'),
                  ),
                ),
              ],
            ],
          ),
        ),
        ], // end if (_isLoan) borrower panel
      ],
    );
  }
}

class _DirectionBanner extends StatelessWidget {
  final CashLedgerCategoryMeta meta;
  const _DirectionBanner({required this.meta});

  @override
  Widget build(BuildContext context) {
    final inflow = meta.isInflow;
    final color = inflow ? AppTheme.success : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(inflow ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${inflow ? 'Cash IN' : 'Cash OUT'} — ${meta.hint}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
