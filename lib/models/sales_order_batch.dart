// Models for the Sales Orders batch endpoints (`/sales-orders/batch/*`).

enum BatchAction { submit, approve, reject, cancel, convert }

extension BatchActionX on BatchAction {
  String get path => name;

  /// Server-side cap per request; the client chunks to this size.
  int get cap => this == BatchAction.convert ? 25 : 50;

  String get verb {
    switch (this) {
      case BatchAction.submit:
        return 'Submit';
      case BatchAction.approve:
        return 'Approve';
      case BatchAction.reject:
        return 'Reject';
      case BatchAction.cancel:
        return 'Cancel';
      case BatchAction.convert:
        return 'Convert';
    }
  }
}

/// Server cap for `batch/revalidate`.
const int kBatchRevalidateCap = 200;

/// Splits [items] into chunks of at most [size], preserving order.
List<List<T>> chunkList<T>(List<T> items, int size) {
  assert(size > 0);
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
int _int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// An order id with the version the operator saw, for optimistic locking.
class BatchRef {
  final int id;
  final int? version;
  const BatchRef(this.id, [this.version]);

  Map<String, dynamic> toJson() => {'id': id, if (version != null) 'version': version};
}

/// Compact pre-flight verdict for one order.
class BatchVerdict {
  final int id;
  final String orderNumber;
  final String status;
  final double total;
  final bool canConvert;
  final int blockingCount;
  final int warningCount;
  final String? firstBlocking;
  final bool creditBlocked;
  final bool stale;
  final bool hasOpenShift;

  const BatchVerdict({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.canConvert,
    required this.blockingCount,
    required this.warningCount,
    this.firstBlocking,
    this.creditBlocked = false,
    this.stale = false,
    this.hasOpenShift = false,
  });

  factory BatchVerdict.fromJson(Map<String, dynamic> j) => BatchVerdict(
        id: _int(j['id']),
        orderNumber: j['order_number']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        total: _num(j['total']),
        canConvert: j['can_convert'] == true,
        blockingCount: _int(j['blocking_count']),
        warningCount: _int(j['warning_count']),
        firstBlocking: j['first_blocking']?.toString(),
        creditBlocked: j['credit_blocked'] == true,
        stale: j['stale'] == true,
        hasOpenShift: j['has_open_register_shift'] == true,
      );
}

class BatchSuccess {
  final int id;
  final String orderNumber;
  final String status;
  final int? saleId;
  final String? invoiceNo;
  final String? note;

  const BatchSuccess({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.saleId,
    this.invoiceNo,
    this.note,
  });

  bool get alreadyDone => note == 'already converted';

  factory BatchSuccess.fromJson(Map<String, dynamic> j) => BatchSuccess(
        id: _int(j['id']),
        orderNumber: j['order_number']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        saleId: j['sale_id'] == null ? null : _int(j['sale_id']),
        invoiceNo: j['invoice_no']?.toString(),
        note: j['note']?.toString(),
      );
}

class BatchFailure {
  final int id;
  final String orderNumber;
  final String code;
  final String message;
  final String? field;

  const BatchFailure({
    required this.id,
    required this.orderNumber,
    required this.code,
    required this.message,
    this.field,
  });

  factory BatchFailure.fromJson(Map<String, dynamic> j) => BatchFailure(
        id: _int(j['id']),
        orderNumber: j['order_number']?.toString() ?? '',
        code: j['code']?.toString() ?? 'SERVER_ERROR',
        message: j['message']?.toString() ?? '',
        field: j['field']?.toString(),
      );
}

/// Aggregate across every chunk of one bulk run.
///
/// [unknown] holds ids whose chunk errored at the transport level (network,
/// 5xx): the outcome is not known, so they are neither succeeded nor failed.
/// Re-running the pre-flight is safe — the server's CAS guards make completed
/// orders report as succeeded ("already converted").
class BatchOutcome {
  final List<BatchSuccess> succeeded = [];
  final List<BatchFailure> failed = [];
  final List<int> unknown = [];
  String? unknownReason;

  int get requested => succeeded.length + failed.length + unknown.length;

  Map<String, List<BatchFailure>> failuresByCode() {
    final out = <String, List<BatchFailure>>{};
    for (final f in failed) {
      out.putIfAbsent(f.code, () => []).add(f);
    }
    return out;
  }

  void addResponse(Map<String, dynamic> data) {
    for (final s in (data['succeeded'] as List? ?? const [])) {
      if (s is Map<String, dynamic>) succeeded.add(BatchSuccess.fromJson(s));
    }
    for (final f in (data['failed'] as List? ?? const [])) {
      if (f is Map<String, dynamic>) failed.add(BatchFailure.fromJson(f));
    }
  }
}
