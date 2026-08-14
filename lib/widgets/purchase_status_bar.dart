import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Compact status strip at the top of the Create Purchase screen.
///
/// [light] = false (default) → original dark navy bar (36 px).
/// [light] = true            → white/light bar (30 px) matching the reference
///                             POS layout (teal text for branch, dark text for
///                             other items, bottom border).
class PurchaseStatusBar extends StatefulWidget {
  final bool light;
  final bool showBackButton;

  const PurchaseStatusBar({super.key, this.light = false, this.showBackButton = false});

  @override
  State<PurchaseStatusBar> createState() => _PurchaseStatusBarState();
}

class _PurchaseStatusBarState extends State<PurchaseStatusBar> {
  // ── Clock ────────────────────────────────────────────────────────────────
  late DateTime _now;
  Timer? _clock;

  // ── Connectivity ─────────────────────────────────────────────────────────
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Read initial connectivity state without blocking initState.
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      setState(() => _online = results.any((r) => r != ConnectivityResult.none));
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => _online = results.any((r) => r != ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String get _timeStr {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _dateStr {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[_now.month - 1]} ${_now.day}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shift = context.watch<RegisterShiftProvider>();

    final userName = _extractName(auth.user);
    final roleLabel = _extractRole(auth.user);

    final isLight = widget.light;
    final barHeight = isLight ? 30.0 : 36.0;
    final bgColor = isLight ? Colors.white : AppTheme.navy;
    final textColor = isLight ? AppTheme.navy : Colors.white;
    final mutedColor =
        isLight ? AppTheme.textMuted : const Color(0xFF94A3B8);
    final iconColor = mutedColor;

    return Container(
      height: barHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: isLight
            ? const Border(
                bottom: BorderSide(color: AppTheme.border),
              )
            : null,
      ),
      child: Row(
        children: [
          // Back button
          if (widget.showBackButton && Navigator.canPop(context))
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(Icons.arrow_back_rounded, size: 16, color: iconColor),
              ),
            ),

          // Branch chip (master admin only)
          const BranchIndicator(),

          // Cashier name + role
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_rounded, size: 13, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  userName,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: .1,
                  ),
                ),
                if (roleLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _RolePill(label: roleLabel, light: isLight),
                ],
              ],
            ),
          ),

          const Spacer(),

          if (shift.hasActiveShift) ...[
            Icon(Icons.point_of_sale_rounded, size: 13, color: AppTheme.success),
            const SizedBox(width: 4),
            Text('Shift #${shift.id}', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
          ],

          // Connectivity indicator
          _ConnectivityDot(online: _online),

          const SizedBox(width: 8),

          // Date / time
          Text(
            '$_dateStr  $_timeStr',
            style: TextStyle(
              color: mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),

          const SizedBox(width: 8),

          // Shortcuts guide button
          Tooltip(
            message: 'Keyboard shortcuts  (Ctrl + /)',
            preferBelow: true,
            child: InkWell(
              onTap: () => showAppShortcutGuide(
                context,
                extra: PosShortcutCatalog.purchaseCreate,
              ),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_rounded, size: 14, color: iconColor),
                    const SizedBox(width: 4),
                    Text(
                      'Shortcuts',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

String _extractName(Map<String, dynamic>? user) {
  if (user == null) return 'Cashier';
  final n = user['name'] ?? user['display_name'] ?? user['username'] ?? '';
  final s = n.toString().trim();
  return s.isEmpty ? 'Cashier' : s;
}

String _extractRole(Map<String, dynamic>? user) {
  if (user == null) return '';
  // Try flattened role_name first (normalized by AuthProvider._normalizeUser)
  final flat = (user['role_name'] ?? user['role_label'] ?? '').toString().trim();
  if (flat.isNotEmpty) return flat;

  // Then try nested roles array from Sanctum/Spatie response
  final roles = user['roles'];
  if (roles is List && roles.isNotEmpty) {
    final first = roles.first;
    if (first is Map) return (first['name'] ?? first['label'] ?? '').toString();
    return first.toString();
  }
  return '';
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _RolePill extends StatelessWidget {
  final String label;
  final bool light;

  const _RolePill({required this.label, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: light ? AppTheme.surfaceSoft : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: light ? AppTheme.border : const Color(0xFF334155),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: light ? AppTheme.textMuted : const Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _ConnectivityDot extends StatelessWidget {
  final bool online;

  const _ConnectivityDot({required this.online});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: online ? AppTheme.success : AppTheme.danger,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (online ? AppTheme.success : AppTheme.danger).withOpacity(.45),
                blurRadius: 5,
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(
            color: online ? AppTheme.success : AppTheme.danger,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

