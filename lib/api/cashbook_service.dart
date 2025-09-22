import 'package:enterprise_pos/api/core/api_client.dart';

class CashBookService {
  final ApiClient _client;

  CashBookService({required String token}) : _client = ApiClient(token: token);

  /// GET /cashbook (paginated, with professional filters)
  ///
  /// Returns the full ApiResponse-style map:
  /// {
  ///   "success": true,
  ///   "data": {
  ///     opening_balance, inflow, outflow, net_change, closing_balance,
  ///     page_inflow, page_outflow, transactions: [...],
  ///     pagination: { total, per_page, current_page, last_page }
  ///   }
  /// }
  Future<Map<String, dynamic>> getCashBook({
    int page = 1,
    int perPage = 50,
    String status = "approved",
    String? accountId,
    String? branchId,
    String? dateFrom, // "YYYY-MM-DD"
    String? dateTo,   // "YYYY-MM-DD"
    String? source,   // sales|purchases
    String? type,     // receipt|payment|expense|transfer_in|transfer_out
    String? method,   // cash|card|bank|wallet...
    String? amountMin,
    String? amountMax,
    String? search,
  }) async {
    final q = <String, String>{
      "page": page.toString(),
      "per_page": perPage.toString(),
      "status": status,
      if (accountId != null && accountId.isNotEmpty) "account_id": accountId,
      if (branchId != null && branchId.isNotEmpty) "branch_id": branchId,
      if (dateFrom != null && dateFrom.isNotEmpty) "date_from": dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) "date_to": dateTo,
      if (source != null && source.isNotEmpty) "source": source,
      if (type != null && type.isNotEmpty) "type": type,
      if (method != null && method.isNotEmpty) "method": method,
      if (amountMin != null && amountMin.isNotEmpty) "amount_min": amountMin,
      if (amountMax != null && amountMax.isNotEmpty) "amount_max": amountMax,
      if (search != null && search.isNotEmpty) "search": search,
    };

    final res = await _client.get("/cashbook", query: q);
    if (res["success"] == true) {
      return res;
    }
    throw Exception(res["message"] ?? "Failed to load cash book");
  }

  /// POST /cashbook/expense
  /// Body may include either account_id OR method (recommended: method only)
  ///
  /// Returns { success: true, data: <transaction> }
  Future<Map<String, dynamic>> createExpense({
    String? accountId,
    String? method, // e.g., "cash"
    required String amount, // stringified decimal
    String? txnDate, // YYYY-MM-DD
    String? branchId,
    String? reference,
    String? note,
    String status = "approved",
    String? counterpartyType,
    String? counterpartyId,
  }) async {
    final body = <String, String>{
      if (accountId != null && accountId.isNotEmpty) "account_id": accountId,
      if ((accountId == null || accountId.isEmpty) && method != null && method.isNotEmpty) "method": method,
      "amount": amount,
      if (txnDate != null && txnDate.isNotEmpty) "txn_date": txnDate,
      if (branchId != null && branchId.isNotEmpty) "branch_id": branchId,
      if (reference != null && reference.isNotEmpty) "reference": reference,
      if (note != null && note.isNotEmpty) "note": note,
      if (status.isNotEmpty) "status": status,
      if (counterpartyType != null && counterpartyType.isNotEmpty) "counterparty_type": counterpartyType,
      if (counterpartyId != null && counterpartyId.isNotEmpty) "counterparty_id": counterpartyId,
    };

    final res = await _client.post("/cashbook/expense", body: body);
    if (res["success"] == true) {
      return res["data"];
    }
    throw Exception(res["message"] ?? "Failed to create expense");
  }

  /// OPTIONAL helper if you expose /accounts
  /// Expecting: GET /accounts?is_active=1 -> { success:true, data: [ {id,name,code}, ... ] }
  Future<List<Map<String, dynamic>>> getAccounts({bool isActive = true}) async {
    final res = await _client.get("/accounts", query: {
      if (isActive) "is_active": "1",
    });
    if (res["success"] == true) {
      final list = (res["data"] as List?) ?? const [];
      return list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }
}
