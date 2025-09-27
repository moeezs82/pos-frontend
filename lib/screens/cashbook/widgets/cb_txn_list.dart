import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class CBTxnList extends StatelessWidget {
  final List<Map<String, dynamic>> txns;
  const CBTxnList({super.key, required this.txns});

  @override
  Widget build(BuildContext context) {
    if (txns.isEmpty) {
      return const Center(child: Text("No transactions found"));
    }

    final theme = Theme.of(context);
    final divider = theme.dividerColor.withOpacity(0.35);
    final amountStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final balanceStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurface.withOpacity(0.7),
    );
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.6),
    );
    final titleStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withOpacity(0.85),
    );

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: txns.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: divider),
      itemBuilder: (_, i) {
        final t = txns[i];

        final type = (t['type'] ?? '').toString(); // receipt/payment/expense/transfer_in/transfer_out
        final date = (t['date'] ?? '').toString();
        final method = (t['method'] ?? '').toString();
        final source = (t['source'] ?? '').toString();
        final reference = (t['reference'] ?? '').toString();
        final note = (t['note'] ?? '').toString();

        final amount = _toDouble(t['amount']);
        final running = _toDouble(t['running_balance']);

        final isIn = (type == 'receipt' || type == 'transfer_in');
        final isExpense = type == 'expense';
        final sign = isIn ? '+' : '-';
        final iconData = isIn
            ? Icons.call_received_rounded
            : (isExpense ? Icons.receipt_long_rounded : Icons.call_made_rounded);
        final iconColor = isIn
            ? Colors.green.shade700
            : (isExpense ? Colors.orange.shade700 : Colors.red.shade700);
        final amtColor = iconColor;

        // zebra bg
        final rowBg = i.isEven
            ? theme.colorScheme.surface
            : theme.colorScheme.surface.withOpacity(0.96);

        return Container(
          color: rowBg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading icon box
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),

              // Middle: title + meta + optional note (ellipsized)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: date • TYPE
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _TypeChip(type: type),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Meta line: Ref • Method • Source
                    _MetaLine(
                      reference: reference,
                      method: method,
                      source: source,
                      style: metaStyle,
                    ),

                    // Optional note (one line)
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Right: amount + running balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${amount.toStringAsFixed(2)}',
                    style: amountStyle?.copyWith(color: amtColor),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Running', style: metaStyle),
                      const SizedBox(width: 6),
                      Text(running.toStringAsFixed(2), style: balanceStyle),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String reference;
  final String method;
  final String source;
  final TextStyle? style;

  const _MetaLine({
    required this.reference,
    required this.method,
    required this.source,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (reference.isNotEmpty) parts.add('Ref: $reference');
    if (method.isNotEmpty) parts.add('Method: $method');
    if (source.isNotEmpty) parts.add('Source: $source');

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final t = type.toUpperCase();
    Color c;
    if (t == 'RECEIPT' || t == 'TRANSFER_IN') {
      c = Colors.green.shade700;
    } else if (t == 'EXPENSE') {
      c = Colors.orange.shade700;
    } else {
      c = Colors.red.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.30)),
      ),
      child: Text(
        t,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// -------- helpers --------
double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '')) ?? 0.0;
  return 0.0;
}
