import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductVelocitySheet extends StatefulWidget {
  final int productId;
  final String productName;

  const ProductVelocitySheet({super.key, required this.productId, required this.productName});

  @override
  State<ProductVelocitySheet> createState() => _ProductVelocitySheetState();
}

class _ProductVelocitySheetState extends State<ProductVelocitySheet> {
  IntelligenceEnvelope? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final envelope = await IntelligenceService(token: context.read<AuthProvider>().token!).productVelocity(widget.productId);
      if (mounted) {
        setState(() => _data = envelope);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .78,
        child: _error != null
            ? IntelligenceError(error: _error!, onRetry: _load)
            : _data == null
                ? const Center(child: CircularProgressIndicator())
                : _body(),
      ),
    );
  }

  Widget _body() {
    final result = asMap(_data!.result);
    final windows = asMap(result['windows']);
    final season = asMap(result['season']);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.productName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StockClassBadge(value: result['class']?.toString() ?? ''),
                      if ((result['trend']?.toString() ?? '').isNotEmpty)
                        IssueChip(label: titleCase(result['trend'].toString()), color: AppTheme.info),
                      ConfidenceBadge(basis: result['basis']),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: windows.entries.map((entry) {
            final window = asMap(entry.value);
            return MetricCard(
              title: '${window['days'] ?? entry.key} day velocity',
              value: '${(window['velocity_per_day'] as num?)?.toStringAsFixed(2) ?? '0.00'} / day',
              caption: '${qty(window['net_sold'])} sold • ${window['active_days'] ?? 0} active days • ${window['observations'] ?? 0} observations',
              icon: Icons.speed_rounded,
              color: AppTheme.info,
            );
          }).toList(),
        ),
        if ((result['estimated_stockout_days'] as num? ?? 0) > 0) ...[
          const SizedBox(height: 16),
          IntelligenceInfoBanner(
            icon: Icons.warning_amber_rounded,
            title: 'Possible understated demand',
            message: 'Velocity may be understated because approximately ${result['estimated_stockout_days']} stockout days were reconstructed from movement history.',
            color: AppTheme.warning,
          ),
        ],
        if (season.isNotEmpty) ...[
          const SizedBox(height: 16),
          IntelligenceSectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppTheme.purple.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.event_repeat_rounded, color: AppTheme.purple),
              ),
              title: Text(season['name']?.toString() ?? 'Season', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(
                '${titleCase(season['state']?.toString() ?? '')} • ${(season['uplift'] as num?)?.toStringAsFixed(2) ?? '1.00'}× measured uplift • ${season['prior_occurrences'] ?? 0} prior occurrences',
                style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
              ),
              trailing: ConfidenceBadge(basis: season['basis']),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const IntelligenceInfoBanner(
          icon: Icons.insights_outlined,
          title: 'How to read this',
          message: 'This panel explains how the replenishment engine classified the product. The higher the confidence, the more history and observed selling days support the classification.',
          color: AppTheme.info,
        ),
      ],
    );
  }
}
