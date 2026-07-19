import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../api/register_shift_service.dart';

class RegisterShiftProvider extends ChangeNotifier {
  /// Optional factory used to create [RegisterShiftService] instances.
  ///
  /// Production code leaves this null (defaults to [RegisterShiftService.new]).
  /// Tests inject a fake factory so they can control responses without hitting
  /// the network.
  final RegisterShiftService Function(String token) _serviceFactory;

  RegisterShiftProvider({
    RegisterShiftService Function(String token)? serviceFactory,
  }) : _serviceFactory = serviceFactory ?? RegisterShiftService.new;

  Map<String, dynamic>? _shift;
  Map<String, dynamic> _summary = const {};
  Map<String, dynamic> _activity = const {}; // unified drawer activity + reconciliation
  List<Map<String, dynamic>> _occupiedShifts = const [];
  bool _loading = false;
  String? _error;
  String? _token;
  String? _initializedToken;

  // Incremented on every initialize() and clear() call.  Every async
  // operation captures the current generation before it goes async; on
  // completion it compares the captured value against the current one and
  // discards the result if they differ.  This is the standard approach for
  // preventing stale async responses (e.g. User A's refresh() arriving while
  // User B is already logged in) from corrupting the active session's state.
  int _sessionGeneration = 0;

  // Authenticated user ID for the current session.  Used to namespace the
  // SharedPreferences cache key so a new login never loads a previous user's
  // cached shift. Cleared in clear().
  String? _userId;

