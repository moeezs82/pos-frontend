import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

Future<String?> showSalesOrderReasonDialog({
  required BuildContext context,
  required String title,
  required String labelText,
  required String hintText,
  required String confirmText,
  Color confirmColor = AppTheme.danger,
  IconData icon = Icons.warning_amber_rounded,
  bool isRequired = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _SalesOrderReasonDialog(
      title: title,
      labelText: labelText,
      hintText: hintText,
      confirmText: confirmText,
      confirmColor: confirmColor,
      icon: icon,
      isRequired: isRequired,
    ),
  );
}

class _SalesOrderReasonDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String hintText;
  final String confirmText;
  final Color confirmColor;
  final IconData icon;
  final bool isRequired;

  const _SalesOrderReasonDialog({
    required this.title,
    required this.labelText,
    required this.hintText,
    required this.confirmText,
    required this.confirmColor,
    required this.icon,
    required this.isRequired,
  });

  @override
  State<_SalesOrderReasonDialog> createState() =>
      _SalesOrderReasonDialogState();
}

class _SalesOrderReasonDialogState extends State<_SalesOrderReasonDialog> {
  late final TextEditingController _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (widget.isRequired && text.isEmpty) {
      setState(() {
        _errorMessage = 'Reason is required';
      });
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.icon, color: widget.confirmColor, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                errorText: _errorMessage,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: widget.confirmColor,
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
