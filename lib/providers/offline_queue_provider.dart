import 'package:flutter/foundation.dart';

import 'package:enterprise_pos/services/offline_sales_queue_service.dart';

/// Drives the "N sales pending sync" badge (handover doc §2.4). Call
/// [refresh] after enqueueing a sale offline or after any sync attempt so
/// the badge stays in sync with the local queue.
class OfflineQueueProvider extends ChangeNotifier {
  int pendingCount = 0;

  Future<void> refresh() async {
    pendingCount = await OfflineSalesQueueService.instance.pendingCount();
    notifyListeners();
  }
}
