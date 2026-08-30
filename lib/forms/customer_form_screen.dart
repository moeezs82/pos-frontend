import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/customer_area_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/customer_phone_utils.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:enterprise_pos/widgets/reference_data_manager_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CustomerFormScreen extends StatefulWidget {
  final Map<String, dynamic>? customer;
  const CustomerFormScreen({super.key, this.customer});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerCodeController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<TextEditingController> _secondaryPhoneControllers = [];
  final _addressController = TextEditingController();
  final _creditLimitController = TextEditingController();

  /// Opening balance is entered as a positive magnitude; [_openingOwes]
  /// carries the direction. Only offered on CREATE — changing it later would
  /// mean amending a posted journal entry.
  final _openingBalanceController = TextEditingController();
  bool _openingOwes = true;

  bool _unlimitedCredit = true;
  String _creditLimitMode = 'block';

  String _status = 'active';
  String _customerType = 'retail';
  bool _saving = false;
  int? _selectedAreaId;
  List<Map<String, dynamic>> _areas = const [];
  bool _areasLoading = false;
  late CustomerService _customerService;
  late CustomerAreaService _areaService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _customerService = CustomerService(token: token);
    _areaService = CustomerAreaService(token: token);
    final c = widget.customer;
    if (c != null) {
      _customerCodeController.text = (c['customer_code'] ?? '').toString();
      final rawType = (c['customer_type'] ?? 'retail').toString().toLowerCase();
      _customerType = const {'retail', 'wholesale', 'reseller'}.contains(rawType) ? rawType : 'retail';
      _firstNameController.text = (c['first_name'] ?? '').toString();
      _lastNameController.text = (c['last_name'] ?? '').toString();
      _emailController.text = (c['email'] ?? '').toString();
      _phoneController.text = (c['phone'] ?? '').toString();
      for (final phone in CustomerPhoneUtils.secondaryPhones(c['phone_numbers'])) {
        _secondaryPhoneControllers.add(TextEditingController(text: phone));
      }
      _addressController.text = (c['address'] ?? '').toString();
      _selectedAreaId = int.tryParse(c['area_id']?.toString() ?? '');
      _status = (c['status'] ?? 'active').toString();
      final rawCreditLimit = c['credit_limit'];
      if (rawCreditLimit != null && rawCreditLimit.toString().trim().isNotEmpty) {
        _unlimitedCredit = false;
        _creditLimitController.text = rawCreditLimit.toString();
      }
      final rawMode = (c['credit_limit_mode'] ?? 'block').toString().toLowerCase();
      _creditLimitMode = rawMode == 'warning' ? 'warning' : 'block';
    }
    _loadAreas();
  }

  @override
  void dispose() {
    _customerCodeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    for (final controller in _secondaryPhoneControllers) {
      controller.dispose();
    }
    _addressController.dispose();
    _creditLimitController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  bool _areaActive(Map<String, dynamic> area) {
    final value = area['is_active'];
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  Future<void> _loadAreas() async {
    if (mounted) setState(() => _areasLoading = true);
    try {
      final items = await _areaService.getAreas();
      items.sort((a, b) {
        final aa = _areaActive(a);
        final ba = _areaActive(b);
        if (aa != ba) return aa ? -1 : 1;
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            );
      });
      if (!mounted) return;
      setState(() => _areas = items);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Unable to load town / area values: $e');
    } finally {
      if (mounted) setState(() => _areasLoading = false);
    }
  }

  Future<void> _manageAreas() async {
    if (!context.read<AuthProvider>().hasPermission('manage-customers')) return;
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Town / Areas',
      singularLabel: 'Town / Area',
      icon: Icons.location_city_outlined,
      selectedId: _selectedAreaId,
      loadItems: () => _areaService.getAreas(activeOnly: true),
      createItem: _areaService.createArea,
      updateItem: _areaService.updateArea,
      subtitle: 'Create, rename, or choose an area without leaving the customer form.',
      selectedSubtitle: 'Selected for this customer',
    );
    if (!mounted || result == null) return;
    await _loadAreas();
    if (!mounted) return;
    setState(() => _selectedAreaId = result.selectedId);
  }

  Future<void> _saveCustomer() async {
    if (!context.read<AuthProvider>().hasPermission('manage-customers')) {
      AppFeedback.error(context, 'You do not have permission to manage customers.');
      return;
    }
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    // Explicitly Map<String, dynamic>: without password the inferred type
    // would be Map<String, String> and the numeric opening_balance below
    // would not compile.
    final Map<String, dynamic> data = {
      'customer_code': _customerCodeController.text.trim(),
      'customer_type': _customerType,
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'phone_numbers': _secondaryPhoneControllers
          .map((controller) => controller.text.trim())
          .where((phone) => phone.isNotEmpty)
          .toList(growable: false),
      'address': _addressController.text.trim(),
      'area_id': _selectedAreaId,
      'status': _status,
      'credit_limit': _unlimitedCredit
          ? null
          : double.tryParse(_creditLimitController.text.trim()),
      'credit_limit_mode': _creditLimitMode,
    };

    // Opening balance is create-only and signed: positive means the customer
    // owes us (posts DR Accounts Receivable / CR Retained Earnings), negative
    // means they hold a credit with us. Omitted entirely when blank or zero so
    // the backend posts no journal entry at all.
    if (widget.customer == null) {
      final opening = double.tryParse(_openingBalanceController.text.trim());
      if (opening != null && opening.abs() >= 0.005) {
        data['opening_balance'] = _openingOwes ? opening.abs() : -opening.abs();
      }
    }

    if (widget.customer != null) {
      // Preserve Laravel-compatible unique-field update semantics and let the
      // backend exclude this customer while validating branch uniqueness.
      data['id'] = widget.customer!['id'];
    }

    try {
      if (widget.customer == null) {
        final customer = await _customerService.createCustomer(data);
        if (!mounted) return;
        AppFeedback.success(context, 'Customer created successfully');
        Navigator.pop(context, customer);
      } else {
        await _customerService.updateCustomer(widget.customer!['id'], data);
        if (!mounted) return;
        AppFeedback.success(context, 'Customer updated successfully');
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
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
      validator: validator,
    );
  }

  String? _primaryPhoneValidator(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Phone is required';
    if (phone.length > 20) return 'Phone must be 20 characters or fewer';
    return null;
  }

  String? _secondaryPhoneValidator(int index, String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Enter a phone number or remove this row';
    if (phone.length > 20) return 'Phone must be 20 characters or fewer';

    final key = CustomerPhoneUtils.compareKey(phone);
    if (key == CustomerPhoneUtils.compareKey(_phoneController.text)) {
      return 'Secondary phone cannot match the primary phone';
    }
    for (var i = 0; i < _secondaryPhoneControllers.length; i++) {
      if (i == index) continue;
      final other = _secondaryPhoneControllers[i].text.trim();
      if (other.isNotEmpty && CustomerPhoneUtils.compareKey(other) == key) {
        return 'Duplicate secondary phone number';
      }
    }
    return null;
  }

  void _addSecondaryPhone() {
    if (_secondaryPhoneControllers.length >= 4) return;
    setState(() {
      _secondaryPhoneControllers.add(TextEditingController());
    });
  }

  void _removeSecondaryPhone(int index) {
    if (index < 0 || index >= _secondaryPhoneControllers.length) return;
    final controller = _secondaryPhoneControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;
    return EnterprisePage(
      title: isEdit ? 'Edit Customer' : 'New Customer',
      subtitle: isEdit ? 'Update customer profile and contact details.' : 'Create a new customer profile for sales and receivables.',
      icon: Icons.person_rounded,
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _saveCustomer,
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
                    title: 'Customer information',
                    subtitle: 'Keep the required fields simple for faster entry.',
                    icon: Icons.badge_rounded,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 360,
                        child: _field(
                          controller: _customerCodeController,
                          label: isEdit ? 'Customer ID' : 'Customer ID (optional)',
                          icon: Icons.numbers_rounded,
                          helperText: isEdit
                              ? 'Unique within this branch. Leave blank to keep the current ID.'
                              : 'Enter your own ID or leave blank to auto-generate one.',
                          validator: (v) {
                            final code = (v ?? '').trim();
                            if (code.length > 64) return 'Customer ID must be 64 characters or fewer';
                            return null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: 360,
                        child: DropdownButtonFormField<String>(
                          value: _customerType,
                          items: const [
                            DropdownMenuItem(value: 'retail', child: Text('Retail')),
                            DropdownMenuItem(value: 'wholesale', child: Text('Wholesale')),
                            DropdownMenuItem(value: 'reseller', child: Text('Reseller')),
                          ],
                          onChanged: (v) => setState(() => _customerType = v ?? 'retail'),
                          decoration: const InputDecoration(
                            labelText: 'Customer Type',
                            prefixIcon: Icon(Icons.storefront_outlined),
                          ),
                        ),
                      ),
                      SizedBox(width: 360, child: _field(controller: _firstNameController, label: 'First Name *', icon: Icons.person_outline_rounded, validator: (v) => v == null || v.trim().isEmpty ? 'First name is required' : null)),
                      SizedBox(width: 360, child: _field(controller: _lastNameController, label: 'Last Name', icon: Icons.person_outline_rounded)),
                      SizedBox(width: 360, child: _field(controller: _phoneController, label: 'Primary Phone *', icon: Icons.call_outlined, keyboardType: TextInputType.phone, validator: _primaryPhoneValidator)),
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
                              if (parsed < 0) return 'Use the toggle for credit balances';
                              return null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: DropdownButtonFormField<bool>(
                            value: _openingOwes,
                            items: const [
                              DropdownMenuItem(value: true, child: Text('Customer owes us')),
                              DropdownMenuItem(value: false, child: Text('Customer is in credit')),
                            ],
                            onChanged: (v) => setState(() => _openingOwes = v ?? true),
                            decoration: const InputDecoration(
                              labelText: 'Opening Balance Type',
                              prefixIcon: Icon(Icons.swap_vert_rounded),
                              helperText: 'Leave the amount blank if there is no opening balance',
                            ),
                          ),
                        ),
                      ],
                      SizedBox(
                        width: 360,
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedAreaId != null &&
                                        _areas.any((a) =>
                                            int.tryParse(a['id']?.toString() ?? '') ==
                                            _selectedAreaId)
                                    ? _selectedAreaId
                                    : null,
                                isExpanded: true,
                                items: _areas
                                    .where((a) => _areaActive(a) ||
                                        int.tryParse(a['id']?.toString() ?? '') ==
                                            _selectedAreaId)
                                    .map((a) {
                                      final id = int.tryParse(a['id']?.toString() ?? '');
                                      final active = _areaActive(a);
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text(
                                          '${a['name'] ?? ''}${active ? '' : ' (inactive)'}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    })
                                    .where((item) => item.value != null)
                                    .toList(growable: false),
                                onChanged: _areasLoading
                                    ? null
                                    : (value) => setState(() => _selectedAreaId = value),
                                decoration: InputDecoration(
                                  labelText: 'Town / Area',
                                  prefixIcon: const Icon(Icons.location_city_outlined),
                                  helperText: 'Used as the customer default and prefilled on new sales.',
                                  suffixIcon: _areasLoading
                                      ? const Padding(
                                          padding: EdgeInsets.all(14),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Manage town / areas',
                              onPressed: _saving ? null : _manageAreas,
                              icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
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
                    title: 'Additional phone numbers',
                    subtitle: 'Optional. Add up to 4 secondary numbers. The primary phone remains the customer identity and WhatsApp destination.',
                    icon: Icons.contact_phone_outlined,
                  ),
                  const SizedBox(height: 12),
                  if (_secondaryPhoneControllers.isEmpty)
                    const Text(
                      'No secondary phone numbers added.',
                      style: TextStyle(color: AppTheme.textMuted),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(_secondaryPhoneControllers.length, (index) {
                        final controller = _secondaryPhoneControllers[index];
                        return SizedBox(
                          width: 360,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _field(
                                  controller: controller,
                                  label: 'Secondary Phone ${index + 1}',
                                  icon: Icons.phone_in_talk_outlined,
                                  keyboardType: TextInputType.phone,
                                  validator: (value) => _secondaryPhoneValidator(index, value),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: IconButton(
                                  tooltip: 'Remove phone',
                                  onPressed: _saving ? null : () => _removeSecondaryPhone(index),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving || _secondaryPhoneControllers.length >= 4
                        ? null
                        : _addSecondaryPhone,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _secondaryPhoneControllers.length >= 4
                          ? 'Maximum 5 total phone numbers reached'
                          : 'Add secondary phone',
                    ),
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
                    subtitle: 'Limit the customer’s total trade receivable. Payments remain party-level transactions and are not allocated to individual invoices.',
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
                          label: 'Customer Credit Limit',
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
                      if ((widget.customer?['trade_balance'] ?? widget.customer?['balance']) != null)
                        SizedBox(
                          width: 360,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Current Trade Balance',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                            ),
                            child: Text((widget.customer?['trade_balance'] ?? widget.customer?['balance']).toString()),
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
                  onPressed: _saving ? null : _saveCustomer,
                  icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded),
                  label: Text(isEdit ? 'Update Customer' : 'Create Customer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
