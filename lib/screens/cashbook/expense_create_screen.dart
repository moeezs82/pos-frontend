import 'package:enterprise_pos/api/cashbook_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/customer_picker_sheet.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ExpenseCreateScreen extends StatefulWidget {
  const ExpenseCreateScreen({super.key});

  @override
  State<ExpenseCreateScreen> createState() => _ExpenseCreateScreenState();
}

class _ExpenseCreateScreenState extends State<ExpenseCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();

  late final CashBookService _cashBookService;

  List<Map<String, dynamic>> _accounts = [];
  bool _loadingAccounts = true;
  bool _saving = false;

  String? _accountId;
  String _method = 'cash';
  String _status = 'approved';
  DateTime _txnDate = DateTime.now();

  String _partyKind = 'none'; // none|customer|vendor
  Map<String, dynamic>? _selectedParty;

  static const _methods = [
    {'value': 'cash', 'label': 'Cash', 'icon': Icons.payments_rounded},
    {'value': 'bank', 'label': 'Bank', 'icon': Icons.account_balance_rounded},
    {'value': 'card', 'label': 'Card', 'icon': Icons.credit_card_rounded},
    {'value': 'wallet', 'label': 'Wallet', 'icon': Icons.account_balance_wallet_rounded},
  ];

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _cashBookService = CashBookService(token: token);
    _loadAccounts();
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

  Future<void> _loadAccounts() async {
    try {
      final rows = await _cashBookService.getAccounts(isActive: true);
      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _loadingAccounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accounts = [];
        _loadingAccounts = false;
      });
    }
  }

  String _fmtDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String _partyName(Map<String, dynamic>? party) {
    if (party == null) return 'No counterparty selected';
    final first = (party['first_name'] ?? '').toString().trim();
    final last = (party['last_name'] ?? '').toString().trim();
    final name = (party['name'] ?? party['business_name'] ?? party['company_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    return full.isNotEmpty ? full : (name.isNotEmpty ? name : 'Party #${party["id"]}');
  }

  String? get _counterpartyType {
    if (_partyKind == 'customer') return r'App\Models\Customer';
    if (_partyKind == 'vendor') return r'App\Models\Vendor';
    return null;
  }

  String? get _counterpartyId {
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
    if (_partyKind == 'customer') {
      final picked = await showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * .86,
          child: CustomerPickerSheet(token: token),
        ),
      );
      if (picked != null) setState(() => _selectedParty = picked);
    } else if (_partyKind == 'vendor') {
      final picked = await showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(
          height: MediaQuery.of(context).size.height * .86,
          child: VendorPickerSheet(token: token),
        ),
      );
      if (picked != null) setState(() => _selectedParty = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partyKind != 'none' && _selectedParty == null) {
      _showMessage('Please select the $_partyKind from backend list.');
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      _showMessage('Amount must be greater than zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _cashBookService.createExpense(
        accountId: _accountId,
        method: _method,
        amount: amount.toStringAsFixed(2),
        txnDate: _fmtDate(_txnDate),
        reference: _referenceCtrl.text.trim().isNotEmpty ? _referenceCtrl.text.trim() : null,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
        status: _status,
        counterpartyType: _counterpartyType,
        counterpartyId: _counterpartyId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense recorded successfully.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Expense'),
        actions: [
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            _Header(onSubmit: _saving ? null : _submit),
            const SizedBox(height: 16),
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
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving ? 'Saving...' : 'Save Expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Expense details',
            subtitle: 'Fast entry for daily operating expenses, bills, staff expenses, repairs and petty cash.',
            icon: Icons.receipt_long_rounded,
            color: AppTheme.danger,
          ),
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
          const SizedBox(height: 14),
          TextFormField(
            controller: _referenceCtrl,
            decoration: const InputDecoration(
              labelText: 'Reference / bill no',
              prefixIcon: Icon(Icons.tag_rounded),
              hintText: 'Optional receipt, bill or voucher number',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _noteCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_rounded),
              hintText: 'Example: Office rent, fuel, repair, staff meal, electricity bill...',
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.verified_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'approved', child: Text('Approved')),
              DropdownMenuItem(value: 'pending', child: Text('Pending approval')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'approved'),
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
                title: 'Payment source',
                subtitle: 'Use method mapping or select a backend account directly.',
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.teal,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methods.map((m) {
                  final selected = _method == m['value'];
                  return ChoiceChip(
                    selected: selected,
                    avatar: Icon(m['icon'] as IconData, size: 18),
                    label: Text(m['label'].toString()),
                    onSelected: (_) => setState(() => _method = m['value'].toString()),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                value: _accountId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _loadingAccounts ? 'Loading accounts...' : 'Account override',
                  prefixIcon: const Icon(Icons.account_tree_rounded),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Auto by selected method'),
                  ),
                  ..._accounts.map((a) {
                    final code = (a['code'] ?? '').toString();
                    final name = (a['name'] ?? 'Account').toString();
                    return DropdownMenuItem<String?>(
                      value: a['id'].toString(),
                      child: Text(code.isNotEmpty ? '$name ($code)' : name),
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EnterpriseSectionHeader(
                title: 'Counterparty',
                subtitle: 'Optional, but selected from real backend customers/vendors when needed.',
                icon: Icons.groups_2_rounded,
                color: AppTheme.warning,
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'none', label: Text('None'), icon: Icon(Icons.block_rounded)),
                  ButtonSegment(value: 'customer', label: Text('Customer'), icon: Icon(Icons.person_rounded)),
                  ButtonSegment(value: 'vendor', label: Text('Vendor'), icon: Icon(Icons.storefront_rounded)),
                ],
                selected: {_partyKind},
                onSelectionChanged: (set) {
                  final next = set.first;
                  setState(() {
                    _partyKind = next;
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
                            _partyKind == 'none' ? 'General expense' : _partyName(_selectedParty),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _partyKind == 'none'
                                ? 'No customer/vendor will be linked.'
                                : _selectedParty == null
                                    ? 'Select $_partyKind from backend list.'
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
                        tooltip: "Select ${_partyKind == 'customer' ? 'customer' : 'vendor'}",
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
                    label: Text("Choose ${_partyKind == 'customer' ? 'Customer' : 'Vendor'}"),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback? onSubmit;

  const _Header({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payments_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Expense Entry', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                const Text('Record daily expense with account, method, date and party.', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
