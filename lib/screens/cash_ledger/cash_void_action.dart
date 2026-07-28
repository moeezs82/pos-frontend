import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shared "void & reverse" affordance for cash-movement rows.
///
/// The Cash Ledger feed and the Day Book day-details feed are rendered from the
/// SAME backend row builder (`cashItems()` in reports/daybook.go), so every row
/// in both screens carries the same three fields:
///
///   can_void             already false once the entry is voided, and false for
///                        rows not backed by a cash_ledger_entry
///   cash_ledger_entry_id the id to POST to
///   status               "posted" | "void"
///
/// Keeping the button, the guard and the confirm dialog here means the two
/// screens can't drift apart — which is exactly how the Ledger tab and the day
/// details ended up inconsistent in the first place.
class CashVoid {
  const CashVoid._();

  /// The backend already refuses to void twice; this only decides whether to
  /// SHOW the control.
  ///
  /// `can_void` alone is not enough: POST /cash-ledger/{id}/void requires the
  /// `manage-cashbook` permission, so a view-only user would otherwise be shown
  /// a button that always 403s.
  static bool canVoid(BuildContext context, Map<String, dynamic> row) {
    if (row['can_void'] != true) return false;
    if (entryId(row) == null) return false;
    return context.read<AuthProvider>().hasPermission('manage-cashbook');
  }

  static bool isVoided(Map<String, dynamic> row) =>
      (row['status'] ?? 'posted').toString().toLowerCase() == 'void';

  // ── Party-payment reversal ────────────────────────────────────────────────
  //
  // Customer receipts and vendor payments produce cash movements with NO
  // cash_ledger_entry behind them (they show the "journal" source chip), so
  // `can_void` is false and the cash-ledger void endpoint cannot touch them.
  // They reverse through their own endpoints instead. The backend now ships
  // the descriptor needed to pick the right one.

  /// "customer_receipt" | "vendor_payment" | null
  static String? paymentType(Map<String, dynamic> row) {
    final t = row['payment_type']?.toString();
    return (t == null || t.isEmpty) ? null : t;
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int? paymentId(Map<String, dynamic> row) => _int(row['payment_id']);

  /// customer_id / vendor_id — the owning party, needed to build the URL.
  static int? paymentPartyId(Map<String, dynamic> row) => _int(row['payment_party_id']);

  /// "posted" | "reversed" | "reversal" (null for non-payment rows).
  static String? paymentStatus(Map<String, dynamic> row) {
    final s = row['payment_status']?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static bool isReversedPayment(Map<String, dynamic> row) {
    final s = paymentStatus(row);
    return s == 'reversed' || s == 'reversal';
  }

  /// Reversing a party payment is a different permission from voiding a
  /// cash-ledger entry, and deliberately so: it writes against the customer /
  /// vendor ledger, not the cash book.
  static bool canReverse(BuildContext context, Map<String, dynamic> row) {
    if (row['can_reverse'] != true) return false;
    if (paymentId(row) == null || paymentPartyId(row) == null) return false;
    return context.read<AuthProvider>().hasPermission('reverse-party-payments');
  }

  /// True when the row offers either action, so callers can decide whether to
  /// reserve trailing space.
  static bool hasAction(BuildContext context, Map<String, dynamic> row) =>
      canVoid(context, row) || canReverse(context, row);

  /// The cash_ledger_entry id, or null when the movement is a pure journal row
  /// with no cash-ledger record behind it (those cannot be voided).
  static String? entryId(Map<String, dynamic> row) {
    final raw = row['cash_ledger_entry_id'];
    if (raw == null) return null;
    final s = raw.toString();
    return (s.isEmpty || s == '0') ? null : s;
  }

  /// Reversal requires a reason (backend rule: required, 3–1000 chars).
  /// Returns null when cancelled.
  static Future<String?> askReversalReason(BuildContext context, String label) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse payment?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This posts a reversing entry against $label. '
                'The original payment is kept for audit.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'e.g. entered against the wrong customer',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.length < 3) return 'Give a reason of at least 3 characters';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
  }

  static Future<bool> confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void entry?'),
        content: const Text(
          'This posts a reversing journal entry. The original record is kept for audit.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// Undo icon for a row that can be undone — whether that means voiding a
/// cash-ledger entry or reversing a party payment — or a spinner while the
/// action is in flight. Renders nothing when neither applies, so callers can
/// drop it into a trailing Row unconditionally.
class CashVoidButton extends StatelessWidget {
  const CashVoidButton({
    super.key,
    required this.row,
    required this.busy,
    required this.onVoid,
    this.onReverse,
  });

  final Map<String, dynamic> row;
  final bool busy;

  /// Voids a cash_ledger_entry.
  final VoidCallback onVoid;

  /// Reverses a customer receipt / vendor payment. When omitted the row simply
  /// shows no control for those rows (used by screens that don't wire it).
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Padding(
          padding: EdgeInsets.all(7),
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger),
        ),
      );
    }
    if (CashVoid.canVoid(context, row)) {
      return IconButton(
        tooltip: 'Void & reverse this entry',
        onPressed: onVoid,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.undo_rounded, color: AppTheme.danger, size: 20),
      );
    }
    if (onReverse != null && CashVoid.canReverse(context, row)) {
      final isReceipt = CashVoid.paymentType(row) == 'customer_receipt';
      return IconButton(
        tooltip: isReceipt ? 'Reverse this customer receipt' : 'Reverse this vendor payment',
        onPressed: onReverse,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.undo_rounded, color: AppTheme.danger, size: 20),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Red "Voided" caption for an already-reversed row, mirroring how the party
/// payment ledger labels reversed payments. Renders nothing otherwise.
class CashVoidedBadge extends StatelessWidget {
  const CashVoidedBadge({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final label = CashVoid.isVoided(row)
        ? 'Voided'
        : CashVoid.paymentStatus(row) == 'reversed'
            ? 'Reversed'
            : CashVoid.paymentStatus(row) == 'reversal'
                ? 'Reversal'
                : null;
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.danger),
      ),
    );
  }
}
