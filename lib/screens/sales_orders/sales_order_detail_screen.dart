import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/sales_order_revalidation.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/reason_dialog.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/revalidation_panel.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/sales_order_items_table.dart';
import 'package:enterprise_pos/screens/sales_orders/parts/sales_order_timeline.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesOrderDetailScreen extends StatefulWidget {
  final int orderId;

  const SalesOrderDetailScreen({super.key, required this.orderId});

  @override
  State<SalesOrderDetailScreen> createState() => _SalesOrderDetailScreenState();
}

class _SalesOrderDetailScreenState extends State<SalesOrderDetailScreen> {
  SalesOrder? _order;
  RevalidationReport? _revalidationReport;

  bool _loading = true;
  bool _revalidating = false;
  bool _mutating = false;
  String? _loadError;
  bool _isNotFound = false;
  String? _creditOverrideReason;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  SalesOrderService _service() {
    final token = context.read<AuthProvider>().token!;
    return SalesOrderService(token: token);
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _isNotFound = false;
    });

    try {
      final s = _service();
      final orderFuture = s.getOrder(widget.orderId);
      final revalFuture = s
          .revalidate(widget.orderId)
          .then<RevalidationReport?>((r) => r)
          .catchError((_) => null);

      final order = await orderFuture;
      final report = await revalFuture;

      if (!mounted) return;
      setState(() {
        _order = order;
        _revalidationReport = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 404) {
        setState(() {
          _isNotFound = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _revalidateOnly() async {
    if (_order == null) return;
    setState(() => _revalidating = true);
    try {
      final report = await _service().revalidate(_order!.id);
      if (!mounted) return;
      setState(() {
        _revalidationReport = report;
        _revalidating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _revalidating = false);
    }
  }

  Future<void> _handleApprove() async {
    final order = _order;
    if (order == null || _mutating) return;

    if (_revalidationReport?.hasBlockingIssues == true) {
      AppFeedback.error(
        context,
        'Cannot approve: ${_revalidationReport!.blocking.length} blocking issue(s) must be resolved first.',
      );
      return;
    }

    setState(() => _mutating = true);
    try {
      final updated = await _service().approve(order.id, version: order.version);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _mutating = false;
      });
      AppFeedback.success(context, 'Sales order #${order.orderNumber} approved.');
      _revalidateOnly();
    } catch (e) {
      _handleMutationError(e, 'approve');
    }
  }

  Future<void> _handleReject() async {
    final order = _order;
    if (order == null || _mutating) return;

    final reason = await showSalesOrderReasonDialog(
      context: context,
      title: 'Reject Sales Order',
      labelText: 'Rejection Reason *',
      hintText: 'Explain why this order is rejected...',
      confirmText: 'Reject Order',
      confirmColor: AppTheme.danger,
      icon: Icons.thumb_down_alt_outlined,
      isRequired: true,
    );

    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() => _mutating = true);
    try {
      final updated = await _service().reject(
        order.id,
        reason: reason.trim(),
        version: order.version,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _mutating = false;
      });
      AppFeedback.success(context, 'Sales order #${order.orderNumber} rejected.');
      _revalidateOnly();
    } catch (e) {
      _handleMutationError(e, 'reject');
    }
  }

  Future<void> _handleCancel() async {
    final order = _order;
    if (order == null || _mutating) return;

    final reason = await showSalesOrderReasonDialog(
      context: context,
      title: 'Cancel Sales Order',
      labelText: 'Cancellation Reason (Optional)',
      hintText: 'Reason for cancellation...',
      confirmText: 'Cancel Order',
      confirmColor: AppTheme.danger,
      icon: Icons.cancel_outlined,
      isRequired: false,
    );

    if (reason == null || !mounted) return;

    setState(() => _mutating = true);
    try {
      final updated = await _service().cancel(
        order.id,
        reason: reason.trim(),
        version: order.version,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _mutating = false;
      });
      AppFeedback.success(context, 'Sales order #${order.orderNumber} cancelled.');
      _revalidateOnly();
    } catch (e) {
      _handleMutationError(e, 'cancel');
    }
  }

  Future<void> _handleReturnToDraft() async {
    final order = _order;
    if (order == null || _mutating) return;

    setState(() => _mutating = true);
    try {
      final updated = await _service().returnToDraft(order.id, version: order.version);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _mutating = false;
      });
      AppFeedback.success(context, 'Sales order #${order.orderNumber} returned to draft.');
      _revalidateOnly();
    } catch (e) {
      _handleMutationError(e, 'return to draft');
    }
  }

  Future<void> _handleReconcile() async {
    final order = _order;
    if (order == null || _mutating) return;

    setState(() => _mutating = true);
    try {
      final updated = await _service().reconcile(order.id);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _mutating = false;
      });
      AppFeedback.success(context, 'Order conversion reconciled successfully.');
      _revalidateOnly();
    } catch (e) {
      _handleMutationError(e, 'reconcile');
    }
  }

  Future<void> _handleConvertToSale() async {
    final order = _order;
    if (order == null) return;

    final prefill = SalesOrderPrefill(
      order: order,
      creditLimitOverrideReason: _creditOverrideReason,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateSaleScreen(salesOrderPrefill: prefill),
      ),
    );

    if (mounted) {
      _loadData();
    }
  }

  void _handleMutationError(Object e, String actionName) {
    if (!mounted) return;
    setState(() => _mutating = false);

    if (e is ApiException) {
      final code = e.body?['code']?.toString();

      // 409 Already Converted
      if (e.statusCode == 409 && code == 'SALES_ORDER_ALREADY_CONVERTED') {
        final data = e.body?['data'] as Map<String, dynamic>?;
        final saleId = (data?['sale_id'] as num?)?.toInt();
        final invoiceNo = data?['invoice_no']?.toString() ?? 'an existing invoice';

        showDialog(
          context: context,
          builder: (dContext) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.info),
                SizedBox(width: 8),
                Text('Already Invoiced'),
              ],
            ),
            content: Text(
              'This sales order was already converted into invoice $invoiceNo by another session.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dContext),
                child: const Text('Close'),
              ),
              if (saleId != null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SaleDetailScreen(saleId: saleId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Open Invoice'),
                ),
            ],
          ),
        );
        _loadData();
        return;
      }

      // 409 Version Conflict
      if (e.statusCode == 409 && code == 'SALES_ORDER_VERSION_CONFLICT') {
        AppFeedback.warning(
          context,
          'The order was modified by another user. Reloaded the latest version.',
        );
        _loadData();
        return;
      }

      AppFeedback.error(context, e.message);
      return;
    }

    AppFeedback.error(context, 'Failed to $actionName order: ${e.toString().replaceFirst('Exception: ', '')}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales Order Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isNotFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales Order')),
        body: Center(
          child: EnterpriseEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Sales Order Not Found',
            subtitle: 'The requested order does not exist or you do not have permission to view it.',
            action: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to Orders'),
            ),
          ),
        ),
      );
    }

    if (_loadError != null && _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales Order')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppTheme.danger, size: 48),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.danger,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final order = _order!;
    final auth = context.watch<AuthProvider>();
    final canViewProfit = auth.hasPermission('view-sale-profit');
    final canConvert = auth.hasPermission('convert-sales-orders');
    final canApprove = auth.hasPermission('approve-sales-orders');
    final canManage = auth.hasPermission('manage-sales-orders');
    final canCreate = auth.hasPermission('create-sales-orders');

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Sales Order #${order.orderNumber}'),
        actions: [
          IconButton(
            tooltip: 'Refresh Order',
            onPressed: _mutating ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Order Summary Header Card
                    _buildOverviewCard(order),
                    const SizedBox(height: 14),

                    // 2. Revalidation Panel (Problems first, line items second!)
                    RevalidationPanel(
                      report: _revalidationReport,
                      loading: _revalidating,
                      canConvert: canConvert,
                      onRefresh: _revalidateOnly,
                      onCreditOverrideApproved: (reason) {
                        setState(() => _creditOverrideReason = reason);
                        AppFeedback.success(
                          context,
                          'Credit limit override recorded. Proceed with conversion.',
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // 3. Line Items Table
                    SalesOrderItemsTable(
                      items: order.items,
                      subtotal: order.subtotal,
                      discount: order.discount,
                      tax: order.tax,
                      total: order.total,
                      canViewProfit: canViewProfit,
                    ),
                    const SizedBox(height: 14),

                    // 4. Activity & Events Timeline
                    SalesOrderTimeline(events: order.events),
                  ],
                ),
              ),
            ),

            // 5. Sticky Action Bar
            _buildBottomActionBar(
              order: order,
              canApprove: canApprove,
              canConvert: canConvert,
              canManage: canManage,
              canCreate: canCreate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(SalesOrder order) {
    final statusColor = SalesOrderStatus.color(order.status);
    final statusLabel = SalesOrderStatus.label(order.status);

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderNumber,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        EnterpriseStatusBadge(
                          label: statusLabel,
                          color: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Order Date: ${order.orderDate}${order.deliveryDate != null ? '  •  Delivery Date: ${order.deliveryDate}' : ''}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Booked Total',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    AppCurrency.format(order.total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              // Customer block
              Expanded(
                child: _infoBlock(
                  icon: Icons.person_outline_rounded,
                  label: 'Customer',
                  title: order.customer?.name ?? 'Customer #${order.customerId}',
                  subtitle: order.customer?.phone.isNotEmpty == true
                      ? order.customer!.phone
                      : (order.customer?.address ?? 'No contact information'),
                ),
              ),
              const SizedBox(width: 16),
              // Salesman block
              Expanded(
                child: _infoBlock(
                  icon: Icons.badge_outlined,
                  label: 'Salesman (Field Booking)',
                  title: order.salesman?.name ?? 'Salesman #${order.salesmanId}',
                  subtitle: order.salesman?.email ?? 'Field representative',
                ),
              ),
            ],
          ),
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notes: ${order.notes}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.navy,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (order.rejectionReason != null &&
              order.rejectionReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejection Reason: ${order.rejectionReason}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
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

  Widget _infoBlock({
    required IconData icon,
    required String label,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar({
    required SalesOrder order,
    required bool canApprove,
    required bool canConvert,
    required bool canManage,
    required bool canCreate,
  }) {
    final hasBlocking = _revalidationReport?.hasBlockingIssues == true;
    final blockingCount = _revalidationReport?.blocking.length ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          // Order status info
          Text(
            'Order Status: ${SalesOrderStatus.label(order.status)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.textMuted,
            ),
          ),
          const Spacer(),

          // 1. Return to Draft
          if ((order.isSubmitted || order.isRejected) &&
              (canManage || canApprove || canCreate))
            OutlinedButton.icon(
              onPressed: _mutating ? null : _handleReturnToDraft,
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('Return to Draft'),
            ),
          const SizedBox(width: 8),

          // 2. Reject
          if ((order.isSubmitted || order.isApproved) && canApprove)
            OutlinedButton.icon(
              onPressed: _mutating ? null : _handleReject,
              icon: const Icon(Icons.thumb_down_alt_outlined, size: 16),
              label: const Text('Reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
              ),
            ),
          const SizedBox(width: 8),

          // 3. Cancel
          if (!order.isTerminal && (canManage || canApprove))
            OutlinedButton.icon(
              onPressed: _mutating ? null : _handleCancel,
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Cancel Order'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
              ),
            ),
          const SizedBox(width: 8),

          // 4. Reconcile (crashed conversion recovery)
          if (order.isConverted &&
              order.convertedSaleId == null &&
              canConvert)
            FilledButton.icon(
              onPressed: _mutating ? null : _handleReconcile,
              icon: const Icon(Icons.build_circle_outlined, size: 16),
              label: const Text('Reconcile Conversion'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.warning,
              ),
            ),

          // 5. Open Invoice (when converted)
          if (order.convertedSaleId != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SaleDetailScreen(saleId: order.convertedSaleId!),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Open Converted Invoice'),
            ),

          // 6. Approve (when submitted)
          if (order.isSubmitted && canApprove)
            Tooltip(
              message: hasBlocking
                  ? '$blockingCount problem(s) must be resolved before approval'
                  : 'Approve order for invoice conversion',
              child: FilledButton.icon(
                onPressed: (_mutating || hasBlocking) ? null : _handleApprove,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: Text(hasBlocking
                    ? 'Approve ($blockingCount issues)'
                    : 'Approve Order'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.success,
                ),
              ),
            ),
          const SizedBox(width: 8),

          // 7. Create Sale from Order (when approved)
          if (order.isApproved && canConvert)
            FilledButton.icon(
              onPressed: _mutating ? null : _handleConvertToSale,
              icon: const Icon(Icons.point_of_sale_rounded, size: 16),
              label: const Text('Create Sale from Order'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
