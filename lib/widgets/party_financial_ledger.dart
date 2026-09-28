import 'dart:math' as math;

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/services/report_file_saver.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/report_pdf_export_dialog.dart';
import 'package:flutter/material.dart';


typedef PartyLedgerPageLoader = Future<Map<String, dynamic>> Function({
  required int page,
  required int perPage,
  String? from,
  String? to,
  bool latest,
});

typedef PartyLedgerExporter = Future<ApiDownloadResponse> Function({
  required String format,
  String? from,
  String? to,
  String orientation,
  String paperSize,
});

class PartyTradeLedgerView extends StatefulWidget {
  const PartyTradeLedgerView({
    super.key,
    required this.partyLabel,
    required this.loadPage,
    required this.exportLedger,
    required this.money,
    required this.toDouble,
    this.canReversePayments = false,
    this.reversingPaymentId,
    this.onReversePayment,
  });

  final String partyLabel;
  final PartyLedgerPageLoader loadPage;
  final PartyLedgerExporter exportLedger;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;
  final bool canReversePayments;
  final int? reversingPaymentId;
  final Future<void> Function(Map<String, dynamic>)? onReversePayment;

  @override
  State<PartyTradeLedgerView> createState() => _PartyTradeLedgerViewState();
}

class _PartyTradeLedgerViewState extends State<PartyTradeLedgerView> {
  static const int _requestedPageSize = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 54;
  final ScrollController _scroll = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  int _requestGeneration = 0;
  DateTime? _from;
  DateTime? _to;
  int _perPage = _requestedPageSize;
  int _total = 0;
  int _lastPage = 1;
  int _currentPage = 1;
  double _opening = 0;
  Map<String, dynamic> _summary = const {};
  bool _loading = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(1, latest: true, reset: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  String? get _fromText => _from == null ? null : _date(_from!);
  String? get _toText => _to == null ? null : _date(_to!);
  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load(int page, {bool latest = false, bool reset = false}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (reset) {
      _pages.clear();
      _loadingPages.clear();
      _total = 0;
      _lastPage = 1;
      _currentPage = 1;
      _error = null;
    }
    if (_loadingPages.contains(page) || page < 1 || (_total > 0 && page > _lastPage)) return;
    _loadingPages.add(page);
    if (mounted && _pages.isEmpty) setState(() => _loading = true);
    try {
      final res = await widget.loadPage(page: page, perPage: _requestedPageSize, from: _fromText, to: _toText, latest: latest);
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _perPage = math.max(1, (wrap['per_page'] as num?)?.toInt() ?? _requestedPageSize).toInt();
        _total = (wrap['total'] as num?)?.toInt() ?? items.length;
        _lastPage = math.max(1, (wrap['last_page'] as num?)?.toInt() ?? 1).toInt();
        _currentPage = math.max(1, (wrap['current_page'] as num?)?.toInt() ?? page).toInt();
        _opening = widget.toDouble(wrap['opening']);
        _summary = ((wrap['summary'] as Map?) ?? const {}).cast<String, dynamic>();
        _pages[_currentPage] = items;
        _error = null;
        _evict(_currentPage);
      });
      if (reset && latest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients || _total <= 0) return;
          final firstIndex = (_currentPage - 1) * _perPage;
          final target = firstIndex * _rowExtent;
          _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load trade ledger: $e');
    } finally {
      _loadingPages.remove(page);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _total <= 0) return;
    final first = (_scroll.offset / _rowExtent).floor().clamp(0, _total - 1).toInt();
    final visible = (_scroll.position.viewportDimension / _rowExtent).ceil() + 6;
    final last = math.min(_total - 1, first + visible).toInt();
    final firstPage = first ~/ _perPage + 1;
    final lastPage = last ~/ _perPage + 1;
    for (var p = firstPage; p <= lastPage; p++) {
      if (!_pages.containsKey(p)) _load(p);
    }
    if (lastPage < _lastPage && !_pages.containsKey(lastPage + 1)) _load(lastPage + 1);
    if (firstPage > 1 && !_pages.containsKey(firstPage - 1)) _load(firstPage - 1);
  }

  Map<String, dynamic>? _itemAt(int index) {
    final page = index ~/ _perPage + 1;
    final offset = index % _perPage;
    final rows = _pages[page];
    if (rows == null) {
      _load(page);
      return null;
    }
    return offset < rows.length ? rows[offset] : null;
  }

  void _evict(int keepPage) {
    if (_pages.length <= _maxCachedPages) return;
    final keys = _pages.keys.toList()..sort((a, b) => (b - keepPage).abs().compareTo((a - keepPage).abs()));
    while (_pages.length > _maxCachedPages && keys.isNotEmpty) {
      _pages.remove(keys.removeAt(0));
    }
  }

  Future<void> _pickDate(bool from) async {
    final current = from ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final value = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (value == null || !mounted) return;
    setState(() {
      if (from) {
        _from = value;
        if (_to != null && _to!.isBefore(value)) _to = value;
      } else {
        _to = value;
        if (_from != null && _from!.isAfter(value)) _from = value;
      }
    });
    await _load(1, latest: true, reset: true);
  }

  Future<void> _clearDates() async {
    setState(() { _from = null; _to = null; });
    await _load(1, latest: true, reset: true);
  }

  Future<void> _export(String format) async {
    ReportPdfExportOptions? pdf;
    if (format == 'pdf') {
      pdf = await showReportPdfExportDialog(context, reportTitle: '${widget.partyLabel} Trade Ledger');
      if (pdf == null || !mounted) return;
    }
    setState(() => _exporting = true);
    try {
      final file = await widget.exportLedger(format: format, from: _fromText, to: _toText, orientation: pdf?.orientation ?? 'auto', paperSize: pdf?.paperSize ?? 'a4');
      final path = await saveReportFile(bytes: file.bytes, filename: file.filename, mimeType: file.contentType);
      if (mounted) AppFeedback.success(context, 'Saved and opened: $path');
    } on ReportSaveCancelledException {
      // User cancelled save dialog.
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debit = widget.toDouble(_summary['period_debit']);
    final credit = widget.toDouble(_summary['period_credit']);
    final closing = widget.toDouble(_summary['closing']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        children: [
          _LedgerToolbar(from: _from, to: _to, onFrom: () => _pickDate(true), onTo: () => _pickDate(false), onClear: (_from == null && _to == null) ? null : _clearDates, onRefresh: () => _load(1, latest: true, reset: true), exporting: _exporting, onExcel: () => _export('xlsx'), onPdf: () => _export('pdf')),
          const SizedBox(height: 8),
          _LedgerKpis(items: [
            ('Opening', widget.money(_opening), Icons.flag_outlined, AppTheme.info),
            ('Period Debit', widget.money(debit), Icons.south_west_rounded, AppTheme.warning),
            ('Period Credit', widget.money(credit), Icons.north_east_rounded, AppTheme.success),
            ('Closing', widget.money(closing), Icons.account_balance_wallet_outlined, AppTheme.navy),
          ]),
          const SizedBox(height: 8),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_loading && _pages.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _pages.isEmpty) return _LedgerError(message: _error!, onRetry: () => _load(1, latest: true, reset: true));
    if (_total == 0) return const _LedgerEmpty(title: 'No trade ledger movement', subtitle: 'Sales/purchases and party payments will appear here.');
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(920.0, constraints.maxWidth).toDouble();
      return Scrollbar(
        controller: _horizontal,
        thumbVisibility: width > constraints.maxWidth,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Column(children: [
              const _TradeHeader(),
              Expanded(
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowExtent,
                    itemCount: _total,
                    cacheExtent: _rowExtent * 10,
                    itemBuilder: (_, index) {
                      final row = _itemAt(index);
                      if (row == null) return const _LedgerLoadingRow();
                      final debit = widget.toDouble(row['debit']);
                      final credit = widget.toDouble(row['credit']);
                      final paymentId = (row['payment_id'] as num?)?.toInt();
                      final canReverse = widget.canReversePayments && row['can_reverse'] == true && paymentId != null && widget.onReversePayment != null;
                      return _TradeRow(
                        row: row,
                        money: widget.money,
                        debit: debit,
                        credit: credit,
                        reversing: paymentId != null && widget.reversingPaymentId == paymentId,
                        canReverse: canReverse,
                        onReverse: canReverse ? () async { await widget.onReversePayment!(row); await _load(1, latest: true, reset: true); } : null,
                      );
                    },
                  ),
                ),
              ),
              _LedgerFooter(total: _total, cached: _pages.length, maxCached: _maxCachedPages),
            ]),
          ),
        ),
      );
    });
  }
}

