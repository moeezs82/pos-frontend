import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class VendorFormScreen extends StatefulWidget {
  final Map<String, dynamic>? vendor;
  const VendorFormScreen({super.key, this.vendor});

  @override
  State<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends State<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _creditLimitController = TextEditingController();

  /// Opening balance is entered as a positive magnitude; [_openingOwed]
  /// carries the direction. Only offered on CREATE — changing it later would
  /// mean amending a posted journal entry.
  final _openingBalanceController = TextEditingController();
  bool _openingOwed = true;

  bool _unlimitedCredit = true;
  String _creditLimitMode = 'block';

  String _status = 'active';
  bool _saving = false;
  late VendorService _vendorService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _vendorService = VendorService(token: token);
    final v = widget.vendor;
    if (v != null) {
      _firstNameController.text = (v['first_name'] ?? '').toString();
      _lastNameController.text = (v['last_name'] ?? '').toString();
      _emailController.text = (v['email'] ?? '').toString();
      _phoneController.text = (v['phone'] ?? '').toString();
      _addressController.text = (v['address'] ?? '').toString();
      _status = (v['status'] ?? 'active').toString();
      final rawCreditLimit = v['credit_limit'];
      if (rawCreditLimit != null && rawCreditLimit.toString().trim().isNotEmpty) {
        _unlimitedCredit = false;
        _creditLimitController.text = rawCreditLimit.toString();
      }
      final rawMode = (v['credit_limit_mode'] ?? 'block').toString().toLowerCase();
      _creditLimitMode = rawMode == 'warning' ? 'warning' : 'block';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _saveVendor() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    // Explicitly Map<String, dynamic>: without password the inferred type
    // would be Map<String, String> and the numeric opening_balance below
    // would not compile.
    final Map<String, dynamic> data = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'status': _status,
      'credit_limit': _unlimitedCredit
          ? null
          : double.tryParse(_creditLimitController.text.trim()),
      'credit_limit_mode': _creditLimitMode,
    };

    // Opening balance is create-only and signed: positive means we owe the
    // vendor (posts DR Retained Earnings / CR Accounts Payable), negative means
    // we have prepaid them. Omitted entirely when blank or zero so the backend
    // posts no journal entry at all.
    if (widget.vendor == null) {
      final opening = double.tryParse(_openingBalanceController.text.trim());
      if (opening != null && opening.abs() >= 0.005) {
        data['opening_balance'] = _openingOwed ? opening.abs() : -opening.abs();
      }
    }

    try {
      if (widget.vendor == null) {
        final vendor = await _vendorService.createVendor(data);
        if (!mounted) return;
        AppFeedback.success(context, 'Vendor created successfully');
        Navigator.pop(context, vendor);
      } else {
        await _vendorService.updateVendor(widget.vendor!['id'], data);
        if (!mounted) return;
        AppFeedback.success(context, 'Vendor updated successfully');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.vendor != null;
    return EnterprisePage(
      title: isEdit ? 'Edit Vendor' : 'New Vendor',
      subtitle: isEdit ? 'Update vendor profile and contact details.' : 'Create a supplier profile for purchases and payables.',
      icon: Icons.groups_2_rounded,
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _saveVendor,
          icon: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(isEdit ? Icons.save_rounded : Icons.add_rounded),
          label: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            EnterprisePanel(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EnterpriseSectionHeader(
                    title: 'Vendor information',
                    subtitle: 'Keep supplier details clear for purchasing and payments.',
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: 360, child: _field(controller: _firstNameController, label: 'First Name *', icon: Icons.person_outline_rounded, validator: (v) => v == null || v.trim().isEmpty ? 'First name is required' : null)),
                      SizedBox(width: 360, child: _field(controller: _lastNameController, label: 'Last Name', icon: Icons.person_outline_rounded)),
                      SizedBox(width: 360, child: _field(controller: _phoneController, label: 'Phone *', icon: Icons.call_outlined, keyboardType: TextInputType.phone, validator: (v) => v == null || v.trim().isEmpty ? 'Phone is required' : null)),
                      SizedBox(width: 360, child: _field(controller: _emailController, label: 'Email', icon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress)),
                      SizedBox(width: 360, child: DropdownButtonFormField<String>(
                        value: _status,
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'active'),
                        decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.verified_user_outlined)),
                      )),
                      if (!isEdit) ...[
                        SizedBox(
                          width: 360,
                          child: _field(
                            controller: _openingBalanceController,
                            label: 'Opening Balance',
                            icon: Icons.account_balance_wallet_outlined,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return null;
                              final parsed = double.tryParse(s);
                              if (parsed == null) return 'Enter a valid amount';
                              if (parsed < 0) return 'Use the toggle for prepaid balances';
                              return null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: DropdownButtonFormField<bool>(
                            value: _openingOwed,
                            items: const [
                              DropdownMenuItem(value: true, child: Text('We owe the vendor')),
                              DropdownMenuItem(value: false, child: Text('We have prepaid the vendor')),
                            ],
                            onChanged: (v) => setState(() => _openingOwed = v ?? true),
                            decoration: const InputDecoration(
                              labelText: 'Opening Balance Type',
                              prefixIcon: Icon(Icons.swap_vert_rounded),
                              helperText: 'Leave the amount blank if there is no opening balance',
                            ),
                          ),
                        ),
                      ],
                      SizedBox(width: 736, child: _field(controller: _addressController, label: 'Address', icon: Icons.location_on_outlined, maxLines: 2)),
                    ],
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
                    title: 'Credit control',
                    subtitle: 'Limit the vendor’s total trade payable. Payments remain party-level transactions and are not allocated to individual invoices.',
                    icon: Icons.credit_score_rounded,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _unlimitedCredit,
                    onChanged: (value) => setState(() {
                      _unlimitedCredit = value;
                      if (value) _creditLimitController.clear();
                    }),
                    title: const Text('Unlimited credit'),
                    subtitle: const Text('Existing behaviour is preserved while this is enabled.'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 360,
                        child: _field(
                          controller: _creditLimitController,
                          label: 'Vendor Credit Limit',
                          icon: Icons.account_balance_wallet_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          enabled: !_unlimitedCredit,
                          validator: (value) {
                            if (_unlimitedCredit) return null;
                            final amount = double.tryParse((value ?? '').trim());
                            if (amount == null || !amount.isFinite) {
                              return 'Enter a valid credit limit';
                            }
                            if (amount < 0) return 'Credit limit cannot be negative';
                            if (amount > 99999999999999.99) {
                              return 'Credit limit is too large';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: 360,
                        child: DropdownButtonFormField<String>(
                          value: _creditLimitMode,
                          items: const [
                            DropdownMenuItem(value: 'block', child: Text('Block when exceeded')),
                            DropdownMenuItem(value: 'warning', child: Text('Warn but allow')),
                          ],
                          onChanged: _unlimitedCredit
                              ? null
                              : (value) => setState(() => _creditLimitMode = value ?? 'block'),
                          decoration: const InputDecoration(
                            labelText: 'Limit Behaviour',
                            prefixIcon: Icon(Icons.policy_outlined),
                            helperText: 'Block mode can be overridden only with permission and a reason.',
                          ),
                        ),
                      ),
                      if ((widget.vendor?['trade_balance'] ?? widget.vendor?['balance']) != null)
                        SizedBox(
                          width: 360,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Current Trade Balance',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                            ),
                            child: Text((widget.vendor?['trade_balance'] ?? widget.vendor?['balance']).toString()),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _saveVendor,
                  icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded),
                  label: Text(isEdit ? 'Update Vendor' : 'Create Vendor'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
