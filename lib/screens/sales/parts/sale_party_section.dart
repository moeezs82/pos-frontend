import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/customer_display_utils.dart';
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
  final List<Map<String, dynamic>> saleSources;
  final int? selectedSaleSourceId;
  final ValueChanged<int?> onSaleSourceChanged;
  final VoidCallback? onManageSaleSources;
  final bool canManageSaleSources;

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
  final FocusNode? vendorFocusNode;

  /// Optional external [TextEditingController]s — cleared by the parent before
  /// requesting focus, so the field opens with a blank query rather than
  /// leftover text from a previous search.
  final TextEditingController? customerController;
  final TextEditingController? salesmanController;
  final TextEditingController? deliveryBoyController;
  final TextEditingController? vendorController;

  /// Feature flags: when false the corresponding field is hidden.
  /// Both default to true so existing call sites are unaffected.
  final bool showDeliveryBoy;
  final bool showVendor;

  /// Posted-sale amendments deliberately lock customer identity. Moving an
  /// already-posted invoice to another party changes AR/payment history and
  /// therefore belongs to a separate controlled accounting workflow.
  final bool customerLocked;
  final String? customerLockMessage;

  const PartySectionCard({
    super.key,
    required this.isAll,
    required this.selectedCustomer,
    required this.selectedUser,
    required this.selectedDeliveryBoy,
    required this.selectedBranch,
    required this.selectedVendor,
    required this.saleSources,
    required this.selectedSaleSourceId,
    required this.onSaleSourceChanged,
    this.onManageSaleSources,
    this.canManageSaleSources = false,
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
    this.vendorFocusNode,
    this.customerController,
    this.salesmanController,
    this.deliveryBoyController,
    this.vendorController,
    this.showDeliveryBoy = true,
    this.showVendor = true,
    this.customerLocked = false,
    this.customerLockMessage,
  });

  String _customerLabel(PartyMap c) => CustomerDisplayUtils.fullName(c);

  String _customerSubtitle(PartyMap c) => CustomerDisplayUtils.subtitle(c);

  String _personLabel(PartyMap u) => (u['name'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showDeliveryBoy ? 'Customer, staff & delivery' : 'Customer & staff',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Start typing to find someone instantly, or use the list icon to browse.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              );
              final source = SizedBox(
                width: onManageSaleSources != null && canManageSaleSources ? 270 : 230,
                child: _SaleSourceField(
                  items: saleSources,
                  selectedId: selectedSaleSourceId,
                  onChanged: onSaleSourceChanged,
                  onManage: canManageSaleSources ? onManageSaleSources : null,
                ),
              );
              if (headerConstraints.maxWidth < 610) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: source),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 14),
                  source,
                ],
              );
            },
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

              final allFields = [
                if (customerLocked)
                  _LockedPartyField(
                    label: 'Customer',
                    value: selectedCustomer != null
                        ? _customerLabel(selectedCustomer!)
                        : 'Walk-in customer',
                    subtitle: selectedCustomer != null
                        ? _customerSubtitle(selectedCustomer!)
                        : 'Customer identity is locked for this posted invoice',
                    message: customerLockMessage ??
                        'Customer cannot be changed inside a posted-sale amendment because it affects accounts receivable and payment history.',
                  )
                else
                  PartyAutocompleteField<PartyMap>(
                    label: 'Customer',
                    hintText: 'Type customer ID, name, area or phone…',
                    focusNode: customerFocusNode,
                    controller: customerController,
                    getCachedItems: () =>
                        CustomerPickCache.cache.peek(CustomerPickCache.keyFor())?.items ?? const [],
                    onSearchRemote: (query) => CustomerPickCache.searchRemote(
                      customerService,
                      query,
                      branchId: int.tryParse(branchId ?? ''),
                    ),
                    labelOf: _customerLabel,
                    subtitleOf: _customerSubtitle,
                    searchTextOf: CustomerDisplayUtils.searchText,
                    idOf: (c) => (c['id'] ?? '').toString(),
                    selectedLabel: selectedCustomer != null ? _customerLabel(selectedCustomer!) : null,
                    selectedSubtitle: selectedCustomer != null ? _customerSubtitle(selectedCustomer!) : null,
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
                          .peek(UserPickCache.keyFor(branchId: branchId, role: 'salesman'))
                          ?.items ??
                      const [],
                  onSearchRemote: (query) => UserPickCache.searchRemote(
                    userService,
                    query,
                    branchId: branchId,
                    role: 'salesman',
                  ),
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
                  focusNode: vendorFocusNode,
                  controller: vendorController,
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

              final fields = [
                allFields[0], // Customer — always shown
                allFields[1], // Salesman — always shown
                if (showDeliveryBoy) allFields[2],
                if (showVendor) allFields[3],
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
                  for (int i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: fields[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SaleSourceField extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final VoidCallback? onManage;

  const _SaleSourceField({
    required this.items,
    required this.selectedId,
    required this.onChanged,
    required this.onManage,
  });

  int? _id(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  bool _active(dynamic value) =>
      value == true || value == 1 || value?.toString().toLowerCase() == 'true';

  @override
  Widget build(BuildContext context) {
    final selectable = items.where((e) => _active(e['is_active'])).toList();
    final current = items.where((e) => _id(e['id']) == selectedId).toList();
    if (selectedId != null &&
        current.isNotEmpty &&
        !selectable.any((e) => _id(e['id']) == selectedId)) {
      selectable.add(current.first);
    }
    selectable.sort((a, b) {
      final ao = int.tryParse(a['sort_order']?.toString() ?? '') ?? 0;
      final bo = int.tryParse(b['sort_order']?.toString() ?? '') ?? 0;
      if (ao != bo) return ao.compareTo(bo);
      return (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase());
    });

    final dropdown = DropdownButtonFormField<int>(
      value: selectable.any((e) => _id(e['id']) == selectedId)
          ? selectedId
          : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Sale From',
        isDense: true,
        prefixIcon: Icon(Icons.hub_outlined, size: 18),
        border: OutlineInputBorder(),
      ),
      hint: Text(
        items.isEmpty ? 'Sources unavailable' : 'Select source',
        overflow: TextOverflow.ellipsis,
      ),
      items: selectable.map((source) {
        final active = _active(source['is_active']);
        return DropdownMenuItem<int>(
          value: _id(source['id']),
          child: Row(children: [
            Expanded(
              child: Text(
                (source['name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!active)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text(
                  'Inactive',
                  style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                ),
              ),
          ]),
        );
      }).toList(growable: false),
      onChanged: items.isEmpty ? null : onChanged,
    );

    if (onManage == null) return dropdown;
    return Row(
      children: [
        Expanded(child: dropdown),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Manage sale sources',
          child: SizedBox(
            width: 40,
            height: 40,
            child: OutlinedButton(
              onPressed: onManage,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 40),
              ),
              child: const Icon(Icons.settings_outlined, size: 18),
            ),
          ),
        ),
      ],
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


class _LockedPartyField extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final String message;

  const _LockedPartyField({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          suffixIcon: const Icon(Icons.verified_user_outlined, size: 17),
          filled: true,
          fillColor: AppTheme.surfaceSoft,
          border: const OutlineInputBorder(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle.trim().isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