class PartyLoanLedgerView extends StatefulWidget {
  const PartyLoanLedgerView({super.key, required this.partyLabel, required this.partyType, required this.loadPage, required this.exportLedger, required this.money, required this.toDouble});
  final String partyLabel;
  final String partyType;
  final PartyLedgerPageLoader loadPage;
  final PartyLedgerExporter exportLedger;
  final String Function(dynamic value) money;
  final double Function(dynamic value) toDouble;

  @override
  State<PartyLoanLedgerView> createState() => _PartyLoanLedgerViewState();
}

class _PartyLoanLedgerViewState extends State<PartyLoanLedgerView> {
  static const int _requestedPageSize = 40;
  static const int _maxCachedPages = 6;
  static const double _rowExtent = 54;
  final ScrollController _scroll = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final Map<int, List<Map<String, dynamic>>> _pages = {};
  final Set<int> _loadingPages = {};
  int _requestGeneration = 0;
  DateTime? _from;
  DateTime? _to;
  int _perPage = _requestedPageSize, _total = 0, _lastPage = 1, _currentPage = 1;
  double _opening = 0;
  Map<String, dynamic> _summary = const {};
  bool _loading = false, _exporting = false;
  String? _error;

  @override
  void initState() { super.initState(); _scroll.addListener(_onScroll); WidgetsBinding.instance.addPostFrameCallback((_) => _load(1, latest: true, reset: true)); }
  @override
  void dispose() { _scroll.dispose(); _horizontal.dispose(); super.dispose(); }
  String? get _fromText => _from == null ? null : _date(_from!);
  String? get _toText => _to == null ? null : _date(_to!);
  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load(int page, {bool latest = false, bool reset = false}) async {
    if (reset) ++_requestGeneration;
    final generation = _requestGeneration;
    if (reset) { _pages.clear(); _loadingPages.clear(); _total = 0; _lastPage = 1; _currentPage = 1; _error = null; }
    if (_loadingPages.contains(page) || page < 1 || (_total > 0 && page > _lastPage)) return;
    _loadingPages.add(page); if (mounted && _pages.isEmpty) setState(() => _loading = true);
    try {
      final res = await widget.loadPage(page: page, perPage: _requestedPageSize, from: _fromText, to: _toText, latest: latest);
      final wrap = (res['data'] as Map).cast<String, dynamic>();
      final items = ((wrap['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _perPage = math.max(1, (wrap['per_page'] as num?)?.toInt() ?? _requestedPageSize).toInt();
        _total = (wrap['total'] as num?)?.toInt() ?? items.length;
        _lastPage = math.max(1, (wrap['last_page'] as num?)?.toInt() ?? 1).toInt();
        _currentPage = math.max(1, (wrap['current_page'] as num?)?.toInt() ?? page).toInt();
        _opening = widget.toDouble(wrap['opening']);
        _summary = ((wrap['summary'] as Map?) ?? const {}).cast<String, dynamic>();
        _pages[_currentPage] = items; _error = null; _evict(_currentPage);
      });
      if (reset && latest) WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients && _total > 0) { final target = ((_currentPage - 1) * _perPage) * _rowExtent; _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble()); } });
    } catch (e) { if (mounted) setState(() => _error = 'Failed to load loan ledger: $e'); }
    finally { _loadingPages.remove(page); if (mounted) setState(() => _loading = false); }
  }
  void _onScroll() { if (!_scroll.hasClients || _total <= 0) return; final first = (_scroll.offset/_rowExtent).floor().clamp(0,_total-1).toInt(); final last = math.min(_total-1, first+(_scroll.position.viewportDimension/_rowExtent).ceil()+6).toInt(); final fp=first~/_perPage+1, lp=last~/_perPage+1; for(var p=fp;p<=lp;p++){if(!_pages.containsKey(p))_load(p);} if(lp<_lastPage&&!_pages.containsKey(lp+1))_load(lp+1); if(fp>1&&!_pages.containsKey(fp-1))_load(fp-1); }
  Map<String,dynamic>? _itemAt(int index){final p=index~/_perPage+1,o=index%_perPage;final rows=_pages[p];if(rows==null){_load(p);return null;}return o<rows.length?rows[o]:null;}
  void _evict(int keep){if(_pages.length<=_maxCachedPages)return;final keys=_pages.keys.toList()..sort((a,b)=>(b-keep).abs().compareTo((a-keep).abs()));while(_pages.length>_maxCachedPages&&keys.isNotEmpty){_pages.remove(keys.removeAt(0));}}
  Future<void> _pickDate(bool from) async {final current=from?(_from??DateTime.now()):(_to??DateTime.now());final value=await showDatePicker(context:context,initialDate:current,firstDate:DateTime(2000),lastDate:DateTime(2100));if(value==null||!mounted)return;setState((){if(from){_from=value;if(_to!=null&&_to!.isBefore(value))_to=value;}else{_to=value;if(_from!=null&&_from!.isAfter(value))_from=value;}});await _load(1,latest:true,reset:true);}
  Future<void> _clearDates() async {setState((){_from=null;_to=null;});await _load(1,latest:true,reset:true);}
  Future<void> _export(String format) async {ReportPdfExportOptions? pdf;if(format=='pdf'){pdf=await showReportPdfExportDialog(context,reportTitle:'${widget.partyLabel} Loan Ledger');if(pdf==null||!mounted)return;}setState(()=>_exporting=true);try{final file=await widget.exportLedger(format:format,from:_fromText,to:_toText,orientation:pdf?.orientation??'auto',paperSize:pdf?.paperSize??'a4');final path=await saveReportFile(bytes:file.bytes,filename:file.filename,mimeType:file.contentType);if(mounted)AppFeedback.success(context,'Saved and opened: $path');}on ReportSaveCancelledException{}catch(e){if(mounted)AppFeedback.error(context,'Export failed: $e');}finally{if(mounted)setState(()=>_exporting=false);}}

  @override
  Widget build(BuildContext context) {
    final given=widget.toDouble(_summary['loan_given']), recovered=widget.toDouble(_summary['loan_recovered']), closing=widget.toDouble(_summary['loan_balance']);
    return Padding(padding:const EdgeInsets.fromLTRB(16,10,16,14),child:Column(children:[
      _LedgerToolbar(from:_from,to:_to,onFrom:()=>_pickDate(true),onTo:()=>_pickDate(false),onClear:(_from==null&&_to==null)?null:_clearDates,onRefresh:()=>_load(1,latest:true,reset:true),exporting:_exporting,onExcel:()=>_export('xlsx'),onPdf:()=>_export('pdf')),
      const SizedBox(height:8),
      _LedgerKpis(items:[('Opening Loan',widget.money(_opening),Icons.flag_outlined,AppTheme.info),('Loan Given',widget.money(given),Icons.call_made_rounded,AppTheme.warning),('Recovered',widget.money(recovered),Icons.call_received_rounded,AppTheme.success),('Closing Loan',widget.money(closing),Icons.account_balance_wallet_outlined,closing<0?AppTheme.danger:AppTheme.navy)]),
      const SizedBox(height:6),
      Align(alignment:Alignment.centerLeft,child:Text(widget.partyType=='vendor'?'Vendor loans are tracked separately and do not affect the vendor trade payable balance.':'Customer loans are tracked separately and do not affect the customer trade receivable balance.',style:const TextStyle(fontSize:11,color:AppTheme.textMuted,fontWeight:FontWeight.w600))),
      const SizedBox(height:8), Expanded(child:_buildTable()),
    ]));
  }

  Widget _buildTable(){if(_loading&&_pages.isEmpty)return const Center(child:CircularProgressIndicator());if(_error!=null&&_pages.isEmpty)return _LedgerError(message:_error!,onRetry:()=>_load(1,latest:true,reset:true));if(_total==0)return const _LedgerEmpty(title:'No loan activity',subtitle:'Loan given and recovered entries will appear here.');return LayoutBuilder(builder:(context,constraints){final width=math.max(920.0,constraints.maxWidth).toDouble();return Scrollbar(controller:_horizontal,thumbVisibility:width>constraints.maxWidth,child:SingleChildScrollView(controller:_horizontal,scrollDirection:Axis.horizontal,child:SizedBox(width:width,height:constraints.maxHeight,child:Column(children:[const _LoanHeader(),Expanded(child:Scrollbar(controller:_scroll,thumbVisibility:true,child:ListView.builder(controller:_scroll,itemExtent:_rowExtent,itemCount:_total,cacheExtent:_rowExtent*10,itemBuilder:(_,i){final row=_itemAt(i);return row==null?const _LedgerLoadingRow():_LoanRow(row:row,money:widget.money);}))),_LedgerFooter(total:_total,cached:_pages.length,maxCached:_maxCachedPages)])))) ;});}
}

