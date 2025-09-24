import 'package:flutter/material.dart';

class CBFilters extends StatelessWidget {
  final List<Map<String, dynamic>> accounts;
  final bool showBranchNote;
  final String? accountValue;
  final String? methodValue;
  final String? typeValue;
  final List<Map<String, dynamic>> methodOptions;
  final List<Map<String, dynamic>> typeOptions;
  final bool showType;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String> onSearchSubmit;

  const CBFilters({
    super.key,
    required this.accounts,
    required this.showBranchNote,
    required this.accountValue,
    required this.methodValue,
    required this.typeValue,
    required this.methodOptions,
    required this.typeOptions,
    required this.showType,
    required this.onAccountChanged,
    required this.onMethodChanged,
    required this.onTypeChanged,
    required this.onSearchSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Row 1
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (accounts.isNotEmpty)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: accountValue,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Account",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: const Text("All Accounts"),
                      ),
                      ...accounts.map(
                        (a) => DropdownMenuItem<String>(
                          value: a['id'].toString(),
                          child: Text("${a['name']} (${a['code'] ?? ''})"),
                        ),
                      ),
                    ],
                    onChanged: onAccountChanged,
                  ),
                ),
              if (accounts.isNotEmpty) const SizedBox(width: 8),
              if (showBranchNote)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: null,
                    decoration: const InputDecoration(
                      labelText: "Branch (Global applies)",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: const Text("All Branches"),
                      ),
                    ],
                    onChanged: null,
                  ),
                ),
            ],
          ),
        ),

        // Row 2
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: methodValue,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: "Method",
                    border: OutlineInputBorder(),
                  ),
                  items: methodOptions
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m['value'] as String?,
                          child: Text(m['label'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: onMethodChanged,
                ),
              ),
              const SizedBox(width: 8),

              if (showType)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: typeValue,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Type",
                      border: OutlineInputBorder(),
                    ),
                    items: typeOptions
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t['value'] as String?,
                            child: Text(t['label'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: onTypeChanged,
                  ),
                )
              else
                const Spacer(),

              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: "Search",
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: onSearchSubmit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
