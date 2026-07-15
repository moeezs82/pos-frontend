import 'package:enterprise_pos/models/subscription_status.dart';
import 'package:enterprise_pos/services/subscription_service.dart';
import 'package:flutter/material.dart';

/// ChangeNotifier that owns the current branch's subscription state.
///
/// Consumers watch [isLocked] to decide whether to show the branch lock screen
/// and [showAlert] + [status] to decide whether to show a warning banner.
///
/// LIFECYCLE
/// - After login → [checkForBranch] is called by _AuthOrchestrator
/// - After branch switch → [checkForBranch] is called
/// - On app resume after >15 min → [checkForBranch] is called
/// - When any API call returns 402 → [markExpiredFromResponse] is called
/// - On logout → [clear] is called
///
/// STATES
/// - _status == null: not yet checked (loading state)
/// - _status.isLocked == true: branch is blocked
/// - _checking == true: a server request is in flight
class SubscriptionProvider with ChangeNotifier {
  final _service = SubscriptionService.instance;

  SubscriptionStatus? _status;
  bool _checking = false;
  String? _error;

  // Prevent spamming the server: record when the last successful check ran.
  DateTime? _lastChecked;
  static const _minRefreshInterval = Duration(minutes: 15);

  // ── Getters ──────────────────────────────────────────────────────────────

  SubscriptionStatus? get status => _status;
  bool get isLocked => _status?.isLocked ?? false;
  bool get showAlert => _status?.showAlert ?? false;
  bool get isChecking => _checking;
  String? get error => _error;

  /// True while the first check for this session has not yet completed.
  bool get isInitializing => _status == null && _checking;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Checks subscription status for [branchId].
  ///
  /// Uses the 24-hour cache first.  Forces a server call when [forceRefresh]
  /// is true or when the last check is older than [_minRefreshInterval].
  Future<void> checkForBranch({
    required String token,
    required int branchId,
    bool forceRefresh = false,
  }) async {
    // Rate-limit: skip if we checked recently and this isn't forced.
    if (!forceRefresh &&
        _lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < _minRefreshInterval &&
        _status?.branchId == branchId) {
      return;
    }

    _checking = true;
    _error = null;
    notifyListeners();

    try {
      // Try cache first.
      SubscriptionStatus? result = forceRefresh
          ? null
          : await _service.getCachedStatus(branchId);

      // No valid cache — hit the server.
      result ??= await _service.checkFromServer(
        token: token,
        branchId: branchId,
      );

      // If server is unreachable AND cache is stale AND we have no previous
      // status, fail closed — lock the branch until the server can be reached.
      // This matches the backend's fail-closed policy: no verified subscription
      // means no access.  A valid 24-hour cache keeps users operational during
      // brief connectivity interruptions without requiring a server round-trip.
      if (result == null) {
        _error = 'Could not verify subscription. Please reconnect to continue.';
        if (_status?.branchId != branchId) {
          // New branch, no cache, server unreachable — lock until verified.
          _status = SubscriptionStatus.notConfigured(branchId);
        }
      } else {
        _status = result;
        _error = null;
      }

      _lastChecked = DateTime.now();
    } catch (e) {
      _error = 'Subscription check failed: $e';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Called by the API interceptor when any endpoint returns 402
  /// BRANCH_SUBSCRIPTION_EXPIRED.  Updates state immediately without a
  /// separate server round-trip.
  Future<void> markExpiredFromResponse(
      int branchId, Map<String, dynamic> responseBody) async {
    final locked = await _service.onExpiredResponse(branchId, responseBody);
    _status = locked;
    _error = null;
    notifyListeners();
  }

  /// Forces a fresh server check, bypassing the cache.
  /// Called when the user taps "Refresh" on the lock screen.
  Future<void> refresh({required String token, required int branchId}) {
    return checkForBranch(
        token: token, branchId: branchId, forceRefresh: true);
  }

  /// Clears subscription state on logout or branch clear.
  Future<void> clear() async {
    await _service.clearAll();
    _status = null;
    _checking = false;
    _error = null;
    _lastChecked = null;
    notifyListeners();
  }

  /// Clears state for a specific branch (called before switching away).
  Future<void> clearForBranch(int branchId) async {
    await _service.clearCacheForBranch(branchId);
    if (_status?.branchId == branchId) {
      _status = null;
      _lastChecked = null;
      notifyListeners();
    }
  }
}
