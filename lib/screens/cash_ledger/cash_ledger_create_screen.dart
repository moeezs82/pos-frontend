import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/partner_service.dart';
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

/// Addon keys used to gate loan and qameti categories. Kept as top-level
/// constants so they match BranchAddonService values without importing backend.
const _kAddonLoan    = 'loan_module';
const _kAddonQameti  = 'qameti_module';
const _kAddonOwnerEquity = 'owner_equity';
const _kAddonExtendedAccounts = 'extended_accounts';

/// Owner capital/drawings also need this permission (backend enforces it).
const kOwnerEquityPermission = 'manage-owner-equity';

/// Loans payable / accruals / prepayments also need this permission (backend
/// enforces it, for void too).
const kExtendedAccountsPermission = 'manage-extended-accounts';

/// Metadata for each cash-ledger category, kept in one place so the form and
/// the list screen render them consistently.
class CashLedgerCategoryMeta {
  final String value; // backend enum
  final String label;
  final String direction; // in | out | none (no cash leg)
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

  /// Accruals and prepaid recognition post DR expense / CR 2310 or 1500 with
  /// no cash leg: no payment method, no drawer check, no register shift.
  bool get isNonCash => direction == 'none';

  /// The addon key this category requires, or null if no addon is needed.
  String? get requiredAddon => switch (value) {
    'LOAN_GIVEN' || 'LOAN_RECOVERED' => _kAddonLoan,
    'QAMETI_PAYMENT' || 'QAMETI_COLLECTION' => _kAddonQameti,
    'CAPITAL_IN' || 'OWNER_DRAWINGS' || 'OWNER_CAPITAL_REASSIGN' => _kAddonOwnerEquity,
    'LOAN_RECEIVED' || 'LOAN_REPAID' || 'ACCRUED_EXPENSE' || 'ACCRUED_PAYMENT' ||
    'PREPAID_PAYMENT' || 'PREPAID_EXPENSE_RECOGNISE' => _kAddonExtendedAccounts,
    _ => null,
  };

