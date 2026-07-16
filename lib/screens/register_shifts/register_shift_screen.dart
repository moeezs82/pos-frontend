import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/register_shift_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/offline_queue_provider.dart';
import '../../providers/register_shift_provider.dart';
import '../../theme/app_theme.dart';

class RegisterShiftScreen extends StatefulWidget {
  const RegisterShiftScreen({super.key});
  @override State<RegisterShiftScreen> createState() => _RegisterShiftScreenState();
}

class _RegisterShiftScreenState extends State<RegisterShiftScreen> {
  List<Map<String, dynamic>> _registers = const [];
  List<Map<String, dynamic>> _availableRegisters(RegisterShiftProvider state) {
    final occupiedIds = state.occupiedShifts
        .map((shift) => int.tryParse(shift['register_id']?.toString() ?? ''))
        .whereType<int>()
        .toSet();
    return _registers.where((register) {
      final id = int.tryParse(register['id']?.toString() ?? '');
      return id != null && !occupiedIds.contains(id);
    }).toList();
  }
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  Future<void> _load() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try { final rows = await RegisterShiftService(token).registers(); if (mounted) setState(() => _registers = rows); } catch (_) {}
    if (mounted) await context.read<RegisterShiftProvider>().refresh();
  }

  @override Widget build(BuildContext context) {
    final state = context.watch<RegisterShiftProvider>();
    final auth = context.watch<AuthProvider>();
    final role = auth.roleLabel.toLowerCase();
    final canManageRegisters = auth.hasPermission('manage-register-shifts') || role.contains('admin') || role.contains('manager');
    final availableRegisters = _availableRegisters(state);
    return Scaffold(
      appBar: AppBar(title: const Text('Register Shift'), actions: [
        if (canManageRegisters)
          IconButton(tooltip: 'Manage registers', onPressed: _manageRegisters, icon: const Icon(Icons.settings_rounded)),
        IconButton(tooltip: 'Shift history', onPressed: _showHistory, icon: const Icon(Icons.history_rounded)),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: state.loading && state.shift == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              if (!state.hasActiveShift && state.hasOccupiedRegisters && availableRegisters.isEmpty)
                _occupiedCard(state)
              else if (!state.hasActiveShift)
                _openCard(state, availableRegisters)
              else ...[
                _activeHeader(state),
                const SizedBox(height: 16),
                _summaryGrid(state),
                const SizedBox(height: 16),
                _methodTotals(state),
                _actions(state),
                const SizedBox(height: 16),
                _movementList(state.shift?['movements']),
              ],
              if (state.error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Last server check: ${state.error}', style: const TextStyle(color: AppTheme.warning))),
            ]),
    );
  }

  Widget _openCard(RegisterShiftProvider state, List<Map<String, dynamic>> availableRegisters) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 620),
    child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
      const Icon(Icons.point_of_sale_rounded, size: 52, color: AppTheme.primary), const SizedBox(height: 12),
      const Text('Open your register', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6), const Text('An open shift is required before counter sales.', style: TextStyle(color: AppTheme.textMuted)),
      if (state.hasOccupiedRegisters) ...[
        const SizedBox(height: 10),
        Text('${state.occupiedShifts.length} other register(s) currently in use. ${availableRegisters.length} available.', style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 20), FilledButton.icon(onPressed: availableRegisters.isEmpty ? null : () => _openDialog(availableRegisters), icon: const Icon(Icons.lock_open_rounded), label: Text(availableRegisters.isEmpty ? 'No register available' : 'Open Shift')),
    ]))),
  ));

  Widget _occupiedCard(RegisterShiftProvider state) {
    final occupied = state.occupiedShifts.first;
    final register = occupied['register'] is Map ? occupied['register'] as Map : const {};
    final cashier = occupied['cashier'] is Map ? occupied['cashier'] as Map : const {};
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock_clock_rounded, size: 52, color: AppTheme.warning),
                const SizedBox(height: 12),
                const Text('Register already in use', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '${register['name'] ?? 'Register'} has active Shift #${occupied['id']} opened by ${cashier['name'] ?? 'another cashier'}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeHeader(RegisterShiftProvider state) {
    final shift = state.shift!; final register = shift['register'] is Map ? shift['register'] as Map : const {};
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.primary.withValues(alpha: .25))), child: Row(children: [
      const CircleAvatar(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, child: Icon(Icons.point_of_sale_rounded)), const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(register['name']?.toString() ?? 'Register', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), Text('Shift #${shift['id']} • Opened ${shift['opened_at'] ?? ''}', style: const TextStyle(color: AppTheme.textMuted))])),
      const Chip(avatar: Icon(Icons.circle, size: 10, color: AppTheme.success), label: Text('ACTIVE')),
    ]));
  }

  Widget _summaryGrid(RegisterShiftProvider state) {
    final s = state.summary;
    final values = <(String, dynamic, IconData)>[
      ('Expected cash', s['expected_cash'], Icons.account_balance_wallet_rounded),
      ('Cash sales', s['cash_sales'], Icons.payments_rounded),
      ('Card / KNET', s['card_sales'], Icons.credit_card_rounded),
      ('Gross sales', s['gross_sales'], Icons.receipt_long_rounded),
      ('Cash refunds', s['cash_refunds'], Icons.keyboard_return_rounded),
      ('Transactions', s['transaction_count'], Icons.numbers_rounded),
    ];

    return LayoutBuilder(
      builder: (_, constraints) {
        final width = (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: values.map((value) {
            return SizedBox(
              width: width.clamp(220.0, 420.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(value.$3, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.$1,
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          Text(
                            value.$2?.toString() ?? '0.00',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _methodTotals(RegisterShiftProvider state) {
    final raw = state.summary['method_totals'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    String money(dynamic v) => (v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0)
        .toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment methods',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              const Text('Only drawer methods affect expected cash.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              ...raw.map((m) {
                final map = (m is Map) ? m : const {};
                final drawer = map['affects_cash_drawer'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(drawer ? Icons.payments_rounded : Icons.credit_card_rounded,
                          size: 18,
                          color: drawer ? AppTheme.primary : AppTheme.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          (map['name'] ?? map['method'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!drawer)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Text('non-drawer',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ),
                      Text('In ${money(map['in'])}',
                          style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Text('Out ${money(map['out'])}',
                          style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(RegisterShiftProvider state) => Row(children: [
    OutlinedButton.icon(onPressed: () => _movementDialog('in'), icon: const Icon(Icons.add_rounded), label: const Text('Cash In')),
    const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _movementDialog('out'), icon: const Icon(Icons.remove_rounded), label: const Text('Cash Out')),
    const Spacer(), FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: AppTheme.danger), onPressed: _closeDialog, icon: const Icon(Icons.lock_rounded), label: const Text('Close Shift')),
  ]);

  Widget _movementList(dynamic rawMovements) {
    final movements = rawMovements is List ? rawMovements : const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.swap_vert_rounded, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('Register Cash Movements', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            if (movements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No Cash In or Cash Out recorded in this shift.', style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ...movements.map((item) {
                final movement = item is Map ? item : const {};
                final creator = movement['creator'] is Map ? movement['creator'] as Map : const {};
                final approver = movement['approver'] is Map ? movement['approver'] as Map : const {};
                final isIn = movement['direction'] == 'in';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: (isIn ? AppTheme.success : AppTheme.danger).withValues(alpha: .12),
                    foregroundColor: isIn ? AppTheme.success : AppTheme.danger,
                    child: Icon(isIn ? Icons.south_west_rounded : Icons.north_east_rounded),
                  ),
                  title: Text(
                    '${isIn ? 'Cash In' : 'Cash Out'} • ${movement['reason'] ?? 'No reason'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${creator['name'] ?? 'Unknown user'} • ${movement['occurred_at'] ?? ''}${movement['note'] == null ? '' : '\n${movement['note']}'}${approver.isEmpty ? '' : '\nApproved by ${approver['name']}'}'),
                  trailing: Text(
                    '${isIn ? '+' : '-'}${movement['amount'] ?? '0.00'}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: isIn ? AppTheme.success : AppTheme.danger),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openDialog(List<Map<String, dynamic>> availableRegisters) async {
    int registerId = int.parse(availableRegisters.first['id'].toString()); final cash = TextEditingController(text: '0.00'); final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Open Register Shift'), content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<int>(initialValue: registerId, decoration: const InputDecoration(labelText: 'Register'), items: availableRegisters.map((r) => DropdownMenuItem(value: int.parse(r['id'].toString()), child: Text(r['name'].toString()))).toList(), onChanged: (v) => registerId = v!), const SizedBox(height: 12), TextField(controller: cash, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening cash')), const SizedBox(height: 12), TextField(controller: note, decoration: const InputDecoration(labelText: 'Opening note (optional)'))])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Open Shift'))]));
    if (ok == true && mounted) { try { await context.read<RegisterShiftProvider>().open(registerId: registerId, openingCash: double.tryParse(cash.text) ?? 0, note: note.text); } catch (e) { _error(e); } }
  }

  Future<void> _manageRegisters() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final service = RegisterShiftService(token);
      var registers = await service.registers(includeInactive: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Manage Registers'),
            content: SizedBox(
              width: 720,
              height: 460,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final saved = await _registerEditor(service);
                        if (saved && dialogContext.mounted) {
                          registers = await service.registers(includeInactive: true);
                          setDialogState(() {});
                        }
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Register'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: registers.isEmpty
                        ? const Center(child: Text('No registers configured.'))
                        : ListView.separated(
                            itemCount: registers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final register = registers[index];
                              final active = register['is_active'] == true || register['is_active'] == 1;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (active ? AppTheme.success : AppTheme.textMuted).withValues(alpha: .12),
                                  foregroundColor: active ? AppTheme.success : AppTheme.textMuted,
                                  child: const Icon(Icons.point_of_sale_rounded),
                                ),
                                title: Text(register['name']?.toString() ?? 'Register', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('Code: ${register['code'] ?? ''}${register['device_identifier'] == null ? '' : ' • Device: ${register['device_identifier']}'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(label: Text(active ? 'Active' : 'Inactive')),
                                    IconButton(
                                      tooltip: 'Edit register',
                                      onPressed: () async {
                                        final saved = await _registerEditor(service, register: register);
                                        if (saved && dialogContext.mounted) {
                                          registers = await service.registers(includeInactive: true);
                                          setDialogState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.edit_rounded),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
          ),
        ),
      );
      await _load();
    } catch (e) { _error(e); }
  }

  Future<bool> _registerEditor(RegisterShiftService service, {Map<String, dynamic>? register}) async {
    final name = TextEditingController(text: register?['name']?.toString() ?? '');
    final code = TextEditingController(text: register?['code']?.toString() ?? '');
    final device = TextEditingController(text: register?['device_identifier']?.toString() ?? '');
    var isActive = register == null || register['is_active'] == true || register['is_active'] == 1;
    final save = await showDialog<bool>(
      context: context,
      builder: (editorContext) => StatefulBuilder(
        builder: (_, setEditorState) => AlertDialog(
          title: Text(register == null ? 'Add Register' : 'Edit Register'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Register name')),
                const SizedBox(height: 12),
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Unique code', hintText: 'REGISTER-2')),
                const SizedBox(height: 12),
                TextField(controller: device, decoration: const InputDecoration(labelText: 'Device identifier (optional)')),
                const SizedBox(height: 8),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: isActive, onChanged: (value) => setEditorState(() => isActive = value)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(editorContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(editorContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true) return false;
    try {
      final body = <String, dynamic>{
        'name': name.text.trim(), 'code': code.text.trim().toUpperCase(),
        'device_identifier': device.text.trim().isEmpty ? null : device.text.trim(), 'is_active': isActive,
      };
      if (register == null) {
        await service.createRegister(body);
      } else {
        await service.updateRegister(int.parse(register['id'].toString()), body);
      }
      return true;
    } catch (e) { _error(e); return false; }
  }

  Future<void> _movementDialog(String direction) async {
    final amount = TextEditingController(); final reason = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: Text(direction == 'in' ? 'Cash In' : 'Cash Out'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')), const SizedBox(height: 12), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Record'))]));
    if (ok == true && mounted) { try { await context.read<RegisterShiftProvider>().addMovement(direction: direction, amount: double.tryParse(amount.text) ?? 0, reason: reason.text); } catch (e) { _error(e); } }
  }

  Future<void> _closeDialog() async {
    final counted = TextEditingController(); final note = TextEditingController(); final pending = context.read<OfflineQueueProvider>().pendingCount;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Close Register Shift'), content: Column(mainAxisSize: MainAxisSize.min, children: [if (pending > 0) Text('$pending offline sale(s) must sync before closing.', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)), TextField(controller: counted, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Counted cash')), const SizedBox(height: 12), TextField(controller: note, decoration: const InputDecoration(labelText: 'Closing notes'))]), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: pending > 0 ? null : () => Navigator.pop(d, true), child: const Text('Close Shift'))]));
    if (ok == true && mounted) { try { await context.read<RegisterShiftProvider>().close(countedCash: double.tryParse(counted.text) ?? 0, pendingSyncCount: pending, note: note.text); } catch (e) { _error(e); } }
  }
  Future<void> _showHistory() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final page = await RegisterShiftService(token).history();
      final rows = (page['data'] as List?) ?? const [];
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (d) => AlertDialog(
        title: const Text('Shift History'),
        content: SizedBox(width: 760, height: 480, child: rows.isEmpty ? const Center(child: Text('No completed shifts yet.')) : ListView.separated(
          itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) { final row = rows[i] as Map; final register = row['register'] is Map ? row['register'] as Map : const {}; return ListTile(
            onTap: () async {
              Navigator.pop(d);
              await _showShiftDetail(int.parse(row['id'].toString()));
            },
            leading: Icon(row['status'] == 'open' ? Icons.lock_open_rounded : Icons.lock_rounded, color: row['status'] == 'open' ? AppTheme.success : AppTheme.textMuted),
            title: Text('${register['name'] ?? 'Register'} • Shift #${row['id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${row['opened_at'] ?? ''}  →  ${row['closed_at'] ?? 'Active'}'),
            trailing: row['variance'] == null ? null : Text('Variance ${row['variance']}', style: TextStyle(fontWeight: FontWeight.w800, color: (double.tryParse(row['variance'].toString()) ?? 0) == 0 ? AppTheme.success : AppTheme.danger)),
          ); },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ));
    } catch (e) { _error(e); }
  }
  Future<void> _showShiftDetail(int shiftId) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    try {
      final data = await RegisterShiftService(token).detail(shiftId);
      if (!mounted) return;
      final shift = data['shift'] is Map ? data['shift'] as Map : const {};
      final summary = data['summary'] is Map ? data['summary'] as Map : const {};
      await showDialog<void>(context: context, builder: (d) => AlertDialog(
        title: Text('Shift #$shiftId Details'),
        content: SizedBox(width: 820, height: 560, child: ListView(children: [
          Wrap(spacing: 12, runSpacing: 8, children: [
            Chip(label: Text('Status: ${shift['status'] ?? ''}')),
            Chip(label: Text('Expected: ${summary['expected_cash'] ?? shift['expected_cash'] ?? '0.00'}')),
            Chip(label: Text('Counted: ${shift['counted_cash'] ?? 'Not closed'}')),
            Chip(label: Text('Variance: ${shift['variance'] ?? '0.00'}')),
          ]),
          const SizedBox(height: 12),
          _movementList(shift['movements']),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
      ));
    } catch (e) { _error(e); }
  }
  void _error(Object e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger)); }
}
