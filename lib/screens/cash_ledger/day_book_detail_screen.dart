import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Every cash movement for ONE calendar day — what came in, what went out,
/// and the opening/closing balance for that day. Tapping a day in the Day
/// Book list opens this. Rows use the exact same labels and party-name
/// resolution as the main Cash Ledger feed, because they come from the
/// same backend source (UnifiedCashFlowService).
class DayBookDetailScreen extends StatefulWidget {
  final String date; // YYYY-MM-DD

  const DayBookDetailScreen({super.key, required this.date});

  @override
  State<DayBookDetailScreen> createState() => _DayBookDetailScreenState();
}

class _DayBookDetailScreenState extends State<DayBookDetailScreen> {
  late final CashLedgerService _service;
  final _money = NumberFormat('#,##0.00');

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _totals = {};
  num _opening = 0;
  num _closing = 0;

  int _page = 1;
  int _lastPage = 1;
  String _direction = 'all'; // in|out|all
  String _kind = 'all'; // all|module|received|sent|expense
  String? _method; // null = all methods

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _fetch(page: 1);
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final data = await _service.getDayBookDetails(
        date: widget.date,
        direction: _direction,
        kind: _kind,
        method: _method,
        page: page,
        perPage: 50,
      );
      if (!mounted) return;
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _items = items;
        _totals = Map<String, dynamic>.from(data['totals'] ?? {});
        _opening = _toNum(data['opening']);
        _closing = _toNum(data['closing']);
        final p = Map<String, dynamic>.from(data['pagination'] ?? {});
        _page = (p['current_page'] as num?)?.toInt() ?? page;
        _lastPage = (p['last_page'] as num?)?.toInt() ?? 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtHeading() {
    try {
      final d = DateTime.parse(widget.date);
      return DateFormat('EEEE, d MMM yyyy').format(d);
    } catch (_) {
      return widget.date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day Details'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetch(page: _page),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            EnterprisePanel(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EnterpriseSectionHeader(
                    title: _fmtHeading(),
                    subtitle: 'Opening, every movement, and closing balance for the day',
                    icon: Icons.today_rounded,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                label: 'Opening',
                                value: _money.format(_opening),
                                color: AppTheme.navy,
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Stat(
                                label: 'Closing',
                                value: _money.format(_closing),
                                color: AppTheme.navy,
                                icon: Icons.account_balance_wallet_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                label: 'Received',
                                value: _money.format(_toNum(_totals['in'])),
                                color: AppTheme.success,
                                icon: Icons.south_west_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Stat(
                                label: 'Paid',
                                value: _money.format(_toNum(_totals['out'])),
                                color: AppTheme.danger,
                                icon: Icons.north_east_rounded,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            EnterprisePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Direction', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        selected: _direction == 'all',
                        label: const Text('All'),
                        onSelected: (_) {
                          setState(() => _direction = 'all');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _direction == 'in',
                        label: const Text('Incoming'),
                        onSelected: (_) {
                          setState(() => _direction = 'in');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _direction == 'out',
                        label: const Text('Outgoing'),
                        onSelected: (_) {
                          setState(() => _direction = 'out');
                          _fetch(page: 1);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Source', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        selected: _kind == 'all',
                        label: const Text('All sources'),
                        onSelected: (_) {
                          setState(() => _kind = 'all');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'received',
                        label: const Text('Received'),
                        onSelected: (_) {
                          setState(() => _kind = 'received');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'sent',
                        label: const Text('Paid'),
                        onSelected: (_) {
                          setState(() => _kind = 'sent');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'expense',
                        label: const Text('Expenses'),
                        onSelected: (_) {
                          setState(() => _kind = 'expense');
                          _fetch(page: 1);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'module',
                        label: const Text('Module only'),
                        onSelected: (_) {
                          setState(() => _kind = 'module');
                          _fetch(page: 1);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Payment method filter (Cash / Bank / KNET / …).
                  Builder(builder: (context) {
                    final methods =
                        context.watch<PaymentMethodProvider>().activeMethods;
                    if (methods.isEmpty) return const SizedBox.shrink();
                    return Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          selected: _method == null,
                          label: const Text('All methods'),
                          onSelected: (_) {
                            setState(() => _method = null);
                            _fetch(page: 1);
                          },
                        ),
                        ...methods.map((m) => FilterChip(
                              selected: _method == m.method,
                              label: Text(m.displayName),
                              onSelected: (_) {
                                setState(() => _method = m.method);
                                _fetch(page: 1);
                              },
                            )),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const SizedBox.shrink()
            else if (_items.isEmpty)
              EnterprisePanel(
                child: Column(
                  children: const [
                    SizedBox(height: 16),
                    Icon(Icons.receipt_long_outlined, size: 56, color: AppTheme.textMuted),
                    SizedBox(height: 10),
                    Text('No transactions for this day', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800)),
                    SizedBox(height: 16),
                  ],
                ),
              )
            else
              Column(children: _items.map(_buildRow).toList()),
            const SizedBox(height: 12),
            if (_items.isNotEmpty && _lastPage > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _page > 1 ? () => _fetch(page: _page - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                  const SizedBox(width: 16),
                  Text('Page $_page of $_lastPage', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _page < _lastPage ? () => _fetch(page: _page + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final direction = (e['direction'] ?? '').toString();
    final label = (e['label'] ?? 'Entry').toString();
    final source = (e['source'] ?? 'journal').toString();
    final amount = _toNum(e['amount']);
    final color = direction == 'in' ? AppTheme.success : AppTheme.danger;
    final sourceIcon = source == 'module' ? Icons.add_circle_outline : Icons.book_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(13)),
          child: Icon(
            direction == 'in' ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy),
              ),
            ),
            // Fund / payment account this movement went through.
            if ((e['method'] ?? e['account']?['name'] ?? '').toString().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (e['method'] ?? e['account']?['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primaryDark),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sourceIcon, size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 3),
                  Text(
                    source,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            (e['party'] ?? 'Unlinked').toString(),
            if ((e['reference'] ?? '').toString().isNotEmpty) 'Ref: ${e['reference']}',
            if ((e['memo'] ?? '').toString().isNotEmpty) (e['memo']).toString(),
          ].join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${direction == 'in' ? '+' : '-'} ${_money.format(amount)}',
          style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Stat({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}
