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
  final bool embedded;
  final VoidCallback? onBack;

  const DayBookDetailScreen({
    super.key,
    required this.date,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<DayBookDetailScreen> createState() => _DayBookDetailScreenState();
}

class _DayBookDetailScreenState extends State<DayBookDetailScreen> {
  late final CashLedgerService _service;
  final _money = const AppMoneyFormatter();

  static const int _requestedPerPage = 50;
  int _serverPerPage = _requestedPerPage;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 62;
  bool _loading = true;
  final ScrollController _pageScrollController = ScrollController();
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
  void dispose(){ _pageScrollController.dispose(); _scrollController.dispose(); super.dispose(); }

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
    if(reset){_pages.clear();_loadingPages.clear();_lastPage=1;_total=0;_serverPerPage=_requestedPerPage;if(_scrollController.hasClients)_scrollController.jumpTo(0);if(_pageScrollController.hasClients)_pageScrollController.jumpTo(0);}
    if(_loadingPages.contains(page)||page<1||(_total>0&&page>_lastPage))return;
    _loadingPages.add(page);if(mounted&&_pages.isEmpty)setState(()=>_loading=true);
    try{
      final data=await _service.getDayBookDetails(date:widget.date,direction:_direction,kind:_kind,method:_method,page:page,perPage:_requestedPerPage);
      if(!mounted)return;
      final items=(data['items'] as List? ?? []).whereType<Map>().map((e)=>e.cast<String,dynamic>()).toList();
      final pg=Map<String,dynamic>.from(data['pagination']??{});
      setState((){
        final reportedPerPage=(pg['per_page'] as num?)?.toInt()??0;
        if(reportedPerPage>0){
          _serverPerPage=reportedPerPage;
        }else if(page==1&&items.isNotEmpty){
          _serverPerPage=items.length;
        }
        _pages[page]=items;
        if(page==1){_totals=Map<String,dynamic>.from(data['totals']??{});_opening=_toNum(data['opening']);_closing=_toNum(data['closing']);}
        _lastPage=(pg['last_page'] as num?)?.toInt()??1;
        _total=(pg['total'] as num?)?.toInt()??(_lastPage<=1?items.length:_lastPage*_serverPerPage);
        _evictPages(keepPage:page);
      });
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{_loadingPages.remove(page);if(mounted)setState(()=>_loading=false);}
  }

  void _onScroll(){if(!_scrollController.hasClients||_total<=0)return;final first=(_scrollController.offset/_rowExtent).floor().clamp(0,_total-1);final last=(first+(_scrollController.position.viewportDimension/_rowExtent).ceil()+5).clamp(0,_total-1);final fp=first~/_serverPerPage+1,lp=last~/_serverPerPage+1;for(var p=fp;p<=lp;p++){if(!_pages.containsKey(p))_fetch(page:p);}if(lp<_lastPage&&!_pages.containsKey(lp+1))_fetch(page:lp+1);}
  Map<String,dynamic>? _itemAt(int index){final p=index~/_serverPerPage+1,o=index%_serverPerPage;final rows=_pages[p];if(rows==null){_fetch(page:p);return null;}return o<rows.length?rows[o]:null;}
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
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final listHeight = (constraints.maxHeight * .70).clamp(430.0, 760.0);
        return Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          child: RefreshIndicator(
            onRefresh: () => _fetch(page: 1, reset: true),
            child: SingleChildScrollView(
              controller: _pageScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 0 : 16,
                8,
                widget.embedded ? 8 : 16,
                20,
              ),
              child: Column(
                children: [
                  // The persistent Cash Ledger header already owns the Back to
                  // Day Book action when this screen is embedded. Keeping a
                  // second back button here wasted vertical space and made the
                  // drill-down feel like another stacked page.
                  EnterprisePanel(
                    elevated: false,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      children: [
                        EnterpriseSectionHeader(
                          title: _fmtHeading(),
                          subtitle: 'Opening, movement and closing balance',
                          icon: Icons.today_rounded,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(height: 10),
                        if (_loading && _pages.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: _Stat(label: 'Opening', value: _money.format(_opening), color: AppTheme.navy, icon: Icons.account_balance_wallet_outlined)),
                              const SizedBox(width: 8),
                              Expanded(child: _Stat(label: 'Received', value: _money.format(_toNum(_totals['in'])), color: AppTheme.success, icon: Icons.south_west_rounded)),
                              const SizedBox(width: 8),
                              Expanded(child: _Stat(label: 'Paid', value: _money.format(_toNum(_totals['out'])), color: AppTheme.danger, icon: Icons.north_east_rounded)),
                              const SizedBox(width: 8),
                              Expanded(child: _Stat(label: 'Closing', value: _money.format(_closing), color: AppTheme.navy, icon: Icons.account_balance_wallet_rounded)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  EnterprisePanel(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 175,
                          child: DropdownButtonFormField<String>(
                            value: _direction,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Direction',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All directions')),
                              DropdownMenuItem(value: 'in', child: Text('Incoming')),
                              DropdownMenuItem(value: 'out', child: Text('Outgoing')),
                            ],
                            onChanged: (value) {
                              if (value == null || value == _direction) return;
                              setState(() => _direction = value);
                              _fetch(page: 1, reset: true);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            value: _kind,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Source',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All sources')),
                              DropdownMenuItem(value: 'received', child: Text('Received')),
                              DropdownMenuItem(value: 'sent', child: Text('Paid')),
                              DropdownMenuItem(value: 'expense', child: Text('Expenses')),
                              DropdownMenuItem(value: 'module', child: Text('Module only')),
                            ],
                            onChanged: (value) {
                              if (value == null || value == _kind) return;
                              setState(() => _kind = value);
                              _fetch(page: 1, reset: true);
                            },
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final methods = context.watch<PaymentMethodProvider>().activeMethods;
                            final selected = _method ?? '__all__';
                            return SizedBox(
                              width: 215,
                              child: DropdownButtonFormField<String>(
                                value: selected,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: 'Payment method',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                                ),
                                items: [
                                  const DropdownMenuItem(value: '__all__', child: Text('All methods')),
                                  ...methods.map((m) => DropdownMenuItem<String>(value: m.method, child: Text(m.displayName))),
                                ],
                                onChanged: (value) {
                                  final next = value == '__all__' ? null : value;
                                  if (next == _method) return;
                                  setState(() => _method = next);
                                  _fetch(page: 1, reset: true);
                                },
                              ),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _fetch(page: 1, reset: true),
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: listHeight,
                    child: _loading && _pages.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _total == 0
                            ? EnterprisePanel(
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
                            : Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemExtent: _rowExtent,
                                  itemCount: _total,
                                  cacheExtent: _rowExtent * 12,
                                  itemBuilder: (_, index) {
                                    final item = _itemAt(index);
                                    return item == null
                                        ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                        : _buildRow(item);
                                  },
                                ),
                              ),
                  ),
                  if (_total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$_total transactions • $_lastPage server pages • bounded cache ${_pages.length}/$_maxCachedPages pages',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day Details'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 8), child: BranchIndicator(tappable: false)),
        ],
      ),
      body: content,
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
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minLeadingWidth: 38,
        leading: Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(10)),
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
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy, fontSize: 13),
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
              style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 10.5)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
