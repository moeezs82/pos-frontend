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
  String? _initializedContext;
  int? _branchId;

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
  Map<String, dynamic>? get closeRequest {
    final raw = _shift?['close_request'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  bool get hasPendingCloseRequest => closeRequest?['status'] == 'pending';

  /// Cache key for SharedPreferences, namespaced by user and branch.
  ///
  /// Including the branch prevents the same Master Admin account from showing
  /// Business A's cached open register after switching to Business B.
  String _cacheKey() =>
      'register_shift_${_userId ?? 'default'}_b${_branchId ?? 'none'}';

  /// Called by [_AuthOrchestrator] in `main.dart` whenever a new session
  /// starts (login, token refresh, auto-login restore).
  ///
  /// [token]  — the new Sanctum bearer token.
  /// [userId] — string representation of `user.id`.
  /// [branchId] — selected independent business; part of both the in-memory
  ///              context guard and the SharedPreferences cache key.
  ///
  /// Idempotent: if token and branch equal the initialized context the call is
  /// a no-op (safe to call from [_AuthOrchestrator]'s listener, which may
  /// fire on every [AuthProvider.notifyListeners]).
  ///
  /// Session-generation guard: the generation is bumped *before* any await so
  /// a stale refresh() or initialize() from the previous user is discarded as
  /// soon as it resumes.
  Future<void> initialize(
    String? token, {
    String? userId,
    int? branchId,
  }) async {
    if (token == null || branchId == null || branchId <= 0) {
      return clear(removeCachedShift: false);
    }
    final contextKey = '$token#$branchId';
    if (_initializedContext == contextKey) return;

    // Bump the session generation so any in-flight async from the old session
    // (e.g. User A's refresh()) will see a generation mismatch on resume and
    // discard its result.
    final gen = ++_sessionGeneration;

    _initializedContext = contextKey;
    _token = token;
    _userId = userId;
    _branchId = branchId;

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

    final cacheKey = _cacheKey();
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final map = jsonDecode(cached);
        if (map is Map) {
          _shift = Map<String, dynamic>.from(map);
          notifyListeners();
        }
      } catch (_) {
        await prefs.remove(cacheKey);
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

  Future<bool> close({
    required double countedCash,
    required int pendingSyncCount,
    String? note,
  }) async {
    if (_token == null || id == null) throw StateError('No active shift');
    _setLoading(true);
    try {
      final result = await _serviceFactory(_token!).close(id!, {
        'client_ref': const Uuid().v4(),
        'counted_cash': countedCash,
        'pending_sync_count': pendingSyncCount,
        'accept_pending_sync': false,
        if (note?.trim().isNotEmpty == true) 'closing_note': note!.trim(),
      });

      if (result['approval_required'] == true) {
        final shiftData = result['shift'];
        _shift = shiftData is Map
            ? Map<String, dynamic>.from(shiftData)
            : _shift;
        _error = null;
        await _persist();
        await refresh();
        return true;
      }

      _shift = null;
      _summary = const {};
      _activity = const {};
      _occupiedShifts = const [];
      _error = null;
      await _persist();
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Clears all state and stops the current session.
  ///
  /// Bumps [_sessionGeneration] so any in-flight refresh() from the cleared
  /// session discards its result.
  ///
  /// Removes the per-user cache key (not a shared key) so the next login
  /// starts clean.  If the provider is already fully cleared the call is a
  /// fast no-op (safe to call repeatedly from the logout path).
  Future<void> clear({bool removeCachedShift = true}) async {
    final alreadyClear = _token == null &&
        _initializedContext == null &&
        _shift == null &&
        _summary.isEmpty &&
        _error == null &&
        _userId == null &&
        _branchId == null;
    if (alreadyClear) return;

    // Capture the current key before wiping _userId so _persist() can remove
    // it.  We can't call _cacheKey() after _userId is nulled.
    final prevKey = _cacheKey();

    ++_sessionGeneration; // invalidate any pending async from this session
    _token = null;
    _initializedContext = null;
    _userId = null;
    _branchId = null;
    _shift = null;
    _summary = const {};
    _activity = const {};
    _occupiedShifts = const [];
    _error = null;

    if (removeCachedShift) {
      final p = await SharedPreferences.getInstance();
      await p.remove(prevKey);
    }
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
