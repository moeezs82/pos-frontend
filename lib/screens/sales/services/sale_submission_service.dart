import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/api/sales_order_service.dart';
import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/models/whatsapp_invoice_format.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/offline_queue_provider.dart';
import 'package:enterprise_pos/screens/sales/services/sale_cart_validator.dart';
import 'package:enterprise_pos/screens/sales/services/sale_checkout_totals.dart';
import 'package:enterprise_pos/screens/sales/services/sale_meta_builder.dart';
import 'package:enterprise_pos/screens/sales/services/sale_offline_credit_service.dart';
import 'package:enterprise_pos/screens/sales/services/sale_receipt_dispatcher.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/offline_invoice_seq_service.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/services/whatsapp_invoice_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/network_failure.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class SaleSubmissionService {
  static double _rowNum(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0.0;

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Runs all validations before attempting checkout.
  /// Returns false if submission should be aborted.
  static bool validatePreflight({
    required BuildContext context,
    required List<Map<String, dynamic>> items,
    required bool sendInvoiceOnWhatsApp,
    required String whatsAppPhone,
    required bool isMasterAdmin,
    required int? globalBranchId,
    required int? originBranchId,
    required double subtotal,
    required double discount,
    required double tax,
    required double shipping,
    required double saleTotal,
  }) {
    if (items.isEmpty) {
      AppFeedback.warning(context, "Add at least 1 item before creating sale.");
      return false;
    }

    final quantityViolation = SaleCartValidator.firstQuantityViolation(items);
    if (quantityViolation != null) {
      AppFeedback.warning(context, quantityViolation);
      return false;
    }

    if (sendInvoiceOnWhatsApp) {
      try {
        WhatsAppInvoiceService.instance.normalizePhone(whatsAppPhone);
      } on FormatException catch (e) {
        AppFeedback.warning(context, e.message.toString());
        return false;
      }
    }

    if (isMasterAdmin && globalBranchId == null) {
      AppFeedback.warning(
        context,
        'Please select a working branch from Branch Control before creating sale.',
      );
      return false;
    }

    if (originBranchId == null || originBranchId <= 0) {
      AppFeedback.warning(
        context,
        'A valid working branch is required before creating a sale.',
      );
      return false;
    }

    final hasUnlinkedReturn = items.any(
      (i) => _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] == null,
    );
    if (hasUnlinkedReturn) {
      AppFeedback.warning(
        context,
        'Every negative quantity must be linked to its original invoice before saving.',
      );
      return false;
    }

    final linkedReturns = items
        .where((i) =>
            _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] != null)
        .toList(growable: false);
    final linkedInvoiceIds = linkedReturns
        .map((i) => _metaInt(i['original_sale_id']))
        .whereType<int>()
        .toSet();
    if (linkedInvoiceIds.length > 1) {
      AppFeedback.warning(
        context,
        'All returned items in one transaction must come from the same original invoice.',
      );
      return false;
    }

    if (subtotal <= 0.004 &&
        linkedReturns.isNotEmpty &&
        (discount.abs() > 0.004 || tax.abs() > 0.004 || shipping.abs() > 0.004)) {
      AppFeedback.warning(
        context,
        'A return-only transaction cannot add a new invoice discount, tax, or delivery charge. Original delivery is non-refundable.',
      );
      return false;
    }

    if (saleTotal < -0.004) {
      AppFeedback.warning(context, 'The new-sale total cannot be negative.');
      return false;
    }

    return true;
  }

  /// Executes the sale checkout transaction, handling online posting,
  /// credit limit overrides, deterministic rejections, offline queueing,
  /// receipt dispatching, and user notifications.
  static Future<void> executeSubmitSale({
    required BuildContext context,
    required SaleService saleService,
    required AuthProvider auth,
    required List<Map<String, dynamic>> items,
    required SaleCheckoutTotals totals,
    required bool printReceipt,
    required bool sendInvoiceOnWhatsApp,
    required String whatsAppPhone,
    required String effectiveBranchId,
    required int originBranchId,
    required int? originUserId,
    required String registerCode,
    required Map<String, dynamic>? selectedCustomer,
    required String? selectedCustomerId,
    required List<String> selectedCustomerSecondaryPhones,
    required String walkInCustomerName,
    required String walkInPhone,
    required String walkInAddress,
    required int? selectedAreaId,
    required String? selectedAreaName,
    required Map<String, dynamic>? selectedUser,
    required int? selectedUserId,
    required Map<String, dynamic>? selectedDeliveryBoy,
    required int? selectedDeliveryBoyId,
    required Map<String, dynamic>? selectedVendor,
    required int? selectedVendorId,
    required int? selectedSaleSourceId,
    required String? selectedSaleSourceName,
    required Map<String, dynamic>? selectedBranch,
    required String effectiveMethod,
    required SalesOrderPrefill? salesOrderPrefill,
    required double Function(Map<String, dynamic>) lineTotalFallback,
    required void Function({
      required String receiptNo,
      required WhatsAppInvoicePreparation prepared,
      required String message,
    }) onAddPendingWhatsAppTask,
    required void Function({required bool keepInitialCustomer}) onResetSale,
    required bool keepInitialCustomer,
    required VoidCallback onFocusProductSearch,
  }) async {
    final clientRef = const Uuid().v4();
    final occurredAt = DateTime.now();

    String? offlineInvoiceNo;
    try {
      offlineInvoiceNo = await OfflineInvoiceSeqService.instance.next(
        branchId: originBranchId,
        registerCode: registerCode,
        occurredAt: occurredAt,
      );
    } catch (e, s) {
      debugPrint('offline_invoice_seq error: $e');
      debugPrintStack(stackTrace: s);
    }

    Map<String, dynamic>? res;
    var queuedOffline = false;

    final meta = SaleMetaBuilder.buildSaleMeta(
      context: context,
      effectiveBranchId: effectiveBranchId,
      selectedBranch: selectedBranch,
      selectedCustomer: selectedCustomer,
      selectedCustomerId: selectedCustomerId,
      walkInCustomerName: walkInCustomerName,
      walkInPhone: walkInPhone,
      selectedCustomerSecondaryPhones: selectedCustomerSecondaryPhones,
      walkInAddress: walkInAddress,
      selectedAreaId: selectedAreaId,
      selectedAreaName: selectedAreaName,
      selectedUser: selectedUser,
      selectedUserId: selectedUserId,
      selectedDeliveryBoy: selectedDeliveryBoy,
      selectedDeliveryBoyId: selectedDeliveryBoyId,
      selectedVendor: selectedVendor,
      selectedVendorId: selectedVendorId,
      selectedSaleSourceId: selectedSaleSourceId,
      selectedSaleSourceName: selectedSaleSourceName,
      subtotal: totals.subtotal,
      discount: totals.discount,
      tax: totals.tax,
      shipping: totals.shipping,
      total: totals.saleTotal,
      paid: totals.paid,
      balance: totals.balance,
      cashReceived: totals.cashReceived,
      changeAmount: totals.changeAmount,
      paymentsToSend: totals.paymentsToSend,
    );

    final linkedReturns = items
        .where((i) =>
            _rowNum(i['quantity']) < 0 && i['original_sale_item_id'] != null)
        .toList(growable: false);

    if (linkedReturns.isNotEmpty) {
      meta['return_preview'] = {
        'return_credit': totals.returnCredit,
        'applied_to_original': totals.appliedToOriginal,
        'applied_to_exchange': totals.appliedToExchange,
        'refund_due': totals.refundDue,
        'original_delivery_refund': 0,
      };
    }

    final payload = saleService.buildSalePayload(
      branchId: effectiveBranchId,
      customerId: selectedCustomerId != null
          ? int.tryParse(selectedCustomerId)
          : null,
      vendorId: selectedVendorId,
      userId: selectedUserId,
      deliveryBoyId: selectedDeliveryBoyId,
      saleSourceId: selectedSaleSourceId,
      areaId: selectedAreaId,
      areaName: selectedAreaName,
      saleType: selectedDeliveryBoyId != null ? 'delivery' : null,
      items: items,
      payments: totals.paymentsToSend,
      refund: totals.refundToSend,
      discount: totals.discount,
      tax: totals.tax,
      delivery: totals.shipping,
      meta: meta,
      clientRef: clientRef,
      originBranchId: originBranchId,
      occurredAt: occurredAt,
      offlineInvoiceNo: offlineInvoiceNo,
    );

    String? queueReason;
    Object? submitError;

    if (salesOrderPrefill != null) {
      final prefill = salesOrderPrefill;
      try {
        final convertRes = await SalesOrderService(token: auth.token!).convert(
          prefill.order.id,
          paymentMethod: effectiveMethod,
          paid: totals.paid,
          payments: totals.paymentsToSend.isNotEmpty
              ? totals.paymentsToSend
              : null,
          version: prefill.order.version,
          creditLimitOverrideReason: prefill.creditLimitOverrideReason,
        ).timeout(const Duration(seconds: 15));
        res = {'data': convertRes};
      } catch (e) {
        submitError = e;
      }
    } else {
      try {
        res = await saleService
            .createSaleFromPayload(payload)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        submitError = e;
      }
    }

    final firstCreditIssue = submitError == null
        ? null
        : CreditLimitIssue.fromException(submitError);
    if (firstCreditIssue != null) {
      final mayOverride = firstCreditIssue.canOverride &&
          auth.hasPermission('override-party-credit-limit');
      if (!mayOverride) {
        if (!context.mounted) return;
        AppFeedback.error(context, firstCreditIssue.summary);
        return;
      }
      final reason = await showCreditLimitOverrideDialog(
        context,
        firstCreditIssue,
      );
      if (!context.mounted) return;
      if (reason == null) return;

      if (salesOrderPrefill != null) {
        final prefill = salesOrderPrefill;
        try {
          final convertRes = await SalesOrderService(token: auth.token!).convert(
            prefill.order.id,
            paymentMethod: effectiveMethod,
            paid: totals.paid,
            payments: totals.paymentsToSend.isNotEmpty
                ? totals.paymentsToSend
                : null,
            version: prefill.order.version,
            creditLimitOverrideReason: reason,
          ).timeout(const Duration(seconds: 15));
          res = {'data': convertRes};
          submitError = null;
        } catch (e) {
          submitError = e;
        }
      } else {
        payload['credit_limit_override'] = {'reason': reason};
        try {
          res = await saleService
              .createSaleFromPayload(payload)
              .timeout(const Duration(seconds: 15));
          submitError = null;
        } catch (e) {
          submitError = e;
        }
      }
    }

    if (submitError != null) {
      final e = submitError;
      if (salesOrderPrefill != null) {
        if (!context.mounted) return;
        if (e is ApiException && e.statusCode == 409) {
          final body = e.body is Map ? (e.body as Map) : null;
          final invoiceNo = body?['invoice_no']?.toString();
          final msg = (invoiceNo != null && invoiceNo.isNotEmpty)
              ? 'This order has already been converted into invoice $invoiceNo.'
              : (e.message.isNotEmpty
                  ? e.message
                  : 'This order was modified by another transaction.');
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
                  SizedBox(width: 8),
                  Text('Order Conflict'),
                ],
              ),
              content: Text(msg),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Stay Here'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Back to Order'),
                ),
              ],
            ),
          );
          return;
        }
        AppFeedback.error(
          context,
          e is ApiException
              ? e.message
              : e.toString().replaceFirst('Exception: ', ''),
        );
        return;
      }

      if (linkedReturns.isNotEmpty &&
          (!(e is ApiException) ||
              e.isRetryable ||
              e.isAuthFailure ||
              e.statusCode == 402 ||
              isNetworkFailure(e))) {
        if (!context.mounted) return;
        AppFeedback.error(
          context,
          'Return/exchange requires a live CounterIQ connection. Nothing was queued or posted.',
        );
        return;
      }

      if (e is ApiException &&
          !e.isRetryable &&
          !e.isAuthFailure &&
          e.statusCode != 402) {
        SaleCartValidator.applyServerLineErrors(items, e);
        if (!context.mounted) return;
        final issue = CreditLimitIssue.fromException(e);
        AppFeedback.error(
          context,
          issue?.summary ?? SaleCartValidator.describeRejection(items, e),
        );
        return;
      }

      queueReason = isNetworkFailure(e)
          ? 'Offline: could not reach the server ($e).'
          : 'Server responded with a retryable error, queued for review on sync: $e';

      final offlineCredit =
          await SaleOfflineCreditService.prepareOfflineCreditQueue(
        context: context,
        auth: auth,
        customer: selectedCustomer,
        customerIdStr: selectedCustomerId,
        branchId: originBranchId,
        currentLedgerDelta: totals.signedTotal - totals.paid,
        payload: payload,
      );
      if (!context.mounted) return;
      if (!offlineCredit.allowed) {
        AppFeedback.error(
          context,
          offlineCredit.message ??
              'This offline credit sale was not approved.',
        );
        return;
      }
      if (offlineCredit.message != null &&
          offlineCredit.message!.trim().isNotEmpty) {
        queueReason = '$queueReason ${offlineCredit.message}';
      }

      await OfflineSalesQueueService.instance.enqueue(
        clientRef: clientRef,
        originBranchId: originBranchId,
        originUserId: originUserId,
        payload: payload,
        occurredAt: occurredAt,
        offlineInvoiceNo: offlineInvoiceNo,
        initialError: queueReason,
      );
      queuedOffline = true;
      if (context.mounted) {
        context.read<OfflineQueueProvider>().refresh();
      }
    }

    final creditLimitNotice = queuedOffline
        ? null
        : CreditLimitIssue.fromWarning(
            res?['data']?['credit_limit_warning'],
          );

    final receiptNo = queuedOffline
        ? (offlineInvoiceNo ?? 'OFF-PENDING')
        : (res?['data']?['invoice_no'] ??
                res?['data']?['sale']?['invoice_no'] ??
                res?['data']?['id'] ??
                'N/A')
            .toString();

    final prepareWhatsAppInvoice = sendInvoiceOnWhatsApp && !queuedOffline;

    if (printReceipt || prepareWhatsAppInvoice) {
      final receiptSubtotal = totals.subtotal - totals.returnCredit;
      final receiptItems = SaleReceiptDispatcher.mapCartToReceiptItems(
        items,
        lineTotalFallback: lineTotalFallback,
      );
      await SaleReceiptDispatcher.dispatch(
        context: context,
        print: printReceipt,
        prepareWhatsAppInvoice: prepareWhatsAppInvoice,
        receiptNo: receiptNo,
        occurredAt: occurredAt,
        receiptItems: receiptItems,
        receiptSubtotal: receiptSubtotal,
        discount: totals.discount,
        tax: totals.tax,
        total: totals.signedTotal,
        cashReceived: totals.cashReceived,
        changeAmount: totals.changeAmount,
        paid: totals.paid,
        balance: totals.balance,
        meta: meta,
        whatsappPhone: whatsAppPhone,
        rawCustomerBalance: res?['data']?['customer_balance'],
        onWhatsAppTaskPrepared: onAddPendingWhatsAppTask,
      );
    }

    if (!context.mounted) return;
    onResetSale(keepInitialCustomer: keepInitialCustomer);

    if (queuedOffline) {
      AppFeedback.warning(
        context,
        "Offline — Pending Sync. Receipt: $receiptNo. ${queueReason ?? ''} Official invoice number will be assigned when synced.${sendInvoiceOnWhatsApp ? ' WhatsApp invoice was not prepared; send it after synchronization.' : ''}",
      );
    } else if (creditLimitNotice != null) {
      AppFeedback.warning(
        context,
        creditLimitNotice.overrideUsed
            ? 'Sale $receiptNo created with an authorized credit-limit override. ${creditLimitNotice.summary}'
            : 'Sale $receiptNo created with a credit-limit warning. ${creditLimitNotice.summary}',
      );
    } else {
      final postedReturn = res?['data']?['return'];
      if (postedReturn is Map) {
        final returned = _metaNum(postedReturn['return_credit']);
        final appliedOld = _metaNum(postedReturn['applied_to_original']);
        final appliedExchange = _metaNum(postedReturn['applied_to_exchange']);
        final refunded = _metaNum(postedReturn['refunded']);
        final creditLeft = _metaNum(postedReturn['customer_credit_left']);
        final postedReturnNo = (postedReturn['return_no'] ?? receiptNo).toString();
        final creditSuffix = creditLeft > 0.004
            ? ' • ${AppCurrency.format(creditLeft)} customer credit'
            : '';
        AppFeedback.success(
          context,
          'Return $postedReturnNo posted: '
          '${AppCurrency.format(returned)} credit • '
          '${AppCurrency.format(appliedOld)} old balance • '
          '${AppCurrency.format(appliedExchange)} exchange • '
          '${AppCurrency.format(refunded)} refunded$creditSuffix.',
        );
      } else {
        if (salesOrderPrefill != null) {
          AppFeedback.success(
            context,
            "Order ${salesOrderPrefill.order.orderNumber} successfully converted to Sale $receiptNo.",
          );
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
            return;
          }
        } else {
          AppFeedback.success(
            context,
            "Sale $receiptNo created successfully. Ready for next sale.",
          );
        }
      }
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      onFocusProductSearch();
    });
  }
}
