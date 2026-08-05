import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/api/register_shift_service.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

Future<void> showRegisterShiftManagementDialog({
  required BuildContext context,
  required String token,
  required Future<void> Function() onChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RegisterShiftManagementDialog(
      token: token,
      onChanged: onChanged,
    ),
  );
}

class _RegisterShiftManagementDialog extends StatefulWidget {
  final String token;
  final Future<void> Function() onChanged;

  const _RegisterShiftManagementDialog({
    required this.token,
    required this.onChanged,
  });

  @override
  State<_RegisterShiftManagementDialog> createState() =>
      _RegisterShiftManagementDialogState();
}

class _RegisterShiftManagementDialogState
    extends State<_RegisterShiftManagementDialog> {
  late final RegisterShiftService _service;
  List<Map<String, dynamic>> _shifts = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busyShiftIds = <int>{};

  @override
  void initState() {
    super.initState();
    _service = RegisterShiftService(widget.token);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.openShifts();
      if (!mounted) return;
      setState(() => _shifts = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 10),
      contentPadding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppTheme.primarySoft,
            foregroundColor: AppTheme.primary,
            child: Icon(Icons.admin_panel_settings_rounded),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open Shift Management'),
                SizedBox(height: 2),
                Text(
                  'Review cashier close requests, request a recount, or force-close an abandoned shift.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12.5,
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
        ],
      ),
      content: SizedBox(
        width: 1120,
        height: 650,
        child: _buildBody(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppTheme.danger,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
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
    if (_shifts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 54,
              color: AppTheme.success,
            ),
            SizedBox(height: 12),
            Text(
              'No open register shifts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              'Every register in this business is currently closed.',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    final pending = _shifts.where(_hasPendingRequest).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _summaryChip(
              Icons.lock_open_rounded,
              '${_shifts.length} open shift${_shifts.length == 1 ? '' : 's'}',
              AppTheme.info,
            ),
            _summaryChip(
              Icons.pending_actions_rounded,
              '$pending approval request${pending == 1 ? '' : 's'}',
              pending > 0 ? AppTheme.warning : AppTheme.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            itemCount: _shifts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) => _shiftCard(_shifts[index]),
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _shiftCard(Map<String, dynamic> shift) {
    final register = _map(shift['register']);
    final cashier = _map(shift['cashier']);
    final summary = _map(shift['summary']);
    final request = _mapOrNull(shift['close_request']);
    final isPending = request?['status'] == 'pending';
    final variance = _number(request?['variance'] ?? shift['variance']);
    final pendingSync = _integer(
      request?['pending_sync_count'] ?? shift['pending_sync_count'],
    );
    final shiftId = _integer(shift['id']);
    final busy = _busyShiftIds.contains(shiftId);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppTheme.warning.withValues(alpha: .45)
              : AppTheme.border,
          width: isPending ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: isPending
                    ? AppTheme.warning.withValues(alpha: .11)
                    : AppTheme.primarySoft,
                foregroundColor:
                    isPending ? AppTheme.warning : AppTheme.primary,
                child: Icon(
                  isPending
                      ? Icons.pending_actions_rounded
                      : Icons.point_of_sale_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${register['name'] ?? 'Register'} • Shift #$shiftId',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Cashier: ${cashier['name'] ?? 'Unknown'}  •  Opened ${shift['opened_at'] ?? ''}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPending
                      ? AppTheme.warning.withValues(alpha: .10)
                      : AppTheme.success.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPending ? 'APPROVAL REQUIRED' : 'OPEN',
                  style: TextStyle(
                    color: isPending ? AppTheme.warning : AppTheme.success,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(
                'Expected',
                AppCurrency.format(summary['expected_cash'] ?? shift['expected_cash']),
                Icons.account_balance_wallet_outlined,
              ),
              _metric(
                'Counted',
                request == null
                    ? 'Not submitted'
                    : AppCurrency.format(request['counted_cash']),
                Icons.fact_check_outlined,
              ),
              _metric(
                'Variance',
                request == null
                    ? '—'
                    : AppCurrency.formatSigned(variance),
                variance == 0
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                color: variance == 0
                    ? AppTheme.success
                    : (variance < 0 ? AppTheme.danger : AppTheme.warning),
              ),
              _metric(
                'Pending offline',
                '$pendingSync',
                Icons.cloud_sync_outlined,
                color: pendingSync > 0 ? AppTheme.warning : null,
              ),
            ],
          ),
          if (request != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notes_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (request['closing_note']?.toString().trim().isNotEmpty ??
                              false)
                          ? request['closing_note'].toString()
                          : 'Cashier did not add a closing note.',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _showDetails(shiftId),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Review Activity'),
                ),
                if (isPending)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _reject(shiftId, _integer(request?['id'])),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Reject for Recount'),
                  ),
                if (isPending)
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _approve(
                              shiftId,
                              _integer(request?['id']),
                              pendingSync,
                            ),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Approve & Close'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : () => _forceClose(
                            shiftId,
                            pendingSync,
                            initialCount: request?['counted_cash'],
                          ),
                  icon: const Icon(Icons.lock_clock_rounded),
                  label: const Text('Force Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final tone = color ?? AppTheme.navy;
    return Container(
      constraints: const BoxConstraints(minWidth: 175),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: TextStyle(color: tone, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approve(int shiftId, int requestId, int pendingSync) async {
    final input = await showDialog<_ManagerDecisionInput>(
      context: context,
      builder: (_) => _ManagerDecisionDialog(
        title: 'Approve & Close Shift',
        message:
            'The cashier count and resulting variance will be finalized. A cash shortage or overage journal will be posted automatically.',
        confirmLabel: 'Approve & Close',
        pendingSyncCount: pendingSync,
      ),
    );
    if (input == null) return;
    await _runAction(shiftId, () async {
      await _service.approveCloseRequest(
        shiftId: shiftId,
        requestId: requestId,
        decisionNote: input.note,
        acceptPendingSync: input.acceptPendingSync,
      );
    }, success: 'Shift approved and closed.');
  }

  Future<void> _reject(int shiftId, int requestId) async {
    final input = await showDialog<_ManagerDecisionInput>(
      context: context,
      builder: (_) => const _ManagerDecisionDialog(
        title: 'Reject for Recount',
        message:
            'The shift will remain open. The cashier must count the drawer again and submit a new close request.',
        confirmLabel: 'Reject Request',
        destructive: true,
      ),
    );
    if (input == null) return;
    await _runAction(shiftId, () async {
      await _service.rejectCloseRequest(
        shiftId: shiftId,
        requestId: requestId,
        decisionNote: input.note,
      );
    }, success: 'Close request rejected for recount.');
  }

  Future<void> _forceClose(
    int shiftId,
    int pendingSync, {
    dynamic initialCount,
  }) async {
    final input = await showDialog<_ForceCloseInput>(
      context: context,
      builder: (_) => _ForceCloseDialog(
        pendingSyncCount: pendingSync,
        initialCount: initialCount,
      ),
    );
    if (input == null) return;
    await _runAction(shiftId, () async {
      await _service.forceClose(shiftId, {
        'client_ref': const Uuid().v4(),
        'counted_cash': input.countedCash,
        'approval_note': input.reason,
        'pending_sync_count': pendingSync,
        'accept_pending_sync': input.acceptPendingSync,
      });
    }, success: 'Shift force-closed.');
  }

  Future<void> _runAction(
    int shiftId,
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_busyShiftIds.contains(shiftId)) return;
    setState(() => _busyShiftIds.add(shiftId));
    try {
      await action();
      await widget.onChanged();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(error)),
          backgroundColor: AppTheme.danger,
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busyShiftIds.remove(shiftId));
    }
  }

  Future<void> _showDetails(int shiftId) async {
    try {
      final data = await _service.detail(shiftId);
      if (!mounted) return;
      final shift = _map(data['shift']);
      final summary = _map(data['summary']);
      final activity = _map(data['activity']);
      final items = (activity['items'] as List?)
              ?.map((item) => Map<String, dynamic>.from(item as Map))
              .toList() ??
          const <Map<String, dynamic>>[];
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Shift #$shiftId Activity'),
          content: SizedBox(
            width: 860,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'Expected ${AppCurrency.format(summary['expected_cash'] ?? shift['expected_cash'])}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Counted ${shift['counted_cash'] == null ? 'Not submitted' : AppCurrency.format(shift['counted_cash'])}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Variance ${AppCurrency.formatSigned(shift['variance'])}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text('No drawer activity recorded.'),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final item = items[index];
                            final direction = item['direction']?.toString();
                            final isOut = direction == 'out';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (isOut
                                        ? AppTheme.danger
                                        : AppTheme.success)
                                    .withValues(alpha: .09),
                                foregroundColor:
                                    isOut ? AppTheme.danger : AppTheme.success,
                                child: Icon(
                                  isOut
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                ),
                              ),
                              title: Text(item['label']?.toString() ?? 'Activity'),
                              subtitle: Text(
                                '${item['occurred_at'] ?? ''}${item['reference'] == null ? '' : ' • ${item['reference']}'}',
                              ),
                              trailing: Text(
                                AppCurrency.formatSigned(
                                  isOut
                                      ? -_number(item['amount'])
                                      : _number(item['amount']),
                                ),
                                style: TextStyle(
                                  color:
                                      isOut ? AppTheme.danger : AppTheme.success,
                                  fontWeight: FontWeight.w900,
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(error)),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
}

class _ManagerDecisionInput {
  final String note;
  final bool acceptPendingSync;

  const _ManagerDecisionInput({
    required this.note,
    required this.acceptPendingSync,
  });
}

class _ManagerDecisionDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final int pendingSyncCount;
  final bool destructive;

  const _ManagerDecisionDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.pendingSyncCount = 0,
    this.destructive = false,
  });

  @override
  State<_ManagerDecisionDialog> createState() =>
      _ManagerDecisionDialogState();
}

class _ManagerDecisionDialogState extends State<_ManagerDecisionDialog> {
  late final TextEditingController _note;
  bool _acceptPending = false;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closing) return;
    final note = _note.text.trim();
    if (note.length < 5) {
      setState(() => _error = 'Enter a clear reason of at least 5 characters.');
      return;
    }
    if (widget.pendingSyncCount > 0 && !_acceptPending) {
      setState(() => _error = 'Confirm how pending offline sales should be handled.');
      return;
    }
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _ManagerDecisionInput(
        note: note,
        acceptPendingSync: _acceptPending,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.message,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Manager decision note',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (widget.pendingSyncCount > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptPending,
                onChanged: (value) =>
                    setState(() => _acceptPending = value ?? false),
                title: Text(
                  'Accept ${widget.pendingSyncCount} pending offline sale(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Their original sale time must fall inside this shift when they synchronize.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed: _closing ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ForceCloseInput {
  final double countedCash;
  final String reason;
  final bool acceptPendingSync;

  const _ForceCloseInput({
    required this.countedCash,
    required this.reason,
    required this.acceptPendingSync,
  });
}

class _ForceCloseDialog extends StatefulWidget {
  final int pendingSyncCount;
  final dynamic initialCount;

  const _ForceCloseDialog({
    required this.pendingSyncCount,
    this.initialCount,
  });

  @override
  State<_ForceCloseDialog> createState() => _ForceCloseDialogState();
}

class _ForceCloseDialogState extends State<_ForceCloseDialog> {
  late final TextEditingController _counted;
  late final TextEditingController _reason;
  bool _acceptPending = false;
  String? _countError;
  String? _reasonError;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final count = widget.initialCount == null
        ? ''
        : _number(widget.initialCount).toStringAsFixed(2);
    _counted = TextEditingController(text: count);
    _reason = TextEditingController();
  }

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closing) return;
    final counted = double.tryParse(_counted.text.trim());
    final reason = _reason.text.trim();
    setState(() {
      _countError = counted == null || counted < 0
          ? 'Enter a valid counted cash amount.'
          : null;
      _reasonError = reason.length < 5
          ? 'Enter a clear reason of at least 5 characters.'
          : null;
    });
    if (_countError != null || _reasonError != null) return;
    if (widget.pendingSyncCount > 0 && !_acceptPending) {
      setState(() {
        _reasonError = 'Accept pending offline sales or synchronize them first.';
      });
      return;
    }
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _ForceCloseInput(
        countedCash: counted!,
        reason: reason,
        acceptPendingSync: _acceptPending,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Force Close Register Shift'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: .20),
                ),
              ),
              child: const Text(
                'Use this only when the cashier is unavailable, the device failed, or a normal close request cannot be completed. The physical variance will be posted to accounting.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _counted,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Final counted cash',
                prefixText: AppCurrency.inputPrefix(),
                suffixText: AppCurrency.inputSuffix,
                errorText: _countError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Force-close reason',
                errorText: _reasonError,
              ),
            ),
            if (widget.pendingSyncCount > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptPending,
                onChanged: (value) =>
                    setState(() => _acceptPending = value ?? false),
                title: Text(
                  'Accept ${widget.pendingSyncCount} pending offline sale(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: _closing ? null : _submit,
          icon: const Icon(Icons.lock_clock_rounded),
          label: const Text('Force Close'),
        ),
      ],
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Map<String, dynamic>? _mapOrNull(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

bool _hasPendingRequest(Map<String, dynamic> shift) =>
    _mapOrNull(shift['close_request'])?['status'] == 'pending';

int _integer(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0;
}

String _errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}
