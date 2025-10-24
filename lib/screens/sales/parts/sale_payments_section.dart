import 'package:flutter/material.dart';

class SalePaymentsSection extends StatelessWidget {
  final List payments;
  final VoidCallback onAddPayment;
  final void Function(Map p) onEditPayment;
  final void Function(int paymentId) onDeletePayment;

  const SalePaymentsSection({
    super.key,
    required this.payments,
    required this.onAddPayment,
    required this.onEditPayment,
    required this.onDeletePayment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text("Payments",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ElevatedButton.icon(
                  onPressed: onAddPayment,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Payment"),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (payments.isEmpty) const ListTile(title: Text("No payments yet")),
          ...payments.map((p) => ListTile(
                title: Text("\$${p['amount']}"),
                subtitle: Text("Method: ${p['method']}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // IconButton(icon: const Icon(Icons.edit), onPressed: () => onEditPayment(p)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => onDeletePayment(p['id'] as int),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
