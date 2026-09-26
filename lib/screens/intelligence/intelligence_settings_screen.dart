import 'package:enterprise_pos/api/intelligence_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/intelligence/widgets/intelligence_widgets.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IntelligenceSettingsScreen extends StatefulWidget {
  const IntelligenceSettingsScreen({super.key});

  @override
  State<IntelligenceSettingsScreen> createState() => _IntelligenceSettingsScreenState();
}

class _IntelligenceSettingsScreenState extends State<IntelligenceSettingsScreen> {
  IntelligenceService? _service;
  Object? _error;
  bool _loading = true;
  bool _saving = false;
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};

  static const List<_FieldDef> _fields = <_FieldDef>[
    _FieldDef('target_margin_pct', 'Target margin %', 'Used by repricing and replenishment economics.', group: 'Margins', percent: true),
    _FieldDef('min_margin_pct', 'Minimum margin floor %', 'Money Finder recoverable floor.', group: 'Margins', percent: true),
    _FieldDef('dead_stock_days', 'Dead stock days', 'No-sale threshold before stock is classed dead.', group: 'Stock'),
    _FieldDef('velocity_short_days', 'Short velocity window', 'Recent demand window in days.', group: 'Velocity'),
    _FieldDef('velocity_mid_days', 'Mid velocity window', 'Primary demand window in days.', group: 'Velocity'),
    _FieldDef('velocity_long_days', 'Long velocity window', 'Long context / anomaly window in days.', group: 'Velocity'),
    _FieldDef('review_period_days', 'Review period days', 'How far beyond lead time the suggested order covers.', group: 'Replenishment'),
    _FieldDef('service_level_z', 'Service-level Z', 'Statistical safety-stock factor.', group: 'Replenishment', decimal: true),
    _FieldDef('safety_days_fallback', 'Fallback safety days', 'Used while statistical history is still thin.', group: 'Replenishment'),
    _FieldDef('default_lead_time_days', 'Default vendor lead time', 'Used only when no configured/measured vendor lead time exists.', group: 'Replenishment'),
    _FieldDef('snapshot_ttl_minutes', 'Snapshot cache minutes', 'How long calculated intelligence can be reused.', group: 'System'),
  ];

  IntelligenceService _api() => _service ??= IntelligenceService(token: context.read<AuthProvider>().token!);

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field.key] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final envelope = await _api().settings();
      final result = asMap(envelope.result);
      for (final field in _fields) {
        final dynamic value = result[field.key];
        if (field.percent && value is num) {
          _controllers[field.key]!.text = (value * 100).toStringAsFixed(1);
        } else {
          _controllers[field.key]!.text = value?.toString() ?? '';
        }
      }
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> body = <String, dynamic>{};
      for (final field in _fields) {
        final raw = _controllers[field.key]!.text.trim();
        if (raw.isEmpty) continue;
        if (field.decimal || field.percent) {
          final number = double.parse(raw);
          body[field.key] = field.percent ? number / 100 : number;
        } else {
          body[field.key] = int.parse(raw);
        }
      }
      await _api().updateSettings(body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Intelligence settings saved. Cached calculations were invalidated.')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Intelligence Settings')),
        body: IntelligenceError(error: _error!, onRetry: _load),
      );
    }

    final Map<String, List<_FieldDef>> grouped = <String, List<_FieldDef>>{};
    for (final field in _fields) {
      grouped.putIfAbsent(field.group, () => <_FieldDef>[]).add(field);
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Intelligence Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const IntelligencePageHeader(
            title: 'Advisory calculation settings',
            subtitle: 'These values tune intelligence logic only. Saving does not alter historical sales, stock, prices, accounting or journal entries.',
          ),
          const SizedBox(height: 16),
          const IntelligenceInfoBanner(
            icon: Icons.tune_rounded,
            title: 'Settings only change future calculations',
            message: 'Use these fields to tune thresholds, confidence windows and reorder behaviour. After saving, CounterIQ recalculates intelligence using the updated rules.',
            color: AppTheme.info,
          ),
          const SizedBox(height: 16),
          ...grouped.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IntelligenceSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(_groupHelp(entry.key), style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: entry.value.map((field) => _fieldCard(field)).toList(),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _fieldCard(_FieldDef field) {
    return SizedBox(
      width: 320,
      child: TextField(
        controller: _controllers[field.key],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.help,
          helperMaxLines: 3,
          suffixText: field.percent ? '%' : null,
        ),
      ),
    );
  }

  String _groupHelp(String group) {
    switch (group) {
      case 'Margins':
        return 'Controls how strictly CounterIQ evaluates product pricing and recoverable margin.';
      case 'Velocity':
        return 'Defines the short, mid and long windows used when measuring demand.';
      case 'Replenishment':
        return 'Affects days of cover, safety stock and default lead time behaviour.';
      case 'Stock':
        return 'Defines how long stock can sit before it is treated as dead stock.';
      default:
        return 'Operational settings that control caching and supporting system behaviour.';
    }
  }
}

class _FieldDef {
  final String key;
  final String label;
  final String help;
  final String group;
  final bool percent;
  final bool decimal;

  const _FieldDef(
    this.key,
    this.label,
    this.help, {
    required this.group,
    this.percent = false,
    this.decimal = false,
  });
}
