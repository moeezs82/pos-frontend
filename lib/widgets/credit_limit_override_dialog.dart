import 'dart:convert';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/material.dart';

class CreditLimitIssue {
  final String partyType;
  final int? partyId;
  final double limit;
  final double balanceBefore;
  final double projectedBalance;
  final double exceededBy;
  final String mode;
  final bool canOverride;
  final bool overrideUsed;

  const CreditLimitIssue({
    required this.partyType,
    required this.partyId,
    required this.limit,
    required this.balanceBefore,
    required this.projectedBalance,
    required this.exceededBy,
    required this.mode,
    required this.canOverride,
    this.overrideUsed = false,
  });

  static CreditLimitIssue? fromException(Object error) {
    if (error is! ApiException) return null;
    final body = error.body;
    if (body?['code']?.toString() != 'PARTY_CREDIT_LIMIT_EXCEEDED') {
      return null;
    }
    final data = _asMap(body?['data']);
    if (data == null) return null;
    return CreditLimitIssue(
      partyType: data['party_type']?.toString() ?? 'party',
      partyId: _toInt(data['party_id']),
      limit: _toDouble(data['credit_limit']),
      balanceBefore: _toDouble(data['balance_before']),
      projectedBalance: _toDouble(data['projected_balance']),
      exceededBy: _toDouble(data['exceeded_by']),
      mode: data['mode']?.toString() ?? 'block',
      canOverride: _toBool(data['can_override']),
      overrideUsed: _toBool(data['override_used']),
    );
  }

  static CreditLimitIssue? fromStoredError(String? error) {
    if (error == null || !error.contains('PARTY_CREDIT_LIMIT_EXCEEDED')) {
      return null;
    }
    for (final line in error.split('\n')) {
      const prefix = 'CREDIT_LIMIT_DATA:';
      if (!line.startsWith(prefix)) continue;
      try {
        return fromWarning(jsonDecode(line.substring(prefix.length)));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static CreditLimitIssue? fromWarning(dynamic raw) {
    final data = _asMap(raw);
    if (data == null ||
        data['code']?.toString() != 'PARTY_CREDIT_LIMIT_EXCEEDED') {
      return null;
    }
    return CreditLimitIssue(
      partyType: data['party_type']?.toString() ?? 'party',
      partyId: _toInt(data['party_id']),
      limit: _toDouble(data['credit_limit']),
      balanceBefore: _toDouble(data['balance_before']),
      projectedBalance: _toDouble(data['projected_balance']),
      exceededBy: _toDouble(data['exceeded_by']),
      mode: data['mode']?.toString() ?? 'warning',
      canOverride: false,
      overrideUsed: _toBool(data['override_used']),
    );
  }

  String get partyLabel {
    switch (partyType.toLowerCase()) {
      case 'customer':
        return 'Customer';
      case 'vendor':
        return 'Vendor';
      default:
        return 'Party';
    }
  }

  String get summary =>
      '$partyLabel trade balance would become ${AppCurrency.format(projectedBalance)}, '
      'which is ${AppCurrency.format(exceededBy)} above the limit of ${AppCurrency.format(limit)}.';

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}
        .contains(value?.toString().trim().toLowerCase());
  }
}

Future<String?> showCreditLimitOverrideDialog(
  BuildContext context,
  CreditLimitIssue issue,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreditLimitOverrideDialog(issue: issue),
  );
}

class _CreditLimitOverrideDialog extends StatefulWidget {
  final CreditLimitIssue issue;

  const _CreditLimitOverrideDialog({required this.issue});

  @override
  State<_CreditLimitOverrideDialog> createState() =>
      _CreditLimitOverrideDialogState();
}

class _CreditLimitOverrideDialogState
    extends State<_CreditLimitOverrideDialog> {
  late final TextEditingController _controller;
  late final FocusNode _reasonFocusNode;
  String? _validationMessage;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _reasonFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reasonFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reasonFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([String? result]) {
    if (_closing || !mounted) return;
    _closing = true;
    _reasonFocusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  void _approve() {
    final reason = _controller.text.trim();
    if (reason.length < 5) {
      setState(() {
        _validationMessage = 'Enter at least 5 characters';
      });
      return;
    }
    _close(reason);
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gpp_maybe_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('Credit limit exceeded')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(issue.summary),
            const SizedBox(height: 14),
            _AmountRow(label: 'Balance before', value: issue.balanceBefore),
            _AmountRow(
              label: 'Projected balance',
              value: issue.projectedBalance,
            ),
            _AmountRow(label: 'Credit limit', value: issue.limit),
            _AmountRow(label: 'Over limit by', value: issue.exceededBy),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _reasonFocusNode,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _approve(),
              decoration: InputDecoration(
                labelText: 'Override reason *',
                hintText: 'Explain why this transaction is being approved',
                errorText: _validationMessage,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This approval is written to the permanent credit-control audit log.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => _close(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _closing ? null : _approve,
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text('Approve Override'),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;

  const _AmountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            AppCurrency.format(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Future<String?> showOfflineCreditDataOverrideDialog(
  BuildContext context, {
  required String message,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OfflineCreditDataOverrideDialog(message: message),
  );
}

class _OfflineCreditDataOverrideDialog extends StatefulWidget {
  final String message;

  const _OfflineCreditDataOverrideDialog({required this.message});

  @override
  State<_OfflineCreditDataOverrideDialog> createState() =>
      _OfflineCreditDataOverrideDialogState();
}

class _OfflineCreditDataOverrideDialogState
    extends State<_OfflineCreditDataOverrideDialog> {
  late final TextEditingController _controller;
  late final FocusNode _reasonFocusNode;
  String? _validationMessage;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _reasonFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reasonFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _reasonFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([String? result]) {
    if (_closing || !mounted) return;
    _closing = true;
    _reasonFocusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  void _approve() {
    final reason = _controller.text.trim();
    if (reason.length < 5) {
      setState(() {
        _validationMessage = 'Enter at least 5 characters';
      });
      return;
    }
    _close(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud_off_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('Offline credit approval')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 14),
            const Text(
              'The backend will recheck the authoritative party trade ledger during synchronization. The sale may still require review if the balance changed on another device.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _reasonFocusNode,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _approve(),
              decoration: InputDecoration(
                labelText: 'Offline override reason *',
                hintText: 'Explain why offline credit is being approved',
                errorText: _validationMessage,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => _close(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _closing ? null : _approve,
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text('Approve Offline Credit'),
        ),
      ],
    );
  }
}
