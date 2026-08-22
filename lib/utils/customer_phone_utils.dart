import 'dart:convert';

/// Shared helpers for the customer's optional secondary phone numbers.
///
/// The server stores them as JSON text for SQLite/MariaDB portability, while
/// API responses expose them as a normal JSON array. These helpers accept both
/// shapes so old/local cached data remains safe during upgrades.
class CustomerPhoneUtils {
  CustomerPhoneUtils._();

  static List<String> secondaryPhones(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return const [];
      try {
        value = jsonDecode(text);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];

    final out = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final phone = (item ?? '').toString().trim();
      if (phone.isEmpty) continue;
      final key = compareKey(phone);
      if (!seen.add(key)) continue;
      out.add(phone);
      if (out.length == 4) break;
    }
    return out;
  }

  static String compareKey(String value) {
    final trimmed = value.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isNotEmpty ? digits : trimmed.toLowerCase();
  }

  static bool boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes' || text == 'on';
  }

  static List<String> printableSecondaryPhones(
    Map<String, dynamic>? meta,
    Map<String, dynamic> customerSnapshot,
  ) {
    // Invoice printing always includes every saved secondary phone number.
    // `meta` is retained in the signature for compatibility with existing
    // print call sites and older sale snapshots.
    return secondaryPhones(customerSnapshot['phone_numbers']);
  }
}
