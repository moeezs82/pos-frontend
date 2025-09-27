import 'package:flutter/material.dart';

class CBFilters extends StatelessWidget {
  final List<Map<String, dynamic>> accounts;
  final bool showBranchNote;

  final String? accountValue;
  final String? methodValue;
  final String? typeValue;

  /// Expects items like: [{"label":"Cash","value":"cash"}]
  final List<Map<String, dynamic>> methodOptions;
  /// Expects items like: [{"label":"Receipt","value":"receipt"}]
  final List<Map<String, dynamic>> typeOptions;

  final bool showType;

  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String>   onSearchSubmit;

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
    const hPad = 12.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
      child: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth;
          final gap = 8.0;

          // Simple responsive columns
          final cols = maxW >= 900 ? 3 : (maxW >= 580 ? 2 : 1);
          final itemW = ((maxW - gap * (cols - 1)) / cols).clamp(240.0, double.infinity);

          final children = <Widget>[
            if (accounts.isNotEmpty)
              SizedBox(
                width: itemW,
                child: _DenseDropdown<String?>(
                  value: accountValue,
                  label: 'Account',
                  icon: Icons.account_balance_wallet_outlined,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Accounts'),
                    ),
                    ...accounts.map((a) {
                      final id = a['id']?.toString();
                      final name = (a['name'] ?? '').toString();
                      final code = (a['code'] ?? '').toString();
                      return DropdownMenuItem<String?>(
                        value: id,
                        child: Text(code.isEmpty ? name : '$name ($code)'),
                      );
                    }),
                  ],
                  onChanged: onAccountChanged,
                ),
              ),

            if (showBranchNote)
              SizedBox(
                width: itemW,
                child: _DenseReadOnlyField(
                  label: 'Branch (Global applies)',
                  value: 'All Branches',
                  icon: Icons.apartment_rounded,
                ),
              ),

            if (showType && typeOptions.isNotEmpty)
              SizedBox(
                width: itemW,
                child: _DenseDropdown<String?>(
                  value: typeValue,
                  label: 'Type',
                  icon: Icons.compare_arrows_rounded,
                  items: typeOptions.map((t) {
                    return DropdownMenuItem<String?>(
                      value: t['value'] as String?,
                      child: Text(t['label'] as String),
                    );
                  }).toList(),
                  onChanged: onTypeChanged,
                ),
              ),

            if (methodOptions.isNotEmpty)
              SizedBox(
                width: itemW,
                child: _DenseDropdown<String?>(
                  value: methodValue,
                  label: 'Method',
                  icon: Icons.payments_rounded,
                  items: methodOptions.map((m) {
                    return DropdownMenuItem<String?>(
                      value: m['value'] as String?,
                      child: Text(m['label'] as String),
                    );
                  }).toList(),
                  onChanged: onMethodChanged,
                ),
              ),

            // Search
            SizedBox(
              width: itemW,
              child: _DenseSearchField(
                label: 'Search',
                onSubmit: onSearchSubmit,
              ),
            ),
          ];

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: children,
          );
        },
      ),
    );
  }
}

/// Dense dropdown using proper InputDecoration
class _DenseDropdown<T> extends StatelessWidget {
  final T value;
  final String label;
  final IconData? icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DenseDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Read-only field to show branch note (disabled look)
class _DenseReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const _DenseReadOnlyField({
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Dense search with clear + submit
class _DenseSearchField extends StatefulWidget {
  final String label;
  final ValueChanged<String> onSubmit;
  const _DenseSearchField({
    required this.label,
    required this.onSubmit,
  });

  @override
  State<_DenseSearchField> createState() => _DenseSearchFieldState();
}

class _DenseSearchFieldState extends State<_DenseSearchField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _clear() {
    _c.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.search,
      onSubmitted: widget.onSubmit,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: _clear,
              ),
      ),
      onChanged: (_) => setState(() {}), // toggle clear icon
    );
  }
}
