import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SalesOrderTimeline extends StatelessWidget {
  final List<SalesOrderEvent> events;

  const SalesOrderTimeline({
    super.key,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text(
          'No activity events recorded for this order yet.',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Activity & Approval Timeline (${events.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final event = events[index];
              final isLast = index == events.length - 1;
              return _buildTimelineItem(event, isLast: isLast);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(SalesOrderEvent event, {required bool isLast}) {
    final color = _actionColor(event.action);
    final icon = _actionIcon(event.action);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _actionTitle(event.action),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (event.fromStatus != null && event.toStatus != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSoft,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        '${event.fromStatus} → ${event.toStatus}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (event.createdAt != null)
                    Text(
                      event.createdAt!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'By ${event.user?.name ?? 'User #${event.userId}'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navy,
                ),
              ),
              if (event.notes != null && event.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    event.notes!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.navy,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _actionColor(String action) {
    switch (action.toUpperCase()) {
      case 'CREATED':
        return AppTheme.textMuted;
      case 'UPDATED':
        return AppTheme.info;
      case 'SUBMITTED':
        return AppTheme.info;
      case 'APPROVED':
        return AppTheme.success;
      case 'CONVERTED':
      case 'CONVERT_RECONCILED':
        return AppTheme.primary;
      case 'REJECTED':
      case 'CANCELLED':
      case 'CONVERT_FAILED':
        return AppTheme.danger;
      case 'RETURNED_TO_DRAFT':
      case 'CONVERT_ROLLED_BACK':
        return AppTheme.warning;
      default:
        return AppTheme.primary;
    }
  }

  IconData _actionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'CREATED':
        return Icons.note_add_outlined;
      case 'UPDATED':
        return Icons.edit_outlined;
      case 'SUBMITTED':
        return Icons.send_rounded;
      case 'APPROVED':
        return Icons.check_circle_outline_rounded;
      case 'CONVERTED':
        return Icons.point_of_sale_rounded;
      case 'CONVERT_RECONCILED':
        return Icons.build_circle_outlined;
      case 'REJECTED':
        return Icons.thumb_down_alt_outlined;
      case 'CANCELLED':
        return Icons.cancel_outlined;
      case 'CONVERT_FAILED':
        return Icons.error_outline_rounded;
      case 'RETURNED_TO_DRAFT':
        return Icons.replay_rounded;
      case 'CONVERT_ROLLED_BACK':
        return Icons.undo_rounded;
      default:
        return Icons.timeline_rounded;
    }
  }

  String _actionTitle(String action) {
    switch (action.toUpperCase()) {
      case 'CREATED':
        return 'Order Created';
      case 'UPDATED':
        return 'Order Updated';
      case 'SUBMITTED':
        return 'Submitted for Approval';
      case 'APPROVED':
        return 'Order Approved';
      case 'CONVERTED':
        return 'Converted to Invoice';
      case 'CONVERT_RECONCILED':
        return 'Conversion Reconciled';
      case 'CONVERT_ROLLED_BACK':
        return 'Conversion Rolled Back';
      case 'CONVERT_FAILED':
        return 'Conversion Failed';
      case 'REJECTED':
        return 'Order Rejected';
      case 'CANCELLED':
        return 'Order Cancelled';
      case 'RETURNED_TO_DRAFT':
        return 'Returned to Draft';
      default:
        return action;
    }
  }
}
