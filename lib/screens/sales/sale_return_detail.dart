import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/screens/sales/sale_detail.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SaleReturnDetailScreen extends StatefulWidget {
  final int returnId;
  const SaleReturnDetailScreen({super.key, required this.returnId});

  @override
  State<SaleReturnDetailScreen> createState() => _SaleReturnDetailScreenState();
}

class _SaleReturnDetailScreenState extends State<SaleReturnDetailScreen> {
  Map<String, dynamic>? _return;
  bool _loading = true;
  bool _changed = false;

  // Derived amounts
  double _subtotal = 0, _tax = 0, _total = 0, _refunded = 0, _remaining = 0;

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

    final refunds = (map['refunds'] as List?) ?? const [];
    _refunded = refunds.fold<double>(
      0.0,
      (sum, r) => sum + _toDouble((r as Map)['amount']),
    );
    _remaining = (_total - _refunded);
    if (_remaining < 0) _remaining = 0;
  }

  Future<void> _fetchDetail() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/sales/returns/${widget.returnId}",
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
        final map = (data['data'] as Map<String, dynamic>);
        _deriveMoney(map);
        setState(() {
          _return = map;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load return details")),
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

  Future<void> _approveReturn() async {
    // final decision = await showDialog<_RefundDecision>(
    //   context: context,
    //   builder: (_) => _RefundDialog(
    //     title: "Approve Return",
    //     maxAmount: _remaining.clamp(0.0, _toDouble(_return?['total'])),
    //     defaultAmount: _remaining > 0
    //         ? _remaining
    //         : _toDouble(_return?['total']),
    //   ),
    // );

    // if (decision == null) return;

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/sales/returns/${widget.returnId}/approve",
    );

    final body = <String, String>{};
    // if (decision.issueRefund && decision.amount > 0) {
    //   body.addAll({
    //     "refund[amount]": decision.amount.toStringAsFixed(2),
    //     "refund[method]": decision.method,
    //     if (decision.reference?.trim().isNotEmpty == true)
    //       "refund[reference]": decision.reference!.trim(),
    //     if (decision.date != null)
    //       "refund[refunded_at]": DateFormat(
    //         "yyyy-MM-dd",
    //       ).format(decision.date!),
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
      String msg = "Return approved";
      try {
        final data = jsonDecode(res.body);
        final refundedTotal = _toDouble(data['data']?['refunded_total']);
        final left = _toDouble(data['data']?['refundable_left']);
        // if (decision.issueRefund && decision.amount > 0) {
        //   msg =
        //       "Approved. Refunded ${_currency.format(decision.amount)} "
        //       "(Total refunded: ${_currency.format(refundedTotal)}, Left: ${_currency.format(left)})";
        // }
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      String message = "Failed to approve return";
      try {
        final data = jsonDecode(res.body);
        if (data is Map && data['message'] != null)
          message = data['message'].toString();
      } catch (_) {}
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _refundReturn() async {
    if (_remaining <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nothing left to refund.")));
      return;
    }

    final decision = await showDialog<_RefundDecision>(
      context: context,
      builder: (_) => _RefundDialog(
        title: "Refund Return",
        maxAmount: _remaining,
        defaultAmount: _remaining,
      ),
    );

    if (decision == null || !decision.issueRefund || decision.amount <= 0)
      return;

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final uri = Uri.parse(
      "${ApiClient.baseUrl}/sales/returns/${widget.returnId}/refund",
    );

    final body = <String, String>{
      "amount": decision.amount.toStringAsFixed(2),
      "method": decision.method,
      if (decision.reference?.trim().isNotEmpty == true)
        "reference": decision.reference!.trim(),
      if (decision.date != null)
        "refunded_at": DateFormat("yyyy-MM-dd").format(decision.date!),
    };

    final res = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
      body: body,
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      await _fetchDetail();
      String msg = "Refund posted";
      try {
        final data = jsonDecode(res.body);
        final refundedTotal = _toDouble(data['data']?['refunded_total']);
        final left = _toDouble(data['data']?['refundable_left']);
        msg =
            "Refunded ${_currency.format(decision.amount)} "
            "(Total refunded: ${_currency.format(refundedTotal)}, Left: ${_currency.format(left)})";
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      String message = "Failed to refund";
      try {
        final data = jsonDecode(res.body);
        if (data is Map && data['message'] != null)
          message = data['message'].toString();
      } catch (_) {}
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "approved":
        return Colors.green.shade600;
      case "pending":
        return Colors.orange.shade700;
      default:
        return Colors.red.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: "Return"),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_return == null) {
      return const Scaffold(
        appBar: _SimpleAppBar(title: "Return"),
        body: Center(child: Text("Failed to load return details")),
      );
    }

    final status = (_return!['status'] ?? '').toString();
    final sale = (_return!['sale'] as Map<String, dynamic>?);
    final items = (_return!['items'] as List?) ?? const [];
    final refunds = (_return!['refunds'] as List?) ?? const [];

    return PopScope(
      canPop: false, // intercept back (system, app bar, gestures)
      onPopInvoked: (didPop) {
        if (didPop) return; // already popped; don't pop again
        Navigator.pop(context, _changed); // return result to parent
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Return #${_return!['return_no']}"),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 8),
              // child: BranchIndicator(tappable: false),
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
                      DateFormat.yMMMd().add_jm().format(
                        DateTime.parse(_return!['created_at']),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Header card: invoice, customer, branch, link
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Invoice: ${sale?['invoice_no'] ?? '—'}",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Customer: ${sale?['customer'] != null ? "${sale!['customer']['first_name']} ${sale['customer']['last_name'] ?? ''}".trim() : "Walk-In"}",
                      ),
                      Text("Branch: ${sale?['branch']?['name'] ?? '—'}"),
                      if ((_return!['reason']?.toString().isNotEmpty ??
                          false)) ...[
                        const SizedBox(height: 8),
                        Text("Reason: ${_return!['reason']}"),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: sale == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SaleDetailScreen(
                                        saleId: sale['id'] as int,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.receipt_long),
                          label: const Text("View Sale Details"),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Money summary (Total / Refunded / Remaining)
                // Row(
                //   children: [
                //     Expanded(
                //       child: _KpiTile(
                //         title: "Total",
                //         value: _currency.format(_total),
                //         icon: Icons.summarize,
                //       ),
                //     ),
                //     const SizedBox(width: 8),
                //     Expanded(
                //       child: _KpiTile(
                //         title: "Refunded",
                //         value: _currency.format(_refunded),
                //         icon: Icons.payments,
                //       ),
                //     ),
                //     const SizedBox(width: 8),
                //     Expanded(
                //       child: _KpiTile(
                //         title: "Remaining",
                //         value: _currency.format(_remaining),
                //         icon: Icons.account_balance_wallet_outlined,
                //       ),
                //     ),
                //   ],
                // ),

                // const SizedBox(height: 20),

                // Items
                _SectionHeader(title: "Returned Items"),
                if (items.isEmpty)
                  _EmptyNote(text: "No items found for this return.")
                else
                  Column(
                    children: items.map((item) {
                      final qty =
                          (item['quantity'] as num?)?.toInt() ??
                          int.tryParse(item['quantity'].toString()) ??
                          0;
                      final price = _toDouble(item['price']);
                      final lineTotal = _toDouble(item['total']);
                      return _ListCard(
                        leading: _QtyBubble(qty: qty),
                        title: item['product']?['name'] ?? '—',
                        subtitle:
                            "SKU: ${item['product']?['sku'] ?? '—'} • Price: ${_currency.format(price)}",
                        trailing: Text(
                          _currency.format(lineTotal),
                          style: theme.textTheme.titleMedium,
                        ),
                      );
                    }).toList(),
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

                // Refunds history
                // _SectionHeader(title: "Refunds"),
                // if (refunds.isEmpty)
                //   _EmptyNote(text: "No refunds have been issued yet.")
                // else
                //   Column(
                //     children: refunds.map((r) {
                //       final amount = _toDouble(r['amount']);
                //       final method = (r['method'] ?? '—').toString();
                //       final ref = (r['reference'] ?? '').toString();
                //       final dateStr =
                //           (r['refunded_at'] ?? r['created_at'] ?? '')
                //               .toString();
                //       String when = "—";
                //       if (dateStr.isNotEmpty) {
                //         try {
                //           when = DateFormat.yMMMd().format(
                //             DateTime.parse(dateStr),
                //           );
                //         } catch (_) {}
                //       }
                //       return _ListCard(
                //         leading: const CircleAvatar(
                //           child: Icon(Icons.reply_all_rounded),
                //         ),
                //         title: _currency.format(amount),
                //         subtitle:
                //             "Method: $method${ref.isNotEmpty ? " • Ref: $ref" : ""}",
                //         trailing: Text(when),
                //       );
                //     }).toList(),
                //   ),

                // const SizedBox(height: 16),

                // Action buttons
                // if (status == "approved") ...[
                //   SizedBox(
                //     width: double.infinity,
                //     child: OutlinedButton.icon(
                //       onPressed: _remaining <= 0 ? null : _refundReturn,
                //       icon: const Icon(Icons.money_off),
                //       label: Text(
                //         _remaining <= 0 ? "Fully Refunded" : "Refund",
                //       ),
                //     ),
                //   ),
                // ],
                if (status == "pending") ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _approveReturn,
                      icon: const Icon(Icons.check),
                      label: const Text("Approve Return"),
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

/// ---------- Small UI building blocks ----------

class _SimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _SimpleAppBar({required this.title, super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title));
  }
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
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: padding, child: child),
    );
  }
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
  const _QtyBubble({required this.qty});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.blue.shade50,
      child: Text(
        qty.toString(),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
      ),
    );
  }
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

/// ---------- Refund dialog ----------

class _RefundDecision {
  final bool issueRefund;
  final double amount;
  final String method;
  final String? reference;
  final DateTime? date;
  _RefundDecision({
    required this.issueRefund,
    required this.amount,
    required this.method,
    this.reference,
    this.date,
  });
}

class _RefundDialog extends StatefulWidget {
  final String title;
  final double maxAmount;
  final double defaultAmount;
  const _RefundDialog({
    required this.title,
    required this.maxAmount,
    required this.defaultAmount,
  });

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  bool _issueRefund = true;
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
            value: _issueRefund,
            onChanged: (v) => setState(() => _issueRefund = v),
            title: const Text("Issue refund now"),
          ),
          if (_issueRefund) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    "Refund Amount (max ${widget.maxAmount.toStringAsFixed(2)})",
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
                DropdownMenuItem(value: "card", child: Text("Card")),
                DropdownMenuItem(value: "bank", child: Text("Bank")),
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
            if (!_issueRefund) {
              Navigator.pop(
                context,
                _RefundDecision(issueRefund: false, amount: 0, method: 'cash'),
              );
              return;
            }
            final amt = _toDouble(_amountCtrl.text);
            if (amt <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Enter a valid refund amount")),
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
              _RefundDecision(
                issueRefund: true,
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