  Map<String, dynamic>? get shift => _shift;
  Map<String, dynamic> get summary => _summary;
  Map<String, dynamic> get activity => _activity;
  List<Map<String, dynamic>> get activityItems =>
      (_activity['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [];
  Map<String, dynamic> get reconciliation =>
      (_activity['reconciliation'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<Map<String, dynamic>> get occupiedShifts => _occupiedShifts;
  bool get hasOccupiedRegisters => _occupiedShifts.isNotEmpty;
  bool get hasActiveShift => _shift != null && _shift!['status'] == 'open';
  bool get loading => _loading;
  String? get error => _error;
  String? get clientRef => _shift?['client_ref']?.toString();
  int? get id => int.tryParse(_shift?['id']?.toString() ?? '');

  /// Cache key for SharedPreferences, namespaced by user ID.
  ///
  /// Using a per-user key prevents User B from reading User A's cached shift
  /// on startup and showing "open register" when the shift belongs to someone
  /// else.  The key format is `register_shift_<userId>`; for backward
  /// compatibility with the default-user flow (guest mode, if ever needed) it
  /// falls back to `register_shift_default`.
  String _cacheKey() => 'register_shift_${_userId ?? 'default'}';

  /// Called by [_AuthOrchestrator] in `main.dart` whenever a new session
  /// starts (login, token refresh, auto-login restore).
  ///
  /// [token]  — the new Sanctum bearer token.
  /// [userId] — string representation of `user.id`; used to namespace the
  ///            SharedPreferences cache key.
  ///
  /// Idempotent: if [token] equals the already-initialized token the call is
  /// a no-op (safe to call from [_AuthOrchestrator]'s listener, which may
  /// fire on every [AuthProvider.notifyListeners]).
  ///
  /// Session-generation guard: the generation is bumped *before* any await so
  /// a stale refresh() or initialize() from the previous user is discarded as
  /// soon as it resumes.
  Future<void> initialize(String? token, {String? userId}) async {
    if (token == null) return clear();
    if (_initializedToken == token) return; // already set up for this token

    // Bump the session generation so any in-flight async from the old session
    // (e.g. User A's refresh()) will see a generation mismatch on resume and
    // discard its result.
    final gen = ++_sessionGeneration;

    _initializedToken = token;
    _token = token;
    _userId = userId;

    // Immediately surface an empty slate — do NOT show the previous user's
    // shift while the network round-trip is in flight.
    _shift = null;
    _summary = const {};
    _activity = const {};
    _occupiedShifts = const [];
    _error = null;
    notifyListeners();

    // Try to show a cached shift for this user instantly, before the network
    // call.  This gives the cashier instant UI feedback on app startup/login.
    final prefs = await SharedPreferences.getInstance();
    if (gen != _sessionGeneration) return; // superseded by a newer initialize/clear

    final cached = prefs.getString(_cacheKey());
    if (cached != null) {
      final map = jsonDecode(cached);
      if (map is Map) {
        _shift = Map<String, dynamic>.from(map);
        notifyListeners();
      }
    }

    // Always validate against the server — the cached value may be stale
    // (shift closed by a manager, different device, etc.).
    if (gen == _sessionGeneration) await refresh(generation: gen);
  }

  /// Re-fetches the active shift and occupied registers from the server.
  ///
  /// [generation] — when supplied, the call discards its result if
  ///   [_sessionGeneration] has moved on (i.e. another login/logout
  ///   superseded this session while the request was in flight).  Callers
  ///   inside [initialize] always supply it; external callers (register-shift
  ///   screen, open/close actions) omit it to force an update.
  Future<void> refresh({int? generation}) async {
    if (_token == null) return;
    final gen = generation ?? _sessionGeneration;
    _setLoading(true);
    try {
      final data = await _serviceFactory(_token!).active();
      if (gen != _sessionGeneration) return; // stale — discard

      _shift = data?['shift'] == null
          ? null
          : Map<String, dynamic>.from(data!['shift'] as Map);
      _summary = data?['summary'] == null
          ? const {}
          : Map<String, dynamic>.from(data!['summary'] as Map);
      _activity = data?['activity'] == null
          ? const {}
          : Map<String, dynamic>.from(data!['activity'] as Map);
      final occupied = data?['occupied_shifts'];
      _occupiedShifts = occupied is List
          ? occupied
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
          : const [];
      _error = null;
      await _persist();
    } catch (e) {
      if (gen != _sessionGeneration) return;
      _error = e.toString(); // retain cached shift while temporarily offline
    } finally {
      if (gen == _sessionGeneration) _setLoading(false);
    }
  }

  Future<void> open({
    required int registerId,
    required double openingCash,
    String? note,
    String? deviceIdentifier,
  }) async {
    if (_token == null) throw StateError('Not authenticated');
    _setLoading(true);
    try {
      _shift = await _serviceFactory(_token!).open({
        'register_id': registerId,
        'client_ref': const Uuid().v4(),
        'opening_cash': openingCash,
        if (note?.trim().isNotEmpty == true) 'opening_note': note!.trim(),
        if (deviceIdentifier?.trim().isNotEmpty == true)
          'device_identifier': deviceIdentifier!.trim(),
        'opened_at': DateTime.now().toIso8601String(),
      });
      _error = null;
      await _persist();
      await refresh();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addMovement({
    required String direction,
    required double amount,
    required String reason,
    String? note,
  }) async {
    if (_token == null || id == null) throw StateError('No active shift');
    await _serviceFactory(_token!).movement(id!, {
      'client_ref': const Uuid().v4(),
      'direction': direction,
      'amount': amount,
      'reason': reason,
      if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
      'occurred_at': DateTime.now().toIso8601String(),
    });
    await refresh();
  }

  Future<void> close({
    required double countedCash,
    required int pendingSyncCount,
    String? note,
  }) async {
    if (_token == null || id == null) throw StateError('No active shift');
    await _serviceFactory(_token!).close(id!, {
      'client_ref': const Uuid().v4(),
      'counted_cash': countedCash,
      'pending_sync_count': pendingSyncCount,
      'accept_pending_sync': false,
      if (note?.trim().isNotEmpty == true) 'closing_note': note!.trim(),
    });
    _shift = null;
    _summary = const {};
    _activity = const {};
    _occupiedShifts = const [];
    await _persist();
    notifyListeners();
  }

  /// Clears all state and stops the current session.
  ///
  /// Bumps [_sessionGeneration] so any in-flight refresh() from the cleared
  /// session discards its result.
  ///
  /// Removes the per-user cache key (not a shared key) so the next login
  /// starts clean.  If the provider is already fully cleared the call is a
  /// fast no-op (safe to call repeatedly from the logout path).
  Future<void> clear() async {
    final alreadyClear = _token == null &&
        _initializedToken == null &&
        _shift == null &&
        _summary.isEmpty &&
        _error == null &&
        _userId == null;
    if (alreadyClear) return;

    // Capture the current key before wiping _userId so _persist() can remove
    // it.  We can't call _cacheKey() after _userId is nulled.
    final prevKey = _cacheKey();

    ++_sessionGeneration; // invalidate any pending async from this session
    _token = null;
    _initializedToken = null;
    _userId = null;
    _shift = null;
    _summary = const {};
    _activity = const {};
    _occupiedShifts = const [];
    _error = null;

    final p = await SharedPreferences.getInstance();
    await p.remove(prevKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    if (_shift == null) {
      await p.remove(_cacheKey());
    } else {
      await p.setString(_cacheKey(), jsonEncode(_shift));
    }
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }
}
