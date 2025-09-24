import 'package:flutter/material.dart';

class CBDailyList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const CBDailyList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text("No daily data"));

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final date = (r['date'] ?? '').toString();
        final pin = (r['payment_in'] ?? '0.00').toString();
        final pout = (r['payment_out'] ?? '0.00').toString();
        final exp = (r['expense'] ?? '0.00').toString();
        final net = (r['net'] ?? '0.00').toString();
        final closing = (r['closing'] ?? '0.00').toString();
        final opening = (r['opening'] ?? '0.00').toString();

        final netVal = double.tryParse(net) ?? 0.0;
        final netColor = netVal >= 0 ? Colors.green : Colors.red;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: ListTile(
            title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _kv("Opening", opening, bold: true),
                  _kv("In", pin),
                  _kv("Out", pout),
                  _kv("Expense", exp),
                  _kv("Net", net, color: netColor, bold: true),
                  _kv("Closing", closing, bold: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {Color? color, bool bold = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          v,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
