import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../api/register_shift_service.dart';
import '../../theme/app_theme.dart';

Future<void> showRegisterShiftVarianceDialog({
  required BuildContext context,
  required String token,
  required bool canResolve,
  Future<void> Function()? onChanged,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RegisterShiftVarianceDialog(
      token: token,
      canResolve: canResolve,
      onChanged: onChanged,
    ),
  );
}

class _RegisterShiftVarianceDialog extends StatefulWidget {
  final String token;
  final bool canResolve;
  final Future<void> Function()? onChanged;

  const _RegisterShiftVarianceDialog({
    required this.token,
    required this.canResolve,
    this.onChanged,
  });

  @override
  State<_RegisterShiftVarianceDialog> createState() =>
      _RegisterShiftVarianceDialogState();
}

class _RegisterShiftVarianceDialogState
    extends State<_RegisterShiftVarianceDialog> {
  late final RegisterShiftService _service;
  bool _loading = true;
  String _status = 'pending';
  String _direction = 'all';
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _service = RegisterShiftService(widget.token);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.variances(
        status: _status,
        direction: _direction == 'all' ? null : _direction,
        page: _page,
        perPage: 50,
      );
      final data = page['data'];
      final rows = data is List
          ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        final currentPage = _integer(page['current_page']);
        final lastPage = _integer(page['last_page']);
        final total = _integer(page['total']);
        _page = currentPage < 1 ? 1 : currentPage;
        _lastPage = lastPage < 1 ? 1 : lastPage;
        _total = total < 0 ? 0 : total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
        child: Column(
          children: [
            _header(),
            const Divider(height: 1),
            _filters(),
            const Divider(height: 1),
            Expanded(child: _body()),
            if (!_loading && _error == null && _total > 0) ...[
              const Divider(height: 1),
              _paginationBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.balance_rounded,
              color: AppTheme.warning,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Variance Center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 2),
                Text(
                  'Closing differences stay pending until an authorized resolution is recorded.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'resolved', label: Text('Resolved')),
              ButtonSegment(value: 'all', label: Text('All')),
            ],
            selected: {_status},
            onSelectionChanged: _loading
                ? null
                : (value) {
                    setState(() {
                      _status = value.first;
                      _page = 1;
                    });
                    _load();
                  },
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              value: _direction,
              decoration: const InputDecoration(
                labelText: 'Variance type',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All types')),
                DropdownMenuItem(value: 'shortage', child: Text('Shortages')),
                DropdownMenuItem(value: 'overage', child: Text('Overages')),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _direction = value;
                        _page = 1;
                      });
                      _load();
                    },
            ),
          ),
          const Spacer(),
          if (_status == 'pending')
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: AppTheme.textMuted,
                ),
                SizedBox(width: 6),
                Text(
                  'Pending amounts do not affect profit or loss.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _paginationBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          Text(
            '$_total variance case${_total == 1 ? '' : 's'} • Page $_page of $_lastPage',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Previous page',
            onPressed: _page > 1
                ? () {
                    setState(() => _page -= 1);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: _page < _lastPage
                ? () {
                    setState(() => _page += 1);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.danger,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: 48,
              color: AppTheme.success,
            ),
            SizedBox(height: 10),
            Text(
              'No cash variances in this view.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => _varianceCard(_rows[index]),
    );
  }

  Widget _varianceCard(Map<String, dynamic> row) {
    final shift = row['shift'] is Map
        ? Map<String, dynamic>.from(row['shift'] as Map)
        : const <String, dynamic>{};
    final shortage = row['direction'] == 'shortage';
    final pending = row['status'] == 'pending';
    final tone = shortage ? AppTheme.danger : AppTheme.warning;
    final original = _number(row['original_amount']);
    final outstanding = _number(row['outstanding_amount']);
    final shiftId = _integer(row['register_shift_id']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pending
              ? tone.withValues(alpha: .34)
              : AppTheme.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: tone.withValues(alpha: .1),
            foregroundColor: tone,
            child: Icon(
              shortage
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${shortage ? 'Cash Shortage' : 'Cash Overage'} • Shift #$shiftId',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _statusPill(row['status']?.toString() ?? ''),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${shift['register_name'] ?? 'Register'} • ${shift['cashier_name'] ?? 'Cashier'} • Closed ${shift['closed_at'] ?? ''}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _amountChip('Original', original, tone),
                    _amountChip(
                      'Outstanding',
                      outstanding,
                      pending ? tone : AppTheme.success,
                    ),
                    _smallChip(
                      'Expected ${AppCurrency.format(shift['expected_cash'])}',
                    ),
                    _smallChip(
                      'Counted ${AppCurrency.format(shift['counted_cash'])}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppCurrency.formatSigned(
                  shortage ? -original : original,
                ),
                style: TextStyle(
                  color: tone,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _showDetail(row),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Review'),
              ),
              if (pending && widget.canResolve) ...[
                const SizedBox(height: 7),
                FilledButton.icon(
                  onPressed: () => _resolve(row),
                  icon: const Icon(Icons.rule_rounded, size: 18),
                  label: const Text('Resolve'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final resolved = status == 'resolved';
    final tone = resolved ? AppTheme.success : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        resolved ? 'RESOLVED' : 'PENDING INVESTIGATION',
        style: TextStyle(
          color: tone,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _amountChip(String label, double amount, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label ${AppCurrency.format(amount)}',
        style: TextStyle(color: tone, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _smallChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Future<void> _showDetail(Map<String, dynamic> row) async {
    final id = _integer(row['id']);
    try {
      final detail = await _service.varianceDetail(id);
      if (!mounted) return;
      final shift = detail['shift'] is Map
          ? Map<String, dynamic>.from(detail['shift'] as Map)
          : const <String, dynamic>{};
      final resolutions = (detail['resolutions'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const <Map<String, dynamic>>[];
      final closingNote = shift['closing_note']?.toString().trim() ?? '';
      final approvalNote = shift['approval_note']?.toString().trim() ?? '';
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Variance #$id Audit Trail'),
          content: SizedBox(
            width: 760,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _smallChip(
                            'Expected ${AppCurrency.format(shift['expected_cash'])}',
                          ),
                          _smallChip(
                            'Counted ${AppCurrency.format(shift['counted_cash'])}',
                          ),
                          _smallChip(
                            'Variance ${AppCurrency.formatSigned(_number(shift['variance']))}',
                          ),
                          _smallChip(
                            'Outstanding ${AppCurrency.format(detail['outstanding_amount'])}',
                          ),
                        ],
                      ),
                      if (closingNote.isNotEmpty || approvalNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        if (closingNote.isNotEmpty)
                          _auditNote(
                            'Cashier closing note',
                            closingNote,
                            Icons.sticky_note_2_outlined,
                          ),
                        if (closingNote.isNotEmpty && approvalNote.isNotEmpty)
                          const SizedBox(height: 8),
                        if (approvalNote.isNotEmpty)
                          _auditNote(
                            'Manager approval note',
                            approvalNote,
                            Icons.verified_user_outlined,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Resolution history',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: resolutions.isEmpty
                      ? const Center(
                          child: Text(
                            'No resolution has been recorded yet.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: resolutions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final resolution = resolutions[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(
                                  Icons.receipt_long_rounded,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                '${_resolutionLabel(resolution['resolution_type']?.toString() ?? '')} • ${AppCurrency.format(resolution['amount'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${resolution['note'] ?? ''}\nBy ${resolution['resolved_by_name'] ?? 'User'} • ${resolution['resolved_at'] ?? ''}',
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                'JE #${resolution['journal_entry_id'] ?? ''}',
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Widget _auditNote(String label, String note, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                TextSpan(text: note),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _resolve(Map<String, dynamic> variance) async {
    final direction = variance['direction']?.toString() ?? '';
    final opposite = direction == 'shortage' ? 'overage' : 'shortage';
    List<Map<String, dynamic>> openShifts = const [];
    List<Map<String, dynamic>> oppositeVariances = const [];

    try {
      final results = await Future.wait([
        _service.openShifts(),
        _service.variances(
          status: 'pending',
          direction: opposite,
          perPage: 100,
        ),
      ]);
      openShifts = (results[0] as List<Map<String, dynamic>>);
      final page = results[1] as Map<String, dynamic>;
      oppositeVariances = (page['data'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => _integer(e['id']) != _integer(variance['id']))
              .toList() ??
          const <Map<String, dynamic>>[];
    } catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;

    final input = await showDialog<_VarianceResolutionInput>(
      context: context,
      builder: (_) => _VarianceResolutionDialog(
        variance: variance,
        openShifts: openShifts,
        oppositeVariances: oppositeVariances,
      ),
    );
    if (input == null) return;

    try {
      await _service.resolveVariance(_integer(variance['id']), {
        'client_ref': const Uuid().v4(),
        'resolution_type': input.type,
        'amount': input.amount,
        'note': input.note,
        if (input.targetShiftId != null)
          'target_register_shift_id': input.targetShiftId,
        if (input.counterVarianceId != null)
          'counter_variance_id': input.counterVarianceId,
      });
      if (widget.onChanged != null) await widget.onChanged!();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash variance resolution recorded.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
    );
  }
}

class _VarianceResolutionInput {
  final String type;
  final double amount;
  final String note;
  final int? targetShiftId;
  final int? counterVarianceId;

  const _VarianceResolutionInput({
    required this.type,
    required this.amount,
    required this.note,
    this.targetShiftId,
    this.counterVarianceId,
  });
}

class _VarianceResolutionDialog extends StatefulWidget {
  final Map<String, dynamic> variance;
  final List<Map<String, dynamic>> openShifts;
  final List<Map<String, dynamic>> oppositeVariances;

  const _VarianceResolutionDialog({
    required this.variance,
    required this.openShifts,
    required this.oppositeVariances,
  });

  @override
  State<_VarianceResolutionDialog> createState() =>
      _VarianceResolutionDialogState();
}

class _VarianceResolutionDialogState extends State<_VarianceResolutionDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _type;
  int? _targetShiftId;
  int? _counterVarianceId;
  String? _amountError;
  String? _noteError;
  String? _selectionError;

  bool get _shortage => widget.variance['direction'] == 'shortage';

  @override
  void initState() {
    super.initState();
    _type = _shortage ? 'cash_found' : 'confirmed_overage';
    _amount = TextEditingController(
      text: _number(widget.variance['outstanding_amount']).toStringAsFixed(2),
    );
    _note = TextEditingController();
    if (widget.openShifts.isNotEmpty) {
      _targetShiftId = _integer(widget.openShifts.first['id']);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    final outstanding = _number(widget.variance['outstanding_amount']);
    final note = _note.text.trim();
    String? amountError;
    String? noteError;
    String? selectionError;

    if (amount == null || amount <= 0 || amount - outstanding > .0049) {
      amountError = 'Enter an amount up to ${AppCurrency.format(outstanding)}.';
    }
    if (note.length < 5) {
      noteError = 'Add a clear investigation note (minimum 5 characters).';
    }
    if (_type == 'cash_found' && _targetShiftId == null) {
      selectionError = 'Select the open register receiving the found cash.';
    }
    if (_type == 'offset_opposite_variance' && _counterVarianceId == null) {
      selectionError = 'Select the opposite pending variance to offset.';
    }

    setState(() {
      _amountError = amountError;
      _noteError = noteError;
      _selectionError = selectionError;
    });
    if (amountError != null || noteError != null || selectionError != null) {
      return;
    }

    Navigator.of(context).pop(
      _VarianceResolutionInput(
        type: _type,
        amount: amount!,
        note: note,
        targetShiftId: _type == 'cash_found' ? _targetShiftId : null,
        counterVarianceId:
            _type == 'offset_opposite_variance' ? _counterVarianceId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = _number(widget.variance['outstanding_amount']);
    return AlertDialog(
      title: Text(
        'Resolve ${_shortage ? 'Cash Shortage' : 'Cash Overage'}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Outstanding: ${AppCurrency.format(outstanding)}. '
                  'Only the selected amount will be resolved; the original shift count is never overwritten.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Resolution'),
                items: [
                  if (_shortage)
                    const DropdownMenuItem(
                      value: 'cash_found',
                      child: Text('Cash found / recovered'),
                    ),
                  if (_shortage)
                    const DropdownMenuItem(
                      value: 'confirmed_shortage',
                      child: Text('Confirm as genuine cash shortage'),
                    ),
                  if (!_shortage)
                    const DropdownMenuItem(
                      value: 'confirmed_overage',
                      child: Text('Confirm as genuine cash overage'),
                    ),
                  const DropdownMenuItem(
                    value: 'offset_opposite_variance',
                    child: Text('Offset against an opposite variance'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _type = value;
                    _selectionError = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount to resolve',
                  prefixText: AppCurrency.inputPrefix(),
                  suffixText: AppCurrency.inputSuffix,
                  errorText: _amountError,
                ),
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
              ),
              if (_type == 'cash_found') ...[
                const SizedBox(height: 12),
                if (widget.openShifts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Open a register first. Found cash must be assigned to the drawer that physically receives it.',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    value: _targetShiftId,
                    decoration: const InputDecoration(
                      labelText: 'Register receiving found cash',
                    ),
                    items: widget.openShifts.map((shift) {
                      final register = shift['register'] is Map
                          ? Map<String, dynamic>.from(shift['register'] as Map)
                          : const <String, dynamic>{};
                      final cashier = shift['cashier'] is Map
                          ? Map<String, dynamic>.from(shift['cashier'] as Map)
                          : const <String, dynamic>{};
                      final id = _integer(shift['id']);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '${register['name'] ?? 'Register'} • Shift #$id • ${cashier['name'] ?? 'Cashier'}',
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() {
                      _targetShiftId = value;
                      _selectionError = null;
                    }),
                  ),
              ],
              if (_type == 'offset_opposite_variance') ...[
                const SizedBox(height: 12),
                if (widget.oppositeVariances.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'There is no opposite pending variance available to offset.',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<int>(
                    value: _counterVarianceId,
                    decoration: const InputDecoration(
                      labelText: 'Opposite pending variance',
                    ),
                    items: widget.oppositeVariances.map((row) {
                      final shift = row['shift'] is Map
                          ? Map<String, dynamic>.from(row['shift'] as Map)
                          : const <String, dynamic>{};
                      final id = _integer(row['id']);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          'Variance #$id • Shift #${row['register_shift_id']} • ${AppCurrency.format(row['outstanding_amount'])} • ${shift['closed_at'] ?? ''}',
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() {
                      _counterVarianceId = value;
                      _selectionError = null;
                    }),
                  ),
              ],
              if (_selectionError != null) ...[
                const SizedBox(height: 7),
                Text(
                  _selectionError!,
                  style: const TextStyle(
                    color: AppTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Investigation / resolution note',
                  errorText: _noteError,
                  helperText:
                      'This note becomes part of the permanent variance audit trail.',
                ),
                onChanged: (_) {
                  if (_noteError != null) setState(() => _noteError = null);
                },
              ),
              const SizedBox(height: 4),
              _accountingExplanation(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Record Resolution'),
        ),
      ],
    );
  }

  Widget _accountingExplanation() {
    String message;
    switch (_type) {
      case 'cash_found':
        message =
            'Cash is restored and the pending shortage is reduced. This does not create an expense.';
        break;
      case 'confirmed_shortage':
        message =
            'Only this confirmed amount is moved from pending investigation to Cash Shortage Expense.';
        break;
      case 'confirmed_overage':
        message =
            'Only this confirmed amount is moved from pending investigation to Cash Overage Income.';
        break;
      default:
        message =
            'The selected shortage and overage are cleared against each other without changing cash or profit/loss.';
    }
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.account_balance_outlined,
            size: 18,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _resolutionLabel(String type) {
  switch (type) {
    case 'cash_found':
      return 'Cash found';
    case 'confirmed_shortage':
      return 'Confirmed shortage';
    case 'confirmed_overage':
      return 'Confirmed overage';
    case 'offset_opposite_variance':
      return 'Offset opposite variance';
    default:
      return type;
  }
}

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
