/// Typed representation of the branch subscription state returned by
/// GET /subscription/status.
///
/// Stored in SharedPreferences as JSON so the last server-verified state
/// survives app restarts.  The [checkedAt] timestamp tells the service
/// whether the cached value is still within the 24-hour offline window.
///
/// FAIL-CLOSED POLICY
/// The client follows the same fail-closed approach as the backend.  When
/// a subscription check cannot be completed (no cache, server unreachable),
/// the provider uses [notConfigured] to lock the branch until the server
/// can be reached.  A 24-hour cache window avoids locking users out during
/// brief connectivity interruptions.
class SubscriptionStatus {
  final int branchId;

  /// Canonical status: trial | active | grace_period | expired | suspended | not_configured
  final String status;

  /// true when the branch should be blocked.
  final bool isLocked;

  /// The subscription expiry timestamp, if one is set.
  final DateTime? expiresAt;

  /// Whole days remaining until expiry.  null when there is no expiry date.
  final int? remainingDays;

  /// Whether the client should show a non-blocking expiry warning.
  final bool showAlert;

  /// Human-readable message from the backend (already translated by the server).
  final String message;

  /// When this status was last verified with the server (device UTC time).
  final DateTime checkedAt;

  const SubscriptionStatus({
    required this.branchId,
    required this.status,
    required this.isLocked,
    this.expiresAt,
    this.remainingDays,
    required this.showAlert,
    required this.message,
    required this.checkedAt,
  });

  /// True when the status represents a branch with no subscription record.
  bool get isNotConfigured => status == 'not_configured';

  /// Creates a locked "not_configured" value used when the server cannot be
  /// reached AND there is no valid cache.  The branch is locked until the
  /// server confirms it has an active subscription.
  ///
  /// This replaces the old [defaultActive] factory which silently granted
  /// access — the system now fails closed when verification is impossible.
  factory SubscriptionStatus.notConfigured(int branchId) {
    return SubscriptionStatus(
      branchId: branchId,
      status: 'not_configured',
      isLocked: true,
      showAlert: false,
      message: 'Could not verify subscription. Please reconnect to continue.',
      checkedAt: DateTime.now().toUtc(),
    );
  }

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json,
      {DateTime? checkedAt}) {
    return SubscriptionStatus(
      branchId: _parseInt(json['branch_id']) ?? 0,
      status: json['status']?.toString() ?? 'active',
      isLocked: _parseBool(json['is_locked']),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      remainingDays: _parseInt(json['remaining_days']),
      showAlert: _parseBool(json['show_alert']),
      message: json['message']?.toString() ?? '',
      checkedAt: checkedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'status': status,
        'is_locked': isLocked,
        'expires_at': expiresAt?.toIso8601String(),
        'remaining_days': remainingDays,
        'show_alert': showAlert,
        'message': message,
        'checked_at': checkedAt.toIso8601String(),
      };

  /// Returns true when the cached value is older than [maxAge].
  bool isStale({Duration maxAge = const Duration(hours: 24)}) {
    return DateTime.now().toUtc().difference(checkedAt) > maxAge;
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = v?.toString().trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'yes';
  }
}
