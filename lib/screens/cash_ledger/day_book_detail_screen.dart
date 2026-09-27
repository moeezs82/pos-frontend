import 'package:enterprise_pos/api/cash_ledger_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/screens/cash_ledger/cash_void_action.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/payment_method_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
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
  final _money = const AppMoneyFormatter();

  static const int _perPage = 50;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 82;
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  final Map<int,List<Map<String,dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  Map<String, dynamic> _totals = {};
  num _opening = 0;
  num _closing = 0;

  int _lastPage = 1;
  int _total = 0;
  String _direction = 'all'; // in|out|all
  String _kind = 'all'; // all|module|received|sent|expense
  String? _method; // null = all methods

  /// cash_ledger_entry_id currently being voided (spinner on that row only).
  String? _voidingId;

  @override
  void initState() {
    super.initState();
    final token = context.read<AuthProvider>().token!;
    _service = CashLedgerService(token: token);
    _scrollController.addListener(_onScroll);
    _fetch(page: 1, reset: true);
  }

  @override
  void dispose(){ _scrollController.dispose(); super.dispose(); }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  /// Void & reverse one cash-ledger entry. The backend owns the rules — it
  /// refuses to void twice and posts the reversing journal entry — so this only
  /// confirms, calls, and refreshes.
  /// Reverse a customer receipt / vendor payment shown in this feed. These rows
  /// have no cash_ledger_entry behind them, so the cash-ledger void endpoint
  /// cannot touch them — they go through the party-payment reversal endpoints,
  /// exactly as the Party Payments screen does.
  Future<void> _reversePayment(Map<String, dynamic> e) async {
    final payId = CashVoid.paymentId(e);
    final partyId = CashVoid.paymentPartyId(e);
    final kind = CashVoid.paymentType(e);
    if (payId == null || partyId == null || kind == null) return;
    if (_voidingId != null) return;

    final label = (e['party'] ?? 'this party').toString();
    final reason = await CashVoid.askReversalReason(context, label);
    if (reason == null || !mounted) return;

    final busyKey = 'pay_$payId';
    setState(() => _voidingId = busyKey);
    try {
      if (kind == 'customer_receipt') {
        await CustomerService(token: context.read<AuthProvider>().token!)
            .reverseReceipt(customerId: partyId, receiptId: payId, reason: reason);
      } else {
        await VendorService(token: context.read<AuthProvider>().token!)
            .reversePayment(vendorId: partyId, paymentId: payId, reason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment reversed.')),
      );
      await _fetch(page: 1, reset: true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _voidEntry(Map<String, dynamic> e) async {
    final id = CashVoid.entryId(e);
    if (id == null || _voidingId != null) return;
    if (!await CashVoid.confirm(context)) return;
    if (!mounted) return;

    setState(() => _voidingId = id);
    try {
      await _service.voidEntry(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry voided and reversed.')),
      );
      await _fetch(page: 1, reset: true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _voidingId = null);
    }
  }

  Future<void> _fetch({int page = 1, bool reset = false}) async {
    if(reset){_pages.clear();_loadingPages.clear();_lastPage=1;_total=0;if(_scrollController.hasClients)_scrollController.jumpTo(0);}
    if(_loadingPages.contains(page)||page<1||(_total>0&&page>_lastPage))return;
    _loadingPages.add(page);if(mounted&&_pages.isEmpty)setState(()=>_loading=true);
    try{
      final data=await _service.getDayBookDetails(date:widget.date,direction:_direction,kind:_kind,method:_method,page:page,perPage:_perPage);
      if(!mounted)return;
      final items=(data['items'] as List? ?? []).whereType<Map>().map((e)=>e.cast<String,dynamic>()).toList();
      final pg=Map<String,dynamic>.from(data['pagination']??{});
      setState((){_pages[page]=items;if(page==1){_totals=Map<String,dynamic>.from(data['totals']??{});_opening=_toNum(data['opening']);_closing=_toNum(data['closing']);}
        _lastPage=(pg['last_page'] as num?)?.toInt()??1;_total=(pg['total'] as num?)?.toInt()??(_lastPage<=1?items.length:_lastPage*_perPage);_evictPages(keepPage:page);});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{_loadingPages.remove(page);if(mounted)setState(()=>_loading=false);}
  }

  void _onScroll(){if(!_scrollController.hasClients||_total<=0)return;final first=(_scrollController.offset/_rowExtent).floor().clamp(0,_total-1);final last=(first+(_scrollController.position.viewportDimension/_rowExtent).ceil()+5).clamp(0,_total-1);final fp=first~/_perPage+1,lp=last~/_perPage+1;for(var p=fp;p<=lp;p++){if(!_pages.containsKey(p))_fetch(page:p);}if(lp<_lastPage&&!_pages.containsKey(lp+1))_fetch(page:lp+1);}
  Map<String,dynamic>? _itemAt(int index){final p=index~/_perPage+1,o=index%_perPage;final rows=_pages[p];if(rows==null){_fetch(page:p);return null;}return o<rows.length?rows[o]:null;}
  void _evictPages({required int keepPage}){if(_pages.length<=_maxCachedPages)return;final keys=_pages.keys.toList()..sort((a,b)=>(b-keepPage).abs().compareTo((a-keepPage).abs()));while(_pages.length>_maxCachedPages&&keys.isNotEmpty){_pages.remove(keys.removeAt(0));}}

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
        onRefresh: () => _fetch(page: 1, reset: true),
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
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _direction == 'in',
                        label: const Text('Incoming'),
                        onSelected: (_) {
                          setState(() => _direction = 'in');
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _direction == 'out',
                        label: const Text('Outgoing'),
                        onSelected: (_) {
                          setState(() => _direction = 'out');
                          _fetch(page: 1, reset: true);
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
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'received',
                        label: const Text('Received'),
                        onSelected: (_) {
                          setState(() => _kind = 'received');
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'sent',
                        label: const Text('Paid'),
                        onSelected: (_) {
                          setState(() => _kind = 'sent');
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'expense',
                        label: const Text('Expenses'),
                        onSelected: (_) {
                          setState(() => _kind = 'expense');
                          _fetch(page: 1, reset: true);
                        },
                      ),
                      FilterChip(
                        selected: _kind == 'module',
                        label: const Text('Module only'),
                        onSelected: (_) {
                          setState(() => _kind = 'module');
                          _fetch(page: 1, reset: true);
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
                            _fetch(page: 1, reset: true);
                          },
                        ),
                        ...methods.map((m) => FilterChip(
                              selected: _method == m.method,
                              label: Text(m.displayName),
                              onSelected: (_) {
                                setState(() => _method = m.method);
                                _fetch(page: 1, reset: true);
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
            else if (_total == 0)
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
              SizedBox(
                height: 520,
                child: ListView.builder(
                  controller: _scrollController, itemExtent: _rowExtent, itemCount: _total, cacheExtent: _rowExtent * 12,
                  itemBuilder: (_, index) { final item = _itemAt(index); return item == null ? const Center(child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))) : _buildRow(item); },
                ),
              ),
            if (_total > 0) ...[
              const SizedBox(height: 8),
              Text('$_total transactions • bounded cache ${_pages.length}/$_maxCachedPages pages', style: const TextStyle(color:AppTheme.textMuted,fontSize:11,fontWeight:FontWeight.w700)),
            ],
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
            CashVoidedBadge(row: e),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${direction == 'in' ? '+' : '-'} ${_money.format(amount)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15),
            ),
            CashVoidButton(
              row: e,
              busy: _voidingId != null &&
                  (_voidingId == CashVoid.entryId(e) ||
                      _voidingId == 'pay_${CashVoid.paymentId(e)}'),
              onVoid: () => _voidEntry(e),
              onReverse: () => _reversePayment(e),
            ),
          ],
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
