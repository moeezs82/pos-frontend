import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:enterprise_pos/widgets/party_autocomplete_field.dart';
import 'package:flutter/material.dart';

typedef PartyMap = Map<String, dynamic>;

class PartySectionCard extends StatelessWidget {
  final bool isAll;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedUser;
  final Map<String, dynamic>? selectedDeliveryBoy;
  final Map<String, dynamic>? selectedBranch;
  final Map<String, dynamic>? selectedVendor;

  /// Needed to call the live, full-database search endpoints
  /// (customers/vendors/users) as the user types past whatever's in the
  /// local cache — a 10,000-row customer table can never live entirely in
  /// memory, so typing always falls through to a real server search.
  final String token;

  /// The same effective branch id used to open the salesman/delivery-boy
  /// sheets and to prefetch their caches — must match exactly, since the
  /// cache is bucketed by branchId+role. Passing the wrong value here would
  /// make the autocomplete field "miss" data that's actually sitting in the
  /// cache under a different branch key.
  final String? branchId;

  /// Manual "Select…" taps still supported (e.g. tapping an already-filled
  /// field) — opens the exact same full picker sheet as before.
  final VoidCallback onPickCustomer;
  final VoidCallback onPickUser;
  final VoidCallback onPickDeliveryBoy;
  final VoidCallback onPickVendor;
  final VoidCallback onClearVendor;

  /// Browse-all fallbacks used by the autocomplete field's "Browse full
  /// list…" action and trailing list icon — for staff who'd rather scroll
  /// a list than type. Returns the picked map, or null for "cleared".
  final Future<Map<String, dynamic>?> Function() onBrowseCustomerSheet;
  final void Function(Map<String, dynamic>?) onApplyCustomer;
  final Future<Map<String, dynamic>?> Function() onBrowseUserSheet;
  final void Function(Map<String, dynamic>?) onApplyUser;
  final Future<Map<String, dynamic>?> Function() onBrowseDeliveryBoySheet;
  final void Function(Map<String, dynamic>?) onApplyDeliveryBoy;
  final Future<Map<String, dynamic>?> Function() onBrowseVendorSheet;
  final void Function(Map<String, dynamic>?) onApplyVendor;

  /// Optional external [FocusNode]s for each autocomplete field so that
  /// keyboard shortcuts on the parent screen can jump focus directly into the
  /// field. When null, each field manages its own internal node (unchanged
  /// behavior for any call site that doesn't supply them).
  final FocusNode? customerFocusNode;
  final FocusNode? salesmanFocusNode;
  final FocusNode? deliveryBoyFocusNode;

  /// Optional external [TextEditingController]s — cleared by the parent before
  /// requesting focus, so the field opens with a blank query rather than
  /// leftover text from a previous search.
  final TextEditingController? customerController;
  final TextEditingController? salesmanController;
  final TextEditingController? deliveryBoyController;

  const PartySectionCard({
    super.key,
    required this.isAll,
    required this.selectedCustomer,
    required this.selectedUser,
    required this.selectedDeliveryBoy,
    required this.selectedBranch,
    required this.selectedVendor,
    required this.token,
    required this.onPickCustomer,
    required this.onPickUser,
    required this.onPickDeliveryBoy,
    required this.onPickVendor,
    required this.onClearVendor,
    required this.onBrowseCustomerSheet,
    required this.onApplyCustomer,
    required this.onBrowseUserSheet,
    required this.onApplyUser,
    required this.onBrowseDeliveryBoySheet,
    required this.onApplyDeliveryBoy,
    required this.onBrowseVendorSheet,
    required this.onApplyVendor,
    this.branchId,
    this.customerFocusNode,
    this.salesmanFocusNode,
    this.deliveryBoyFocusNode,
    this.customerController,
    this.salesmanController,
    this.deliveryBoyController,
  });

  String _customerLabel(PartyMap c) {
    final first = (c['first_name'] ?? '').toString();
    final last = (c['last_name'] ?? '').toString();
    return "$first ${last.isNotEmpty ? last : ''}".trim();
  }

