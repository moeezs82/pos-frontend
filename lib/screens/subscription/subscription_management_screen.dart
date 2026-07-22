import 'package:enterprise_pos/api/subscription_api_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Owner-only screen for viewing and managing branch subscriptions.
///
/// Normal users are blocked from seeing this screen (hidden in the UI and
/// the backend independently rejects their requests with 403).
///
/// Shows a summary row of counts (total, active, not_configured, expiring,
/// etc.) above the paginated branch list so the owner gets an at-a-glance
/// health picture before drilling into individual branches.
class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _statusFilter;
  late SubscriptionApiService _api;

  // not_configured is a computed status (no row in branch_subscriptions)
  final _filters = [
    '',
    'active',
    'trial',
    'grace_period',
    'expiring_soon',
    'expired',
    'suspended',
    'not_configured',
  ];

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token ?? '';
    _api = SubscriptionApiService(token: token);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.listBranches(
          search: _search, status: _statusFilter);

      // Response shape: { data: { branches: { data: [...], ... }, summary: {...} } }
      final outer     = res['data'] as Map? ?? {};
      final paged     = outer['branches'] as Map? ?? {};
      final items     = paged['data'] as List? ?? [];
      final summary   = Map<String, dynamic>.from(
          (outer['summary'] as Map?) ?? {});

      setState(() {
        _branches = items
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isMasterAdmin) {
      return const Scaffold(
        body: Center(child: Text('Access denied — owner only.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Subscriptions'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // ── Summary cards ─────────────────────────────────────────────────
          if (!_loading && _summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SummaryCards(summary: _summary),
            const SizedBox(height: 4),
          ],

          // ── Search & filter bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search branches…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _search = v;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('All'),
                  items: _filters
                      .map((s) => DropdownMenuItem(
                          value: s.isEmpty ? null : s,
                          child: Text(s.isEmpty ? 'All' : _filterLabel(s))))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _load();
                  },
                ),
              ],
            ),
          ),

          // ── Branch list ───────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppTheme.danger, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style:
                                      const TextStyle(color: AppTheme.danger)),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                                onPressed: _load,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _branches.isEmpty
                        ? const Center(child: Text('No branches found.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _branches.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) =>
                                _BranchSubscriptionTile(
                              branch: _branches[i],
                              api: _api,
                              onUpdated: _load,
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(String s) => switch (s) {
        'active' => 'Active',
        'trial' => 'Trial',
        'grace_period' => 'Grace Period',
        'expiring_soon' => 'Expiring Soon',
        'expired' => 'Expired',
        'suspended' => 'Suspended',
        'not_configured' => 'Not Configured',
        _ => s,
      };
}

// ── Summary cards row ─────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    int _n(String key) => (summary[key] as num?)?.toInt() ?? 0;

    final cards = [
      _SummaryCard('Total',          _n('total'),          AppTheme.navy),
      _SummaryCard('Active',         _n('active'),         AppTheme.success),
      _SummaryCard('Trial',          _n('trial'),          AppTheme.info),
      _SummaryCard('Grace',          _n('grace_period'),   AppTheme.warning),
      _SummaryCard('Expiring',       _n('expiring_soon'),  AppTheme.warning),
      _SummaryCard('Not Set Up',     _n('not_configured'), AppTheme.danger),
      _SummaryCard('Expired',        _n('expired'),        AppTheme.danger),
      _SummaryCard('Suspended',      _n('suspended'),      AppTheme.danger),
      _SummaryCard('Locked',         _n('locked'),         AppTheme.danger),
      _SummaryCard('Barcode',        _n('barcode_labels_addon'), AppTheme.purple),
    ];

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryCard(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Branch tile ───────────────────────────────────────────────────────────────

class _BranchSubscriptionTile extends StatelessWidget {
  final Map<String, dynamic> branch;
  final SubscriptionApiService api;
  final VoidCallback onUpdated;

  const _BranchSubscriptionTile({
    required this.branch,
    required this.api,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final status = (branch['computed_status'] ??
            branch['subscription_status'] ??
            'not_configured')
        .toString();
    final isLocked = branch['is_locked'] == true;
    final isNotConfigured = status == 'not_configured';
    final remaining = branch['remaining_days'];
    final expiresAt = branch['expires_at']?.toString();
    final branchId = branch['id'] as int;
    final branchName = branch['name']?.toString() ?? 'Branch $branchId';
    final location = branch['location']?.toString();
    final message = branch['message']?.toString();
    final addons = branch['addons'] as Map? ?? const {};
    final barcodeAddonActive = addons['barcode_labels'] == true;

    Color borderColor;
    if (isNotConfigured) {
      borderColor = AppTheme.warning.withOpacity(.35);
    } else if (isLocked) {
      borderColor = AppTheme.danger.withOpacity(.3);
    } else {
      borderColor = AppTheme.border;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: borderColor),
        boxShadow: AppTheme.softShadow,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _StatusBadge(status: status),
        title: Row(
          children: [
            Expanded(
              child: Text(
                branchName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.navy),
              ),
            ),
            if (branch['is_active'] == false)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Inactive',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (location != null && location.isNotEmpty)
              Text(location,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textMuted)),
            if (isNotConfigured)
              const Text('No subscription record — branch is blocked.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.warning, fontWeight: FontWeight.w600))
            else ...[
              if (expiresAt != null)
                Text('Expires: ${_fmtDate(expiresAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              if (remaining != null)
                Text(
                  '$remaining day(s) remaining',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (remaining as num) <= 7
                          ? AppTheme.warning
                          : AppTheme.textMuted),
                ),
            ],
            if (isLocked && !isNotConfigured && message != null && message.isNotEmpty)
              Text(message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.danger)),
            if (barcodeAddonActive)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Add-on: Barcode Label Printing',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        trailing: OutlinedButton(
          style: isNotConfigured
              ? OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  side: const BorderSide(color: AppTheme.warning))
              : null,
          onPressed: () => _openEditDialog(context, branchId, branchName),
          child: Text(isNotConfigured ? 'Set Up' : 'Manage'),
        ),
      ),
    );
  }

  Future<void> _openEditDialog(
      BuildContext context, int branchId, String branchName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SubscriptionEditDialog(
        branchId: branchId,
        branchName: branchName,
        api: api,
      ),
    );
    if (result == true) {
      onUpdated();
      final auth = context.read<AuthProvider>();
      final subProvider = context.read<SubscriptionProvider>();
      if (auth.activeBranchId == branchId && auth.token != null) {
        await subProvider.refresh(token: auth.token!, branchId: branchId);
        await auth.refreshMe();
      }
    }
  }

  static String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Color _color() => switch (status) {
        'active' || 'trial' => AppTheme.success,
        'grace_period' => AppTheme.warning,
        'not_configured' => AppTheme.warning,
        'expired' || 'suspended' => AppTheme.danger,
        _ => AppTheme.textMuted,
      };

  String _label() => switch (status) {
        'trial' => 'Trial',
        'active' => 'Active',
        'grace_period' => 'Grace',
        'expired' => 'Expired',
        'suspended' => 'Suspended',
        'not_configured' => 'Not Set Up',
        _ => status,
      };
}

