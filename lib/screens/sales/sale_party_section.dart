import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';

class PartySectionCard extends StatelessWidget {
  final bool isAll;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedUser;
  final Map<String, dynamic>? selectedBranch;
  final Map<String, dynamic>? selectedVendor;

  final VoidCallback onPickCustomer;
  final VoidCallback onPickUser;
  final VoidCallback onPickVendor;
  final VoidCallback onClearVendor;

  const PartySectionCard({
    super.key,
    required this.isAll,
    required this.selectedCustomer,
    required this.selectedUser,
    required this.selectedBranch,
    required this.selectedVendor,
    required this.onPickCustomer,
    required this.onPickUser,
    required this.onPickVendor,
    required this.onClearVendor,
  });

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer & staff', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final fields = [
                SelectField(
                  label: 'Customer',
                  icon: Icons.person_search_outlined,
                  valueText: selectedCustomer?['first_name']?.toString() ?? 'Walk-in customer',
                  onTap: onPickCustomer,
                ),
                SelectField(
                  label: 'Salesman',
                  icon: Icons.badge_outlined,
                  valueText: selectedUser?['name']?.toString() ?? 'Select salesman',
                  onTap: onPickUser,
                ),
                SelectField(
                  label: 'Vendor',
                  icon: Icons.storefront_outlined,
                  valueText: selectedVendor?['first_name']?.toString() ?? 'Optional',
                  onTap: onPickVendor,
                  showClear: selectedVendor != null,
                  onClear: onClearVendor,
                ),
              ];

              if (!wide) {
                return Column(
                  children: [
                    for (int i = 0; i < fields.length; i++) ...[
                      fields[i],
                      if (i != fields.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class SelectField extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final VoidCallback onTap;
  final bool showClear;
  final VoidCallback? onClear;

  const SelectField({
    super.key,
    required this.label,
    required this.valueText,
    required this.icon,
    required this.onTap,
    this.showClear = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (showClear)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
