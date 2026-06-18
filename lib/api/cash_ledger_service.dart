import 'package:enterprise_pos/api/core/api_client.dart';

/// Talks to the backend Non-Sales Cash Ledger module
/// (Qameti, personal/party loans, other cash movements).
///
/// Mirrors the conventions of [CashBookService]: constructed with a bearer
/// token, methods return decoded maps and throw on a non-success envelope.
class CashLedgerService {
  final ApiClient _client;

  CashLedgerService({required String token}) : _client = ApiClient(token: token);

  /// POST /cash-ledger
  ///
  /// [category] is one of the backend enum values:
  ///   QAMETI_PAYMENT | QAMETI_COLLECTION | LOAN_GIVEN | LOAN_RECOVERED | OTHER_EXPENSE
  /// [partyKind] is the friendly alias the backend maps to a model:
  ///   'customer' | 'vendor' | 'user'  (null when unlinked)
  /// When no party is linked, [referenceName] is required by the backend.
  Future<Map<String, dynamic>> createEntry({
    required String category,
    required String amount, // stringified decimal, e.g. "1500.00"
    String? txnDate, // YYYY-MM-DD
    String method = 'cash', // cash|bank|card|wallet
    String? partyKind, // customer|vendor|user
    String? partyId,
    String? referenceName,
    String? note,
    String? expenseAccountCode, // OTHER_EXPENSE override only
    bool allowNegativeCash = false,
  }) async {
    final body = <String, Object?>{
      'category': category,
      'amount': amount,
      'method': method,
      if (txnDate != null && txnDate.isNotEmpty) 'txn_date': txnDate,
      if (partyKind != null && partyKind.isNotEmpty) 'party_type': partyKind,
      if (partyId != null && partyId.isNotEmpty) 'party_id': partyId,
      if (referenceName != null && referenceName.trim().isNotEmpty)
        'reference_name': referenceName.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (expenseAccountCode != null && expenseAccountCode.isNotEmpty)
        'expense_account_code': expenseAccountCode,
      if (allowNegativeCash) 'allow_negative_cash': true,
    };

    final res = await _client.post('/cash-ledger', body: body);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to record cash ledger entry');
  }

  /// GET /cash-ledger (paginated history of MODULE entries only)
  ///
  /// Returns: { items: [...], total, per_page, current_page, last_page }
  Future<Map<String, dynamic>> getEntries({
    int page = 1,
    int perPage = 20,
    String? category,
    String? partyKind, // customer|vendor|user
    String? partyId,
    String? from, // YYYY-MM-DD
    String? to, // YYYY-MM-DD
    String? status, // posted|void
  }) async {
    final q = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (category != null && category.isNotEmpty) 'category': category,
      if (partyKind != null && partyKind.isNotEmpty) 'party_type': partyKind,
      if (partyId != null && partyId.isNotEmpty) 'party_id': partyId,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (status != null && status.isNotEmpty) 'status': status,
    };

    final res = await _client.get('/cash-ledger', query: q);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load cash ledger');
  }

  /// GET /cash-ledger/{id}
  Future<Map<String, dynamic>> getEntry(String id) async {
    final res = await _client.get('/cash-ledger/$id');
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load entry');
  }

  /// POST /cash-ledger/{id}/void  (writes a reversing journal entry)
  Future<Map<String, dynamic>> voidEntry(String id) async {
    final res = await _client.post('/cash-ledger/$id/void');
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to void entry');
  }

  /// GET /cash-ledger/transactions  (paginated UNIFIED ledger: all cash movements)
  ///
  /// Includes customer receipts, vendor payments, expenses, Qameti, loans, etc.
  /// Params:
  ///   direction: 'in'|'out'|'all'
  ///   kind: 'all'|'module'|'received'|'sent'|'expense'
  ///   category: one of the module enum values
  ///   search: free-text party/memo search
  Future<Map<String, dynamic>> getTransactions({
    int page = 1,
    int perPage = 20,
    String? from,
    String? to,
    String direction = 'all',
    String kind = 'all',
    String? category,
    String? search,
  }) async {
    final q = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (direction != 'all') 'direction': direction,
      if (kind != 'all') 'kind': kind,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final res = await _client.get('/cash-ledger/transactions', query: q);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load transactions');
  }

  /// GET /cash-ledger/cash-flow  (unified summary)
  ///
  /// Returns: { filters, summary: { opening, incoming{...,total},
  ///            outgoing{...,total}, net_movement, closing } }
  Future<Map<String, dynamic>> getCashFlow({
    String? from,
    String? to,
  }) async {
    final q = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };

    final res = await _client.get('/cash-ledger/cash-flow', query: q);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load cash flow');
  }

  /// GET /daybook  (day-by-day opening/in/out/net/closing over the SAME
  /// unified ledger as getTransactions/getCashFlow — not a separate system).
  ///
  /// Returns: { opening, totals{in,out,net,closing}, page_totals{in,out,net},
  ///            days: [ {date, opening, in, out, net, closing, transaction_count} ],
  ///            pagination, order }
  Future<Map<String, dynamic>> getDayBook({
    String? from,
    String? to,
    int page = 1,
    int perPage = 30,
    String order = 'desc',
  }) async {
    final q = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      'page': page.toString(),
      'per_page': perPage.toString(),
      'order': order,
    };

    final res = await _client.get('/daybook', query: q);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load day book');
  }

  /// GET /daybook/day-details  (every cash movement for ONE day, labelled
  /// exactly like getTransactions — same row shape, same party resolution).
  ///
  /// Returns: { date, opening, closing, totals{in,out,net}, items: [...], pagination }
  Future<Map<String, dynamic>> getDayBookDetails({
    required String date, // YYYY-MM-DD
    String direction = 'all', // in|out|all
    String kind = 'all', // all|module|received|sent|expense
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final q = <String, String>{
      'date': date,
      if (direction != 'all') 'direction': direction,
      if (kind != 'all') 'kind': kind,
      if (search != null && search.isNotEmpty) 'search': search,
      'page': page.toString(),
      'per_page': perPage.toString(),
    };

    final res = await _client.get('/daybook/day-details', query: q);
    if (res['success'] == true) return Map<String, dynamic>.from(res['data'] ?? {});
    throw Exception(res['message'] ?? 'Failed to load day details');
  }
}
