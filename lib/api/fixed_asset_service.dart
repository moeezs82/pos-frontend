import 'package:enterprise_pos/api/core/api_client.dart';

/// Fixed assets and straight-line depreciation of the active branch
/// (add-on `fixed_assets`, writes need `manage-fixed-assets`).
///
/// The backend posts every entry (purchase, monthly depreciation, disposal)
/// and every undo as an exact mirror entry; nothing is deleted.
class FixedAssetService {
  final ApiClient _client;

  FixedAssetService({required String token}) : _client = ApiClient(token: token);

  Map<String, dynamic> _data(Map<String, dynamic> res, String fallback) {
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? fallback);
  }

  /// GET /fixed-assets → { items: [...], summary: { active_assets, cost, accumulated_depreciation, book_value } }
  Future<Map<String, dynamic>> list({String? status, String? search}) async => _data(
        await _client.get('/fixed-assets', query: {
          if (status != null && status.isNotEmpty) 'status': status,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        }),
        'Failed to load fixed assets',
      );

  /// GET /fixed-assets/{id} → { asset, depreciations: [...] }
  Future<Map<String, dynamic>> show(int id) async => _data(await _client.get('/fixed-assets/$id'), 'Failed to load the asset');

  /// POST /fixed-assets — register and post the purchase.
  /// [funding] is 'cash' (paid via [paymentMethod]) or 'vendor' (on credit, [vendorId]).
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      _data(await _client.post('/fixed-assets', body: body), 'Failed to register the asset');

  /// PUT /fixed-assets/{id} — name, category, asset_code, notes only.
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> changes) async =>
      _data(await _client.put('/fixed-assets/$id', body: changes), 'Failed to update the asset');

  Future<Map<String, dynamic>> voidAsset(int id) async =>
      _data(await _client.post('/fixed-assets/$id/void', body: const {}), 'Failed to void the asset');

  Future<Map<String, dynamic>> dispose(int id, {required String date, double proceeds = 0, String? paymentMethod, String? note}) async =>
      _data(
        await _client.post('/fixed-assets/$id/dispose', body: {
          'disposal_date': date,
          'proceeds': proceeds,
          if (paymentMethod != null) 'payment_method': paymentMethod,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }),
        'Failed to dispose of the asset',
      );

  Future<Map<String, dynamic>> voidDisposal(int id) async =>
      _data(await _client.post('/fixed-assets/$id/disposal/void', body: const {}), 'Failed to reverse the disposal');

  /// GET /fixed-assets/depreciation-preview?period=YYYY-MM → { lines, summary }
  Future<Map<String, dynamic>> previewDepreciation(String period) async =>
      _data(await _client.get('/fixed-assets/depreciation-preview', query: {'period': period}), 'Failed to preview depreciation');

  /// POST /fixed-assets/depreciation-run — posts every pending month through [period].
  Future<Map<String, dynamic>> runDepreciation(String period) async =>
      _data(await _client.post('/fixed-assets/depreciation-run', body: {'period': period}), 'Failed to run depreciation');

  /// POST /fixed-assets/depreciation-run/reverse — reverses [period] (latest month only).
  Future<Map<String, dynamic>> reverseDepreciation(String period) async =>
      _data(await _client.post('/fixed-assets/depreciation-run/reverse', body: {'period': period}), 'Failed to reverse depreciation');
}
