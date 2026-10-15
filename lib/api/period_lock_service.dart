import 'package:enterprise_pos/api/core/api_client.dart';

/// Accounting period lock of the active branch (`/period-lock`).
///
/// The backend refuses any posting dated on or before the lock. Moving the
/// lock forward needs `manage-period-lock`; moving it back or clearing it is
/// Master Admin only and needs a reason. A lock written by year-close is
/// returned as `year_close_closed_through` and can never be lowered here.
class PeriodLockService {
  final ApiClient _client;

  PeriodLockService({required String token}) : _client = ApiClient(token: token);

  Map<String, dynamic> _data(Map<String, dynamic> res, String fallback) {
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? fallback);
  }

  /// GET /period-lock → { closed_through, year_close_closed_through,
  /// effective_closed_through, today, can_reopen, last_changed_by,
  /// last_changed_at, last_reason, history: [...] }
  Future<Map<String, dynamic>> fetch() async => _data(await _client.get('/period-lock'), 'Failed to load the period lock');

  /// PUT /period-lock. [closedThrough] null clears the lock (Master Admin).
  Future<Map<String, dynamic>> update({required String? closedThrough, String? reason}) async => _data(
        await _client.put('/period-lock', body: {
          'closed_through': closedThrough,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        }),
        'Failed to update the period lock',
      );
}
