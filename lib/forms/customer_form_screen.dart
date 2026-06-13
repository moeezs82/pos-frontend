import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
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
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  String _status = 'active';
  bool _saving = false;
  late CustomerService _customerService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _customerService = CustomerService(token: token);
    final c = widget.customer;
    if (c != null) {
      _firstNameController.text = (c['first_name'] ?? '').toString();
      _lastNameController.text = (c['last_name'] ?? '').toString();
      _emailController.text = (c['email'] ?? '').toString();
      _phoneController.text = (c['phone'] ?? '').toString();
      _addressController.text = (c['address'] ?? '').toString();
      _status = (c['status'] ?? 'active').toString();
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final data = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'password': _passwordController.text.isNotEmpty ? _passwordController.text : null,
      'status': _status,
    };
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
      validator: validator,
    );
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
                      if (!isEdit) SizedBox(width: 360, child: _field(controller: _passwordController, label: 'Password', icon: Icons.lock_outline_rounded, obscure: true)),
                      SizedBox(width: 736, child: _field(controller: _addressController, label: 'Address', icon: Icons.location_on_outlined, maxLines: 2)),
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
