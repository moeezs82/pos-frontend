import 'package:enterprise_pos/api/subscription_api_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/subscription_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
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
  static const int _maxCachedPages = 6;
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _statusFilter;
  late SubscriptionApiService _api;
  final ScrollController _scrollController = ScrollController();
  int _total = 0;
  int _perPage = 20;
  int _lastPage = 1;
  int _requestGeneration = 0;

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
    _scrollController.addListener(_onScroll);
    _load();
  }

  Future<void> _load({bool reset = true, int page = 1}) async {
    if (reset) {
      ++_requestGeneration;
      _pages.clear();
      _loadingPages.clear();
      _total = 0;
      _lastPage = 1;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      if (mounted) setState(() { _loading = true; _error = null; });
    }
    final generation = _requestGeneration;
    if (page < 1 || _loadingPages.contains(page) || (!reset && _pages.containsKey(page)) || (_total > 0 && page > _lastPage)) return;
    _loadingPages.add(page);
    try {
      final res = await _api.listBranches(search: _search, status: _statusFilter, page: page);
      final outer = res['data'] as Map? ?? {};
      final paged = outer['branches'] as Map? ?? {};
      final items = (paged['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false);
      if (!mounted || generation != _requestGeneration) return;
      final summary = Map<String, dynamic>.from((outer['summary'] as Map?) ?? {});
      final current = (paged['current_page'] as num?)?.toInt() ?? page;
      final per = (paged['per_page'] as num?)?.toInt() ?? (items.isEmpty ? _perPage : items.length);
      final total = (paged['total'] as num?)?.toInt() ?? items.length;
      final last = (paged['last_page'] as num?)?.toInt() ?? 1;
      setState(() {
        _pages[current] = items;
        _summary = summary;
        _perPage = per <= 0 ? 20 : per;
        _total = total;
        _lastPage = last < 1 ? 1 : last;
        _loading = false;
        _error = null;
        _evictPages(current);
      });
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() { _error = e.toString(); _loading = false; });
    } finally {
      _loadingPages.remove(page);
    }
  }

  int get _loadedCount => _pages.values.fold<int>(0, (n, rows) => n + rows.length);

  Map<String, dynamic>? _branchAt(int index) {
    final page = index ~/ _perPage + 1;
    final offset = index % _perPage;
    final rows = _pages[page];
    if (rows == null) { _load(reset: false, page: page); return null; }
    return offset < rows.length ? rows[offset] : null;
  }

  void _evictPages(int keepPage) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()..sort((a,b) => (b-keepPage).abs().compareTo((a-keepPage).abs()));
    while (_pages.length > _maxCachedPages && keys.isNotEmpty) { _pages.remove(keys.removeAt(0)); }
  }

  void _reload() => _load(reset: true, page: 1);

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _total <= 0) return;
    final first = (_scrollController.offset / 86).floor().clamp(0, _total - 1);
    final last = (first + (_scrollController.position.viewportDimension / 86).ceil() + 6).clamp(0, _total - 1);
    final firstPage = first ~/ _perPage + 1;
    final lastPage = last ~/ _perPage + 1;
    for (var p = firstPage; p <= lastPage; p++) { if (!_pages.containsKey(p)) _load(reset: false, page: p); }
    if (lastPage < _lastPage && !_pages.containsKey(lastPage + 1)) _load(reset: false, page: lastPage + 1);
    _evictPages(firstPage);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isMasterAdmin) {
      return const EnterprisePage(
        title: 'Subscriptions',
        subtitle: 'Branch subscription and add-on administration.',
        icon: Icons.workspace_premium_outlined,
        child: Center(child: Text('Access denied — owner only.')),
      );
    }

    return EnterprisePage(
      title: 'Subscriptions',
      subtitle: 'Monitor branch subscription health, expiry status and commercial add-ons.',
      icon: Icons.workspace_premium_outlined,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        children: [
          if (!_loading && _summary.isNotEmpty) ...[
            _SummaryCards(summary: _summary),
            const SizedBox(height: 10),
          ],
          EnterpriseToolbar(
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search branches…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (v) {
                    _search = v.trim();
                    _reload();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: _statusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: _filters
                      .map((value) => DropdownMenuItem<String?>(
                            value: value.isEmpty ? null : value,
                            child: Text(value.isEmpty ? 'All statuses' : _filterLabel(value)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _reload();
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '$_total branches • $_loadedCount cached',
                  style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null && _pages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 36),
                                const SizedBox(height: 10),
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted)),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _total == 0
                          ? const Center(child: Text('No branches found.'))
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _total,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final branch = _branchAt(i);
                                if (branch == null) {
                                  return const SizedBox(height: 78, child: Center(child: LinearProgressIndicator(minHeight: 2)));
                                }
                                return _BranchSubscriptionTile(branch: branch, api: _api, onUpdated: _reload);
                              },
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
      _SummaryCard('Barcode',        _n('barcode_labels_addon'),   AppTheme.purple),
      _SummaryCard('Loans',          _n('loan_module_addon'),      AppTheme.teal),
      _SummaryCard('Qameti',         _n('qameti_module_addon'),    AppTheme.info),
      _SummaryCard('WhatsApp',       _n('whatsapp_invoice_addon'), const Color(0xFF128C7E)),
      _SummaryCard('Intelligence',    _n('intelligence_addon'),     AppTheme.purple),
      _SummaryCard('Field Sales',     _n('field_sales_addon'),      AppTheme.primary),
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
    // Collect labels for every active addon so the card shows all of them.
    const _addonLabels = <String, String>{
      'barcode_labels':  'Barcode Labels',
      'loan_module':     'Loans',
      'qameti_module':   'Qameti',
      'whatsapp_invoice': 'WhatsApp',
      'intelligence':     'Intelligence',
      'field_sales':      'Field Sales',
    };
    const _addonColors = <String, Color>{
      'barcode_labels':  AppTheme.purple,
      'loan_module':     AppTheme.teal,
      'qameti_module':   AppTheme.info,
      'whatsapp_invoice': Color(0xFF128C7E),
      'intelligence':     AppTheme.purple,
      'field_sales':      AppTheme.primary,
    };
    final activeAddons = _addonLabels.keys
        .where((k) => addons[k] == true)
        .toList();

    Color borderColor;
    if (isNotConfigured) {
      borderColor = AppTheme.warning.withOpacity(.35);
    } else if (isLocked) {
      borderColor = AppTheme.danger.withOpacity(.3);
    } else {
      borderColor = AppTheme.border;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
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
            if (activeAddons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: activeAddons.map((key) {
                    final color = _addonColors[key]!;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(.30)),
                      ),
                      child: Text(
                        _addonLabels[key]!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
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
      if (!context.mounted) return;
      final auth = context.read<AuthProvider>();
      final subProvider = context.read<SubscriptionProvider>();
      if (auth.activeBranchId == branchId && auth.token != null) {
        await subProvider.refresh(token: auth.token!, branchId: branchId);
        if (context.mounted) await auth.refreshMe();
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
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Form state
  String? _selectedStatus;
  DateTime? _expiresAt;
  DateTime? _graceUntil;
  bool _barcodeLabelsAddon  = false;
  bool _loanModuleAddon     = false;
  bool _qametiModuleAddon   = false;
  bool _whatsappInvoiceAddon = false;
  bool _intelligenceAddon    = false;
  bool _fieldSalesAddon      = false;
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
      bool _addonBool(String key) {
        final v = addons[key];
        return v is Map ? v['active'] == true : v == true;
      }
      setState(() {
        _selectedStatus = sub['status']?.toString() ?? 'active';
        _expiresAt = sub['expires_at'] != null
            ? DateTime.tryParse(sub['expires_at'].toString())
            : null;
        _graceUntil = sub['grace_until'] != null
            ? DateTime.tryParse(sub['grace_until'].toString())
            : null;
        _notesCtrl.text = sub['notes']?.toString() ?? '';
        _suspendReasonCtrl.text = sub['suspended_reason']?.toString() ?? '';
        _barcodeLabelsAddon   = _addonBool('barcode_labels');
        _loanModuleAddon      = _addonBool('loan_module');
        _qametiModuleAddon    = _addonBool('qameti_module');
        _whatsappInvoiceAddon = _addonBool('whatsapp_invoice');
        _intelligenceAddon     = _addonBool('intelligence');
        _fieldSalesAddon      = _addonBool('field_sales');
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
        'addons': {
          'barcode_labels':  _barcodeLabelsAddon,
          'loan_module':     _loanModuleAddon,
          'qameti_module':   _qametiModuleAddon,
          'whatsapp_invoice': _whatsappInvoiceAddon,
          'intelligence':      _intelligenceAddon,
          'field_sales':      _fieldSalesAddon,
        },
      };

      await widget.api.updateSubscription(widget.branchId, payload);

      if (mounted) {
        final auth = context.read<AuthProvider>();
        if (auth.activeBranchId == widget.branchId) {
          await auth.refreshMe();
        }
      }

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
                    Material(
                      color: AppTheme.purple.withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: AppTheme.purple.withOpacity(.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
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
                    const SizedBox(height: 8),
                    Material(
                      color: AppTheme.teal.withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: AppTheme.teal.withOpacity(.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _loanModuleAddon,
                        onChanged: (value) =>
                            setState(() => _loanModuleAddon = value),
                        secondary: const Icon(
                          Icons.request_quote_rounded,
                          color: AppTheme.teal,
                        ),
                        title: const Text(
                          'Loan Management',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Record and track cash loans given to and recovered from customers, vendors, or staff.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: AppTheme.info.withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: AppTheme.info.withOpacity(.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _qametiModuleAddon,
                        onChanged: (value) =>
                            setState(() => _qametiModuleAddon = value),
                        secondary: const Icon(
                          Icons.savings_rounded,
                          color: AppTheme.info,
                        ),
                        title: const Text(
                          'Qameti Management',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Record committee/Qameti installment payments and collection payouts.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFF128C7E).withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: const Color(0xFF128C7E).withOpacity(.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _whatsappInvoiceAddon,
                        onChanged: (value) =>
                            setState(() => _whatsappInvoiceAddon = value),
                        secondary: const Icon(
                          Icons.chat_rounded,
                          color: Color(0xFF128C7E),
                        ),
                        title: const Text(
                          'WhatsApp Invoice Assistant',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Prepares the sale PDF and opens WhatsApp so the cashier can send the invoice manually.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: AppTheme.purple.withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: AppTheme.purple.withOpacity(.2),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _intelligenceAddon,
                        onChanged: (value) =>
                            setState(() => _intelligenceAddon = value),
                        secondary: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppTheme.purple,
                        ),
                        title: const Text(
                          'Business Intelligence',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Enables Money Finder, Replenishment, business seasons, and derived sales/inventory intelligence for this branch.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: AppTheme.primary.withOpacity(.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: AppTheme.primary.withOpacity(.2),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _fieldSalesAddon,
                        onChanged: (value) =>
                            setState(() => _fieldSalesAddon = value),
                        secondary: const Icon(
                          Icons.assignment_outlined,
                          color: AppTheme.primary,
                        ),
                        title: const Text(
                          'Field Sales & Orders',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Enables field sales agent booking, sales orders management, stock allocation, and POS conversion.',
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
