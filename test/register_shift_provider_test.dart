// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enterprise_pos/api/register_shift_service.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';

// ---------------------------------------------------------------------------
// Fake RegisterShiftService
//
// Returned responses are controlled per-call via a queue of [Completer]s so
// tests can deterministically control when an async response arrives.  This
// lets us reproduce the session-generation race: start a response for User A,
// switch to User B, then complete User A's response and assert that it is
// discarded.
// ---------------------------------------------------------------------------

class _FakeService implements RegisterShiftService {
  // Each element is one pending call.  add() enqueues a completer; active()
  // pops the first one so callers can complete it from outside.
  final _pending = <Completer<Map<String, dynamic>?>>[];

  /// How many times active() has been called.  Used to assert idempotency.
  int activeCalls = 0;

  /// Enqueue a completer for the *next* active() call and return it so the
  /// test can complete (or error) it at the right moment.
  Completer<Map<String, dynamic>?> nextActiveCompleter() {
    final c = Completer<Map<String, dynamic>?>();
    _pending.add(c);
    return c;
  }

  @override
  Future<Map<String, dynamic>?> active() {
    activeCalls++;
    if (_pending.isEmpty) {
      // Default: return null (no active shift) immediately.
      return Future.value(null);
    }
    return _pending.removeAt(0).future;
  }

  // ---- remaining interface members not needed in these tests ----

  @override
  Future<List<Map<String, dynamic>>> registers({bool includeInactive = false}) =>
      Future.value(const []);

  @override
  Future<Map<String, dynamic>> createRegister(Map<String, dynamic> body) =>
      Future.value(const {});

  @override
  Future<Map<String, dynamic>> updateRegister(int id, Map<String, dynamic> body) =>
      Future.value(const {});

  @override
  Future<Map<String, dynamic>> open(Map<String, dynamic> body) =>
      Future.value(const {});

  @override
  Future<Map<String, dynamic>> movement(int id, Map<String, dynamic> body) =>
      Future.value(const {});

  @override
  Future<Map<String, dynamic>> close(int id, Map<String, dynamic> body) =>
      Future.value(const {});

  @override
  Future<Map<String, dynamic>> history() => Future.value(const {});

  @override
  Future<Map<String, dynamic>> detail(int id) => Future.value(const {});
}

// ---------------------------------------------------------------------------
// Helper: build a minimal shift payload
// ---------------------------------------------------------------------------

