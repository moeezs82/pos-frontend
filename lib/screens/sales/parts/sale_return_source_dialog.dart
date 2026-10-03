import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

class ReturnSourceDialog extends StatefulWidget {
  final String initialInvoice;
  final String initialReason;

  const ReturnSourceDialog({
    super.key,
    required this.initialInvoice,
    required this.initialReason,
  });

  @override
  State<ReturnSourceDialog> createState() => _ReturnSourceDialogState();
}

class _ReturnSourceDialogState extends State<ReturnSourceDialog> {
  static const _reasons = <String>[
    'Customer changed mind',
    'Wrong item',
    'Wrong size / variant',
    'Damaged / defective',
    'Quality issue',
    'Duplicate purchase',
    'Other',
  ];

  late final TextEditingController _invoiceController;
  late final TextEditingController _otherController;
  late String _reason;

  @override
  void initState() {
    super.initState();
    _invoiceController = TextEditingController(text: widget.initialInvoice);
    _otherController = TextEditingController();
    _reason = _reasons.contains(widget.initialReason)
        ? widget.initialReason
        : (widget.initialReason.trim().isNotEmpty ? 'Other' : _reasons.first);
    if (_reason == 'Other' &&
        widget.initialReason.trim().isNotEmpty &&
        widget.initialReason != 'Other') {
      _otherController.text = widget.initialReason;
    }
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  void _submit() {
    final invoice = _invoiceController.text.trim();
    final reason = _reason == 'Other'
        ? _otherController.text.trim()
        : _reason;
    if (invoice.isEmpty || reason.isEmpty) {
      AppFeedback.warning(
        context,
        'Original invoice and return reason are required.',
      );
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'invoice': invoice,
      'reason': reason,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment_return_outlined),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Link return to original invoice',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _invoiceController,
                autofocus: widget.initialInvoice.trim().isEmpty,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Original invoice *',
                  hintText: 'Invoice no. / offline receipt no.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _reason,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Return reason *',
                  border: OutlineInputBorder(),
                ),
                items: _reasons
                    .map(
                      (reason) => DropdownMenuItem<String>(
                        value: reason,
                        child: Text(reason),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(
                  () => _reason = value ?? _reasons.first,
                ),
              ),
              if (_reason == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otherController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Reason details *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text(
                  'Stock is restored automatically. CounterIQ calculates the refundable merchandise, original invoice discount and tax from the original invoice. Original delivery is never refunded.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text('Find original item'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
