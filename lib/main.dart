import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'api/core/api_client.dart';
import 'providers/auth_provider.dart';
import 'providers/branch_provider.dart';
import 'providers/offline_queue_provider.dart';
import 'providers/register_shift_provider.dart';
import 'providers/printer_config_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/payment_method_provider.dart';
import 'providers/branch_feature_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/connectivity_auto_sync_service.dart';
import 'theme/app_theme.dart';
import 'services/app_navigator.dart';
import 'widgets/app_keyboard_shortcuts.dart';
import 'widgets/subscription_warning_banner.dart';

void main() {
  // The offline sales queue (handover doc §2.1) is driven through
  // sqflite_common_ffi rather than the plain sqflite plugin, because that
  // plugin has no Windows/Linux implementation — only Android/iOS platform
  // channels. Without this, openDatabase() on Windows either throws
  // MissingPluginException or never completes, which is what made the sync
  // screen spin forever. This must run before anything touches the queue.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => BranchProvider()),
        ChangeNotifierProvider(create: (_) => PrinterConfigProvider()..loadFromCache()),
        ChangeNotifierProvider(create: (_) => OfflineQueueProvider()),
        ChangeNotifierProvider(create: (_) => RegisterShiftProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => PaymentMethodProvider()),
        ChangeNotifierProvider(create: (_) => BranchFeatureProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        navigatorObservers: [posNavObserver],
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'Enterprise POS',
        theme: AppTheme.light,
        scrollBehavior: const _AppScrollBehavior(),
        // _AuthOrchestrator lives in MaterialApp.builder, which wraps the
        // entire app ABOVE the Navigator.  It is never unmounted by route
        // pushes or replacements, so it reacts to every auth state change
        // (login, logout, re-login) regardless of which screen is active.
        //
        // The previous Consumer2 addPostFrameCallback approach broke because
        // LoginScreen calls Navigator.pushReplacement(HomeScreen), which
        // removes Consumer2's route from the stack.  From that point on,
        // Consumer2 was never rebuilt, so initialize/clear/start were never
        // called again — leaving RegisterShiftProvider._token and
        // ConnectivityAutoSyncService stuck on the first user's revoked
        // token for every subsequent session.
        builder: (context, child) => _AuthOrchestrator(
          child: AppKeyboardShortcuts(child: child ?? const SizedBox.shrink()),
        ),
        home: Consumer<AuthProvider>(
          builder: (_, auth, __) =>
              auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),
        ),
      ),
    );
  }
}

/// Permanent auth-state orchestrator.
///
/// Placed in [MaterialApp.builder] so it lives above the Navigator and is
/// never unmounted by route changes.  It registers a direct listener on
/// [AuthProvider] (not a Consumer rebuild) and synchronises all
/// token-dependent services whenever the auth state changes:
///
/// • [RegisterShiftProvider.initialize] / [RegisterShiftProvider.clear]
/// • [ConnectivityAutoSyncService.start] / [ConnectivityAutoSyncService.stop]
/// • [BranchProvider.syncFromAuthUser] / [BranchProvider.reset]
/// • [PrinterConfigProvider.ensureLoadedFor] / [PrinterConfigProvider.stopAutoRefresh]
/// • [OfflineQueueProvider.refresh]
///
/// The idempotent guards inside each of those services ensure that repeated
/// calls with the same token (e.g. from a BranchProvider change triggering
/// an auth rebuild) are cheap no-ops.
class _AuthOrchestrator extends StatefulWidget {
  final Widget child;
  const _AuthOrchestrator({required this.child});

  @override
  State<_AuthOrchestrator> createState() => _AuthOrchestratorState();
}

class _AuthOrchestratorState extends State<_AuthOrchestrator> {
  late final AuthProvider _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _auth.addListener(_onAuthChanged);

    // Wire up the global 402 interceptor so that any API call that receives
    // BRANCH_SUBSCRIPTION_EXPIRED immediately marks the branch as locked in
    // SubscriptionProvider — without every screen needing its own catch clause.
    ApiClient.onSubscriptionExpired = (body) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final branchId = auth.activeBranchId;
      if (branchId == null) return;
      context.read<SubscriptionProvider>().markExpiredFromResponse(branchId, body);
    };

    // Handle the startup case where tryAutoLogin() completes before or right
    // after the first frame — the listener covers the "after" path; the
    // postFrameCallback covers the "already done by first build" path.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onAuthChanged();
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    ApiClient.onSubscriptionExpired = null;
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();

    if (auth.isAuthenticated) {
      final token = auth.token!;
      final userId = (auth.user?['id'] ?? '').toString();
      final branchId = auth.activeBranchId;

      context.read<BranchProvider>().syncFromAuthUser(auth.user);
      context.read<PrinterConfigProvider>().ensureLoadedFor(token);
      context.read<OfflineQueueProvider>().refresh();

      // initialize() is guarded by _initializedToken == token, so repeated
      // calls for the same session (e.g. from a branch switch notifying
      // listeners) are instant no-ops.
      context
          .read<RegisterShiftProvider>()
          .initialize(token, userId: userId);

      // Load the branch's active payment methods (also cached for offline
      // sale creation). Guarded by token+branch so branch-switch notifications
      // are cheap no-ops.
      context
          .read<PaymentMethodProvider>()
          .initialize(token, branchId: branchId);

      ConnectivityAutoSyncService.instance.start(
        token: token,
        onSynced: () {
          if (mounted) context.read<OfflineQueueProvider>().refresh();
        },
      );

      // Check subscription for the active branch on every auth change (login,
      // branch switch, session restore).  The provider's internal rate-limiter
      // turns this into a no-op if checked recently.
      if (branchId != null) {
        context.read<SubscriptionProvider>().checkForBranch(
          token: token,
          branchId: branchId,
        );

        // Load branch feature flags (delivery_enabled, sale_vendor_enabled).
        // Non-blocking; failures fall back to the cached value or defaults.
        context.read<BranchFeatureProvider>().load(branchId, token);
      }
    } else {
      context.read<BranchProvider>().reset();
      context.read<BranchFeatureProvider>().reset();
      context.read<PrinterConfigProvider>().stopAutoRefresh();
      ConnectivityAutoSyncService.instance.stop();
      // clear() is also guarded — repeated calls when already cleared are no-ops.
      context.read<RegisterShiftProvider>().clear();
      context.read<SubscriptionProvider>().clear();
      context.read<PaymentMethodProvider>().clear();
      SubscriptionWarningBanner.resetSession();
      // Forget tracked routes so shortcuts never return to a previous session's
      // screen after re-login. Navigator callbacks keep the registry accurate
      // once the fresh session starts pushing routes.
      posNavObserver.reset();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
