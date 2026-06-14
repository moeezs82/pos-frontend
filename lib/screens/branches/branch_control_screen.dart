import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
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
                const Expanded(child: BranchSelectSheet()),
              ],
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
