import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/purchases/purchase_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class PurchaseClaimDetailScreen extends StatefulWidget {
  final int claimId;
  const PurchaseClaimDetailScreen({super.key, required this.claimId});

  @override
  State<PurchaseClaimDetailScreen> createState() =>
      _PurchaseClaimDetailScreenState();
}

class _PurchaseClaimDetailScreenState extends State<PurchaseClaimDetailScreen> {
  Map<String, dynamic>? _claim;
  bool _loading = true;
  bool _changed = false;

  // Derived amounts
  double _subtotal = 0, _tax = 0, _total = 0, _received = 0, _left = 0;

  final _currency = NumberFormat.simpleCurrency(decimalDigits: 2, name: "");

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  void _deriveMoney(Map<String, dynamic> map) {
    _subtotal = _toDouble(map['subtotal']);
    _tax = _toDouble(map['tax']);
    _total = _toDouble(map['total']);

    // Prefer server-provided totals if available
    final serverReceived = _toDouble(map['received_total']);
    final serverLeft = _toDouble(map['receivable_left']);

    if (serverReceived > 0 || serverLeft > 0) {
      _received = serverReceived;
      _left = serverLeft;
      // sanity fallback if only received_total provided
      if (_left <= 0) _left = (_total - _received).clamp(0, double.infinity);
      return;
    }

    // Otherwise sum receipts array
    final receipts = (map['receipts'] as List?) ?? const [];
    _received = receipts.fold<double>(
      0.0,
      (sum, r) => sum + _toDouble((r as Map)['amount']),
    );
    _left = (_total - _received);
    if (_left < 0) _left = 0;
  }

