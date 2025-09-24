import 'package:flutter/material.dart';

class CBTxnList extends StatelessWidget {
  final List<Map<String, dynamic>> txns;
  const CBTxnList({super.key, required this.txns});

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) return const Center(child: Text("No transactions found"));

    return ListView.builder(
      itemCount: txns.length,
      itemBuilder: (_, i) {
        final t = txns[i];
        final type = (t['type'] ?? '').toString();
        final date = (t['date'] ?? '').toString();
        final amount = (t['amount'] ?? '0.00').toString();
        final method = (t['method'] ?? '').toString();
        final note = (t['note'] ?? '').toString();
        final reference = (t['reference'] ?? '').toString();
        final running = (t['running_balance'] ?? '0.00').toString();
        final source = (t['source'] ?? '').toString();

        final isIn = (type == 'receipt' || type == 'transfer_in');
        final sign = isIn ? '+' : '-';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: ListTile(
            title: Text(
              "$date • ${type.toUpperCase()} • $sign$amount",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isIn ? Colors.green : Colors.red,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reference.isNotEmpty) Text("Ref: $reference"),
                if (method.isNotEmpty) Text("Method: $method"),
                if (source.isNotEmpty) Text("Source: $source"),
                if (note.isNotEmpty) Text(note),
              ],
            ),
            trailing: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [Text("Running")],
            ),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet),
                Text(running, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}
