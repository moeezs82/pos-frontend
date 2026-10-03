import 'package:enterprise_pos/api/sale_service.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/utils/customer_phone_utils.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';

class SaleCustomerLookupService {
  /// Resolves an existing customer account by phone number.
  /// Handles deduplication, archived warnings, and notifications.
  static Future<bool> performLookup({
    required BuildContext context,
    required SaleService saleService,
    required String phone,
    required String key,
    required bool Function() isCurrentPhoneValid,
    required void Function(Map<String, dynamic> customer) onCustomerMatched,
  }) async {
    try {
      final data = await saleService.resolveCustomerByPhone(phone);
      if (!context.mounted) return false;

      // Ignore a stale response when the cashier changed/cleared the phone or
      // explicitly selected a different customer while the request was away.
      if (!isCurrentPhoneValid()) {
        return true;
      }

      if (data['ambiguous'] == true) {
        AppFeedback.warning(
          context,
          'This phone matches multiple customer records. Resolve the duplicate customers before saving this sale.',
        );
        return false;
      }
      if (data['archived'] == true) {
        AppFeedback.warning(
          context,
          'An archived customer already uses this phone number. Restore or update that customer before saving.',
        );
        return false;
      }

      final raw = data['customer'];
      if (raw is Map) {
        final customer = Map<String, dynamic>.from(raw);
        onCustomerMatched(customer);
        if (!context.mounted) return false;
        final type =
            SalePricing.normalizeCustomerType(customer['customer_type']);
        final name = [
          (customer['first_name'] ?? '').toString().trim(),
          (customer['last_name'] ?? '').toString().trim(),
        ].where((v) => v.isNotEmpty).join(' ').trim();
        AppFeedback.info(
          context,
          '${name.isEmpty ? 'Existing customer' : name} selected from phone${type == 'retail' ? '' : ' • ${type[0].toUpperCase()}${type.substring(1)}'}.',
        );
      }
      return true;
    } catch (_) {
      // No connectivity is not a reason to block sale composition. The exact
      // same phone resolution/create step runs transactionally on the backend
      // when an online or queued sale is eventually posted.
      return true;
    }
  }
}
