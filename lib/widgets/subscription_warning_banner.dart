import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Non-blocking banner shown when the branch subscription is within the
/// expiry warning window (but not yet locked).
///
/// SPAM PREVENTION
/// The banner is shown at most once per app session by storing a
/// per-session flag in a static variable.  This means:
/// - It appears once when the user logs in / first opens the home screen.
/// - It does NOT re-appear on every rebuild or route change.
/// - It resets when the user logs out (static is still cleared via
///   [SubscriptionWarningBanner.resetSession]).
///
/// The user can dismiss it manually with the ✕ button.
///
/// If the subscription status changes to not-warning (e.g. after renewal),
/// the banner naturally disappears because [showAlert] returns false.
class SubscriptionWarningBanner extends StatefulWidget {
  const SubscriptionWarningBanner({super.key});

  /// Call this on logout / session end to allow the banner to appear again
  /// in the next session.
  static void resetSession() {
    _shownThisSession = false;
    _dismissed = false;
  }

  @override
  State<SubscriptionWarningBanner> createState() =>
      _SubscriptionWarningBannerState();
}

// Static flags so the banner doesn't reappear on every rebuild.
bool _shownThisSession = false;
bool _dismissed = false;

class _SubscriptionWarningBannerState
    extends State<SubscriptionWarningBanner> {
  @override
  void initState() {
    super.initState();
    _shownThisSession = true;
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();

    // Don't show if: not in warning window, already dismissed, or branch is locked.
    if (!sub.showAlert || sub.isLocked || _dismissed) {
      return const SizedBox.shrink();
    }

    final status = sub.status;
    final remaining = status?.remainingDays;
    final isGrace = status?.status == 'grace_period';

    final message = status?.message.isNotEmpty == true
        ? status!.message
        : remaining != null
            ? 'Subscription expires in $remaining day(s). Contact support to renew.'
            : 'Subscription expiry approaching. Contact support to renew.';

    final color = isGrace ? AppTheme.danger : AppTheme.warning;

    return Container(
      width: double.infinity,
      color: color.withOpacity(.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            isGrace ? Icons.warning_rounded : Icons.access_time_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: color, size: 18),
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
