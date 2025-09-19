import 'package:enterprise_pos/api/common_service.dart';
import 'package:flutter/material.dart';

class BranchPickerSheet extends StatefulWidget {
  final String token;
  const BranchPickerSheet({super.key, required this.token});

  @override
  State<BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends State<BranchPickerSheet> {
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String _search = "";

  late CommonService _commonService;

  @override
  void initState() {
    super.initState();
    _commonService = CommonService(token: widget.token);
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    final data = await _commonService.getBranches();
    setState(() {
      _branches = data.cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _branches
        : _branches
            .where((b) =>
                b['name'].toString().toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search branch...",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _search = val),
            ),
            const SizedBox(height: 12),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final b = filtered[i];
                        return ListTile(
                          title: Text(b['name']),
                          onTap: () => Navigator.pop(context, b),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