  String _personLabel(PartyMap u) => (u['name'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer, staff & delivery', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Start typing to find someone instantly, or use the list icon to browse.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;

              // Built once per build — cheap (just wraps an ApiClient), and
              // these are what actually let typing reach the full database
              // instead of only the ~200-row warm cache.
              final customerService = CustomerService(token: token);
              final vendorService = VendorService(token: token);
              final userService = UsersService(token: token);

              final fields = [
                PartyAutocompleteField<PartyMap>(
                  label: 'Customer',
                  hintText: 'Type customer name or phone…',
                  focusNode: customerFocusNode,
                  controller: customerController,
                  getCachedItems: () =>
                      CustomerPickCache.cache.peek(CustomerPickCache.keyFor())?.items ?? const [],
                  onSearchRemote: (query) => CustomerPickCache.searchRemote(customerService, query),
                  labelOf: _customerLabel,
                  subtitleOf: (c) => (c['phone'] ?? '').toString(),
                  idOf: (c) => (c['id'] ?? '').toString(),
                  selectedLabel: selectedCustomer != null ? _customerLabel(selectedCustomer!) : null,
                  selectedSubtitle: selectedCustomer != null ? (selectedCustomer!['phone'] ?? '').toString() : null,
                  onSelectedTap: onPickCustomer,
                  onSelected: (c) => onApplyCustomer(c),
                  onCleared: () => onApplyCustomer(null),
                  onBrowseAll: onBrowseCustomerSheet,
                ),
                PartyAutocompleteField<PartyMap>(
                  label: 'Salesman',
                  hintText: 'Type salesman name…',
                  focusNode: salesmanFocusNode,
                  controller: salesmanController,
                  getCachedItems: () => UserPickCache.cache
                          .peek(UserPickCache.keyFor(branchId: branchId, role: null))
                          ?.items ??
                      const [],
                  onSearchRemote: (query) =>
                      UserPickCache.searchRemote(userService, query, branchId: branchId),
                  labelOf: _personLabel,
                  subtitleOf: (u) => (u['phone'] ?? '').toString(),
                  idOf: (u) => (u['id'] ?? '').toString(),
                  selectedLabel: selectedUser != null ? _personLabel(selectedUser!) : null,
                  selectedSubtitle: selectedUser != null ? (selectedUser!['phone'] ?? '').toString() : null,
                  onSelectedTap: onPickUser,
                  onSelected: (u) => onApplyUser(u),
                  onCleared: () => onApplyUser(null),
                  onBrowseAll: onBrowseUserSheet,
                ),
                PartyAutocompleteField<PartyMap>(
                  label: 'Delivery Boy',
                  hintText: 'Type delivery boy name… (optional)',
                  focusNode: deliveryBoyFocusNode,
                  controller: deliveryBoyController,
                  getCachedItems: () => UserPickCache.cache
                          .peek(UserPickCache.keyFor(branchId: branchId, role: 'delivery'))
                          ?.items ??
                      const [],
                  onSearchRemote: (query) => UserPickCache.searchRemote(
                    userService,
                    query,
                    branchId: branchId,
                    role: 'delivery',
                  ),
                  labelOf: _personLabel,
                  subtitleOf: (u) => (u['phone'] ?? '').toString(),
                  idOf: (u) => (u['id'] ?? '').toString(),
                  selectedLabel: selectedDeliveryBoy != null ? _personLabel(selectedDeliveryBoy!) : null,
                  selectedSubtitle: selectedDeliveryBoy != null ? (selectedDeliveryBoy!['phone'] ?? '').toString() : null,
                  onSelectedTap: onPickDeliveryBoy,
                  onSelected: (u) => onApplyDeliveryBoy(u),
                  onCleared: () => onApplyDeliveryBoy(null),
                  onBrowseAll: onBrowseDeliveryBoySheet,
                ),
                PartyAutocompleteField<PartyMap>(
                  label: 'Vendor',
                  hintText: 'Type vendor name… (optional)',
                  getCachedItems: () =>
                      VendorPickCache.cache.peek(VendorPickCache.keyFor())?.items ?? const [],
                  onSearchRemote: (query) => VendorPickCache.searchRemote(vendorService, query),
                  labelOf: _customerLabel,
                  subtitleOf: (v) => (v['phone'] ?? '').toString(),
                  idOf: (v) => (v['id'] ?? '').toString(),
                  selectedLabel: selectedVendor != null ? _customerLabel(selectedVendor!) : null,
                  selectedSubtitle: selectedVendor != null ? (selectedVendor!['phone'] ?? '').toString() : null,
                  onSelectedTap: onPickVendor,
                  onSelected: (v) => onApplyVendor(v),
                  onCleared: onClearVendor,
                  onBrowseAll: onBrowseVendorSheet,
                ),
              ];

              if (!wide) {
                return Column(
                  children: [
                    for (int i = 0; i < fields.length; i++) ...[
                      fields[i],
                      if (i != fields.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[2]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[3]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Kept for any other screen still constructing a plain tap-to-open field
/// (e.g. branch selector elsewhere) — unchanged from the original behavior.
class SelectField extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final VoidCallback onTap;
  final bool showClear;
  final VoidCallback? onClear;

  const SelectField({
    super.key,
    required this.label,
    required this.valueText,
    required this.icon,
    required this.onTap,
    this.showClear = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (showClear)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
