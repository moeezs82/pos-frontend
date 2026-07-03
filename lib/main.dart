import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/auth_provider.dart';
import 'providers/branch_provider.dart';
import 'providers/offline_queue_provider.dart';
import 'providers/printer_config_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/connectivity_auto_sync_service.dart';
import 'theme/app_theme.dart';
import 'services/app_navigator.dart';
import 'widgets/app_keyboard_shortcuts.dart';

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
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'Enterprise POS',
        theme: AppTheme.light,
        scrollBehavior: const _AppScrollBehavior(),
        builder: (context, child) => AppKeyboardShortcuts(child: child ?? const SizedBox.shrink()),
        home: Consumer2<AuthProvider, BranchProvider>(
          builder: (ctx, auth, branchProvider, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              if (auth.isAuthenticated) {
                branchProvider.syncFromAuthUser(auth.user);
                // No-op once already loaded for this exact token; does a
                // real, authenticated fetch the first time (or after a
                // different user logs in).
                ctx.read<PrinterConfigProvider>().ensureLoadedFor(auth.token);
                ctx.read<OfflineQueueProvider>().refresh();
                // Auto-trigger a background sync attempt when the device
                // regains connectivity (§2.5) — a UX nicety on top of the
                // manual "Sync Now" button on the sync screen, not a
                // replacement for it, since a device can show "connected"
                // while the backend itself is still down.
                if (auth.token != null) {
                  ConnectivityAutoSyncService.instance.start(
                    token: auth.token!,
                    onSynced: () => ctx.read<OfflineQueueProvider>().refresh(),
                  );
                }
              } else {
                branchProvider.reset();
                ctx.read<PrinterConfigProvider>().stopAutoRefresh();
                ConnectivityAutoSyncService.instance.stop();
              }
            });

            return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
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
