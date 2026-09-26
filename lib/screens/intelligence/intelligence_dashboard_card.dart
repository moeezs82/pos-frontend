import 'dart:ui';

import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/intelligence_hub_screen.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IntelligenceDashboardCard extends StatefulWidget {
  const IntelligenceDashboardCard({super.key});

  @override
  State<IntelligenceDashboardCard> createState() => _IntelligenceDashboardCardState();
}

class _IntelligenceDashboardCardState extends State<IntelligenceDashboardCard> {
  bool _loading = true;
  bool _obscured = true;
  String _recoverable = '0.00';
  int _lines = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthProvider>().token!;
      final envelope = await IntelligenceService(token: token).marginLeaks(groupBy: 'product', perPage: 1);
      final totals = asMap(asMap(envelope.result)['totals']);
      if (mounted) {
        setState(() {
          _recoverable = money(totals['recoverable']);
          _lines = (totals['lines_flagged'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceHubScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppTheme.warning.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.warning),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Intelligence • Money Finder', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text('Quick view of recoverable margin in the current branch.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 8),
                    if (_loading)
                      const SizedBox(width: 120, child: LinearProgressIndicator())
                    else
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: _obscured ? 7 : 0, sigmaY: _obscured ? 7 : 0),
                        child: Text(
                          '$_recoverable recoverable • $_lines flagged lines',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.warning),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _obscured ? 'Show figure' : 'Hide figure',
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(_obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
