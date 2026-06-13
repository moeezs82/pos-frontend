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
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
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

  Future<void> _saveVendor() async {
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