  Future<void> _fetchDetail() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/purchase-claims/${widget.claimId}",
    );

    try {
      final res = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // The API might send either { data: { claim, received_total, receivable_left } } or just the claim
        final raw = data['data'];
        Map<String, dynamic> map;
        if (raw is Map && raw['claim'] is Map) {
          map = (raw['claim'] as Map<String, dynamic>);
          // copy computed fields onto map so UI can use one source
          map['received_total'] = raw['received_total'];
          map['receivable_left'] = raw['receivable_left'];
        } else {
          map = (raw as Map<String, dynamic>);
        }

        _deriveMoney(map);
        setState(() {
          _claim = map;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load claim details")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _approveClaim() async {
    // Optional "receive now" dialog on approval
    // final decision = await showDialog<_ReceiptDecision>(
    //   context: context,
    //   builder: (_) => _ReceiptDialog(
    //     title: "Approve Claim",
    //     maxAmount: _left.clamp(0.0, _toDouble(_claim?['total'])),
    //     defaultAmount: _left > 0 ? _left : _toDouble(_claim?['total']),
    //   ),
    // );

    // if (decision == null) return;

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/purchase-claims/${widget.claimId}/approve",
    );

    final body = <String, String>{};
    // if (decision.receiveNow && decision.amount > 0) {
    //   body.addAll({
    //     "receipt[amount]": decision.amount.toStringAsFixed(2),
    //     "receipt[method]": decision.method,
    //     if (decision.reference?.trim().isNotEmpty == true) "receipt[reference]": decision.reference!.trim(),
    //     if (decision.date != null) "receipt[received_at]": DateFormat("yyyy-MM-dd").format(decision.date!),
    //   });
    // }

    final res = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      body: body.isEmpty ? null : body,
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      _changed = true;
      await _fetchDetail();
      String msg = "Claim approved";
      try {
        final data = jsonDecode(res.body);
        final receivedTotal = _toDouble(data['data']?['received_total']);
        final left = _toDouble(data['data']?['receivable_left']);
        // if (decision.receiveNow && decision.amount > 0) {
        //   msg = "Approved. Received ${_currency.format(decision.amount)} "
        //       "(Total received: ${_currency.format(receivedTotal)}, Left: ${_currency.format(left)})";
        // }
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      String msg = "Failed to approve claim";
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) msg = body['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _postReceipt() async {
    if (_left <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nothing left to receive.")));
      return;
    }

    final decision = await showDialog<_ReceiptDecision>(
      context: context,
      builder: (_) => _ReceiptDialog(
        title: "Record Receipt",
        maxAmount: _left,
        defaultAmount: _left,
      ),
    );

    if (decision == null || !decision.receiveNow || decision.amount <= 0)
      return;

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/purchase-claims/${widget.claimId}/receipt",
    );

    final body = <String, String>{
      "amount": decision.amount.toStringAsFixed(2),
      "method": decision.method,
      if (decision.reference?.trim().isNotEmpty == true)
        "reference": decision.reference!.trim(),
      if (decision.date != null)
        "received_at": DateFormat("yyyy-MM-dd").format(decision.date!),
    };

    final res = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      body: body,
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      _changed = true;
      await _fetchDetail();
      String msg = "Receipt posted";
      try {
        final data = jsonDecode(res.body);
        final receivedTotal = _toDouble(data['data']?['received_total']);
        final left = _toDouble(data['data']?['receivable_left']);
        msg =
            "Received ${_currency.format(decision.amount)} "
            "(Total received: ${_currency.format(receivedTotal)}, Left: ${_currency.format(left)})";
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      String msg = "Failed to post receipt";
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) msg = body['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _rejectClaim({String? reason}) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/purchase-claims/${widget.claimId}/reject",
    );

    final res = await http.post(
      uri,
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
        if (reason != null && reason.trim().isNotEmpty)
          "Content-Type": "application/json",
      },
      body: (reason != null && reason.trim().isNotEmpty)
          ? jsonEncode({"reason": reason.trim()})
          : null,
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      _changed = true;
      await _fetchDetail();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Claim rejected")));
    } else {
      String msg = "Failed to reject claim";
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] is String) msg = body['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmRejectDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reject Claim"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Optional reason...",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _rejectClaim(reason: controller.text);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "approved":
        return Colors.green.shade600;
      case "pending":
        return Colors.orange.shade700;
      case "rejected":
        return Colors.red.shade600;
      case "closed":
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: "Claim"),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_claim == null) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: "Claim"),
        body: Center(child: Text("Failed to load claim details")),
      );
    }

    final status = (_claim!['status'] ?? '').toString();
    final purchase = (_claim!['purchase'] as Map<String, dynamic>?);
    final items = (_claim!['items'] as List?) ?? const [];
    final receipts = (_claim!['receipts'] as List?) ?? const [];
    final createdAt = _claim!['created_at'];
    final created = createdAt != null ? DateTime.tryParse(createdAt) : null;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Claim #${_claim!['claim_no']}"),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: BranchIndicator(tappable: false),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _fetchDetail,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Status & date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(
                      label: Text(
                        status.toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: _statusColor(status),
                    ),
                    Text(
                      created != null
                          ? DateFormat.yMMMd().add_jm().format(created)
                          : '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Header card
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Invoice: ${purchase?['invoice_no'] ?? 'N/A'}",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Vendor: ${purchase?['vendor']?['name'] ?? purchase?['vendor']?['first_name'] ?? 'N/A'}",
                      ),
                      Text("Branch: ${_claim?['branch']?['name'] ?? 'N/A'}"),
                      Text("Type: ${_claim!['type'] ?? 'N/A'}"),
                      if ((_claim!['reason'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text("Reason: ${_claim!['reason']}"),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: purchase == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PurchaseDetailScreen(
                                        purchaseId: purchase['id'] as int,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.receipt_long),
                          label: const Text("View Purchase Details"),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // KPI summary: Total / Received / Left
                // Row(
                //   children: [
                //     Expanded(child: _KpiTile(title: "Total", value: _currency.format(_total), icon: Icons.summarize)),
                //     const SizedBox(width: 8),
                //     Expanded(child: _KpiTile(title: "Received", value: _currency.format(_received), icon: Icons.download)),
                //     const SizedBox(width: 8),
                //     Expanded(child: _KpiTile(title: "Left", value: _currency.format(_left), icon: Icons.account_balance_wallet_outlined)),
                //   ],
                // ),
                const SizedBox(height: 20),

                // Items
                _SectionHeader(title: "Claimed Items"),
                if (items.isEmpty)
                  const _EmptyNote(text: "No items found for this claim.")
                else
                  _SectionCard(
                    padding: EdgeInsets.zero,
                    child: _ItemsTable(
                      items: items.cast<Map<String, dynamic>>(),
                      currency: _currency,
                    ),
                  ),
                const SizedBox(height: 20),

                // Summary (Subtotal / Tax / Total)
                Align(
                  alignment: Alignment.centerRight,
                  child: _SectionCard(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _RowPrice(
                          label: "Subtotal",
                          value: _currency.format(_subtotal),
                        ),
                        _RowPrice(label: "Tax", value: _currency.format(_tax)),
                        const Divider(height: 14),
                        _RowPrice(
                          label: "Total",
                          value: _currency.format(_total),
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Receipts
                // _SectionHeader(title: "Receipts"),
                // if (receipts.isEmpty)
                //   const _EmptyNote(text: "No receipts posted yet.")
                // else
                //   Column(
                //     children: receipts.map((r) {
                //       final amount = _toDouble(r['amount']);
                //       final method = (r['method'] ?? '—').toString();
                //       final ref = (r['reference'] ?? '').toString();
                //       final dateStr = (r['received_at'] ?? r['created_at'] ?? '').toString();
                //       String when = "—";
                //       if (dateStr.isNotEmpty) {
                //         try { when = DateFormat.yMMMd().format(DateTime.parse(dateStr)); } catch (_) {}
                //       }
                //       return _ListCard(
                //         leading: const CircleAvatar(child: Icon(Icons.download_done)),
                //         title: _currency.format(amount),
                //         subtitle: "Method: $method${ref.isNotEmpty ? " • Ref: $ref" : ""}",
                //         trailing: Text(when),
                //       );
                //     }).toList(),
                //   ),
                const SizedBox(height: 16),

                // Actions
                // if (status == "approved") ...[
                //   SizedBox(
                //     width: double.infinity,
                //     child: OutlinedButton.icon(
                //       onPressed: _left <= 0 ? null : _postReceipt,
                //       icon: const Icon(Icons.attach_money),
                //       label: Text(_left <= 0 ? "Fully Received" : "Record Receipt"),
                //     ),
                //   ),
                // ],
                if (status == "pending") ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _approveClaim,
                          icon: const Icon(Icons.check),
                          label: const Text("Approve"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _confirmRejectDialog,
                          icon: const Icon(Icons.cancel),
                          label: const Text("Reject"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemsTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final NumberFormat currency;

  const _ItemsTable({required this.items, required this.currency});

  double _toD(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _fmtQty(num q) {
    // show 0 decimals when whole number, else up to 3
    final d = q.toDouble();
    if (d % 1 == 0) return NumberFormat('#,##0').format(d);
    return NumberFormat('#,##0.###').format(d);
  }

  Widget _right(String s, {FontWeight? weight}) => Align(
    alignment: Alignment.centerRight,
    child: Text(s, style: TextStyle(fontWeight: weight)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rows = items.map((item) {
      final prod = (item['product'] ?? {}) as Map;
      final name = (prod['name'] ?? 'Product').toString();
      final sku = (prod['sku'] ?? '-').toString();
      final price = _toD(item['price']);
      final discount = _toD(item['discount']);
      final qty = _toD(item['quantity']);
      final total = _toD(item['total']);

      final batch = (item['batch_no'] ?? '').toString();
      final expiry = (item['expiry_date'] ?? '').toString();
      final remarks = (item['remarks'] ?? '').toString();
      final notes = [
        if (batch.isNotEmpty) "Batch: $batch",
        if (expiry.isNotEmpty) "Exp: $expiry",
        if (remarks.isNotEmpty) remarks,
      ].join(" • ");

      return DataRow(
        cells: [
          DataCell(
            SizedBox(
              width: 260, // keeps product cell tidy
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "SKU: $sku",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DataCell(_right(currency.format(price))),
          DataCell(_right(currency.format(discount))),
          DataCell(_right(_fmtQty(qty))),
          DataCell(_right(currency.format(total), weight: FontWeight.w600)),
          DataCell(
            SizedBox(
              width: 320,
              child: Text(
                notes.isEmpty ? '—' : notes,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          columns: const [
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('Price'), numeric: true),
            DataColumn(label: Text('Discount'), numeric: true),
            DataColumn(label: Text('Qty'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Notes')),
          ],
          rows: rows,
          // Subtle, professional density
          dataRowMinHeight: 44,
          dataRowMaxHeight: 60,
          dividerThickness: 0.6,
        ),
      ),
    );
  }
}

/// ---------- Small UI building blocks ----------

class _SimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _SimpleAppBar({required this.title, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(title: Text(title));
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Expanded(child: Divider(indent: 12)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Card(
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(padding: padding, child: child),
  );
}

class _ListCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _ListCard({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing,
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _KpiTile({
    required this.title,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          CircleAvatar(radius: 18, child: Icon(icon, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyBubble extends StatelessWidget {
  final int qty;
  final Color color;
  const _QtyBubble({required this.qty, this.color = Colors.blue});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: color.withOpacity(0.1),
    child: Text(
      qty.toString(),
      style: TextStyle(fontWeight: FontWeight.bold, color: color),
    ),
  );
}

class _RowPrice extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  const _RowPrice({
    required this.label,
    required this.value,
    this.isBold = false,
  });
  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)
        : const TextStyle(fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const _EmptyNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          children: [
            CircleAvatar(radius: 18, child: Icon(icon, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- Receipt dialog ----------

class _ReceiptDecision {
  final bool receiveNow;
  final double amount;
  final String method;
  final String? reference;
  final DateTime? date;
  _ReceiptDecision({
    required this.receiveNow,
    required this.amount,
    required this.method,
    this.reference,
    this.date,
  });
}

class _ReceiptDialog extends StatefulWidget {
  final String title;
  final double maxAmount;
  final double defaultAmount;
  const _ReceiptDialog({
    required this.title,
    required this.maxAmount,
    required this.defaultAmount,
  });

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  bool _receiveNow = true;
  late final TextEditingController _amountCtrl;
  final _refCtrl = TextEditingController();
  String _method = 'cash';
  DateTime? _pickedDate;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.defaultAmount.toStringAsFixed(2),
    );
  }

  double _toDouble(String s) => double.tryParse(s.trim()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            value: _receiveNow,
            onChanged: (v) => setState(() => _receiveNow = v),
            title: const Text("Record receipt now"),
          ),
          if (_receiveNow) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    "Receipt Amount (max ${widget.maxAmount.toStringAsFixed(2)})",
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(
                labelText: "Method",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: "cash", child: Text("Cash")),
                DropdownMenuItem(value: "bank", child: Text("Bank")),
                DropdownMenuItem(
                  value: "credit_note",
                  child: Text("Credit Note"),
                ),
                DropdownMenuItem(value: "wallet", child: Text("Wallet")),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'cash'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: "Reference (optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _pickedDate == null
                          ? "Pick Date"
                          : DateFormat.yMMMd().format(_pickedDate!),
                    ),
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _pickedDate ?? now,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (d != null) setState(() => _pickedDate = d);
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text("Confirm"),
          onPressed: () {
            if (!_receiveNow) {
              Navigator.pop(
                context,
                _ReceiptDecision(receiveNow: false, amount: 0, method: 'cash'),
              );
              return;
            }
            final amt = _toDouble(_amountCtrl.text);
            if (amt <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Enter a valid receipt amount")),
              );
              return;
            }
            if (amt > widget.maxAmount + 0.0001) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Amount cannot exceed ${widget.maxAmount.toStringAsFixed(2)}",
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _ReceiptDecision(
                receiveNow: true,
                amount: amt,
                method: _method,
                reference: _refCtrl.text,
                date: _pickedDate,
              ),
            );
          },
        ),
      ],
    );
  }
}
