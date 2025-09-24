import 'package:flutter/material.dart';

class CBModeToggle extends StatelessWidget {
  final bool dailyMode;
  final ValueChanged<bool> onChanged;
  const CBModeToggle({super.key, required this.dailyMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ToggleButtons(
        isSelected: [dailyMode == false, dailyMode == true],
        onPressed: (idx) => onChanged(idx == 1),
        borderRadius: BorderRadius.circular(8),
        constraints: const BoxConstraints(minWidth: 90),
        children: const [
          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Transactions")),
          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Daily")),
        ],
      ),
    );
  }
}
