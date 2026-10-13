import 'package:enterprise_pos/api/core/api_client.dart';

/// Business partners / co-owners of the active branch (add-on `owner_equity`).
///
/// Balances are never stored on the partner: capital and drawings are cash
/// ledger entries tagged with the partner, and the Partner Statement report
/// derives everything from the ledger.
class PartnerService {
  final ApiClient _client;

  PartnerService({required String token}) : _client = ApiClient(token: token);

  /// GET /partners → { partners: [...], active_ownership_percent_total }
  Future<Map<String, dynamic>> list({bool activeOnly = false}) async {
    final res = await _client.get('/partners', query: {if (activeOnly) 'active_only': '1'});
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load partners');
  }

  /// POST /partners
  Future<Map<String, dynamic>> create({
    required String name,
    required double ownershipPercent,
    String? phone,
    String? notes,
  }) async {
    final res = await _client.post('/partners', body: {
      'name': name,
      'ownership_percent': ownershipPercent,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    if (res['success'] == true) return Map<String, dynamic>.from(res['data']?['partner'] ?? {});
    throw Exception(res['message'] ?? 'Failed to create partner');
  }

  /// PUT /partners/{id} — edit, or set status 'inactive' / 'active'.
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> changes) async {
    final res = await _client.put('/partners/$id', body: changes);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data']?['partner'] ?? {});
    throw Exception(res['message'] ?? 'Failed to update partner');
  }
}
