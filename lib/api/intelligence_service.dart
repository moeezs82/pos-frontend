import 'package:enterprise_pos/api/core/api_client.dart';

class IntelligenceEnvelope {
  final String computedAt;
  final bool stale;
  final dynamic result;

  const IntelligenceEnvelope({
    required this.computedAt,
    required this.stale,
    required this.result,
  });

  factory IntelligenceEnvelope.fromResponse(Map<String, dynamic> response) {
    final data = response['data'];
    if (response['success'] != true || data is! Map) {
      throw Exception(response['message'] ?? 'Failed to load intelligence data');
    }
    final map = Map<String, dynamic>.from(data);
    return IntelligenceEnvelope(
      computedAt: map['computed_at']?.toString() ?? '',
      stale: map['stale'] == true,
      result: map['result'],
    );
  }
}

class IntelligenceService {
  final ApiClient _client;

  IntelligenceService({required String token}) : _client = ApiClient(token: token);

  Future<IntelligenceEnvelope> marginLeaks({
    String? from,
    String? to,
    String mode = 'gross',
    String groupBy = 'product',
    String? flag,
    int page = 1,
    int perPage = 50,
  }) => _get('/intelligence/margin-leaks', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'mode': mode,
        'group_by': groupBy,
        if (flag != null && flag.isNotEmpty) 'flag': flag,
        'page': '$page',
        'per_page': '$perPage',
      });

  Future<IntelligenceEnvelope> marginLeakDetail({
    required String groupKey,
    String? from,
    String? to,
    String mode = 'gross',
    String groupBy = 'product',
    String? flag,
  }) => _get('/intelligence/margin-leaks/detail', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'mode': mode,
        'group_by': groupBy,
        'group_key': groupKey,
        if (flag != null && flag.isNotEmpty) 'flag': flag,
      });

  Future<IntelligenceEnvelope> discountAnomalies({
    String? from,
    String? to,
    String actor = 'cashier',
  }) => _get('/intelligence/discount-anomalies', {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'actor': actor,
      });

  Future<IntelligenceEnvelope> repricingAlerts({int page = 1, int perPage = 50}) =>
      _get('/intelligence/repricing-alerts', {'page': '$page', 'per_page': '$perPage'});

  Future<IntelligenceEnvelope> deadStock({int? days, int page = 1, int perPage = 50}) =>
      _get('/intelligence/dead-stock', {
        if (days != null) 'days': '$days',
        'page': '$page',
        'per_page': '$perPage',
      });

  Future<IntelligenceEnvelope> replenishment({
    String? stockClass,
    bool onlyReorder = false,
    int page = 1,
    int perPage = 100,
  }) => _get('/intelligence/replenishment', {
        if (stockClass != null && stockClass.isNotEmpty) 'class': stockClass,
        if (onlyReorder) 'only_reorder': '1',
        'page': '$page',
        'per_page': '$perPage',
      });

  Future<IntelligenceEnvelope> productVelocity(int productId) =>
      _get('/intelligence/product-velocity/$productId', const {});

  Future<IntelligenceEnvelope> settings() => _get('/intelligence/settings', const {});

  Future<IntelligenceEnvelope> updateSettings(Map<String, dynamic> body) async {
    final response = await _client.put('/intelligence/settings', body: body);
    return IntelligenceEnvelope.fromResponse(response);
  }

  Future<IntelligenceEnvelope> seasons() => _get('/intelligence/seasons', const {});

  Future<IntelligenceEnvelope> createSeason(Map<String, dynamic> body) async {
    final response = await _client.post('/intelligence/seasons', body: body);
    return IntelligenceEnvelope.fromResponse(response);
  }

  Future<IntelligenceEnvelope> updateSeason(int id, Map<String, dynamic> body) async {
    final response = await _client.put('/intelligence/seasons/$id', body: body);
    return IntelligenceEnvelope.fromResponse(response);
  }

  Future<void> deleteSeason(int id) async {
    final response = await _client.delete('/intelligence/seasons/$id');
    IntelligenceEnvelope.fromResponse(response);
  }

  Future<IntelligenceEnvelope> addSeasonTag(
    int seasonId, {
    required String scope,
    required int scopeId,
  }) async {
    final response = await _client.post('/intelligence/seasons/$seasonId/tags', body: {
      'scope': scope,
      'scope_id': scopeId,
    });
    return IntelligenceEnvelope.fromResponse(response);
  }

  Future<void> refresh() async {
    final response = await _client.post('/intelligence/refresh');
    IntelligenceEnvelope.fromResponse(response);
  }

  Future<IntelligenceEnvelope> _get(String path, Map<String, String> query) async {
    final response = await _client.get(path, query: query);
    return IntelligenceEnvelope.fromResponse(response);
  }
}
