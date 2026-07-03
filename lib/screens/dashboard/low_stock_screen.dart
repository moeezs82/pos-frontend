import 'package:enterprise_pos/api/reports_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Full list of products at or below their reorder level, sourced from the
/// existing 'low-stock' enterprise report (App\Services\Reports\
/// EnterpriseReportService::currentStock with $lowOnly = true). No new
/// backend endpoint was needed for this screen.
class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  final _numberFmt = NumberFormat.decimalPattern();
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token!;
      final service = ReportsService(token: token);
      final data = await service.runEnterpriseReport(
        reportKey: 'low-stock',
        filters: const {'per_page': 200, 'sort_by': 'quantity', 'direction': 'asc'},
      );
      final rows = ((data['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.error(context, 'Failed to load low stock: $e');
    }
  }

  num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return EnterprisePage(
      title: 'Low Stock',
      subtitle: 'Products at or below their reorder level',
      icon: Icons.warning_amber_rounded,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const EnterpriseEmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'All stocked up',
                  subtitle: 'No products are currently at or below their reorder level.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final name = (row['product'] ?? 'Product').toString();
                      final sku = (row['sku'] ?? '—').toString();
                      final qty = _num(row['quantity']);
                      final reorderLevel = _num(row['reorder_level']);
                      final branch = (row['branch'] ?? '').toString();
                      final category = (row['category'] ?? '—').toString();

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.danger.withOpacity(.10),
                            foregroundColor: AppTheme.danger,
                            child: const Icon(Icons.inventory_2_outlined),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                EnterpriseMetricChip(label: 'SKU', value: sku, color: AppTheme.info, icon: Icons.qr_code_rounded),
                                EnterpriseMetricChip(label: 'Category', value: category, color: AppTheme.textMuted),
                                if (branch.isNotEmpty) EnterpriseMetricChip(label: 'Branch', value: branch, color: AppTheme.purple),
                              ],
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _numberFmt.format(qty),
                                style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.danger, fontSize: 16),
                              ),
                              Text(
                                'reorder at ${_numberFmt.format(reorderLevel)}',
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
