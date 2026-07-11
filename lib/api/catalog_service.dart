import 'package:enterprise_pos/api/core/api_client.dart';

/// Thin wrapper over the read-only catalog feed (handover doc G1 / Phase 1).
/// The device pulls reference data (products + price/tax + customers) from
/// here into its local catalog_cache.db so a sale can be composed offline.
class CatalogService {
  final ApiClient _client;

  CatalogService({required String token}) : _client = ApiClient(token: token);

  /// Full current catalog for [branchId] (or the caller's own branch when
  /// omitted). Used when the local cache is empty.
  Future<Map<String, dynamic>> snapshot({int? branchId}) async {
    final res = await _client.get('/catalog/snapshot', query: {
      if (branchId != null) 'branch_id': branchId.toString(),
    });
    return _data(res);
  }

  /// Rows changed since [since] (an ISO-8601 `catalog_version` returned by a
  /// previous snapshot/changes call), plus tombstones for soft-deleted rows.
  Future<Map<String, dynamic>> changes({
    required String since,
    int? branchId,
  }) async {
    final res = await _client.get('/catalog/changes', query: {
      'since': since,
      if (branchId != null) 'branch_id': branchId.toString(),
    });
    return _data(res);
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map<String, dynamic>) return data;
    throw Exception('Unexpected catalog response shape');
  }
}
