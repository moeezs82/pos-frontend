import 'dart:async' show unawaited;
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SaleWalkInSection extends StatelessWidget {
  final TextEditingController nameController;
  final FocusNode nameFocusNode;

  final TextEditingController phoneController;
  final FocusNode phoneFocusNode;
  final VoidCallback onPhoneEditingComplete;

  final TextEditingController addressController;
  final FocusNode addressFocusNode;

  final String? selectedCustomerId;
  final Map<String, dynamic>? selectedCustomer;
  final List<String> selectedCustomerSecondaryPhones;
  final VoidCallback onClearCustomer;

  final bool sendInvoiceOnWhatsApp;
  final ValueChanged<bool> onWhatsAppChanged;
  final String whatsAppDestinationPhone;

  final List<Map<String, dynamic>> customerAreas;
  final int? selectedAreaId;
  final ValueChanged<int?> onAreaChanged;
  final VoidCallback onClearArea;
  final VoidCallback? onManageCustomerAreas;

  final bool submitting;

  const SaleWalkInSection({
    super.key,
    required this.nameController,
    required this.nameFocusNode,
    required this.phoneController,
    required this.phoneFocusNode,
    required this.onPhoneEditingComplete,
    required this.addressController,
    required this.addressFocusNode,
    required this.selectedCustomerId,
    this.selectedCustomer,
    this.selectedCustomerSecondaryPhones = const [],
    required this.onClearCustomer,
    required this.sendInvoiceOnWhatsApp,
    required this.onWhatsAppChanged,
    required this.whatsAppDestinationPhone,
    required this.customerAreas,
    required this.selectedAreaId,
    required this.onAreaChanged,
    required this.onClearArea,
    this.onManageCustomerAreas,
    this.submitting = false,
  });

  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _areaActive(Map<String, dynamic> area) {
    final active = area['is_active'];
    if (active == null) return true;
    if (active is bool) return active;
    if (active is num) return active != 0;
    final text = active.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  Map<String, dynamic>? _areaById(int? id) {
    if (id == null) return null;
    for (final area in customerAreas) {
      if (_metaInt(area['id']) == id) return area;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
    );

    Widget nameField() => Tooltip(
          message: 'Focus: Ctrl+Shift+N',
          child: SizedBox(
            height: 40,
            child: TextFormField(
              controller: nameController,
              focusNode: nameFocusNode,
              decoration: inputDecoration.copyWith(hintText: 'Customer name'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );

    Widget phoneField() => Tooltip(
          message: 'Focus: Ctrl+Shift+H',
          child: SizedBox(
            height: 40,
            child: TextFormField(
              controller: phoneController,
              focusNode: phoneFocusNode,
              keyboardType: TextInputType.phone,
              decoration: inputDecoration.copyWith(hintText: 'Phone'),
              style: const TextStyle(fontSize: 12),
              onEditingComplete: onPhoneEditingComplete,
            ),
          ),
        );

    Widget addressField() => Tooltip(
          message: 'Focus: Ctrl+Shift+A',
          child: SizedBox(
            height: 40,
            child: TextFormField(
              controller: addressController,
              focusNode: addressFocusNode,
              decoration: inputDecoration.copyWith(
                hintText: 'Address (optional)',
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );

    Widget clearCustomerButton() {
      if (selectedCustomerId == null) return const SizedBox.shrink();
      return InkWell(
        onTap: onClearCustomer,
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: AppTheme.danger,
          ),
        ),
      );
    }

    Widget whatsAppToggle() {
      if (!context.watch<AuthProvider>().hasAddon('whatsapp_invoice')) {
        return const SizedBox.shrink();
      }
      return Tooltip(
        message:
            'Prepare this receipt for WhatsApp after the sale is saved. Registered customers always use their primary phone.',
        child: InkWell(
          onTap: submitting ? null : () => onWhatsAppChanged(!sendInvoiceOnWhatsApp),
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: sendInvoiceOnWhatsApp,
                onChanged: submitting
                    ? null
                    : (value) => onWhatsAppChanged(value ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const Text(
                'WhatsApp invoice',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    Widget whatsAppDestination() {
      if (!sendInvoiceOnWhatsApp) return const SizedBox.shrink();
      return Container(
        constraints: const BoxConstraints(maxWidth: 230),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(6),
          color: AppTheme.surfaceSoft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_rounded, size: 14, color: Color(0xFF128C7E)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                whatsAppDestinationPhone.isEmpty
                    ? 'Primary phone required'
                    : 'To: $whatsAppDestinationPhone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget areaRow() => Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: DropdownButtonFormField<int>(
                  value: _areaById(selectedAreaId) == null ? null : selectedAreaId,
                  isExpanded: true,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Town / Area',
                    hintText: 'Select sale area',
                    prefixIcon: const Icon(
                      Icons.location_city_outlined,
                      size: 15,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  items: customerAreas
                      .where(_areaActive)
                      .map(
                        (area) => DropdownMenuItem<int>(
                          value: _metaInt(area['id']),
                          child: Text(
                            (area['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .where((item) => item.value != null)
                      .toList(growable: false),
                  onChanged: submitting ? null : onAreaChanged,
                ),
              ),
            ),
            if (selectedAreaId != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Clear sale area',
                child: SizedBox(
                  width: 38,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: submitting ? null : onClearArea,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
              ),
            ],
            if (context.read<AuthProvider>().hasPermission('manage-customers') &&
                onManageCustomerAreas != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Create or rename Town / Area',
                child: SizedBox(
                  width: 38,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: submitting ? null : onManageCustomerAreas,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    child: const Icon(Icons.tune_rounded, size: 17),
                  ),
                ),
              ),
            ],
            if (selectedCustomerId != null &&
                _metaInt(selectedCustomer?['area_id']) != null &&
                selectedAreaId != _metaInt(selectedCustomer?['area_id'])) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message:
                    'This changes only this sale. The customer default area is not modified.',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ],
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide)
                Row(
                  children: [
                    const SizedBox(
                      width: 48,
                      child: Text(
                        'Walk-in',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Expanded(flex: 3, child: nameField()),
                    const SizedBox(width: 6),
                    SizedBox(width: 126, child: phoneField()),
                    if (selectedCustomerId != null) ...[
                      const SizedBox(width: 4),
                      clearCustomerButton(),
                    ],
                    const SizedBox(width: 6),
                    Expanded(flex: 4, child: addressField()),
                    if (context.watch<AuthProvider>().hasAddon('whatsapp_invoice')) ...[
                      const SizedBox(width: 6),
                      whatsAppToggle(),
                    ],
                  ],
                )
              else ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 48,
                      child: Text(
                        'Walk-in',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Expanded(child: nameField()),
                    const SizedBox(width: 6),
                    SizedBox(width: 120, child: phoneField()),
                    if (selectedCustomerId != null) ...[
                      const SizedBox(width: 4),
                      clearCustomerButton(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: addressField()),
                    if (context.watch<AuthProvider>().hasAddon('whatsapp_invoice')) ...[
                      const SizedBox(width: 6),
                      whatsAppToggle(),
                    ],
                  ],
                ),
              ],
              if (sendInvoiceOnWhatsApp) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: whatsAppDestination(),
                ),
              ],
              const SizedBox(height: 4),
              areaRow(),
              if (selectedCustomerId != null &&
                  selectedCustomerSecondaryPhones.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.print_outlined,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Invoice phones:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedCustomerSecondaryPhones.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
