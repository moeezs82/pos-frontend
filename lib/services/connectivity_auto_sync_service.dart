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
  int? _activeBranchId;
  int _generation = 0;
  bool _syncing = false;

  void start({
    required String token,
    required int branchId,
    void Function()? onSynced,
  }) {
    if (branchId <= 0) {
      stop();
      return;
    }
    if (_sub != null &&
        _activeToken == token &&
        _activeBranchId == branchId) {
      return; // already running for this authenticated business context
    }
    stop();
    _activeToken = token;
    _activeBranchId = branchId;
    final generation = _generation;

    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      if (generation != _generation) return;
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnection || _syncing) return;

      _syncing = true;
      try {
        await OfflineSyncService(token: token, branchId: branchId).syncAll();
        if (generation == _generation) onSynced?.call();
      } catch (_) {
        // Best-effort background sync — errors are already recorded per-item
        // in the local queue by OfflineSyncService; the sync screen's
        // manual "Sync Now" / per-row retry remains the source of truth for
        // the cashier to act on.
      } finally {
        // An older branch listener must not clear the busy flag of a newer
        // branch sync that started after stop()/start().
        if (generation == _generation) _syncing = false;
      }
    });
  }

  void stop() {
    _generation++;
    _sub?.cancel();
    _sub = null;
    _activeToken = null;
    _activeBranchId = null;
    _syncing = false;
  }
}
