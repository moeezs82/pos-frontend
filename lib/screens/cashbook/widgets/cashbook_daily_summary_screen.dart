import 'package:enterprise_pos/screens/cashbook/widgets/daybook_day_details_screen.dart';
import 'package:flutter/material.dart';

import 'cb_daily_list.dart';
import 'cashbook_day_details_screen.dart';

class CashbookDailySummaryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> rows;

  /// Optional async refresh handler provided by the parent
  /// e.g., () async { await provider.reload(); }
  final Future<void> Function()? fetch;

  const CashbookDailySummaryScreen({super.key, required this.rows, this.fetch});

  @override
  State<CashbookDailySummaryScreen> createState() =>
      _CashbookDailySummaryScreenState();
}

class _CashbookDailySummaryScreenState
    extends State<CashbookDailySummaryScreen> {
  bool _loading =
      false; // let parent manage rows; we just show a spinner while calling fetch()
  String? _error;

  // (optional) filters — wire these if you want
  String? _dateFrom;
  String? _dateTo;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _handleRefresh() async {
    if (widget.fetch == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.fetch!.call();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openDay(String date) {
    Navigator.of(context).push(
      // MaterialPageRoute(builder: (_) => CashbookDayDetailsScreen(date: date)),
      MaterialPageRoute(builder: (_) => DayBookDayDetailsScreen(date: date)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final onRefresh = widget.fetch != null ? _handleRefresh : null;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: onRefresh ?? () {})
          : rows.isEmpty
          ? const Center(child: Text("No daily data"))
          : CBDailyList(rows: rows, onViewDay: _openDay),
      // (Optional) a simple footer to show current filter dates
      bottomNavigationBar: (_dateFrom != null || _dateTo != null)
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Range: ${_dateFrom ?? '—'} → ${_dateTo ?? '—'}",
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 8),
          Text(
            "Failed to load",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text("Retry")),
        ],
      ),
    );
  }
}