  /// The extra permission this category requires, or null.
  String? get requiredPermission => switch (value) {
    'CAPITAL_IN' || 'OWNER_DRAWINGS' || 'OWNER_CAPITAL_REASSIGN' => kOwnerEquityPermission,
    'LOAN_RECEIVED' || 'LOAN_REPAID' || 'ACCRUED_EXPENSE' || 'ACCRUED_PAYMENT' ||
    'PREPAID_PAYMENT' || 'PREPAID_EXPENSE_RECOGNISE' => kExtendedAccountsPermission,
    _ => null,
  };

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
    // Owner equity (add-on owner_equity). Listed last so the Ctrl+1..5
    // shortcuts of the existing categories keep their positions.
    CashLedgerCategoryMeta(
      value: 'CAPITAL_IN',
      label: 'Owner Capital',
      direction: 'in',
      icon: Icons.account_balance_rounded,
      color: AppTheme.success,
      hint: 'Money the owner puts into the business. Not income — it increases owner equity.',
    ),
    CashLedgerCategoryMeta(
      value: 'OWNER_DRAWINGS',
      label: 'Owner Drawings',
      direction: 'out',
      icon: Icons.person_remove_alt_1_rounded,
      color: AppTheme.warning,
      hint: 'Money the owner takes out for personal use. Not an expense — it reduces owner equity.',
    ),
    // Loans payable, accruals, prepayments (add-on extended_accounts).
    CashLedgerCategoryMeta(
      value: 'LOAN_RECEIVED',
      label: 'Loan Received',
      direction: 'in',
      icon: Icons.call_received_rounded,
      color: AppTheme.info,
      hint: 'Money borrowed by the business. Not income — it is owed back to the lender (Loans Payable).',
    ),
    CashLedgerCategoryMeta(
      value: 'LOAN_REPAID',
      label: 'Loan Repaid',
      direction: 'out',
      icon: Icons.call_made_rounded,
      color: AppTheme.warning,
      hint: 'Repayment of money the business borrowed. Not an expense — it reduces Loans Payable.',
    ),
    CashLedgerCategoryMeta(
      value: 'ACCRUED_EXPENSE',
      label: 'Accrued Expense',
      direction: 'none',
      icon: Icons.pending_actions_rounded,
      color: AppTheme.purple,
      hint: 'An expense incurred but not yet paid (e.g. this month\'s electricity bill). No cash moves now.',
    ),
    CashLedgerCategoryMeta(
      value: 'ACCRUED_PAYMENT',
      label: 'Pay Accrued Expense',
      direction: 'out',
      icon: Icons.task_alt_rounded,
      color: AppTheme.danger,
      hint: 'Paying an expense that was already accrued. Clears Accrued Expenses; not a new expense.',
    ),
    CashLedgerCategoryMeta(
      value: 'PREPAID_PAYMENT',
      label: 'Prepaid Expense',
      direction: 'out',
      icon: Icons.event_available_rounded,
      color: AppTheme.danger,
      hint: 'Paying in advance for a future period (e.g. yearly rent or insurance). Becomes an expense later.',
    ),
    CashLedgerCategoryMeta(
      value: 'PREPAID_EXPENSE_RECOGNISE',
      label: 'Recognise Prepaid',
      direction: 'none',
      icon: Icons.update_rounded,
      color: AppTheme.purple,
      hint: 'Move the used-up part of a prepayment into expenses for this period. No cash moves now.',
    ),
  ];

  /// Reassign unassigned capital to a partner (DR 3000 untagged / CR 3000
  /// partner, no cash). Not in [all]: it cannot be created from this form,
  /// only from Owner Equity → Reassign to partner
  /// (POST /owner-equity/reassign-capital).
  static const capitalReassign = CashLedgerCategoryMeta(
    value: 'OWNER_CAPITAL_REASSIGN',
    label: 'Capital Reassigned to Partner',
    direction: 'none',
    icon: Icons.swap_horiz_rounded,
    color: AppTheme.purple,
    hint: 'Moves capital recorded without a partner to a partner. No cash moves.',
  );

  static CashLedgerCategoryMeta byValue(String value) => value == capitalReassign.value
      ? capitalReassign
      : all.firstWhere((c) => c.value == value, orElse: () => all.first);
}

class CashLedgerCreateScreen extends StatefulWidget {
  /// Optionally pre-select a category when launched from a shortcut.
  final String? initialCategory;

  /// When true, the pre-selected category cannot be changed. Used by focused
  /// module flows such as Expenses -> Add Expense. Existing callers default
  /// to false and retain the full multi-category cash-ledger form.
  final bool lockCategory;

  /// Embedded mode: when set, the form is hosted inside another workspace
  /// view (e.g. Cash Ledger → Owner Equity) instead of being a pushed route.
  /// Called with `true` after a successful save and `false` on cancel/close,
  /// in place of popping the navigator.
  final ValueChanged<bool>? onClose;

  const CashLedgerCreateScreen({
    super.key,
    this.initialCategory,
    this.lockCategory = false,
    this.onClose,
  });

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

  // Partner selector (CAPITAL_IN / OWNER_DRAWINGS only). The backend requires a
  // partner once the branch has more than one active partner and assigns the
  // only one automatically; the form mirrors that.
  late final PartnerService _partnersApi;
  List<Map<String, dynamic>> _partners = [];
  int? _partnerId;
  bool _partnersLoaded = false;
  String? _partnersError;

  static bool _isOwnerValue(String v) => v == 'CAPITAL_IN' || v == 'OWNER_DRAWINGS';
  bool get _isOwner => _isOwnerValue(_category);
  bool get _partnerRequired => _isOwner && _partners.length > 1;

