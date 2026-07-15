import 'dart:convert';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/subscription_api_service.dart';
import 'package:enterprise_pos/models/subscription_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages branch subscription state: server verification, 24-hour offline
/// cache, and expiry detection.
///
/// OFFLINE POLICY
/// After a successful server check, the result is cached in SharedPreferences
/// under a branch-specific key.  Subsequent calls within 24 hours use the
/// cache without a network round-trip.  After 24 hours the app requires fresh
/// server verification before any branch-operational actions are permitted.
///
/// Pending offline sales in the local queue are NEVER deleted when a branch
/// expires.  The sync layer surfaces them visibly; the SaaS Owner must
/// reactivate the subscription before the backend will accept them.
///
/// SECURITY
/// This class never stores a bypass key or secret.  All lock/unlock decisions
/// come from the server.  The 24-hour window is a convenience tolerance; it
/// does not allow overriding a server-confirmed locked state.
class SubscriptionService {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  static const Duration _offlineWindow = Duration(hours: 24);
  static const String _prefKeyPrefix = 'subscription_status_branch_';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetches a fresh status from the server and caches it.
  ///
  /// On network failure the cached value (if any, not older than 24h) is
  /// returned instead so a brief outage doesn't immediately lock the UI.
  ///
  /// Returns null only when there is no cached value AND the server is
  /// unreachable — callers should treat null as "assume locked until verified".
  Future<SubscriptionStatus?> checkFromServer({
    required String token,
    required int branchId,
    int? queryBranchId, // master admin querying a different branch
  }) async {
    try {
      final api = SubscriptionApiService(token: token);
      final response = await api.getStatus(branchId: queryBranchId);
      final data = _asMap(response['data']) ?? response;

      final status = SubscriptionStatus.fromJson(data,
          checkedAt: DateTime.now().toUtc());

      // Always cache the result for the resolved branch_id reported by the
      // server (not necessarily what the user passed).
      await _cacheStatus(status);
      return status;
    } on ApiException catch (e) {
      // 402 — the server confirmed the branch is locked.  Build a typed locked
      // status from the response body so the lock screen shows the right message
      // without a separate status call.  Both error codes are handled the same way.
      if (e.statusCode == 402) {
        final body = e.body ?? {};
        final locked = _buildLockedFromBody(branchId, body);
        await _cacheStatus(locked);
        return locked;
      }
      // For other errors (network, 401, etc.) fall back to cache.
      return getCachedStatus(branchId);
    } catch (_) {
      return getCachedStatus(branchId);
    }
  }

  /// Returns the cached status for [branchId] if it exists and is within the
  /// 24-hour offline window, or null if it is missing or stale.
  Future<SubscriptionStatus?> getCachedStatus(int branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKeyPrefix + branchId.toString());
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Restore checkedAt from cache.
      final checkedAt = json['checked_at'] != null
          ? DateTime.tryParse(json['checked_at'].toString())
          : null;
      final status = SubscriptionStatus.fromJson(json,
          checkedAt: checkedAt ?? DateTime.now().toUtc());

      if (status.isStale(maxAge: _offlineWindow)) return null;
      return status;
    } catch (_) {
      return null;
    }
  }

  /// Called when a backend API returns 402 BRANCH_SUBSCRIPTION_EXPIRED or
  /// 402 BRANCH_SUBSCRIPTION_NOT_CONFIGURED mid-session.  Immediately updates
  /// the cache so the lock screen shows consistent information without a
  /// separate status call.
  Future<SubscriptionStatus> onExpiredResponse(
      int branchId, Map<String, dynamic> responseBody) async {
    final locked = _buildLockedFromBody(branchId, responseBody);
    await _cacheStatus(locked);
    return locked;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Builds a locked [SubscriptionStatus] from a 402 response body.
  /// Handles both BRANCH_SUBSCRIPTION_EXPIRED and BRANCH_SUBSCRIPTION_NOT_CONFIGURED.
  SubscriptionStatus _buildLockedFromBody(
      int branchId, Map<String, dynamic> body) {
    final data = _asMap(body['data']) ?? body;
    final code = body['code']?.toString() ?? '';
    final isNotConfigured = code == 'BRANCH_SUBSCRIPTION_NOT_CONFIGURED';

    return SubscriptionStatus.fromJson({
      'branch_id':      data['branch_id'] ?? branchId,
      'status':         isNotConfigured
          ? 'not_configured'
          : (data['status'] ?? 'expired'),
      'is_locked':      true,
      'expires_at':     data['expires_at'],
      'remaining_days': data['remaining_days'] ?? 0,
      'show_alert':     false,
      'message':        body['message'] ??
          (isNotConfigured
              ? 'Subscription not configured for this branch.'
              : 'Subscription has expired.'),
    }, checkedAt: DateTime.now().toUtc());
  }

  /// Clears the cached status for [branchId].  Called when switching branches
  /// or logging out so stale data from a previous session is not shown.
  Future<void> clearCacheForBranch(int branchId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyPrefix + branchId.toString());
  }

  /// Clears all cached subscription statuses (call on logout).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys()
        .where((k) => k.startsWith(_prefKeyPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<void> _cacheStatus(SubscriptionStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyPrefix + status.branchId.toString(),
      jsonEncode(status.toJson()),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }
}
