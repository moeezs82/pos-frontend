import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:enterprise_pos/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Result returned by the dialog.
// ---------------------------------------------------------------------------

/// Describes how the user selected the range.
enum BatchRangeMode { rows, invoiceNumbers }

class BatchRangeSelection {
  const BatchRangeSelection({
    required this.mode,
    this.fromRow,
    this.toRow,
    this.fromInvoice,
    this.toInvoice,
  });

  final BatchRangeMode mode;

  // Row-range (1-indexed, inclusive)
  final int? fromRow;
  final int? toRow;

  // Invoice-number range (raw strings, inclusive, compared lexicographically)
  final String? fromInvoice;
  final String? toInvoice;
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

/// Shows a two-tab dialog to select a batch print range.
/// Returns null when the user cancels.
Future<BatchRangeSelection?> showBatchRangeDialog(
  BuildContext context, {
  required int totalRows,
  String confirmLabel = 'Confirm Range',
}) {
  return showDialog<BatchRangeSelection>(
    context: context,
    builder: (_) => _BatchRangeDialog(
      totalRows: totalRows,
      confirmLabel: confirmLabel,
    ),
  );
}

class _BatchRangeDialog extends StatefulWidget {
  const _BatchRangeDialog({
    required this.totalRows,
    this.confirmLabel = 'Confirm Range',
  });
  final int totalRows;
  final String confirmLabel;

  @override
  State<_BatchRangeDialog> createState() => _BatchRangeDialogState();
}

class _BatchRangeDialogState extends State<_BatchRangeDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Row range
  final _fromRowCtrl = TextEditingController(text: '1');
  final _toRowCtrl = TextEditingController();

  // Invoice range
  final _fromInvCtrl = TextEditingController();
  final _toInvCtrl = TextEditingController();

  String? _rowError;
  String? _invError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _toRowCtrl.text = widget.totalRows.toString();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _fromRowCtrl.dispose();
    _toRowCtrl.dispose();
    _fromInvCtrl.dispose();
    _toInvCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_tabs.index == 0) {
      // Row range
      final from = int.tryParse(_fromRowCtrl.text.trim());
      final to = int.tryParse(_toRowCtrl.text.trim());
      if (from == null || to == null || from < 1 || to < from) {
        setState(() =>
            _rowError = 'Enter valid row numbers (from ≤ to, min 1).');
        return;
      }
      if (from > widget.totalRows) {
        setState(() => _rowError =
            '"From" row ($from) exceeds total rows (${widget.totalRows}).');
        return;
      }
      final clampedTo = to.clamp(1, widget.totalRows);
      Navigator.pop(
        context,
        BatchRangeSelection(
          mode: BatchRangeMode.rows,
          fromRow: from,
          toRow: clampedTo,
        ),
      );
    } else {
      // Invoice range
      final from = _fromInvCtrl.text.trim();
      final to = _toInvCtrl.text.trim();
      if (from.isEmpty || to.isEmpty) {
        setState(() => _invError = 'Enter both invoice numbers.');
        return;
      }
      Navigator.pop(
        context,
        BatchRangeSelection(
          mode: BatchRangeMode.invoiceNumbers,
          fromInvoice: from,
          toInvoice: to,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Print Range'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current filter shows ${widget.totalRows} invoice${widget.totalRows == 1 ? '' : 's'}.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              onTap: (_) => setState(() {
                _rowError = null;
                _invError = null;
              }),
              tabs: const [
                Tab(text: 'By Row Range'),
                Tab(text: 'By Invoice Number'),
              ],
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.primary,
              dividerColor: AppTheme.border,
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: _tabs,
              builder: (_, __) => _tabs.index == 0
                  ? _rowRangeTab()
                  : _invoiceRangeTab(),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded, size: 17),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  Widget _rowRangeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fromRowCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'From row',
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _rowError = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _toRowCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'To row',
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _rowError = null),
              ),
            ),
          ],
        ),
        if (_rowError != null) ...[
          const SizedBox(height: 6),
          Text(
            _rowError!,
            style: const TextStyle(
              color: AppTheme.danger,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Rows are numbered 1 → ${widget.totalRows} based on the current sort & filter.',
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _quickSelectRow(),
      ],
    );
  }

  Widget _quickSelectRow() {
    final presets = [
      ('First 10', 1, 10),
      ('First 25', 1, 25),
      ('First 50', 1, 50),
      ('First 100', 1, 100),
      ('All', 1, widget.totalRows),
    ]
        .where((p) => p.$3 <= widget.totalRows)
        .toList();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: presets.map((p) {
        return ActionChip(
          label: Text(p.$1),
          visualDensity: VisualDensity.compact,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          onPressed: () {
            _fromRowCtrl.text = p.$2.toString();
            _toRowCtrl.text = p.$3.clamp(1, widget.totalRows).toString();
            setState(() => _rowError = null);
          },
        );
      }).toList(),
    );
  }

  Widget _invoiceRangeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fromInvCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'From invoice #',
                  hintText: 'e.g. INV-0020',
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _invError = null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _toInvCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'To invoice #',
                  hintText: 'e.g. INV-0040',
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _invError = null),
              ),
            ),
          ],
        ),
        if (_invError != null) ...[
          const SizedBox(height: 6),
          Text(
            _invError!,
            style: const TextStyle(
              color: AppTheme.danger,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'All invoices within this range that match the current filter will be included.',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
