import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:enterprise_pos/services/offline_sync_service.dart';

/// Auto-triggers a background sync attempt when the device regains network
/// connectivity (handover doc §2.5). This is a UX nicety on top of the
/// manual "Sync Now" button on the offline sync screen — NOT a replacement
/// for it, since a device can report "connected" while the backend itself
/// is still down; the actual signal of success is always "did the POST
/// succeed", never just "is Wi-Fi on".
class ConnectivityAutoSyncService {
  ConnectivityAutoSyncService._();
  static final ConnectivityAutoSyncService instance = ConnectivityAutoSyncService._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  String? _activeToken;
  bool _syncing = false;

  void start({required String token, void Function()? onSynced}) {
    if (_sub != null && _activeToken == token) return; // already running for this session
    stop();
    _activeToken = token;

    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnection || _syncing) return;

      _syncing = true;
      try {
        await OfflineSyncService(token: token).syncAll();
        onSynced?.call();
      } catch (_) {
        // Best-effort background sync — errors are already recorded per-item
        // in the local queue by OfflineSyncService; the sync screen's
        // manual "Sync Now" / per-row retry remains the source of truth for
        // the cashier to act on.
      } finally {
        _syncing = false;
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _activeToken = null;
  }
}
