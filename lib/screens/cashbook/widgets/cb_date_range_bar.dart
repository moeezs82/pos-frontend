import 'package:flutter/material.dart';

class CBDateRangeBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final String Function(DateTime) fmt;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const CBDateRangeBar({
    super.key,
    required this.from,
    required this.to,
    required this.fmt,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: {
          Expanded(
            child: InkWell(
              onTap: onPick,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Date Range",
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  (from == null && to == null)
                      ? "All dates"
                      : "${fmt(from!)} → ${fmt(to!)}",
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            label: const Text("Clear Dates"),
          ),
        }.toList(),
      ),
    );
  }
}