  // Expense-account selector state (only used when category == OTHER_EXPENSE).
  static const _defaultExpenseCode = '5300';
  List<Map<String, dynamic>> _expenseAccounts = [];
  String? _expenseAccountCode;
  bool _expenseLoading = false;
  bool _expenseLoadedOnce = false;
  String? _expenseError; // non-null => load failed (distinct from "empty")

  bool get _expenseSelectionReady =>
      !_isExpense || (!_expenseLoading && _expenseError == null && _expenseAccountCode != null);

  /// Categories that debit an expense head chosen with the expense selector.
  static bool _isExpenseValue(String v) =>
      v == 'OTHER_EXPENSE' || v == 'ACCRUED_EXPENSE' || v == 'PREPAID_EXPENSE_RECOGNISE';
  bool get _isExpense => _isExpenseValue(_category);

  CashLedgerCategoryMeta get _meta => CashLedgerCategoryMeta.byValue(_category);

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final available = _availableCategories(auth);
    // If the requested initialCategory is gated off, fall back to the first
    // available category so the screen always opens in a valid state.
    final requested = widget.initialCategory ?? CashLedgerCategoryMeta.all.first.value;
    _category = available.any((c) => c.value == requested)
        ? requested
        : (available.isNotEmpty ? available.first.value : CashLedgerCategoryMeta.all.last.value);
    final token = auth.token!;
    _service = CashLedgerService(token: token);
    _accountsApi = AccountService(token: token);
    _partnersApi = PartnerService(token: token);
    if (_isExpense) _loadExpenseAccounts();
    if (_isOwner) _loadPartners();
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

  /// Returns the subset of categories the current user is allowed to create,
  /// based on which addons are active for their branch. OTHER_EXPENSE is always
  /// included because it requires no addon.
  List<CashLedgerCategoryMeta> _availableCategories(AuthProvider auth) {
    return CashLedgerCategoryMeta.all.where((c) {
      final addon = c.requiredAddon;
      final permission = c.requiredPermission;
      return (addon == null || auth.hasAddon(addon)) &&
          (permission == null || auth.hasPermission(permission));
    }).toList();
  }

  /// Ctrl+1..Ctrl+5 jump straight to a category by its position in the
  /// visible chip list. Index is relative to available categories only, so
  /// gated categories do not shift the numbering of accessible ones.
  void _selectCategoryByIndex(int index) {
    if (widget.lockCategory) return;
    final auth = context.read<AuthProvider>();
    final available = _availableCategories(auth);
    if (index < 0 || index >= available.length) return;
    _applyCategory(available[index].value);
  }

  static bool _isLoanValue(String v) =>
      v == 'LOAN_GIVEN' || v == 'LOAN_RECOVERED' || v == 'LOAN_RECEIVED' || v == 'LOAN_REPAID';
  bool get _isLoan => _isLoanValue(_category);