Map<String, dynamic> _fakeShift({
  int id = 1,
  int registerId = 1,
  String status = 'open',
}) =>
    {
      'id': id,
      'register_id': registerId,
      'cashier_id': 99,
      'status': status,
      'opened_at': '2026-07-14T08:00:00.000Z',
      'opening_cash': '500.00',
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Use an in-memory SharedPreferences for all tests.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Convenience: create a provider backed by a fake service.
  RegisterShiftProvider makeProvider(_FakeService svc) =>
      RegisterShiftProvider(serviceFactory: (_) => svc);

  // -------------------------------------------------------------------------
  // 1. Token isolation: User B's initialize() immediately clears User A's state
  // -------------------------------------------------------------------------

  group('token isolation', () {
    test('state is cleared synchronously when a new token is initialized', () async {
      final svc = _FakeService();

      // Pre-seed User A's shift in SharedPreferences.
      final prefsA = await SharedPreferences.getInstance();
      await prefsA.setString(
        'register_shift_user1',
        '{"id":1,"register_id":1,"status":"open","opened_at":"2026-07-14T08:00:00.000Z","opening_cash":"500.00","cashier_id":99}',
      );

      // Enqueue a completer so User A's active() stays in-flight.
      final completerA = svc.nextActiveCompleter();

      final provider = makeProvider(svc);

      // Initialize for User A but do NOT await — it's in flight.
      final futureA = provider.initialize('token-a', userId: 'user1');

      // Yield twice: once to get past prefs, once more to reach the active()
      // call.  After this, completerA is the in-flight request for User A.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Now switch to User B before the network response arrives.
      final _ = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-b', userId: 'user2');

      // User B is fully initialised — state must be clear (no inherited shift).
      expect(provider.shift, isNull,
          reason: 'Initializing with a new token must clear the previous shift');
      expect(provider.hasActiveShift, isFalse);

      // Complete User A's stale network response — must be discarded.
      completerA.complete({'shift': _fakeShift(id: 1), 'summary': null, 'occupied_shifts': []});
      await futureA;
      await Future<void>.delayed(Duration.zero);

      expect(provider.shift, isNull,
          reason: "User A's stale response must not overwrite User B's state");
    });

    test('initialize() is a no-op when called again with the same token', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // First call: enqueue an immediate null response.
      final _ = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-a', userId: 'user1');

      expect(svc.activeCalls, 1, reason: 'First initialize should call active() once');

      // Second call with identical token: the guard must short-circuit — no
      // additional active() call must be issued.
      await provider.initialize('token-a', userId: 'user1');

      expect(svc.activeCalls, 1,
          reason: 'Second initialize with the same token must not call active() again');
      expect(provider.shift, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Session generation: stale async responses are discarded
  // -------------------------------------------------------------------------

  group('session generation', () {
    test('stale active() result from session N is discarded when session is N+1',
        () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Session 1 (User A): queue a completer that we control.
      final completerA = svc.nextActiveCompleter();
      // Start session 1 but do NOT await it.
      final futureA = provider.initialize('token-a', userId: 'user1');

      // Yield to the event loop so session 1 gets past its prefs read and
      // calls active() — popping completerA from position 0.  Without this
      // delay, session 2 might pop completerA instead, deadlocking the test.
      await Future<void>.delayed(Duration.zero);

      // Session 2 (User B): immediately complete with null.
      final completerB = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-b', userId: 'user2');

      // User A's stale network response finally arrives with a shift.
      completerA.complete({
        'shift': _fakeShift(id: 42),
        'summary': null,
        'occupied_shifts': [],
      });
      await futureA;
      await Future<void>.delayed(Duration.zero);

      // User B's state must be intact — User A's stale result must be discarded.
      expect(provider.shift, isNull,
          reason: 'Stale response from superseded session must not mutate state');
      completerB.future.ignore();
    });

    test('clear() increments session so in-flight refresh() is discarded', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Start a session that keeps the network request in-flight.
      final completer = svc.nextActiveCompleter();
      final future = provider.initialize('token-a', userId: 'user1');

      // Give the event loop enough time for initialize() to reach the
      // active() await so it has actually popped the completer from the queue.
      await Future<void>.delayed(Duration.zero);

      // Logout before the network response arrives.
      await provider.clear();

      // Now complete the stale network response.
      completer.complete({
        'shift': _fakeShift(id: 7),
        'summary': null,
        'occupied_shifts': [],
      });
      await future;
      await Future<void>.delayed(Duration.zero);

      // State must remain cleared — the stale response must be discarded.
      expect(provider.shift, isNull,
          reason: 'Response from a cleared session must not restore shift state');
      expect(provider.hasActiveShift, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 3. SharedPreferences namespacing by user ID
  // -------------------------------------------------------------------------

  group('userId-namespaced cache', () {
    test('different user IDs use different SharedPreferences keys', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Initialize User 1 and simulate an open shift response.
      final c1 = svc.nextActiveCompleter();
      final f1 = provider.initialize('token-1', userId: 'user1');
      c1.complete({
        'shift': _fakeShift(id: 10, registerId: 1),
        'summary': null,
        'occupied_shifts': [],
      });
      await f1;

      // Shift is now persisted under "register_shift_user1".
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('register_shift_user1'), isTrue,
          reason: 'Shift must be cached under user1 key');
      expect(prefs.containsKey('register_shift_user2'), isFalse,
          reason: 'User2 key must not exist yet');

      // Switch to User 2 with no shift.
      final c2 = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-2', userId: 'user2');
      await Future<void>.delayed(Duration.zero);

      // User 2 must not see User 1's cached shift in the provider state.
      expect(provider.shift, isNull,
          reason: 'User 2 must not inherit User 1 cached shift');
      // User 1's key in SharedPreferences is still intact (not wiped by the
      // other user's session).
      expect(prefs.containsKey('register_shift_user1'), isTrue,
          reason: 'clear() must remove only the current user key, not other users');

      // Suppress unused variable warning.
      c2.future.ignore();
    });

    test('clear() removes only the current user key', () async {
      final svc = _FakeService();
      final prefs = await SharedPreferences.getInstance();

      // Pre-seed two users in SharedPreferences.
      await prefs.setString('register_shift_user1',
          '{"id":1,"register_id":1,"status":"open","opened_at":"2026-07-14T08:00:00.000Z","opening_cash":"500.00","cashier_id":99}');
      await prefs.setString('register_shift_user2',
          '{"id":2,"register_id":2,"status":"open","opened_at":"2026-07-14T08:00:00.000Z","opening_cash":"200.00","cashier_id":88}');

      final provider = makeProvider(svc);

      // Initialize and immediately clear User 1.
      final c = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-1', userId: 'user1');
      await provider.clear();

      // User 1's key should be removed; User 2's key must still be there.
      final updated = await SharedPreferences.getInstance();
      expect(updated.containsKey('register_shift_user1'), isFalse,
          reason: 'clear() must remove the current user key');
      expect(updated.containsKey('register_shift_user2'), isTrue,
          reason: 'clear() must not touch other users keys');

      // Suppress unused variable warning.
      c.future.ignore();
    });

    test('shift is recovered from the server after logout and re-login', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Session 1: server confirms an open shift.
      final c1 = svc.nextActiveCompleter();
      final f1 = provider.initialize('token-a', userId: 'user1');
      c1.complete({
        'shift': _fakeShift(id: 5, registerId: 2),
        'summary': null,
        'occupied_shifts': [],
      });
      await f1;
      expect(provider.shift?['id'], 5);

      // Logout — clear() removes the per-user cache key so the next login
      // always validates against the server rather than showing a stale cache.
      await provider.clear();
      expect(provider.shift, isNull);

      // Re-login as the same user with a new token.
      // The cache was removed on logout, so recovery comes entirely from the
      // server response (simulates the "no app restart" re-login scenario).
      final c2 = svc.nextActiveCompleter();
      final f2 = provider.initialize('token-b', userId: 'user1');
      c2.complete({
        'shift': _fakeShift(id: 5, registerId: 2),
        'summary': null,
        'occupied_shifts': [],
      });
      await f2;

      expect(provider.shift?['id'], 5,
          reason: 'Server-returned shift must be restored on re-login without app restart');
      expect(provider.hasActiveShift, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 4. clear() is a no-op when already cleared
  // -------------------------------------------------------------------------

  group('clear() idempotency', () {
    test('clear() is safe to call when provider has never been initialized', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Should not throw, not notify unnecessarily.
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.clear(); // already empty
      expect(notifyCount, 0, reason: 'No-op clear must not notify listeners');
    });

    test('double clear() does not throw or notify twice', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      // Initialize then clear once.
      final c = svc.nextActiveCompleter()..complete(null);
      await provider.initialize('token-a', userId: 'user1');
      await provider.clear();

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // Second clear must be a no-op.
      await provider.clear();
      expect(notifyCount, 0, reason: 'Second clear must not notify');

      // Suppress unused variable warning.
      c.future.ignore();
    });
  });

  // -------------------------------------------------------------------------
  // 5. hasActiveShift getter
  // -------------------------------------------------------------------------

  group('hasActiveShift', () {
    test('returns false when shift is null', () {
      final provider = RegisterShiftProvider();
      expect(provider.hasActiveShift, isFalse);
    });

    test('returns true only when shift status is open', () async {
      final svc = _FakeService();
      final provider = makeProvider(svc);

      final c = svc.nextActiveCompleter();
      final f = provider.initialize('token-a', userId: 'u1');
      c.complete({
        'shift': _fakeShift(status: 'open'),
        'summary': null,
        'occupied_shifts': [],
      });
      await f;

      expect(provider.hasActiveShift, isTrue);

      // If the server returned a closed shift (edge case), the getter must be false.
      final c2 = svc.nextActiveCompleter();
      final f2 = provider.initialize('token-b', userId: 'u2');
      c2.complete({
        'shift': _fakeShift(status: 'closed'),
        'summary': null,
        'occupied_shifts': [],
      });
      await f2;

      expect(provider.hasActiveShift, isFalse,
          reason: 'A closed shift must not be reported as active');
    });
  });
}
