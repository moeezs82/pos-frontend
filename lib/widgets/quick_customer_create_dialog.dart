import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// A compact, lightweight popup dialog to quickly create a customer from the
/// POS sale screen without navigating away to the full customer management form.
class QuickCustomerCreateDialog extends StatefulWidget {
  final String token;
  final String? initialQuery;

  const QuickCustomerCreateDialog({
    super.key,
    required this.token,
    this.initialQuery,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String token,
    String? initialQuery,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuickCustomerCreateDialog(
        token: token,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<QuickCustomerCreateDialog> createState() =>
      _QuickCustomerCreateDialogState();
}

class _QuickCustomerCreateDialogState extends State<QuickCustomerCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final query = (widget.initialQuery ?? '').trim();
    // Detect if the query is filled with a number (contains digits and no letters)
    final hasDigits = RegExp(r'[0-9]').hasMatch(query);
    final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(query);
    final isNumber = hasDigits && !hasLetters;

    _nameController = TextEditingController(text: isNumber ? '' : query);
    _phoneController = TextEditingController(text: isNumber ? query : '');
    _addressController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate() || _submitting) return;

    setState(() => _submitting = true);

    try {
      final rawName = _nameController.text.trim();

      final service = CustomerService(token: widget.token);
      final payload = <String, dynamic>{
        'first_name': rawName,
        'phone': _phoneController.text.trim(),
        if (_addressController.text.trim().isNotEmpty)
          'address': _addressController.text.trim(),
        'customer_type': 'retail',
        'status': 'active',
      };

      final created = await service.createCustomer(payload);

      // Record in warm pick cache so autocomplete finds it immediately
      CustomerPickCache.cache.insertEverywhere(
        created,
        matchesExisting: (c) =>
            (c['id'] ?? '').toString() == (created['id'] ?? '').toString(),
      );

      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Customer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Quickly add a new customer to this sale',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_errorMessage != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: AppTheme.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Customer Name
                TextFormField(
                  controller: _nameController,
                  autofocus: _nameController.text.isEmpty,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Muhammad Ali',
                    prefixIcon:
                        Icon(Icons.person_outline_rounded, size: 18),
                    isDense: true,
                  ),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return 'Customer name is required';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  autofocus: _nameController.text.isNotEmpty &&
                      _phoneController.text.isEmpty,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    hintText: 'e.g. 03001234567',
                    prefixIcon: Icon(Icons.call_outlined, size: 18),
                    isDense: true,
                  ),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return 'Phone number is required';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Address (optional)
                TextFormField(
                  controller: _addressController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSave(),
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                    hintText: 'City, Street or Area',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 18),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _handleSave,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: Text(_submitting ? 'Creating…' : 'Create & Select'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
