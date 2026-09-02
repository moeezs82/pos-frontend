import 'package:enterprise_pos/api/core/api_client.dart';

class RegisterShiftService {
  final ApiClient _client;
  RegisterShiftService(String token) : _client = ApiClient(token: token);

  Future<List<Map<String, dynamic>>> registers({
    bool includeInactive = false,
  }) async {
    final r = await _client.get(
      '/registers',
      query: includeInactive ? {'include_inactive': '1'} : null,
    );
    return ((r['data'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createRegister(
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.post('/registers', body: body))['data'] as Map,
  );

  Future<Map<String, dynamic>> updateRegister(
    int id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.put('/registers/$id', body: body))['data'] as Map,
  );

  Future<Map<String, dynamic>?> active() async {
    final r = await _client.get('/register-shifts/active');
    return r['data'] == null
        ? null
        : Map<String, dynamic>.from(r['data'] as Map);
  }

  Future<Map<String, dynamic>> open(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        (await _client.post('/register-shifts/open', body: body))['data']
            as Map,
      );

  Future<Map<String, dynamic>> movement(
    int id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.post(
          '/register-shifts/$id/cash-movements',
          body: body,
        ))['data']
        as Map,
  );

  Future<Map<String, dynamic>> close(
    int id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.post('/register-shifts/$id/close', body: body))['data']
        as Map,
  );

  Future<List<Map<String, dynamic>>> openShifts() async {
    final response = await _client.get('/register-shifts/open');
    return ((response['data'] as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> approveCloseRequest({
    required int shiftId,
    required int requestId,
    required String decisionNote,
    required bool acceptPendingSync,
  }) async => Map<String, dynamic>.from(
    (await _client.post(
          '/register-shifts/$shiftId/close-requests/$requestId/approve',
          body: {
            'decision_note': decisionNote,
            'accept_pending_sync': acceptPendingSync,
          },
        ))['data']
        as Map,
  );

  Future<Map<String, dynamic>> rejectCloseRequest({
    required int shiftId,
    required int requestId,
    required String decisionNote,
  }) async => Map<String, dynamic>.from(
    (await _client.post(
          '/register-shifts/$shiftId/close-requests/$requestId/reject',
          body: {'decision_note': decisionNote},
        ))['data']
        as Map,
  );

  Future<Map<String, dynamic>> forceClose(
    int shiftId,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.post(
          '/register-shifts/$shiftId/force-close',
          body: body,
        ))['data']
        as Map,
  );

  Future<Map<String, dynamic>> history() async =>
      Map<String, dynamic>.from(
        (await _client.get('/register-shifts'))['data'] as Map,
      );

  Future<Map<String, dynamic>> detail(int id) async =>
      Map<String, dynamic>.from(
        (await _client.get('/register-shifts/$id'))['data'] as Map,
      );
  Future<Map<String, dynamic>> variances({
    String status = 'pending',
    String? direction,
    int page = 1,
    int perPage = 50,
  }) async => Map<String, dynamic>.from(
    (await _client.get(
      '/register-shift-variances',
      query: {
        'status': status,
        'page': '$page',
        'per_page': '$perPage',
        if (direction != null && direction.isNotEmpty) 'direction': direction,
      },
    ))['data'] as Map,
  );

  Future<Map<String, dynamic>> varianceDetail(int varianceId) async =>
      Map<String, dynamic>.from(
        (await _client.get('/register-shift-variances/$varianceId'))['data'] as Map,
      );

  Future<Map<String, dynamic>> resolveVariance(
    int varianceId,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await _client.post(
      '/register-shift-variances/$varianceId/resolve',
      body: body,
    ))['data'] as Map,
  );

}
