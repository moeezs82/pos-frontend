import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/models/product_unit.dart';

/// Units of measure.
///
/// Routes (all require view-units to read, manage-units to write):
///   GET    /units          — list, branch-scoped
///   POST   /units          — create
///   GET    /units/{id}     — show
///   PUT    /units/{id}     — update
///   DELETE /units/{id}     — delete
///
/// Units are branch-scoped like categories and brands: a unit created in one
/// branch is invisible to another. Rows the backend marks global stay visible
/// everywhere; the client does not need to distinguish them.
class UnitService {
  final ApiClient _client;

  UnitService({required String token}) : _client = ApiClient(token: token);

  Future<List<ProductUnit>> list() async {
    final res = await _client.get('/units');
    final data = res['data'];
    final raw = data is Map ? data['units'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ProductUnit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ProductUnit> show(int id) async {
    final res = await _client.get('/units/$id');
    return _unitFrom(res);
  }

  Future<ProductUnit> create({
    required String name,
    String? shortName,
    required bool allowDecimal,
    bool isActive = true,
  }) async {
    final res = await _client.post('/units', body: {
      'name': name,
      if (shortName != null && shortName.trim().isNotEmpty)
        'short_name': shortName.trim(),
      'allow_decimal': allowDecimal,
      'is_active': isActive,
    });
    return _unitFrom(res);
  }

  /// Partial update — only the fields present are changed.
  ///
  /// Turning [allowDecimal] off can be REFUSED by the backend with a 422 on
  /// `allow_decimal` when products using this unit still hold fractional
  /// stock. That is a real business rule, not a transient error: surface the
  /// message rather than retrying.
  Future<ProductUnit> update(
    int id, {
    String? name,
    String? shortName,
    bool? allowDecimal,
    bool? isActive,
  }) async {
    final res = await _client.put('/units/$id', body: {
      if (name != null) 'name': name,
      if (shortName != null) 'short_name': shortName.trim(),
      if (allowDecimal != null) 'allow_decimal': allowDecimal,
      if (isActive != null) 'is_active': isActive,
    });
    return _unitFrom(res);
  }

  /// Deleting a unit that products still reference is refused with a 422 —
  /// every product must keep a unit.
  Future<void> delete(int id) => _client.delete('/units/$id');

  ProductUnit _unitFrom(Map<String, dynamic> res) {
    final data = res['data'];
    final raw = data is Map ? data['unit'] : null;
    if (raw is Map) {
      return ProductUnit.fromJson(Map<String, dynamic>.from(raw));
    }
    throw StateError('Unexpected unit response: $res');
  }
}
