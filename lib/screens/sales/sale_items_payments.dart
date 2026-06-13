import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';

class PaymentsCard extends StatelessWidget {
  final bool autoCashIfEmpty;
  final ValueChanged<bool> onToggleAutoCash;
  final TextEditingController cashReceivedController;
  final String changeAmount;

  const PaymentsCard({
    super.key,
    required this.autoCashIfEmpty,
    required this.onToggleAutoCash,
    required this.cashReceivedController,
    required this.changeAmount,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto cash for counter sale',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Creates a cash payment automatically. Cash received is only saved for receipt snapshot.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: autoCashIfEmpty, onChanged: onToggleAutoCash),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: cashReceivedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cash Received',
              hintText: 'Enter received amount',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_exchange_rounded,
                    color: AppTheme.success, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Change Amount',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '\$$changeAmount',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
