import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BranchIndicator extends StatelessWidget {
  final bool tappable; // if true, allow onTap; else show hint
  final VoidCallback? onTap;

  const BranchIndicator({super.key, this.tappable = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BranchProvider>();
    final text = bp.label;

    final child = Chip(
      label: Text(
        text,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: Colors.blueGrey,
      visualDensity: VisualDensity.compact,
    );

    if (!tappable) {
      return Tooltip(
        message: "Change branch on Home",
        child: child,
      );
    }
    return InkWell(onTap: onTap, child: child);
  }
}