class _LedgerToolbar extends StatelessWidget {
  const _LedgerToolbar({required this.from,required this.to,required this.onFrom,required this.onTo,required this.onClear,required this.onRefresh,required this.exporting,required this.onExcel,required this.onPdf});
  final DateTime? from,to; final VoidCallback onFrom,onTo,onRefresh; final VoidCallback? onClear; final bool exporting; final VoidCallback onExcel,onPdf;
  String _fmt(DateTime? d)=>d==null?'All dates':'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12),border:Border.all(color:AppTheme.border)),child:Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
    OutlinedButton.icon(onPressed:onFrom,icon:const Icon(Icons.calendar_today_rounded,size:16),label:Text('From: ${_fmt(from)}')),
    OutlinedButton.icon(onPressed:onTo,icon:const Icon(Icons.event_rounded,size:16),label:Text('To: ${_fmt(to)}')),
    if(onClear!=null)TextButton.icon(onPressed:onClear,icon:const Icon(Icons.clear_rounded,size:16),label:const Text('All Dates')),
    IconButton(onPressed:onRefresh,tooltip:'Refresh',icon:const Icon(Icons.refresh_rounded,size:18)),
    const SizedBox(width:4),
    OutlinedButton.icon(onPressed:exporting?null:onExcel,icon:const Icon(Icons.table_chart_rounded,size:17),label:const Text('Excel')),
    OutlinedButton.icon(onPressed:exporting?null:onPdf,icon:const Icon(Icons.picture_as_pdf_rounded,size:17),label:const Text('PDF')),
    if(exporting)const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)),
  ]));
}

