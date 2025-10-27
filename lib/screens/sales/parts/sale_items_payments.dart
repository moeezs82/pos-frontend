import 'package:flutter/material.dart';

class ScannerToggleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onActivate;

  const ScannerToggleButton({
    super.key,
    required this.enabled,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        onPressed: onActivate,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? Colors.green : null,
        ),
        icon: Icon(enabled ? Icons.check_circle : Icons.qr_code_scanner),
        label: Text(enabled ? "Scanning Active" : "Start Scanning"),
      ),
    );
  }
}

// class ItemsCard extends StatelessWidget {
//   final List<Map<String, dynamic>> items;
//   final VoidCallback onAddItem;
//   final void Function(int index) onEditItem;
//   final void Function(int index) onRemoveItem;

//   const ItemsCard({
//     super.key,
//     required this.items,
//     required this.onAddItem,
//     required this.onEditItem,
//     required this.onRemoveItem,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 const Expanded(
//                   child: Text("Items",
//                       style: TextStyle(fontWeight: FontWeight.bold)),
//                 ),
//                 TextButton.icon(
//                   onPressed: onAddItem,
//                   icon: const Icon(Icons.add),
//                   label: const Text("Add Product"),
//                 ),
//               ],
//             ),
//             const Divider(),
//             if (items.isEmpty) const Text("No items added"),
//             ...items.asMap().entries.map((entry) {
//               final index = entry.key;
//               final i = entry.value;
//               return ListTile(
//                 dense: true,
//                 title: Text(i['name'],
//                     style: const TextStyle(fontWeight: FontWeight.bold)),
//                 subtitle: Text("Qty: ${i['quantity']} • Price: \$${i['price']}"),
//                 trailing: IconButton(
//                   icon: const Icon(Icons.delete, color: Colors.red),
//                   onPressed: () => onRemoveItem(index),
//                 ),
//                 onTap: () => onEditItem(index),
//               );
//             }),
//           ],
//         ),
//       ),
//     );
//   }
// }

class PaymentsCard extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final bool autoCashIfEmpty;
  final ValueChanged<bool> onToggleAutoCash;
  final VoidCallback onAddPayment;
  final void Function(int index) onRemovePayment;

  const PaymentsCard({
    super.key,
    required this.payments,
    required this.autoCashIfEmpty,
    required this.onToggleAutoCash,
    required this.onAddPayment,
    required this.onRemovePayment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text("Payments",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                // TextButton.icon(
                //   onPressed: onAddPayment,
                //   icon: const Icon(Icons.add),
                //   label: const Text("Add Payment"),
                // ),
              ],
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Auto-cash"),
              subtitle: const Text(
                "When ON, sends full invoice total as CASH.",
              ),
              value: autoCashIfEmpty,
              onChanged: onToggleAutoCash,
            ),
            // if (payments.isEmpty) const Text("No payments yet"),
            ...payments.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              return ListTile(
                dense: true,
                title: Text("\$${p['amount']}"),
                subtitle: Text("Method: ${p['method']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => onRemovePayment(idx),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
