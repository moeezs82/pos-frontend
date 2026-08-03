import 'dart:typed_data';

import 'package:enterprise_pos/api/core/api_client.dart';

class CreditControlExportFile {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const CreditControlExportFile({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
}

class CreditControlService {
  final ApiClient _client;

  CreditControlService({required String token}) : _client = ApiClient(token: token);

  Future<Map<String, dynamic>> overview() async {
    final res = await _client.get('/credit-control/overview');
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return (res['data'] as Map).cast<String, dynamic>();
    }
    throw Exception(res['message'] ?? 'Failed to load credit-control overview');
  }

  Future<Map<String, dynamic>> audits({
    int page = 1,
    int perPage = 25,
    String? partyType,
    int? partyId,
    String? outcome,
    String? sourceType,
    int? actorId,
    String? from,
    String? to,
    String? search,
  }) async {
    final query = _query({
      'page': page,
      'per_page': perPage,
      'party_type': partyType,
      'party_id': partyId,
      'outcome': outcome,
      'source_type': sourceType,
      'actor_id': actorId,
      'from': from,
      'to': to,
      'search': search,
    });
    final res = await _client.get('/credit-control/audits', query: query);
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return (res['data'] as Map).cast<String, dynamic>();
    }
    throw Exception(res['message'] ?? 'Failed to load credit-control audits');
  }

  Future<CreditControlExportFile> exportAudits({
    String? partyType,
    int? partyId,
    String? outcome,
    String? sourceType,
    int? actorId,
    String? from,
    String? to,
    String? search,
  }) async {
    final res = await _client.download(
      '/credit-control/audits/export',
      query: _query({
        'party_type': partyType,
        'party_id': partyId,
        'outcome': outcome,
        'source_type': sourceType,
        'actor_id': actorId,
        'from': from,
        'to': to,
        'search': search,
      }),
    );
    return CreditControlExportFile(
      bytes: res.bytes,
      filename: res.filename,
      contentType: res.contentType,
    );
  }

  Map<String, String> _query(Map<String, dynamic> values) {
    final out = <String, String>{};
    for (final entry in values.entries) {
      if (entry.value == null) continue;
      final value = entry.value.toString().trim();
      if (value.isEmpty || value == 'null') continue;
      out[entry.key] = value;
    }
    return out;
  }
}
