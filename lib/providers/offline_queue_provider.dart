import 'package:flutter/foundation.dart';

import 'package:enterprise_pos/services/offline_sales_queue_service.dart';

/// Drives the "N sales pending sync" badge for the active business only.
class OfflineQueueProvider extends ChangeNotifier {
  int pendingCount = 0;
  int? _activeBranchId;
  int _contextVersion = 0;

  int? get activeBranchId => _activeBranchId;

  Future<void> setBranch(int? branchId) async {
    final normalized = branchId != null && branchId > 0 ? branchId : null;
    final changed = normalized != _activeBranchId;
    _activeBranchId = normalized;
    _contextVersion++;

    // Never leave the previous business's count visible while the new
    // tenant-filtered query is loading.
    if (changed) {
      pendingCount = 0;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    final branchId = _activeBranchId;
    final version = _contextVersion;
    if (branchId == null) {
      if (pendingCount != 0) {
        pendingCount = 0;
        notifyListeners();
      }
      return;
    }
    final next = await OfflineSalesQueueService.instance
        .pendingCount(branchId: branchId);
    if (version != _contextVersion || branchId != _activeBranchId) return;
    if (pendingCount == next) return;
    pendingCount = next;
    notifyListeners();
  }

  void clear() {
    _activeBranchId = null;
    _contextVersion++;
    if (pendingCount == 0) return;
    pendingCount = 0;
    notifyListeners();
  }
}
