import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BranchIndicator extends StatelessWidget {
  final bool tappable;
  final VoidCallback? onTap;

  const BranchIndicator({super.key, this.tappable = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BranchProvider>();
    final auth = context.watch<AuthProvider>();

    // Branch information is a master-admin-only UI concern. Normal branch users
    // are already scoped by backend and should not see any branch traces.
    if (!auth.isMasterAdmin) {
      return const SizedBox.shrink();
    }

    final canTap = tappable && onTap != null;
    final hasBranch = bp.hasActiveBranch;

    final child = Chip(
      avatar: Icon(
        hasBranch ? Icons.apartment_rounded : Icons.warning_amber_rounded,
        size: 17,
        color: Colors.white,
      ),
      label: Text(
        bp.label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      backgroundColor: hasBranch ? const Color(0xFF0F766E) : const Color(0xFFB45309),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );

    const tooltip = 'Master admin active working branch. Change it only from Branch Control.';

    if (!canTap) {
      return Tooltip(message: tooltip, child: child);
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
