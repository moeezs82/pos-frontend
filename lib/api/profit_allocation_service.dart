import 'package:enterprise_pos/api/core/api_client.dart';

/// Partner profit allocation of the active branch (add-on `owner_equity`).
///
/// Posting and reversing need `manage-profit-allocation`; reading needs that,
/// `view-reports` or `view-cashbook`. The backend recomputes everything:
/// the preview is only what the user confirms, and a post is refused if the
/// profit changed since the preview.
class ProfitAllocationService {
  final ApiClient _client;

  ProfitAllocationService({required String token}) : _client = ApiClient(token: token);

  Map<String, dynamic> _data(Map<String, dynamic> res, String fallback) {
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? fallback);
  }

  /// GET /profit-allocations → { items: [...], posted_total, last_allocated_to,
  /// suggested: {period_from, period_to} | null, lock_through }
  Future<Map<String, dynamic>> list({String? status}) async => _data(
        await _client.get('/profit-allocations', query: {if (status != null && status.isNotEmpty) 'status': status}),
        'Failed to load profit allocations',
      );

  /// GET /profit-allocations/preview → { period_from, period_to, net_profit,
  /// percent_total, lines: [{partner_id, partner, ownership_percent, amount}],
  /// total_allocated, blockers: [{code, field, message}], warnings: [...],
  /// can_post, suggested, last_allocated_to, lock_through, lock_will_raise_to }.
  /// Without dates the server uses its suggested next period.
  Future<Map<String, dynamic>> preview({String? from, String? to}) async => _data(
        await _client.get('/profit-allocations/preview', query: {
          if (from != null && from.isNotEmpty) 'period_from': from,
          if (to != null && to.isNotEmpty) 'period_to': to,
        }),
        'Failed to preview the allocation',
      );

  /// POST /profit-allocations — [expectedNetProfit] is the previewed figure.
  Future<Map<String, dynamic>> post({required String from, required String to, required num expectedNetProfit, String? note}) async => _data(
        await _client.post('/profit-allocations', body: {
          'period_from': from,
          'period_to': to,
          'expected_net_profit': expectedNetProfit,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }),
        'Failed to post the allocation',
      );

  /// GET /profit-allocations/{id}
  Future<Map<String, dynamic>> show(int id) async => _data(await _client.get('/profit-allocations/$id'), 'Failed to load the allocation');

  /// POST /profit-allocations/{id}/reverse — latest allocation only, reason 5–500 characters.
  Future<Map<String, dynamic>> reverse(int id, String reason) async =>
      _data(await _client.post('/profit-allocations/$id/reverse', body: {'reason': reason.trim()}), 'Failed to reverse the allocation');
}
