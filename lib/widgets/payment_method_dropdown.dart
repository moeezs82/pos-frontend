import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:enterprise_pos/models/payment_method.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';

/// Shared dropdown of the branch's active payment methods.
///
/// Reads [PaymentMethodProvider] so every screen renders the same dynamic
/// list (Cash, Bank Transfer, Card, KNET, Wallet, Cheque, …) instead of a
/// hard-coded set. When editing a historical record whose method is no longer
/// active, that stored code is still shown (so the value round-trips) via
/// [displayNameFor].
class PaymentMethodDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? labelText;
  final InputDecoration? decoration;

  const PaymentMethodDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.labelText = 'Method',
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final pm = context.watch<PaymentMethodProvider>();
    final methods = List<PaymentMethod>.from(pm.activeMethods);

    final codes = methods.map((m) => m.method).toSet();

    // Keep an inactive/historical selected value selectable so edit dialogs
    // don't lose it.
    final items = <DropdownMenuItem<String>>[
      for (final m in methods)
        DropdownMenuItem(value: m.method, child: Text(m.displayName)),
    ];
    if (value != null && value!.isNotEmpty && !codes.contains(value)) {
      items.add(DropdownMenuItem(
        value: value,
        child: Text('${pm.displayNameFor(value)} (inactive)'),
      ));
    }

    return DropdownButtonFormField<String>(
      value: (value != null && value!.isNotEmpty) ? value : null,
      isExpanded: true,
      decoration: decoration ??
          InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }
}