  /// Loans payable: the linked party is the LENDER, not a borrower.
  bool get _isLender => _category == 'LOAN_RECEIVED' || _category == 'LOAN_REPAID';

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
      // Expense account only applies to expense-debiting categories; clear
      // when leaving, and restore the default when coming back.
      if (!_isExpenseValue(value)) {
        _expenseAccountCode = null;
      } else if (_expenseAccountCode == null && _expenseAccounts.any((a) => a['code']?.toString() == _defaultExpenseCode)) {
        _expenseAccountCode = _defaultExpenseCode;
      }
    });
    if (_isExpenseValue(value)) _loadExpenseAccounts();
    if (_isOwnerValue(value)) _loadPartners();
  }

  Future<void> _loadPartners() async {
    if (_partnersLoaded) return;
    try {
      final data = await _partnersApi.list(activeOnly: true);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(
        (data['partners'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      setState(() {
        _partners = rows;
        _partnersLoaded = true;
        _partnersError = null;
        if (rows.length == 1) _partnerId = (rows.first['id'] as num).toInt();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _partnersError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _buildPartnerSelector() {
    if (_partnersError != null) {
      return Text('Could not load partners: $_partnersError', style: const TextStyle(color: AppTheme.danger));
    }
    if (!_partnersLoaded) return const LinearProgressIndicator();
    if (_partners.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<int>(
      initialValue: _partnerId,
      decoration: InputDecoration(
        labelText: _partnerRequired ? 'Partner *' : 'Partner',
        prefixIcon: const Icon(Icons.handshake_rounded),
      ),
      items: _partners
          .map((p) => DropdownMenuItem<int>(
                value: (p['id'] as num).toInt(),
                child: Text('${p['name']} (${p['ownership_percent']}%)'),
              ))
          .toList(),
      onChanged: (v) => setState(() => _partnerId = v),
      validator: (v) => _partnerRequired && v == null ? 'Select which partner this belongs to' : null,
    );
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
      _showMessage(_isLender ? 'Please select the lender from the list.' : 'Please select the borrower from the list.');
      return;
    }
    if (_partnerRequired && _partnerId == null) {
      _showMessage('Select which partner this capital or drawing belongs to.');
      return;
    }
    final hasPartner = _isOwner && _partnerId != null;
    if (!hasParty && !hasPartner && _referenceCtrl.text.trim().isEmpty) {
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
        partnerId: _isOwner ? _partnerId : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_meta.label} recorded successfully.')),
      );
      _close(true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close([bool saved = false]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(saved);
    } else if (saved) {
      Navigator.pop(context, true);
    } else {
      Navigator.pop(context);
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
            if (!_saving) _close();
          },
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: widget.onClose == null,
            title: Text(widget.onClose == null ? 'Cash Ledger Entry' : _meta.label),
            actions: [
              IconButton(
                tooltip: 'Keyboard shortcuts',
                onPressed: () => showAppShortcutGuide(context, extra: PosShortcutCatalog.cashLedgerCreate),
                icon: const Icon(Icons.keyboard_rounded),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => _close(),
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
                    onPressed: _saving ? null : () => _close(),
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
          Builder(builder: (context) {
            final auth = context.watch<AuthProvider>();
            final available = widget.lockCategory
                ? <CashLedgerCategoryMeta>[CashLedgerCategoryMeta.byValue(_category)]
                : _availableCategories(auth);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: available.map((c) {
                final selected = _category == c.value;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(c.icon, size: 18, color: selected ? c.color : AppTheme.textMuted),
                  label: Text(c.label),
                  onSelected: widget.lockCategory ? null : (_) => _applyCategory(c.value),
                );
              }).toList(),
            );
          }),
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
          if (_isOwner) ...[
            const SizedBox(height: 14),
            _buildPartnerSelector(),
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
              if (_partyKind == 'none' && !(_isOwner && _partnerId != null) && (value == null || value.trim().isEmpty)) {
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
        if (_meta.isNonCash)
          const EnterprisePanel(
            child: EnterpriseSectionHeader(
              title: 'No cash movement',
              subtitle: 'This entry only moves the amount between an expense account and a balance-sheet account. '
                  'It does not touch the cash drawer, the register shift or the day book.',
              icon: Icons.sync_alt_rounded,
              color: AppTheme.purple,
            ),
          )
        else
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
              EnterpriseSectionHeader(
                title: _isLender ? 'Lender' : 'Borrower',
                subtitle: _isLender
                    ? 'Who lent the money to the business / is being repaid. Required for loans payable.'
                    : 'Who received / is repaying the loan. Required for loan entries.',
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
    final color = meta.isNonCash ? AppTheme.purple : (inflow ? AppTheme.success : AppTheme.danger);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(meta.isNonCash ? Icons.sync_alt_rounded : (inflow ? Icons.south_west_rounded : Icons.north_east_rounded), color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${meta.isNonCash ? 'NO CASH' : (inflow ? 'Cash IN' : 'Cash OUT')} — ${meta.hint}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
