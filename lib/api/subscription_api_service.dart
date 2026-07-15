import 'package:enterprise_pos/api/core/api_client.dart';

/// Thin wrapper around the backend subscription endpoints.
///
/// All methods require an authenticated token.  Callers receive raw
/// Map<String, dynamic> responses; the [SubscriptionService] layer
/// applies caching and parses them into [SubscriptionStatus] objects.
class SubscriptionApiService {
  final ApiClient _client;

  SubscriptionApiService({required String token})
      : _client = ApiClient(token: token);

  /// GET /subscription/status
  /// Returns the subscription state for the caller's current active branch.
  /// Master admin may pass [branchId] to query a specific branch.
  Future<Map<String, dynamic>> getStatus({int? branchId}) async {
    final query = branchId != null ? {'branch_id': branchId.toString()} : null;
    return _client.get('/subscription/status', query: query);
  }

  // ── Owner management ───────────────────────────────────────────────────────

  /// GET /subscriptions — all branches with computed status (owner only).
  Future<Map<String, dynamic>> listBranches({
    String? search,
    String? status,
    int page = 1,
  }) async {
    final query = <String, String>{'page': page.toString()};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (status != null && status.isNotEmpty) query['status'] = status;
    return _client.get('/subscriptions', query: query);
  }

  /// GET /subscriptions/{branchId} — full detail for one branch (owner only).
  Future<Map<String, dynamic>> getBranchDetail(int branchId) async {
    return _client.get('/subscriptions/$branchId');
  }

  /// PUT /subscriptions/{branchId} — update subscription (owner only).
  Future<Map<String, dynamic>> updateSubscription(
      int branchId, Map<String, dynamic> payload) async {
    return _client.put('/subscriptions/$branchId', body: payload);
  }

  /// GET /subscriptions/{branchId}/audit — change history (owner only).
  Future<Map<String, dynamic>> getAudit(int branchId, {int page = 1}) async {
    return _client.get('/subscriptions/$branchId/audit',
        query: {'page': page.toString()});
  }
}
