import 'dart:convert';
import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/widgets/app_keyboard_shortcuts.dart';
import 'package:enterprise_pos/widgets/branch_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:enterprise_pos/services/app_currency.dart';

class CreatePurchaseClaimScreen extends StatefulWidget {
  const CreatePurchaseClaimScreen({super.key});

  @override
  State<CreatePurchaseClaimScreen> createState() =>
      _CreatePurchaseClaimScreenState();
}

class _CreatePurchaseClaimScreenState extends State<CreatePurchaseClaimScreen> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedPurchase;
  List<dynamic> _purchaseItems = [];

  // controllers per purchase_item_id
  final Map<int, TextEditingController> _qtyCtrls = {};
  final Map<int, TextEditingController> _remarksCtrls = {};
  final Map<int, TextEditingController> _batchCtrls = {};
  final Map<int, TextEditingController> _expiryCtrls = {};
  final Map<int, bool> _affectsStock = {};
  final Map<int, int?> _claimPackagingIds = {};

  final TextEditingController _reasonCtrl = TextEditingController();
  String _type = 'other'; // shortage|damaged|wrong_item|expired|other

  bool _submitting = false;

  // NEW: Approve + Receipt on create
  bool _approveNow = false;
  bool _receiveNow = false;
  final _receiptAmountCtrl = TextEditingController();
  String _receiptMethod = 'cash';
  final _receiptRefCtrl = TextEditingController();
  DateTime? _receiptDate;

  final _currency = const AppMoneyFormatter();

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  List<Map<String, dynamic>> _activePackagings(dynamic item) {
    final raw = item['packagings'];
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final p = Map<String, dynamic>.from(value);
      final id = int.tryParse(p['id']?.toString() ?? '');
      final factor = _toDouble(p['base_quantity']);
      final active = p['is_active'] == null ||
          p['is_active'] == true ||
          p['is_active'] == 1 ||
          p['is_active'].toString().toLowerCase() == 'true';
      if (id != null && id > 0 && factor > 0 && active) out.add(p);
    }
    out.sort((a, b) {
      final ao = int.tryParse(a['sort_order']?.toString() ?? '') ?? 0;
      final bo = int.tryParse(b['sort_order']?.toString() ?? '') ?? 0;
      if (ao != bo) return ao.compareTo(bo);
      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
    });
    return out;
  }

  Map<String, dynamic>? _selectedPackaging(dynamic item) {
    final pid = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final selectedId = _claimPackagingIds[pid];
    if (selectedId == null) return null;
    for (final p in _activePackagings(item)) {
      if (int.tryParse(p['id']?.toString() ?? '') == selectedId) return p;
    }
    return null;
  }

  double _claimDisplayQty(dynamic item) {
    final pid = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    return double.tryParse(_qtyCtrls[pid]?.text.trim() ?? '') ?? 0.0;
  }

  double _claimBaseQty(dynamic item) {
    final displayQty = _claimDisplayQty(item);
    final packaging = _selectedPackaging(item);
    if (packaging == null) return displayQty;
    return displayQty * _toDouble(packaging['base_quantity']);
  }

  Map<int, double> _allocatedPurchaseNetByItem() {
    final lineCents = <int>[];
    final ids = <int>[];
    var subtotalCents = 0;
    for (final item in _purchaseItems) {
      final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
      final cents = (_toDouble(item['total']) * 100).round().clamp(0, 1 << 62).toInt();
      ids.add(id);
      lineCents.add(cents);
      subtotalCents += cents;
    }
    var discountCents = (_toDouble(_selectedPurchase?['discount']) * 100).round();
    if (discountCents < 0) discountCents = 0;
    if (discountCents > subtotalCents) discountCents = subtotalCents;

    final allocated = List<int>.filled(lineCents.length, 0);
    var allocatedTotal = 0;
    if (subtotalCents > 0 && discountCents > 0) {
      for (var i = 0; i < lineCents.length; i++) {
        allocated[i] = (discountCents * lineCents[i]) ~/ subtotalCents;
        if (allocated[i] > lineCents[i]) allocated[i] = lineCents[i];
        allocatedTotal += allocated[i];
      }
      var left = discountCents - allocatedTotal;
      while (left > 0) {
        var progressed = false;
        for (var i = 0; i < allocated.length && left > 0; i++) {
          if (allocated[i] < lineCents[i]) {
            allocated[i]++;
            left--;
            progressed = true;
          }
        }
        if (!progressed) break;
      }
    }
    return {
      for (var i = 0; i < ids.length; i++) ids[i]: (lineCents[i] - allocated[i]) / 100.0,
    };
  }

  double _claimLineAmount(dynamic item) {
    final purchasedQty = _toDouble(item['quantity']);
    final claimQty = _claimBaseQty(item);
    if (purchasedQty <= 0 || claimQty <= 0) return 0.0;
    final itemId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final allocatedNet = _allocatedPurchaseNetByItem()[itemId] ?? 0.0;
    final value = claimQty * (allocatedNet / purchasedQty);
    return (value * 100).roundToDouble() / 100.0;
  }

  double _computeClaimTotal() {
    return _purchaseItems.fold<double>(
      0.0,
      (sum, item) => sum + _claimLineAmount(item),
    );
  }

  String _claimUnitLabel(dynamic item) {
    final packaging = _selectedPackaging(item);
    if (packaging == null) return 'Base unit';
    final short = (packaging['short_name'] ?? '').toString().trim();
    final name = (packaging['name'] ?? 'Package').toString().trim();
    final factor = _formatQty(_toDouble(packaging['base_quantity']));
    return '${short.isEmpty ? name : short} · 1 = $factor base';
  }

  void _changeClaimPackaging(dynamic item, int? packagingId) {
    final pid = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final oldBaseQty = _claimBaseQty(item);
    Map<String, dynamic>? nextPackaging;
    if (packagingId != null) {
      for (final p in _activePackagings(item)) {
        if (int.tryParse(p['id']?.toString() ?? '') == packagingId) {
          nextPackaging = p;
          break;
        }
      }
      if (nextPackaging == null) return;
    }
    var resetNonWhole = false;
    setState(() {
      _claimPackagingIds[pid] = packagingId;
      if (oldBaseQty <= 0) {
        _qtyCtrls[pid]?.text = '0';
      } else if (nextPackaging == null) {
        _qtyCtrls[pid]?.text = _formatQty(oldBaseQty);
      } else {
        final factor = _toDouble(nextPackaging!['base_quantity']);
        final converted = factor > 0 ? oldBaseQty / factor : 0.0;
        if ((converted - converted.roundToDouble()).abs() < 0.000001) {
          _qtyCtrls[pid]?.text = converted.round().toString();
        } else {
          _qtyCtrls[pid]?.text = '0';
          resetNonWhole = true;
        }
      }
      if (_receiveNow) _syncDefaultReceipt();
    });
    if (resetNonWhole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The current claim quantity is not a whole package, so it was reset to 0.')),
      );
    }
  }

  /// Formats a quantity without a trailing ".0" for whole numbers, but
  /// keeps decimals (e.g. 1.5kg) when present.
  String _formatQty(num v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _syncDefaultReceipt() {
    final t = _computeClaimTotal();
    _receiptAmountCtrl.text = t.toStringAsFixed(2);
  }

  Future<void> _searchPurchase(BuildContext context) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final invCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Search Purchase"),
        content: TextField(
          controller: invCtrl,
          decoration: const InputDecoration(hintText: "Enter invoice no..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (invCtrl.text.isEmpty) return;

              final listUri = Uri.parse(
                "${ApiClient.baseUrl}/purchases",
              ).replace(queryParameters: {"search": invCtrl.text});
              final listRes = await http.get(
                listUri,
                headers: {
                  "Authorization": "Bearer $token",
                  "Accept": "application/json",
                },
              );

              if (listRes.statusCode == 200) {
                final listData = jsonDecode(listRes.body);
                final purchases = listData['data']['data'];
                if (purchases.isNotEmpty) {
                  final purchase = purchases.first;

                  final detailRes = await http.get(
                    Uri.parse(
                      "${ApiClient.baseUrl}/purchases/${purchase['id']}",
                    ),
                    headers: {
                      "Authorization": "Bearer $token",
                      "Accept": "application/json",
                    },
                  );

                  if (!mounted) return;
                  if (detailRes.statusCode == 200) {
                    final detail = jsonDecode(detailRes.body)['data'];
                    setState(() {
                      _selectedPurchase = detail;
                      _purchaseItems = detail['items'] ?? [];

                      _qtyCtrls.clear();
                      _remarksCtrls.clear();
                      _batchCtrls.clear();
                      _expiryCtrls.clear();
                      _affectsStock.clear();
                      _claimPackagingIds.clear();

                      for (final it in _purchaseItems) {
                        final int pid = it['id']; // purchase_item_id
                        _qtyCtrls[pid] = TextEditingController(text: "0")
                          ..addListener(() {
                            if (_receiveNow) setState(_syncDefaultReceipt);
                          });
                        _remarksCtrls[pid] = TextEditingController();
                        _batchCtrls[pid] = TextEditingController();
                        _expiryCtrls[pid] = TextEditingController();
                        _affectsStock[pid] =
                            _type != 'shortage'; // default by type
                        _claimPackagingIds[pid] = null;
                      }
                    });
                  }
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateFor(int purchaseItemId) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      _expiryCtrls[purchaseItemId]?.text = picked
          .toIso8601String()
          .split('T')
          .first;
      setState(() {});
    }
  }

  void _onTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _type = val;
      for (final it in _purchaseItems) {
        final int pid = it['id'];
        _affectsStock[pid] = _type != 'shortage';
      }
    });
  }

  Future<void> _submitClaim(BuildContext context) async {
    if (_selectedPurchase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a purchase first.")),
      );
      return;
    }

    final itemsPayload = _purchaseItems
        .where((i) => _claimBaseQty(i) > 0)
        .map<Map<String, dynamic>>((i) {
          final pid = int.tryParse(i['id']?.toString() ?? '') ?? 0;
          final packaging = _selectedPackaging(i);
          final displayQty = _claimDisplayQty(i);
          return {
            "purchase_item_id": pid,
            "quantity": _claimBaseQty(i),
            "affects_stock": _affectsStock[pid] ?? (_type != 'shortage'),
            if (packaging != null) ...{
              "packaging_id": packaging['id'],
              "packaging_name_snapshot": packaging['name'],
              "packaging_short_name_snapshot": packaging['short_name'],
              "packaging_factor_snapshot": _toDouble(packaging['base_quantity']),
              "packaging_quantity": displayQty,
            },
            if (_remarksCtrls[pid]!.text.isNotEmpty)
              "remarks": _remarksCtrls[pid]!.text,
            if (_batchCtrls[pid]!.text.isNotEmpty)
              "batch_no": _batchCtrls[pid]!.text,
            if (_expiryCtrls[pid]!.text.isNotEmpty)
              "expiry_date": _expiryCtrls[pid]!.text,
          };
        })
        .toList();

    if (itemsPayload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter at least 1 claim quantity.")),
      );
      return;
    }

    // Guard: receipt amount <= total when approve+receive now
    final total = _computeClaimTotal();
    if (_approveNow && _receiveNow) {
      final requested = double.tryParse(_receiptAmountCtrl.text.trim()) ?? 0.0;
      if (requested <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid receipt amount")),
        );
        return;
      }
      if (requested > total + 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Receipt cannot exceed claim total (${_currency.format(total)})",
            ),
          ),
        );
        return;
      }
    }

    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    setState(() => _submitting = true);

    // Build request body
    final Map<String, dynamic> payload = {
      "purchase_id": _selectedPurchase!['id'],
      "type": _type,
      "reason": _reasonCtrl.text,
      "items": itemsPayload,
      if (_approveNow) "approve_now": true,
      if (_approveNow && _receiveNow)
        "receipt": {
          "amount": double.tryParse(_receiptAmountCtrl.text.trim()) ?? total,
          "method": _receiptMethod,
          if (_receiptRefCtrl.text.trim().isNotEmpty)
            "reference": _receiptRefCtrl.text.trim(),
          if (_receiptDate != null)
            "received_at": DateFormat("yyyy-MM-dd").format(_receiptDate!),
        },
    };

    final res = await http.post(
      Uri.parse("${ApiClient.baseUrl}/purchase-claims"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(payload),
    );

    setState(() => _submitting = false);

    if (!mounted) return;
    if (res.statusCode == 200 || res.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _approveNow
                ? (_receiveNow
                      ? "Claim created, approved and receipt posted ${_currency.format(double.tryParse(_receiptAmountCtrl.text) ?? total)}"
                      : "Claim created and approved")
                : "Claim created",
          ),
        ),
      );
      Navigator.pop(context, true);
    } else {
      String msg = "Failed to create purchase claim";
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['message'] is String) msg = d['message'];
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorName =
        _selectedPurchase?['vendor']?['name'] ??
        _selectedPurchase?['vendor']?['first_name'] ??
        'N/A';
    final invoiceNo = _selectedPurchase?['invoice_no'] ?? 'N/A';
    final total = _computeClaimTotal();

    return Focus(
      autofocus: true,
      skipTraversal: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          ...posSaveShortcuts(() {
            if (!_submitting) _submitClaim(context);
          }),
          const SingleActivator(LogicalKeyboardKey.f3): () => _searchPurchase(context),
          posCtrlShift(LogicalKeyboardKey.keyV): () => _searchPurchase(context),
          posCmdShift(LogicalKeyboardKey.keyV): () => _searchPurchase(context),
          posCtrl(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseClaimCreate),
          posCmd(LogicalKeyboardKey.slash): () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseClaimCreate),
        },
        child: Scaffold(
      appBar: AppBar(
        title: const Text("Create Purchase Claim"),
        actions: [
          IconButton(
            tooltip: 'Keyboard shortcuts',
            onPressed: () => showAppShortcutGuide(context, extra: PosShortcutCatalog.purchaseClaimCreate),
            icon: const Icon(Icons.keyboard_rounded),
          ),
          const BranchIndicator(tappable: false),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🔍 Select Purchase
              ListTile(
                title: Text(
                  _selectedPurchase == null
                      ? "No purchase selected"
                      : "Invoice: $invoiceNo",
                ),
                subtitle: Text(
                  _selectedPurchase == null
                      ? "Tap search to select purchase"
                      : "Vendor: $vendorName",
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchPurchase(context),
                ),
              ),
              const Divider(),

              // 🎛️ Claim Type + Reason
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _type,
                      items: const [
                        DropdownMenuItem(
                          value: 'shortage',
                          child: Text('Shortage'),
                        ),
                        DropdownMenuItem(
                          value: 'damaged',
                          child: Text('Damaged'),
                        ),
                        DropdownMenuItem(
                          value: 'wrong_item',
                          child: Text('Wrong Item'),
                        ),
                        DropdownMenuItem(
                          value: 'expired',
                          child: Text('Expired'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: _onTypeChanged,
                      decoration: const InputDecoration(
                        labelText: 'Claim Type',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: "Reason (optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 🧾 Purchase Claim – Items table
              if (_purchaseItems.isEmpty)
                const Expanded(child: Center(child: Text("No purchase items")))
              else
                Expanded(
                  child: Column(
                    children: [
                      const _ClaimTableHeader(),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _purchaseItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final item = _purchaseItems[i];
                            final pid = item['id'] as int; // purchase_item_id
                            final name =
                                item['product']?['name']?.toString() ?? '—';
                            final sku = item['product']?['sku']?.toString();
                            final receivedQty =
                                _toDouble(item['quantity'] ?? 0); // received/accepted qty
                            final originalPackaged = item['packaging_id'] != null;
                            final price = originalPackaged
                                ? _toDouble(item['packaging_unit_price'])
                                : _toDouble(item['price']);
                            final selectedPackaging = _selectedPackaging(item);
                            final amount = _claimLineAmount(item);

                            return SizedBox(
                              height: 64,
                              child: Row(
                                children: [
                                  // Product (+ SKU caption)
                                  Expanded(
                                    flex: 5,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (sku != null && sku.isNotEmpty)
                                            Text(
                                              "SKU: $sku",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).hintColor,
                                                  ),
                                            ),
                                          if (_activePackagings(item).isNotEmpty)
                                            PopupMenuButton<int>(
                                              padding: EdgeInsets.zero,
                                              tooltip: 'Claim unit',
                                              onSelected: (value) =>
                                                  _changeClaimPackaging(item, value == 0 ? null : value),
                                              itemBuilder: (_) => [
                                                const PopupMenuItem(value: 0, child: Text('Base unit')),
                                                for (final p in _activePackagings(item))
                                                  PopupMenuItem(
                                                    value: int.tryParse(p['id']?.toString() ?? '') ?? 0,
                                                    child: Text(
                                                      '${(p['short_name'] ?? p['name'] ?? 'Package')} · 1 = ${_formatQty(_toDouble(p['base_quantity']))} base',
                                                    ),
                                                  ),
                                              ],
                                              child: Text(
                                                _claimUnitLabel(item),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // P.P
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(_currency.format(price)),
                                    ),
                                  ),
                                  // Received
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        originalPackaged
                                            ? '${_formatQty(_toDouble(item['packaging_quantity']))} ${(item['packaging_short_name_snapshot'] ?? item['packaging_name_snapshot'] ?? 'pkg')} (${_formatQty(receivedQty)} base)'
                                            : _formatQty(receivedQty),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ),
                                  // Claim (editable)
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _qtyCtrls[pid],
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.numberWithOptions(
                                        decimal: selectedPackaging == null,
                                      ),
                                      inputFormatters: selectedPackaging == null
                                          ? null
                                          : [FilteringTextInputFormatter.digitsOnly],
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (v) {
                                        final parsed = double.tryParse(v.trim()) ?? 0.0;
                                        final factor = selectedPackaging == null
                                            ? 1.0
                                            : _toDouble(selectedPackaging['base_quantity']);
                                        final requestedBase = parsed * factor;
                                        if (parsed < 0 || requestedBase > receivedQty + 0.0005) {
                                          final maxDisplay = factor > 0 ? receivedQty / factor : 0.0;
                                          final clamped = selectedPackaging == null
                                              ? maxDisplay
                                              : maxDisplay.floorToDouble();
                                          _qtyCtrls[pid]!.text = _formatQty(clamped);
                                          _qtyCtrls[pid]!.selection = TextSelection.fromPosition(
                                            TextPosition(offset: _qtyCtrls[pid]!.text.length),
                                          );
                                        }
                                        setState(() {
                                          if (_receiveNow) _syncDefaultReceipt();
                                        });
                                      },
                                    ),
                                  ),
                                  // Amount (claimQty * price)
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        _currency.format(amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // ✅ Approve & 📥 Receive Now (optional)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text("Approve immediately"),
                        value: _approveNow,
                        onChanged: (v) {
                          setState(() {
                            _approveNow = v;
                            if (!_approveNow) _receiveNow = false;
                            if (_approveNow && _receiveNow)
                              _syncDefaultReceipt();
                          });
                        },
                      ),
                      const Divider(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Claim Total: ${_currency.format(total)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _submitClaim(context),
                  icon: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_submitting ? "Submitting..." : "Submit Claim  Ctrl+Enter"),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}


class _ClaimTableHeader extends StatelessWidget {
  const _ClaimTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).hintColor,
        );
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const Expanded(flex: 5, child: Text("Product")),
          Expanded(flex: 2, child: Text("P.P", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Purchased", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Claim", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Amount", style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
