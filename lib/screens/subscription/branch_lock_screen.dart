import 'package:enterprise_pos/models/subscription_status.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/screens/login_screen.dart';
import 'package:enterprise_pos/screens/subscription/subscription_management_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_select_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Full-screen lock shown when the current branch's subscription has expired
/// or been suspended.
///
/// WHAT THIS SCREEN DOES
/// • Shows branch name, status, expiry date, and a clear contact message.
/// • Provides Refresh (re-check with server), Logout, and Switch Branch.
/// • Shows a Manage Subscriptions button for the authenticated SaaS Owner.
/// • Does NOT expose any main branch-operational UI behind it.
/// • Does NOT delete locally queued offline sales.
///
/// NAVIGATION
/// This widget is shown by HomeScreen (and BranchControlScreen for master admin)
/// when SubscriptionProvider.isLocked == true.  It is never pushed as a route —
/// it replaces the body of the authenticated scaffold so the Navigator stack and
/// queued data remain intact.
class BranchLockScreen extends StatelessWidget {
  const BranchLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final sub = context.watch<SubscriptionProvider>();
    final status = sub.status;
    final branchName = _branchName(auth);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Lock icon ───────────────────────────────────────────────
                Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _statusIcon(status),
                    color: _statusColor(status),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Headline ────────────────────────────────────────────────
                Text(
                  _headline(status),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 8),

                if (branchName != null)
                  Text(
                    branchName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                const SizedBox(height: 20),

                // ── Status card ─────────────────────────────────────────────
                _StatusCard(status: status, accentColor: _statusColor(status)),
                const SizedBox(height: 24),

                // ── Contact message ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.support_agent_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status?.message.isNotEmpty == true
                              ? status!.message
                              : 'Your access has been restricted. Please contact your platform administrator to restore access.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Refresh button ──────────────────────────────────────────
                if (sub.isChecking)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check Again'),
                      onPressed: () => _refresh(context, auth, sub),
                    ),
                  ),
                const SizedBox(height: 10),

                // ── Owner management link ───────────────────────────────────
                if (auth.isMasterAdmin) ...[
                  // ── Switch Branch (if another branch may be available) ──────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Switch Branch'),
                      onPressed: () => _openBranchSheet(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.manage_accounts_rounded),
                      label: const Text('Manage Subscriptions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionManagementScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Logout ──────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppTheme.danger,
                    ),
                    label: const Text(
                      'Logout',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                    onPressed: () => _logout(context, auth, sub),
                  ),
                ),

                if (sub.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    sub.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? _branchName(AuthProvider auth) {
    final branch = auth.user?['branch'] as Map?;
    return branch?['name']?.toString() ??
        (auth.activeBranchId != null ? 'Branch #${auth.activeBranchId}' : null);
  }

  IconData _statusIcon(SubscriptionStatus? status) {
    if (status?.status == 'not_configured') return Icons.warning_amber_rounded;
    if (status?.status == 'suspended') return Icons.block_rounded;
    return Icons.lock_rounded;
  }

  String _headline(SubscriptionStatus? status) {
    if (status?.status == 'not_configured')
      return 'Subscription Not Configured';
    if (status?.status == 'suspended') return 'Branch Suspended';
    return 'Subscription Expired';
  }

  /// Accent colour for the icon, card border, and status card background.
  /// not_configured uses warning (orange) to distinguish a setup gap from a
  /// hard lock caused by expiry or suspension.
  Color _statusColor(SubscriptionStatus? status) {
    if (status?.status == 'not_configured') return AppTheme.warning;
    return AppTheme.danger;
  }

  Future<void> _refresh(
    BuildContext context,
    AuthProvider auth,
    SubscriptionProvider sub,
  ) async {
    final token = auth.token;
    final branchId = auth.activeBranchId;
    if (token == null || branchId == null) return;
    await sub.refresh(token: token, branchId: branchId);
  }

  Future<void> _logout(
    BuildContext context,
    AuthProvider auth,
    SubscriptionProvider sub,
  ) async {
    await auth.logout();
    await sub.clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openBranchSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const BranchSelectSheet(),
      ),
    );
  }
}

// ── Status card widget ────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final SubscriptionStatus? status;
  final Color accentColor;
  const _StatusCard({this.status, this.accentColor = AppTheme.danger});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final rows = <_InfoRow>[
      _InfoRow('Status', _statusLabel(status!.status)),
      if (status!.expiresAt != null)
        _InfoRow('Expired on', _fmtDate(status!.expiresAt!)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(.05),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: accentColor.withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        r.label,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
    'trial' => 'Trial',
    'active' => 'Active',
    'grace_period' => 'Grace Period',
    'expired' => 'Expired',
    'suspended' => 'Suspended',
    'not_configured' => 'Not Configured',
    _ => s,
  };

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
