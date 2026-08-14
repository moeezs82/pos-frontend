import 'package:enterprise_pos/api/core/api_client.dart';

class SaleSourceService {
  final ApiClient _client;

  SaleSourceService({required String token}) : _client = ApiClient(token: token);

  Future<List<Map<String, dynamic>>> getSaleSources() async {
    final res = await _client.get('/sale-sources');
    final raw = res['data']?['sale_sources'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createSaleSource({
    required String name,
    int? sortOrder,
  }) async {
    final res = await _client.post('/sale-sources', body: {
      'name': name.trim(),
      if (sortOrder != null) 'sort_order': sortOrder,
      'is_active': true,
    });
    final raw = res['data']?['sale_source'] ?? res['data'];
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> updateSaleSource(
    int id, {
    String? name,
    bool? isActive,
    int? sortOrder,
  }) async {
    final res = await _client.put('/sale-sources/$id', body: {
      if (name != null) 'name': name.trim(),
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
    final raw = res['data']?['sale_source'] ?? res['data'];
    return Map<String, dynamic>.from(raw as Map);
  }
}