class _LedgerKpis extends StatelessWidget { const _LedgerKpis({required this.items}); final List<(String,String,IconData,Color)> items; @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,c){final w=(c.maxWidth-24)/4;return Wrap(spacing:8,runSpacing:8,children:[for(final x in items)Container(width:math.max(160.0,w).toDouble(),padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12),border:Border.all(color:AppTheme.border)),child:Row(children:[Icon(x.$3,size:17,color:x.$4),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(x.$1,style:const TextStyle(fontSize:10.5,color:AppTheme.textMuted,fontWeight:FontWeight.w700)),const SizedBox(height:2),Text(x.$2,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,color:AppTheme.navy,fontWeight:FontWeight.w900))]))]))]);}); }

class _TradeHeader extends StatelessWidget { const _TradeHeader(); @override Widget build(BuildContext context)=>const _HeaderRow(cells:[('Date',120),('Description',340),('Debit',120),('Credit',120),('Balance',130),('Actions',90)]); }
class _LoanHeader extends StatelessWidget { const _LoanHeader(); @override Widget build(BuildContext context)=>const _HeaderRow(cells:[('Date',120),('Reference',280),('Method',130),('Given',110),('Recovered',110),('Balance',130)]); }
class _HeaderRow extends StatelessWidget { const _HeaderRow({required this.cells}); final List<(String,double)> cells; @override Widget build(BuildContext context)=>Container(height:38,padding:const EdgeInsets.symmetric(horizontal:10),decoration:const BoxDecoration(color:AppTheme.surfaceSoft,border:Border(bottom:BorderSide(color:AppTheme.border))),child:Row(children:[for(final c in cells)SizedBox(width:c.$2,child:Text(c.$1,style:const TextStyle(fontSize:11,color:AppTheme.textMuted,fontWeight:FontWeight.w800))) ])); }
class _TradeRow extends StatelessWidget { const _TradeRow({required this.row,required this.money,required this.debit,required this.credit,required this.reversing,required this.canReverse,this.onReverse}); final Map<String,dynamic> row; final String Function(dynamic) money; final double debit,credit; final bool reversing,canReverse; final VoidCallback? onReverse; @override Widget build(BuildContext context){final status=(row['payment_status']??'posted').toString();return Container(padding:const EdgeInsets.symmetric(horizontal:10),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:AppTheme.border))),child:Row(children:[SizedBox(width:120,child:Text(_shortDate(row['date']),style:_cellStyle)),SizedBox(width:340,child:Text((row['description']??row['memo']??'—').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:_cellStyle)),SizedBox(width:120,child:Text(debit==0?'—':money(debit),style:_numStyle)),SizedBox(width:120,child:Text(credit==0?'—':money(credit),style:_numStyle)),SizedBox(width:130,child:Text(money(row['balance']),style:_boldNumStyle)),SizedBox(width:90,child:Row(children:[if(status!='posted')Tooltip(message:status,child:Icon(status=='reversal'?Icons.undo_rounded:Icons.history_rounded,size:16,color:AppTheme.textMuted)),if(canReverse||reversing)IconButton(tooltip:'Reverse payment',onPressed:reversing?null:onReverse,padding:EdgeInsets.zero,constraints:const BoxConstraints(minWidth:30,minHeight:30),icon:reversing?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.undo_rounded,size:17,color:AppTheme.danger))]))]));}}
class _LoanRow extends StatelessWidget { const _LoanRow({required this.row,required this.money}); final Map<String,dynamic> row; final String Function(dynamic) money; @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:10),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:AppTheme.border))),child:Row(children:[SizedBox(width:120,child:Text(_shortDate(row['date']),style:_cellStyle)),SizedBox(width:280,child:Text((row['reference']??'—').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:_cellStyle)),SizedBox(width:130,child:Text((row['method']??'—').toString(),style:_cellStyle)),SizedBox(width:110,child:Text(money(row['given']),style:_numStyle)),SizedBox(width:110,child:Text(money(row['recovered']),style:_numStyle)),SizedBox(width:130,child:Text(money(row['balance']),style:_boldNumStyle))])); }
class _LedgerLoadingRow extends StatelessWidget { const _LedgerLoadingRow(); @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:12),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:AppTheme.border))),alignment:Alignment.centerLeft,child:const SizedBox(width:140,child:LinearProgressIndicator(minHeight:2))); }
class _LedgerFooter extends StatelessWidget { const _LedgerFooter({required this.total,required this.cached,required this.maxCached}); final int total,cached,maxCached; @override Widget build(BuildContext context)=>Container(height:32,padding:const EdgeInsets.symmetric(horizontal:10),alignment:Alignment.centerLeft,decoration:const BoxDecoration(color:AppTheme.surfaceSoft,border:Border(top:BorderSide(color:AppTheme.border))),child:Text('$total entries • bounded cache $cached/$maxCached pages',style:const TextStyle(fontSize:10.5,color:AppTheme.textMuted,fontWeight:FontWeight.w700))); }
class _LedgerEmpty extends StatelessWidget { const _LedgerEmpty({required this.title,required this.subtitle}); final String title,subtitle; @override Widget build(BuildContext context)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.receipt_long_outlined,size:38,color:AppTheme.textMuted),const SizedBox(height:8),Text(title,style:const TextStyle(color:AppTheme.navy,fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(subtitle,style:const TextStyle(color:AppTheme.textMuted,fontSize:11.5))])); }
class _LedgerError extends StatelessWidget { const _LedgerError({required this.message,required this.onRetry}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text(message,textAlign:TextAlign.center,style:const TextStyle(color:AppTheme.danger)),const SizedBox(height:8),OutlinedButton.icon(onPressed:onRetry,icon:const Icon(Icons.refresh_rounded),label:const Text('Retry'))])); }

String _shortDate(dynamic value){final s=(value??'').toString();if(s.length>=10)return s.substring(0,10);return s.isEmpty?'—':s;}
const _cellStyle=TextStyle(fontSize:11.5,color:AppTheme.navy,fontWeight:FontWeight.w600);
const _numStyle=TextStyle(fontSize:11.5,color:AppTheme.navy,fontWeight:FontWeight.w700);
const _boldNumStyle=TextStyle(fontSize:11.5,color:AppTheme.navy,fontWeight:FontWeight.w900);
