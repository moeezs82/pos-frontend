import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
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

  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();

  String _status = 'active';

  late CustomerService _customerService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _customerService = CustomerService(token: token);
    if (widget.customer != null) {
      final c = widget.customer!;
      _firstNameController.text = c['first_name'] ?? '';
      _lastNameController.text = c['last_name'] ?? '';
      _emailController.text = c['email'] ?? '';
      _phoneController.text = c['phone'] ?? '';
      _addressController.text = c['address'] ?? '';
      _status = c['status'] ?? 'active';
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      "first_name": _firstNameController.text.trim(),
      "last_name": _lastNameController.text.trim(),
      "email": _emailController.text.trim(),
      "phone": _phoneController.text.trim(),
      "address": _addressController.text.trim(),
      "password": _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
      "status": _status,
    };

    try {
      if (widget.customer == null) {
        final customer = await _customerService.createCustomer(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Customer created successfully")),
        );
        Navigator.pop(context, customer);
      } else {
        await _customerService.updateCustomer(widget.customer!['id'], data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Customer updated successfully")),
        );
        Navigator.pop(context, true); 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
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
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Customer" : "New Customer"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField(
                controller: _firstNameController,
                label: "First Name *",
                validator: (v) =>
                    v == null || v.isEmpty ? "First name is required" : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _lastNameController,
                label: "Last Name",
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _emailController,
                label: "Email",
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _phoneController,
                label: "Phone *",
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    v == null || v.isEmpty ? "Phone is required" : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _addressController,
                label: "Address",
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              if (!isEdit)
                _buildTextField(
                  controller: _passwordController,
                  label: "Password",
                  obscure: true,
                  // validator: (v) => !isEdit && (v == null || v.length < 6)
                  //     ? "Password must be at least 6 characters"
                  //     : null,
                ),
              if (!isEdit) const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text("Active")),
                  DropdownMenuItem(value: 'inactive', child: Text("Inactive")),
                  DropdownMenuItem(value: 'blocked', child: Text("Blocked")),
                ],
                onChanged: (v) => setState(() => _status = v!),
                decoration: InputDecoration(
                  labelText: "Status",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(isEdit ? Icons.save : Icons.add),
                  onPressed: _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  label: Text(
                    isEdit ? "Update Customer" : "Create Customer",
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
