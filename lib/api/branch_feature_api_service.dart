import 'package:enterprise_pos/api/core/api_client.dart';

/// Thin API wrapper for branch feature settings endpoints.
///
/// Routes:
///   GET  /branch-features/current        — own branch (any authenticated user)
///   GET  /branches/{id}/features         — any branch (Master Admin only)
///   PUT  /branches/{id}/features         — any branch (Master Admin only)
class BranchFeatureApiService {
  final ApiClient _client;

  BranchFeatureApiService({required String token})
      : _client = ApiClient(token: token);

  /// Returns effective features for the caller's own active branch.
  Future<Map<String, dynamic>> getCurrent() =>
      _client.get('/branch-features/current');

  /// Returns effective features for a specific branch (Master Admin only).
  Future<Map<String, dynamic>> getBranchFeatures(int branchId) =>
      _client.get('/branches/$branchId/features');

  /// Updates features for a specific branch (Master Admin only).
  ///
  /// [values] may contain any subset of the allowed keys:
  ///   { 'delivery_enabled': bool, 'sale_vendor_enabled': bool }
  Future<Map<String, dynamic>> updateBranchFeatures(
    int branchId,
    Map<String, bool> values,
  ) =>
      _client.put('/branches/$branchId/features', body: values);
}