// ── Edit dialog ───────────────────────────────────────────────────────────────

class _SubscriptionEditDialog extends StatefulWidget {
  final int branchId;
  final String branchName;
  final SubscriptionApiService api;

  const _SubscriptionEditDialog({
    required this.branchId,
    required this.branchName,
    required this.api,
  });

  @override
  State<_SubscriptionEditDialog> createState() =>
      _SubscriptionEditDialogState();
}

class _SubscriptionEditDialogState extends State<_SubscriptionEditDialog> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Form state
  String? _selectedStatus;
  DateTime? _expiresAt;
  DateTime? _graceUntil;
  bool _barcodeLabelsAddon = false;
  final _reasonCtrl = TextEditingController();
  final _suspendReasonCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const _statuses = [
    'trial',
    'active',
    'grace_period',
    'expired',
    'suspended',
  ];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _suspendReasonCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await widget.api.getBranchDetail(widget.branchId);
      final data = res['data'] as Map? ?? {};
      final sub = data['subscription'] as Map? ?? {};
      final addons = data['addons'] as Map? ?? {};
      final barcodeAddon = addons['barcode_labels'];
      setState(() {
        _detail = Map<String, dynamic>.from(data);
        _selectedStatus = sub['status']?.toString() ?? 'active';
        _expiresAt = sub['expires_at'] != null
            ? DateTime.tryParse(sub['expires_at'].toString())
            : null;
        _graceUntil = sub['grace_until'] != null
            ? DateTime.tryParse(sub['grace_until'].toString())
            : null;
        _notesCtrl.text = sub['notes']?.toString() ?? '';
        _suspendReasonCtrl.text = sub['suspended_reason']?.toString() ?? '';
        _barcodeLabelsAddon = barcodeAddon is Map
            ? barcodeAddon['active'] == true
            : barcodeAddon == true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedStatus == 'suspended' &&
        _suspendReasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Suspension reason is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'status': _selectedStatus,
        'expires_at': _expiresAt?.toIso8601String(),
        'grace_until': _graceUntil?.toIso8601String(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'reason':
            _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        if (_selectedStatus == 'suspended')
          'suspended_reason': _suspendReasonCtrl.text.trim(),
        'addons': {'barcode_labels': _barcodeLabelsAddon},
      };

      await widget.api.updateSubscription(widget.branchId, payload);

      if (!mounted) return;
      Navigator.of(context).pop(true); // signal parent to reload
      AppFeedback.show(context, '✓ Subscription updated successfully.');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Manage — ${widget.branchName}'),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!,
                            style:
                                const TextStyle(color: AppTheme.danger)),
                      ),

                    // Status
                    const Text('Status',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      items: _statuses
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(_stLabel(s))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedStatus = v),
                      decoration: const InputDecoration(isDense: true),
                    ),
                    const SizedBox(height: 14),

                    // Expires at
                    const Text('Expiry Date',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    _DatePickerRow(
                      date: _expiresAt,
                      hint: 'No expiry (runs forever)',
                      onChanged: (d) => setState(() => _expiresAt = d),
                    ),
                    const SizedBox(height: 14),

                    // Grace until (only relevant for grace_period)
                    if (_selectedStatus == 'grace_period') ...[
                      const Text('Grace Until',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      _DatePickerRow(
                        date: _graceUntil,
                        hint: 'No grace end date',
                        onChanged: (d) => setState(() => _graceUntil = d),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Suspension reason
                    if (_selectedStatus == 'suspended') ...[
                      const Text('Suspension Reason *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _suspendReasonCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Reason for suspension…',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    const Text('Add-on Modules',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.purple.withOpacity(.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.purple.withOpacity(.2)),
                      ),
                      child: SwitchListTile(
                        value: _barcodeLabelsAddon,
                        onChanged: (value) =>
                            setState(() => _barcodeLabelsAddon = value),
                        secondary: const Icon(
                          Icons.qr_code_2_rounded,
                          color: AppTheme.purple,
                        ),
                        title: const Text(
                          'Barcode Label Printing',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Allows authorized branch users to print product barcode and price labels.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    const Text('Notes',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Optional — payment ref, remarks…',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Audit reason
                    const Text('Reason for Change',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Optional — recorded in audit log',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  String _stLabel(String s) => switch (s) {
        'trial' => 'Trial',
        'active' => 'Active',
        'grace_period' => 'Grace Period',
        'expired' => 'Expired',
        'suspended' => 'Suspended',
        _ => s,
      };
}

// ── Date picker row ───────────────────────────────────────────────────────────

class _DatePickerRow extends StatelessWidget {
  final DateTime? date;
  final String hint;
  final ValueChanged<DateTime?> onChanged;

  const _DatePickerRow({
    required this.date,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              date == null ? hint : _fmt(date!),
              style: TextStyle(
                color: date == null ? AppTheme.textMuted : AppTheme.navy,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now().add(const Duration(days: 30)),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              // Set to end of day so "expires on DD/MM/YYYY" is inclusive.
              onChanged(DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
            }
          },
          child: const Text('Pick'),
        ),
        if (date != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.clear_rounded, size: 18),
            tooltip: 'Clear date',
            onPressed: () => onChanged(null),
          ),
        ],
      ],
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/'
        '${l.year}';
  }
}
