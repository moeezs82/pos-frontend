import 'package:flutter/material.dart';

class CBTotals extends StatelessWidget {
  final bool dailyMode;

  // daily
  final String dOpening, dIn, dOut, dExp, dNet, dClosing, dPageIn, dPageOut, dPageExp, dPageNet;

  // txn
  final String opening, inflow, outflow, net, closing, pageInflow, pageOutflow;

  final double Function(String) parse;

  const CBTotals({
    super.key,
    required this.dailyMode,
    required this.dOpening,
    required this.dIn,
    required this.dOut,
    required this.dExp,
    required this.dNet,
    required this.dClosing,
    required this.dPageIn,
    required this.dPageOut,
    required this.dPageExp,
    required this.dPageNet,
    required this.opening,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.closing,
    required this.pageInflow,
    required this.pageOutflow,
    required this.parse,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle label = const TextStyle(fontSize: 12, color: Colors.grey);
    TextStyle value = const TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

    Widget cell(String t, String v, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(t, style: label), Text(v, style: value.copyWith(color: color))],
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: dailyMode
              ? [
                  cell("Opening", dOpening),
                  cell("In", dIn),
                  cell("Out", dOut),
                  cell("Expense", dExp),
                  cell("Net", dNet, color: (parse(dNet) >= 0) ? Colors.green : Colors.red),
                  cell("Closing", dClosing),
                  const Divider(),
                  cell("Page In", dPageIn),
                  cell("Page Out", dPageOut),
                  cell("Page Exp", dPageExp),
                  cell("Page Net", dPageNet, color: (parse(dPageNet) >= 0) ? Colors.green : Colors.red),
                ]
              : [
                  cell("Opening", opening),
                  cell("Inflow", inflow),
                  cell("Outflow", outflow),
                  cell("Net", net, color: (parse(net) >= 0) ? Colors.green : Colors.red),
                  cell("Closing", closing),
                  const Divider(),
                  cell("Page Inflow", pageInflow),
                  cell("Page Outflow", pageOutflow),
                ],
        ),
      ),
    );
  }
}
