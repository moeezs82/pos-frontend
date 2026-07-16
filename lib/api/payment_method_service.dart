import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/payment_method.dart';

/// API client for dynamic, branch-owned payment methods.
class PaymentMethodService {
  final ApiClient _client;
  PaymentMethodService({required String token}) : _client = ApiClient(token: token);

  /// Operational: active methods for the caller's effective branch.
  /// GET /payment-methods
  Future<List<PaymentMethod>> getActive() async {
    final res = await _client.get('/payment-methods');
    return _parseList(res);
  }

  /// Master-admin: every configured method for a branch.
  /// GET /payment-methods/admin?branch_id=..
  Future<List<PaymentMethod>> getAllForBranch(int branchId) async {
    final res = await _client.get('/payment-methods/admin',
        query: {'branch_id': branchId.toString()});
    return _parseList(res);
  }

  /// POST /payment-methods
  Future<PaymentMethod> create({
    required int branchId,
    required String method,
    required String displayName,
    required int accountId,
    bool affectsCashDrawer = false,
    bool isActive = true,
    int sortOrder = 0,
    String? iconKey,
  }) async {
    final res = await _client.post('/payment-methods', body: {
      'branch_id': branchId,
      'method': method,
      'display_name': displayName,
      'account_id': accountId,
      'affects_cash_drawer': affectsCashDrawer,
      'is_active': isActive,
      'sort_order': sortOrder,
      if (iconKey != null) 'icon_key': iconKey,
    });
    return _parseOne(res, 'Failed to create payment method');
  }

  /// PUT /payment-methods/{id}
  Future<PaymentMethod> update(
    int id, {
    String? displayName,
    int? accountId,
    bool? affectsCashDrawer,
    bool? isActive,
    int? sortOrder,
    String? iconKey,
  }) async {
    final res = await _client.put('/payment-methods/$id', body: {
      if (displayName != null) 'display_name': displayName,
      if (accountId != null) 'account_id': accountId,
      if (affectsCashDrawer != null) 'affects_cash_drawer': affectsCashDrawer,
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (iconKey != null) 'icon_key': iconKey,
    });
    return _parseOne(res, 'Failed to update payment method');
  }

  /// PUT /payment-methods/{id}/activate|deactivate
  Future<PaymentMethod> setActive(int id, bool active) async {
    final res = await _client.put(
      '/payment-methods/$id/${active ? 'activate' : 'deactivate'}',
      body: {},
    );
    return _parseOne(res, 'Failed to change payment method status');
  }

  List<PaymentMethod> _parseList(Map<String, dynamic> res) {
    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? const {};
      final rows = (data['payment_methods'] as List?) ?? const [];
      return rows
          .map<PaymentMethod>((e) => PaymentMethod.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw Exception(res['message'] ?? 'Failed to load payment methods');
  }

  PaymentMethod _parseOne(Map<String, dynamic> res, String fallback) {
    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? const {};
      final row = data['payment_method'];
      if (row is Map) {
        return PaymentMethod.fromJson(Map<String, dynamic>.from(row));
      }
    }
    throw Exception(res['message'] ?? fallback);
  }
}
