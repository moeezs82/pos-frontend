import 'package:enterprise_pos/api/core/api_client.dart';

class CustomerAreaService {
  final ApiClient _client;

  CustomerAreaService({required String token}) : _client = ApiClient(token: token);

  Future<List<Map<String, dynamic>>> getAreas({bool activeOnly = false}) async {
    final res = await _client.get(
      '/customer-areas',
      query: {if (activeOnly) 'active_only': '1'},
    );
    final raw = res['data']?['customer_areas'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createArea(String name) async {
    final res = await _client.post(
      '/customer-areas',
      body: {'name': name.trim()},
    );
    final raw = res['data']?['customer_area'] ?? res['data'];
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> updateArea(int id, String name) async {
    final res = await _client.put(
      '/customer-areas/$id',
      body: {'name': name.trim()},
    );
    final raw = res['data']?['customer_area'] ?? res['data'];
    return Map<String, dynamic>.from(raw as Map);
  }
}
