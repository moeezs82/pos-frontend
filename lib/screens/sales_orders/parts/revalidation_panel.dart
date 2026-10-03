import 'package:enterprise_pos/models/sales_order_revalidation.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';

class RevalidationPanel extends StatelessWidget {
  final RevalidationReport? report;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;
  final bool canConvert;
  final ValueChanged<String>? onCreditOverrideApproved;

  const RevalidationPanel({
    super.key,
    required this.report,
    this.loading = false,
    this.error,
    this.onRefresh,
    this.canConvert = false,
    this.onCreditOverrideApproved,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && report == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Running pre-conversion revalidation check...',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (error != null && report == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.danger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Revalidation check failed: $error',
                style: const TextStyle(
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    final rep = report;
    if (rep == null) return const SizedBox.shrink();

    // Terminal status check: applicable == false
    if (!rep.applicable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Order is in a terminal status (${rep.status}). Pre-conversion revalidation is not applicable.',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final blocking = rep.blocking;
    final warnings = rep.warnings;
    final credit = rep.credit;
    final isClean = blocking.isEmpty && warnings.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isClean
            ? AppTheme.success.withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClean
              ? AppTheme.success.withOpacity(0.3)
              : (blocking.isNotEmpty
                  ? AppTheme.danger.withOpacity(0.3)
                  : AppTheme.warning.withOpacity(0.3)),
        ),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of revalidation panel
          Row(
            children: [
              Icon(
                isClean
                    ? Icons.check_circle_outline_rounded
                    : (blocking.isNotEmpty
                        ? Icons.cancel_outlined
                        : Icons.warning_amber_rounded),
                color: isClean
                    ? AppTheme.success
                    : (blocking.isNotEmpty
                        ? AppTheme.danger
                        : AppTheme.warning),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isClean
                      ? 'Ready to Convert'
                      : (blocking.isNotEmpty
                          ? '${blocking.length} Blocking Issue${blocking.length > 1 ? 's' : ''} Must Be Resolved'
                          : '${warnings.length} Warning${warnings.length > 1 ? 's' : ''} (Conversion Permitted)'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: isClean
                        ? AppTheme.success
                        : (blocking.isNotEmpty
                            ? AppTheme.danger
                            : AppTheme.warning),
                  ),
                ),
              ),
              if (rep.stale) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 13, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Text(
                        '${rep.ageHours.toStringAsFixed(1)}h old',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Re-run validation check',
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),

          if (isClean) ...[
            const SizedBox(height: 6),
            const Text(
              'All items and customer requirements pass authoritative checks. Order is safe for invoice conversion.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          // Blocking issues
          if (blocking.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...blocking.map((issue) => _buildIssueRow(
                  context,
                  issue: issue,
                  isBlocking: true,
                  credit: credit,
                )),
          ],

          // Warnings
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...warnings.map((issue) => _buildIssueRow(
                  context,
                  issue: issue,
                  isBlocking: false,
                  credit: credit,
                )),
          ],

          // Converter open register shift check (shown ONLY to users who can convert)
          if (canConvert && !rep.converter.hasOpenRegisterShift) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.warning.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.point_of_sale_rounded,
                      size: 16, color: AppTheme.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You do not have an open register shift. Open a cash shift before converting this order.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIssueRow(
    BuildContext context, {
    required RevalidationIssue issue,
    required bool isBlocking,
    RevalidationCredit? credit,
  }) {
    final color = isBlocking ? AppTheme.danger : AppTheme.warning;
    final lineNum = issue.lineNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isBlocking
                    ? Icons.highlight_off_rounded
                    : Icons.report_problem_outlined,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),
              if (lineNum != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Line $lineNum',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  issue.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),

          // Specialized data chips for STOCK_SHORTFALL
          if (issue.code == 'STOCK_SHORTFALL') ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _inlineMetric(
                    'Ordered',
                    issue.data['ordered']?.toString() ?? '?',
                    color,
                  ),
                  _inlineMetric(
                    'Available in Branch',
                    issue.data['available']?.toString() ?? '0',
                    color,
                  ),
                  _inlineMetric(
                    'Shortfall',
                    issue.data['shortfall']?.toString() ?? '?',
                    color,
                    isHighlight: true,
                  ),
                ],
              ),
            ),
          ],

          // Specialized data chips for PRICE_DRIFT
          if (issue.code == 'PRICE_DRIFT') ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _inlineMetric(
                    'Quoted',
                    AppCurrency.format(
                        _toDouble(issue.data['quoted'])),
                    color,
                  ),
                  _inlineMetric(
                    'Reference',
                    AppCurrency.format(
                        _toDouble(issue.data['reference'])),
                    color,
                  ),
                  _inlineMetric(
                    'Basis',
                    (issue.data['basis']?.toString() ?? 'retail').toUpperCase(),
                    color,
                  ),
                ],
              ),
            ),
          ],

          // Specialized credit block button
          if (issue.code == 'CREDIT_LIMIT_BLOCKED' && credit != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _inlineMetric(
                    'Limit',
                    AppCurrency.format(credit.creditLimit ?? 0),
                    color,
                  ),
                  _inlineMetric(
                    'Balance',
                    AppCurrency.format(credit.balance),
                    color,
                  ),
                  _inlineMetric(
                    'Projected',
                    AppCurrency.format(credit.projectedBalance),
                    color,
                  ),
                  if (credit.canOverride)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final issue = credit.toCreditLimitIssue();
                        final reason = await showCreditLimitOverrideDialog(
                          context,
                          issue,
                        );
                        if (reason != null &&
                            onCreditOverrideApproved != null) {
                          onCreditOverrideApproved!(reason);
                        }
                      },
                      icon: const Icon(Icons.shield_outlined, size: 14),
                      label: const Text('Override Credit Limit'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppTheme.danger,
                        side: const BorderSide(color: AppTheme.danger),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inlineMetric(
    String label,
    String value,
    Color baseColor, {
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlight ? baseColor : AppTheme.border,
          width: isHighlight ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isHighlight ? baseColor : AppTheme.navy,
            ),
          ),
        ],
      ),
    );
  }

  double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    return double.tryParse(val?.toString() ?? '') ?? 0.0;
  }
}
