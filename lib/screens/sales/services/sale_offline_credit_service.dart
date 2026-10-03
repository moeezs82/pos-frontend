import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/services/offline_sales_queue_service.dart';
import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';

class OfflineCreditDecision {
  final bool allowed;
  final String? message;

  const OfflineCreditDecision._(this.allowed, this.message);

  const OfflineCreditDecision.allow([String? message])
      : this._(true, message);

  const OfflineCreditDecision.deny(String message)
      : this._(false, message);
}

class SaleOfflineCreditService {
  static double? finiteCreditNumber(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  /// Applies a conservative device-side check only when an online submission
  /// could not be confirmed and the sale is about to enter the local queue.
  /// The backend remains authoritative and rechecks the actual party trade
  /// ledger during sync. No invoice allocation or paid/unpaid status is used.
  static Future<OfflineCreditDecision> prepareOfflineCreditQueue({
    required BuildContext context,
    required AuthProvider auth,
    required Map<String, dynamic>? customer,
    required String? customerIdStr,
    required int branchId,
    required double currentLedgerDelta,
    required Map<String, dynamic> payload,
  }) async {
    final customerId = int.tryParse(customerIdStr ?? '');
    if (customerId == null || customerId <= 0 || currentLedgerDelta <= 0.004) {
      return const OfflineCreditDecision.allow();
    }

    // A server-presented override may have been approved immediately before
    // the retry lost connectivity. Preserve that reason and idempotency key.
    final existingOverride = payload['credit_limit_override'];
    if (existingOverride is Map &&
        (existingOverride['reason']?.toString().trim().length ?? 0) >= 5) {
      return const OfflineCreditDecision.allow(
        'This queued sale carries the authorized credit-limit override already approved online.',
      );
    }

    final mode = (customer?['credit_limit_mode'] ?? 'block')
        .toString()
        .trim()
        .toLowerCase();
    final warningMode = mode == 'warning';
    final mayOverride = auth.hasPermission('override-party-credit-limit');

    Future<OfflineCreditDecision> unknownDecision(String reason) async {
      final message =
          '$reason The authoritative customer trade balance will be checked when this sale synchronizes.';
      if (warningMode) {
        return OfflineCreditDecision.allow('Credit warning: $message');
      }
      if (!mayOverride) {
        return OfflineCreditDecision.deny(
          '$message An authorized credit-limit override is required before creating additional offline debt.',
        );
      }
      final overrideReason = await showOfflineCreditDataOverrideDialog(
        context,
        message: message,
      );
      if (overrideReason == null) {
        return const OfflineCreditDecision.deny(
          'Offline sale cancelled because credit approval was not completed.',
        );
      }
      payload['credit_limit_override'] = {'reason': overrideReason};
      return const OfflineCreditDecision.allow(
        'Queued with an authorized offline credit override. The server will validate it during synchronization.',
      );
    }

    if (customer == null || !customer.containsKey('credit_limit')) {
      return unknownDecision(
        'This customer was selected from data that does not contain a verified credit-control configuration.',
      );
    }

    // Explicit NULL is the production-compatible unlimited setting.
    if (customer['credit_limit'] == null) {
      return const OfflineCreditDecision.allow();
    }
    final limit = finiteCreditNumber(customer['credit_limit']);
    if (limit == null || limit < 0) {
      return unknownDecision(
        'The cached customer credit limit is invalid or unavailable.',
      );
    }

    final hasBalance = customer.containsKey('balance') ||
        customer.containsKey('trade_balance');
    final cachedBalance = finiteCreditNumber(
      customer['balance'] ?? customer['trade_balance'],
    );
    if (!hasBalance || cachedBalance == null) {
      return unknownDecision(
        'No reliable cached customer trade balance is available while offline.',
      );
    }

    double pendingExposure;
    try {
      pendingExposure = await OfflineSalesQueueService.instance
          .pendingCustomerExposure(
        branchId: branchId,
        customerId: customerId,
      );
    } catch (_) {
      return unknownDecision(
        "The device could not verify this customer's existing unsynced exposure.",
      );
    }

    final balanceBefore = cachedBalance + pendingExposure;
    final projected = balanceBefore + currentLedgerDelta;
    if (projected <= limit + 0.004) {
      return const OfflineCreditDecision.allow();
    }

    final issue = CreditLimitIssue(
      partyType: 'customer',
      partyId: customerId,
      limit: limit,
      balanceBefore: balanceBefore,
      projectedBalance: projected,
      exceededBy: projected - limit,
      mode: warningMode ? 'warning' : 'block',
      canOverride: mayOverride,
    );
    if (warningMode) {
      return OfflineCreditDecision.allow(
        'Credit warning: ${issue.summary} The server will recheck the current party ledger during synchronization.',
      );
    }
    if (!mayOverride) {
      return OfflineCreditDecision.deny(
        '${issue.summary} You do not have permission to approve this offline credit exposure.',
      );
    }

    final reason = await showCreditLimitOverrideDialog(context, issue);
    if (reason == null) {
      return const OfflineCreditDecision.deny(
        'Offline sale cancelled because the credit-limit override was not approved.',
      );
    }
    payload['credit_limit_override'] = {'reason': reason};
    return OfflineCreditDecision.allow(
      'Queued with an authorized offline credit override. ${issue.summary}',
    );
  }
}
