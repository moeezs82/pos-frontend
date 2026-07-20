import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/screens/branches/branch_feature_settings_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_select_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BranchControlScreen extends StatelessWidget {
  const BranchControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final branch = context.watch<BranchProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Control'),
      ),
      body: !auth.isMasterAdmin
          ? const _NotAllowedPanel()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: branch.hasActiveBranch ? AppTheme.primarySoft : AppTheme.warning.withOpacity(.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            branch.hasActiveBranch ? Icons.apartment_rounded : Icons.warning_amber_rounded,
                            color: branch.hasActiveBranch ? AppTheme.primary : AppTheme.warning,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Master admin working branch',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.navy),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                branch.hasActiveBranch
                                    ? 'Currently locked to ${branch.label}. All backend data will load for this branch only.'
                                    : 'Select a branch before creating or loading branch-scoped business data.',
                                style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Master Admin tools ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _MasterAdminToolTile(
                    icon: Icons.toggle_on_rounded,
                    title: 'Module & Workflow Settings',
                    subtitle: 'Enable or disable delivery and vendor features per branch.',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BranchFeatureSettingsScreen(),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: BranchSelectSheet()),
              ],
            ),
    );
  }
}

class _MasterAdminToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MasterAdminToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.navy)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotAllowedPanel extends StatelessWidget {
  const _NotAllowedPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.softShadow,
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 42, color: AppTheme.textMuted),
            SizedBox(height: 10),
            Text('Branch switching is available only for master admin.', style: TextStyle(fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text('Normal users work only inside their assigned branch.', style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
