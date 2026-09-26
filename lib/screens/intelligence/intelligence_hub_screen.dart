import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/intelligence_settings_screen.dart';
import 'package:enterprise_pos/screens/intelligence/money_finder_screen.dart';
import 'package:enterprise_pos/screens/intelligence/replenishment_screen.dart';
import 'package:enterprise_pos/screens/intelligence/seasons_screen.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IntelligenceHubScreen extends StatelessWidget {
  const IntelligenceHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canMoney = auth.hasPermission('view-margin-intelligence') || auth.hasPermission('view-staff-intelligence');
    final canReplenish = auth.hasPermission('view-margin-intelligence');
    final canSeasons = auth.hasPermission('manage-business-seasons');
    final canSettings = auth.hasPermission('manage-intelligence-settings');

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Intelligence')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const IntelligencePageHeader(
            title: 'CounterIQ Intelligence',
            subtitle: 'Operational answers derived from the sales and inventory history you already record. No hidden data capture and no automatic business writes.',
          ),
          const SizedBox(height: 16),
          const IntelligenceInfoBanner(
            icon: Icons.verified_user_outlined,
            title: 'Advisory by design',
            message: 'These screens help owners and managers review pricing, discounting, dead stock and replenishment. They do not automatically change prices, journals, stock or historical transactions.',
            color: AppTheme.primary,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              if (canMoney)
                _HubCard(
                  icon: Icons.savings_outlined,
                  title: 'Money Finder',
                  subtitle: 'Margin leaks, discount observations, repricing alerts and dead stock in one clear review area.',
                  color: AppTheme.warning,
                  bullets: const [
                    'Recoverable margin',
                    'Professional discount review',
                    'Repricing watchlist',
                    'Dead stock exposure',
                  ],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoneyFinderScreen())),
                ),
              if (canReplenish)
                _HubCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Replenishment',
                  subtitle: 'See what to buy, how much and why, using measured velocity, lead time and days of cover.',
                  color: AppTheme.info,
                  bullets: const [
                    'Vendor-grouped reorder view',
                    'Days of cover',
                    'Season uplift awareness',
                    'Package-aware suggestions',
                  ],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplenishmentScreen())),
                ),
              if (canSeasons)
                _HubCard(
                  icon: Icons.event_repeat_rounded,
                  title: 'Business Seasons',
                  subtitle: 'Maintain owner-declared demand seasons such as Ramadan, Eid, summer and wedding season.',
                  color: AppTheme.purple,
                  bullets: const [
                    'Annual fixed seasons',
                    'Year-specific declared dates',
                    'Product / brand / category tagging',
                    'No guessed religious dates',
                  ],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SeasonsScreen())),
                ),
              if (canSettings)
                _HubCard(
                  icon: Icons.tune_rounded,
                  title: 'Intelligence Settings',
                  subtitle: 'Tune thresholds and advisory logic such as margin floors, dead-stock days and velocity windows.',
                  color: AppTheme.primary,
                  bullets: const [
                    'Margin targets',
                    'Velocity windows',
                    'Lead-time fallback',
                    'Snapshot cache TTL',
                  ],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen())),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<String> bullets;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.bullets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withOpacity(.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, color: AppTheme.textMuted),
                  ],
                ),
                const SizedBox(height: 14),
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
                const SizedBox(height: 14),
                ...bullets.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
