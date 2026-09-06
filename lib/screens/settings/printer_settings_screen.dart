import 'dart:convert';
import 'dart:typed_data';

import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:enterprise_pos/models/barcode_label_line.dart';
import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/models/receipt_footer_style.dart';
import 'package:enterprise_pos/models/whatsapp_invoice_format.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/screens/settings/invoice_template_preview_screen.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/services/whatsapp_message_template_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/utils/print_text_utils.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  late final PrinterConfigService _service;
  late final CommonService _common;

  bool _loadingBranches = true;
  bool _loadingConfig = false;
  bool _saving = false;
  bool _testing = false;
  bool _testingSecondary = false;
  bool _testingBarcode = false;
  bool _loadingPrinters = false;

  List<Map<String, dynamic>> _branches = [];
  int? _selectedBranchId;

  // Form controllers
  final _shopNameCtrl = TextEditingController();
  final _shopAddressCtrl = TextEditingController();
  final _shopPhoneCtrl = TextEditingController();
  final _networkIpCtrl = TextEditingController();
  final _networkPortCtrl = TextEditingController(text: '9100');
  final _localPrinterCtrl = TextEditingController();
  final _secondaryNetworkIpCtrl = TextEditingController();
  final _secondaryNetworkPortCtrl = TextEditingController(text: '9100');
  final _secondaryLocalPrinterCtrl = TextEditingController();
  final _secondaryHeaderCtrl = TextEditingController(text: 'KITCHEN COPY');
  final _barcodeLocalPrinterCtrl = TextEditingController();
  final _barcodeNetworkIpCtrl = TextEditingController();
  final _barcodeNetworkPortCtrl = TextEditingController(text: '9100');
  final _barcodeWidthCtrl = TextEditingController(text: '50');
  final _barcodeHeightCtrl = TextEditingController(text: '30');
  final _barcodeGapCtrl = TextEditingController(text: '2');
  final _invoiceHeadingCtrl = TextEditingController(text: 'SALES INVOICE');
  final _qrUrlCtrl = TextEditingController();
  final _qrCaptionCtrl = TextEditingController(text: 'Scan to review us');
  final _whatsAppMessageCtrl = TextEditingController(
    text: WhatsAppMessageTemplateService.defaultTemplate,
  );

  String _activeConnection = 'none';
  bool _secondaryEnabled = false;
  bool _barcodeAddonActive = false;
  bool _barcodePermissionGranted = false;
  String _barcodeConnection = 'dialog';
  String _barcodeLanguage = 'driver';
  int _barcodeDpi = 203;
  String _barcodeOrientation = 'portrait';
  /// The branch's composed label design, in print order.
  final List<_LabelLineEntry> _barcodeLines = [];
  int _barcodeLineSeq = 0;

  List<BarcodeLabelLine> get _barcodeLabelLines =>
      _barcodeLines.map((e) => e.line).toList();

  // The four legacy booleans are still sent on save, derived from the design,
  // so a workstation still running the previous build keeps printing a
  // sensible label during a rolling update.
  bool get _barcodeShowName =>
      BarcodeLabelLine.legacyFlag(_barcodeLabelLines, BarcodeLabelField.productName);
  bool get _barcodeShowValue =>
      BarcodeLabelLine.legacyFlag(_barcodeLabelLines, BarcodeLabelField.barcodeValue);
  bool get _barcodeShowPrice =>
      BarcodeLabelLine.legacyFlag(_barcodeLabelLines, BarcodeLabelField.price);
  bool get _barcodeShowVariantDetails => BarcodeLabelLine.legacyFlag(
      _barcodeLabelLines, BarcodeLabelField.variantDetails);
  List<Printer> _installedPrinters = [];
  InvoiceTemplate _mainTemplate = InvoiceTemplate.standard;
  String _invoicePaperSize = 'a4';
  String _thermalPaperSize = 'mm80';
  bool _printLogoEnabled = false;
  String? _printLogoData;
  bool _qrCodeEnabled = false;
  WhatsAppInvoiceFormat _whatsAppInvoiceFormat = WhatsAppInvoiceFormat.pdf;
  InvoiceTemplate _whatsAppTemplate = InvoiceTemplate.standard;
  ItemDiscountDisplay _itemDiscountDisplay = ItemDiscountDisplay.compact;
  bool _whatsAppShowCustomerBalance = false;
  InvoiceTemplate _secondaryTemplate = InvoiceTemplate.kitchen;
  List<InvoiceTemplate> _templates = InvoiceTemplate.values;

  // Footer lines — each string is one printed line
  final List<TextEditingController> _footerCtrls = [];
  final List<ReceiptFooterStyle> _footerStyles = [];

  // Master-Admin-only software credit line, shown under the shop's own
  // footer on customer-facing invoices/receipts.
  bool _devCreditEnabled = true;
  final _devCreditTextCtrl = TextEditingController(text: 'Powered by A Developers');

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final token = auth.token!;
    _service = PrinterConfigService(token: token);
    _common = CommonService(token: token);
    _loadTemplates();
    _loadInstalledPrinters();
    if (auth.isMasterAdmin) {
      _loadBranches();
    } else {
      _loadingBranches = false;
      _selectedBranchId = auth.activeBranchId;
      if (_selectedBranchId != null) {
        _loadConfigFor(_selectedBranchId);
      }
    }
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await _service.getTemplates();
      if (!mounted) return;
      setState(() => _templates = templates);
    } catch (_) {}
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _shopAddressCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _networkIpCtrl.dispose();
    _networkPortCtrl.dispose();
    _localPrinterCtrl.dispose();
    _secondaryNetworkIpCtrl.dispose();
    _secondaryNetworkPortCtrl.dispose();
    _secondaryLocalPrinterCtrl.dispose();
    _secondaryHeaderCtrl.dispose();
    for (final entry in _barcodeLines) {
      entry.dispose();
    }
    _barcodeLocalPrinterCtrl.dispose();
    _barcodeNetworkIpCtrl.dispose();
    _barcodeNetworkPortCtrl.dispose();
    _barcodeWidthCtrl.dispose();
    _barcodeHeightCtrl.dispose();
    _barcodeGapCtrl.dispose();
    _invoiceHeadingCtrl.dispose();
    _qrUrlCtrl.dispose();
    _qrCaptionCtrl.dispose();
    _whatsAppMessageCtrl.dispose();
    _devCreditTextCtrl.dispose();
    for (final c in _footerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() => _loadingBranches = true);
    try {
      final rows = await _common.getBranches();
      if (!mounted) return;
      final activeBranchId = context.read<AuthProvider>().activeBranchId;
      final availableIds = rows.map((row) => row['id']).whereType<int>().toSet();
      final selected = activeBranchId != null && availableIds.contains(activeBranchId)
          ? activeBranchId
          : (rows.isEmpty ? null : rows.first['id'] as int?);
      setState(() {
        _branches = rows;
        _selectedBranchId = selected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _branches = []);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
    if (_selectedBranchId != null) {
      await _loadConfigFor(_selectedBranchId);
    }
  }

  Future<void> _loadInstalledPrinters() async {
    if (_loadingPrinters) return;
    setState(() => _loadingPrinters = true);
    try {
      final printers = await LocalPrinterService.instance.listInstalledPrinters();
      if (!mounted) return;
      setState(() => _installedPrinters = printers);
    } catch (_) {
      if (mounted) setState(() => _installedPrinters = []);
    } finally {
      if (mounted) setState(() => _loadingPrinters = false);
    }
  }

  Future<void> _loadConfigFor(int? branchId) async {
    setState(() => _loadingConfig = true);
    try {
      final auth = context.read<AuthProvider>();
      if (auth.isMasterAdmin) {
        final all = await _service.getAllPrinterSettings();
        final match = all.where((c) => c.branchId == branchId).toList();
        final config = match.isNotEmpty ? match.first : const PrinterConfig();
        _applyToForm(config.copyWith(
          barcodeAddonActive: _selectedBranchHasBarcodeAddon,
          barcodePermissionGranted: true,
          barcodeAccessGranted: _selectedBranchHasBarcodeAddon,
        ));
      } else {
        if (branchId == null || branchId != auth.activeBranchId) {
          throw Exception('You can only manage printer settings for your own business.');
        }
        final config = await _service.getPrinterConfig();
        _applyToForm(config);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load settings: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
      final auth = context.read<AuthProvider>();
      _applyToForm(PrinterConfig(
        barcodeAddonActive: auth.isMasterAdmin && _selectedBranchHasBarcodeAddon,
        barcodePermissionGranted: auth.isMasterAdmin,
        barcodeAccessGranted: auth.isMasterAdmin && _selectedBranchHasBarcodeAddon,
      ));
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  void _applyToForm(PrinterConfig config) {
    if (!mounted) return;
    // Rebuild footer controllers
    for (final c in _footerCtrls) {
      c.dispose();
    }
    _footerCtrls.clear();
    _footerStyles.clear();
    for (var i = 0; i < config.footerLines.length; i++) {
      _footerCtrls.add(TextEditingController(text: config.footerLines[i]));
      _footerStyles.add(config.footerStyleAt(i));
    }

    setState(() {
      _shopNameCtrl.text = config.shopName ?? '';
      _shopAddressCtrl.text = config.shopAddress ?? '';
      _shopPhoneCtrl.text = config.shopPhone ?? '';
      _activeConnection = config.activeConnection;
      _networkIpCtrl.text = config.networkIp ?? '';
      _networkPortCtrl.text = config.networkPort.toString();
      _localPrinterCtrl.text = config.localPrinterName ?? '';
      _secondaryEnabled = config.secondaryPrintEnabled;
      _secondaryNetworkIpCtrl.text = config.secondaryNetworkIp ?? '';
      _secondaryNetworkPortCtrl.text = config.secondaryNetworkPort.toString();
      _secondaryLocalPrinterCtrl.text = config.secondaryLocalPrinterName ?? '';
      _secondaryHeaderCtrl.text = config.secondaryReceiptHeader.trim().isEmpty
          ? 'KITCHEN COPY'
          : config.secondaryReceiptHeader;
      _mainTemplate = config.mainInvoiceTemplate;
      _invoicePaperSize = config.invoicePaperSize;
      _thermalPaperSize = config.thermalPaperSize;
      _invoiceHeadingCtrl.text = config.invoiceHeading;
      _printLogoEnabled = config.printLogoEnabled;
      _printLogoData = config.printLogoData;
      _qrCodeEnabled = config.qrCodeEnabled;
      _qrUrlCtrl.text = config.qrCodeUrl ?? '';
      _qrCaptionCtrl.text = config.qrCodeCaption;
      _whatsAppInvoiceFormat = config.whatsappInvoiceFormat;
      _whatsAppTemplate = config.whatsappInvoiceTemplate.isCustomerFacing
          ? config.whatsappInvoiceTemplate
          : InvoiceTemplate.standard;
      _itemDiscountDisplay = config.itemDiscountDisplay;
      _whatsAppMessageCtrl.text = config.whatsappMessageTemplate;
      _whatsAppShowCustomerBalance = config.whatsappShowCustomerBalance;
      _secondaryTemplate = config.secondaryInvoiceTemplate.isSecondaryEligible
          ? config.secondaryInvoiceTemplate
          : InvoiceTemplate.kitchen;
      _barcodeAddonActive = config.barcodeAddonActive;
      _barcodePermissionGranted = config.barcodePermissionGranted;
      _barcodeConnection = config.barcodeConnection;
      _barcodeLocalPrinterCtrl.text = config.barcodeLocalPrinterName ?? '';
      _barcodeNetworkIpCtrl.text = config.barcodeNetworkIp ?? '';
      _barcodeNetworkPortCtrl.text = config.barcodeNetworkPort.toString();
      _barcodeLanguage = config.barcodePrinterLanguage;
      _barcodeWidthCtrl.text = _numberText(config.barcodeLabelWidthMm);
      _barcodeHeightCtrl.text = _numberText(config.barcodeLabelHeightMm);
      _barcodeGapCtrl.text = _numberText(config.barcodeLabelGapMm);
      _barcodeDpi = config.barcodeDpi;
      _barcodeOrientation = config.barcodeOrientation;
      _setBarcodeLines(config.effectiveLabelLines);
      _devCreditEnabled = config.devCreditEnabled;
      _devCreditTextCtrl.text = config.devCreditText;
    });
  }

  String _numberText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

  List<String> get _installedPrinterNames {
    final names = _installedPrinters
        .map((p) => p.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  List<String> _printerNamesIncluding(String configuredName) {
    final names = [..._installedPrinterNames];
    final configured = configuredName.trim();
    if (configured.isNotEmpty && !names.any((name) => name.toLowerCase() == configured.toLowerCase())) {
      names.add(configured);
    }
    return names;
  }

  bool _isPrinterCurrentlyInstalled(String printerName) {
    final wanted = printerName.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    return _installedPrinters.any((printer) => printer.name.trim().toLowerCase() == wanted);
  }

  String? _printerDropdownValue(String configuredName, List<String> names) {
    final configured = configuredName.trim();
    if (configured.isEmpty) return null;
    for (final name in names) {
      if (name.toLowerCase() == configured.toLowerCase()) return name;
    }
    return configured;
  }

  Widget _buildLocalPrinterSelector({
    required TextEditingController controller,
    required String label,
  }) {
    final configured = controller.text.trim();
    final names = _printerNamesIncluding(configured);
    final value = _printerDropdownValue(configured, names);
    final available = configured.isNotEmpty && _isPrinterCurrentlyInstalled(configured);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: _loadingPrinters ? 'Loading installed printers...' : 'Select a printer installed in Windows',
            prefixIcon: const Icon(Icons.print_rounded),
            suffixIcon: IconButton(
              tooltip: 'Refresh installed printers',
              onPressed: _loadingPrinters ? null : _loadInstalledPrinters,
              icon: _loadingPrinters
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: _installedPrinters.isEmpty
              ? null
              : (selected) => setState(() => controller.text = selected ?? ''),
        ),
        const SizedBox(height: 8),
        if (!_loadingPrinters && _installedPrinters.isEmpty)
          const Text(
            'No installed Windows printers were found. Install the printer driver, make sure the printer appears in Windows Printers & scanners, then refresh.',
            style: TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w600),
          )
        else if (configured.isNotEmpty && !available)
          Text(
            'The saved printer "$configured" is not currently available on this computer. Select an available printer before printing.',
            style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w600),
          )
        else
          const Text(
            'Uses the Windows printer queue. USB, LAN, Wi-Fi and Bluetooth printers work when their Windows driver is installed.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  List<int> get _activeFooterIndexes => [
        for (var i = 0; i < _footerCtrls.length; i++)
          if (_footerCtrls[i].text.trim().isNotEmpty) i,
      ];

  List<String> get _currentFooterLines =>
      _activeFooterIndexes.map((i) => _footerCtrls[i].text.trim()).toList();

  List<ReceiptFooterStyle> get _currentFooterStyles =>
      _activeFooterIndexes.map((i) => _footerStyles[i]).toList();

  bool get _footerHasUnsupportedEmoji => _footerCtrls.any(
        (controller) => PrintTextUtils.containsUnsupportedEmoji(controller.text),
      );

  String get _selectedBranchCurrency {
    if (_selectedBranchId == null) return 'KD';
    final auth = context.read<AuthProvider>();
    if (!auth.isMasterAdmin) {
      return context.read<BranchProvider>().currency;
    }
    for (final branch in _branches) {
      if (branch['id'] == _selectedBranchId) {
        final value = branch['currency']?.toString().trim();
        return value == null || value.isEmpty ? 'KD' : value;
      }
    }
    return 'KD';
  }

  bool get _selectedBranchHasBarcodeAddon {
    if (_selectedBranchId == null) return false;
    for (final branch in _branches) {
      if (branch['id'] == _selectedBranchId) {
        final addons = branch['addons'];
        if (addons is Map) {
          final value = addons['barcode_labels'];
          if (value is Map) return value['active'] == true || value['is_active'] == true;
          return value == true;
        }
      }
    }
    return false;
  }

  void _addFooterLine() {
    setState(() {
      _footerCtrls.add(TextEditingController());
      _footerStyles.add(const ReceiptFooterStyle());
    });
  }

  void _removeFooterLine(int index) {
    setState(() {
      _footerCtrls[index].dispose();
      _footerCtrls.removeAt(index);
      _footerStyles.removeAt(index);
    });
  }

  void _reorderFooterLine(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final controller = _footerCtrls.removeAt(oldIndex);
      final style = _footerStyles.removeAt(oldIndex);
      _footerCtrls.insert(newIndex, controller);
      _footerStyles.insert(newIndex, style);
    });
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-printer-settings')) {
      _showMessage('You do not have permission to manage printer settings.');
      return;
    }
    final selectedBranchId = _selectedBranchId;
    if (selectedBranchId == null) {
      _showMessage('Select a business before saving printer settings.');
      return;
    }
    final barcodeWidth = double.tryParse(_barcodeWidthCtrl.text.trim());
    final barcodeHeight = double.tryParse(_barcodeHeightCtrl.text.trim());
    final barcodeGap = double.tryParse(_barcodeGapCtrl.text.trim());
    final barcodePort = int.tryParse(_barcodeNetworkPortCtrl.text.trim());

    if (_activeConnection == 'network' && _networkIpCtrl.text.trim().isEmpty) {
      _showMessage('Enter the printer\'s network address.');
      return;
    }
    if (_activeConnection == 'local' && _localPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Select an installed receipt printer.');
      return;
    }
    if (_mainTemplate.isPaged && _activeConnection == 'network') {
      _showMessage('Standard Invoice requires This computer / Windows printer or PDF printing. Raw network thermal mode is not supported.');
      return;
    }
    if (_printLogoEnabled && (_printLogoData ?? '').trim().isEmpty) {
      _showMessage('Upload a print logo or turn Show logo off.');
      return;
    }
    if (_qrCodeEnabled) {
      final rawUrl = _qrUrlCtrl.text.trim();
      final uri = Uri.tryParse(rawUrl);
      if (rawUrl.isEmpty || uri == null || !const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
        _showMessage('Enter a valid http:// or https:// URL for the print QR code.');
        return;
      }
    }
    if (_secondaryEnabled && _activeConnection == 'local' && _secondaryLocalPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Select an installed secondary printer.');
      return;
    }
    if (_secondaryEnabled && _activeConnection == 'network' && _secondaryNetworkIpCtrl.text.trim().isEmpty) {
      _showMessage("Enter the secondary printer's network address.");
      return;
    }
    if (_secondaryEnabled && _secondaryHeaderCtrl.text.trim().isEmpty) {
      _showMessage('Enter a header for the secondary receipt.');
      return;
    }
    if (_barcodeAddonActive && _barcodeConnection == 'local' && _barcodeLocalPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Select an installed printer for barcode labels.');
      return;
    }
    if (_barcodeAddonActive && _barcodeConnection == 'network') {
      if (_barcodeNetworkIpCtrl.text.trim().isEmpty) {
        _showMessage('Enter the barcode printer network address.');
        return;
      }
      if (!const {'zpl', 'tspl'}.contains(_barcodeLanguage)) {
        _showMessage('Choose ZPL or TSPL for direct network barcode printing.');
        return;
      }
      if (barcodePort == null || barcodePort < 1 || barcodePort > 65535) {
        _showMessage('Enter a valid barcode printer port from 1 to 65535.');
        return;
      }
    }
    if (_barcodeAddonActive &&
        (barcodeWidth == null || barcodeWidth < 15 || barcodeWidth > 200 ||
            barcodeHeight == null || barcodeHeight < 10 || barcodeHeight > 200 ||
            barcodeGap == null || barcodeGap < 0 || barcodeGap > 20)) {
      _showMessage('Enter a valid label size (15–200 mm wide, 10–200 mm high, gap 0–20 mm).');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.savePrinterConfig(
        branchId: selectedBranchId,
        shopName: _shopNameCtrl.text.trim(),
        shopAddress: _shopAddressCtrl.text.trim(),
        shopPhone: _shopPhoneCtrl.text.trim(),
        footerLines: _currentFooterLines,
        footerLineStyles: _currentFooterStyles,
        activeConnection: _activeConnection,
        networkIp: _networkIpCtrl.text.trim().isEmpty ? null : _networkIpCtrl.text.trim(),
        networkPort: int.tryParse(_networkPortCtrl.text.trim()) ?? 9100,
        localPrinterName: _localPrinterCtrl.text.trim().isEmpty ? null : _localPrinterCtrl.text.trim(),
        mainInvoiceTemplate: _mainTemplate,
        invoicePaperSize: _invoicePaperSize,
        thermalPaperSize: _thermalPaperSize,
        invoiceHeading: _invoiceHeadingCtrl.text.trim().isEmpty ? 'SALES INVOICE' : _invoiceHeadingCtrl.text.trim(),
        printLogoEnabled: _printLogoEnabled,
        printLogoData: _printLogoData,
        qrCodeEnabled: _qrCodeEnabled,
        qrCodeUrl: _qrUrlCtrl.text.trim().isEmpty ? null : _qrUrlCtrl.text.trim(),
        qrCodeCaption: _qrCaptionCtrl.text.trim(),
        whatsappInvoiceFormat: _whatsAppInvoiceFormat,
        whatsappInvoiceTemplate: _whatsAppTemplate,
        itemDiscountDisplay: _itemDiscountDisplay,
        whatsappMessageTemplate: _whatsAppMessageCtrl.text.trim().isEmpty
            ? WhatsAppMessageTemplateService.defaultTemplate
            : _whatsAppMessageCtrl.text.trim(),
        whatsappShowCustomerBalance: _whatsAppShowCustomerBalance,
        secondaryPrintEnabled: _secondaryEnabled,
        secondaryNetworkIp: _secondaryNetworkIpCtrl.text.trim().isEmpty ? null : _secondaryNetworkIpCtrl.text.trim(),
        secondaryNetworkPort: int.tryParse(_secondaryNetworkPortCtrl.text.trim()) ?? 9100,
        secondaryLocalPrinterName: _secondaryLocalPrinterCtrl.text.trim().isEmpty ? null : _secondaryLocalPrinterCtrl.text.trim(),
        secondaryInvoiceTemplate: _secondaryTemplate,
        secondaryReceiptHeader: _secondaryHeaderCtrl.text.trim(),
        barcodePrintEnabled: _barcodeAddonActive,
        barcodeConnection: _barcodeConnection,
        barcodeLocalPrinterName: _barcodeLocalPrinterCtrl.text.trim().isEmpty ? null : _barcodeLocalPrinterCtrl.text.trim(),
        barcodeNetworkIp: _barcodeNetworkIpCtrl.text.trim().isEmpty ? null : _barcodeNetworkIpCtrl.text.trim(),
        barcodeNetworkPort: barcodePort ?? 9100,
        barcodePrinterLanguage: _barcodeLanguage,
        barcodeLabelWidthMm: barcodeWidth ?? 50,
        barcodeLabelHeightMm: barcodeHeight ?? 30,
        barcodeLabelGapMm: barcodeGap ?? 2,
        barcodeDpi: _barcodeDpi,
        barcodeOrientation: _barcodeOrientation,
        barcodeCurrency: _selectedBranchCurrency,
        barcodeShowName: _barcodeShowName,
        barcodeShowValue: _barcodeShowValue,
        barcodeShowPrice: _barcodeShowPrice,
        barcodeShowVariantDetails: _barcodeShowVariantDetails,
        barcodeLabelLines: _barcodeLabelLines,
        devCreditEnabled: _devCreditEnabled,
        devCreditText: _devCreditTextCtrl.text.trim().isEmpty
            ? 'Powered by A Developers'
            : _devCreditTextCtrl.text.trim(),
      );

      if (!mounted) return;
      _showMessage('Printer settings saved.');

      final token = context.read<AuthProvider>().token;
      if (token != null) {
        await context.read<PrinterConfigProvider>().refresh(
              token,
              branchId: context.read<AuthProvider>().activeBranchId,
            );
      }
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _mainPaperCode {
    if (_mainTemplate.isPaged) return _invoicePaperSize;
    if (_mainTemplate.usesConfigurableThermalWidth) return _thermalPaperSize;
    return _mainTemplate.paperWidthCode;
  }

  Future<void> _testPrint() async {
    if (_activeConnection == 'none') {
      _showMessage('Choose Network or This computer before sending a test print.');
      return;
    }

    if (_mainTemplate.isPaged && _activeConnection == 'network') {
      _showMessage('Paged invoice templates cannot be sent as raw ESC/POS. Choose This computer or use Preview / PDF.');
      return;
    }

    setState(() => _testing = true);
    try {
      if (_activeConnection == 'network') {
        final ip = _networkIpCtrl.text.trim();
        if (ip.isEmpty) {
          throw Exception("Enter the printer's network address first.");
        }
        final port = int.tryParse(_networkPortCtrl.text.trim()) ?? 9100;
        await _service.validateTestDestination(
          activeConnection: 'network',
          networkIp: ip,
          networkPort: port,
        );
        await ThermalPrinterService.instance.testPrintNetwork(
          printerIp: ip,
          port: port,
          shopName: _shopNameCtrl.text.trim().isNotEmpty ? _shopNameCtrl.text.trim() : 'Test Print',
          paperWidth: _mainPaperCode,
          showLogo: _printLogoEnabled && _mainTemplate.isCustomerFacing,
          logoData: _printLogoData,
          showQr: _qrCodeEnabled && _mainTemplate.isCustomerFacing,
          qrUrl: _qrUrlCtrl.text.trim().isEmpty ? null : _qrUrlCtrl.text.trim(),
          qrCaption: _qrCaptionCtrl.text.trim(),
          footerLines: _currentFooterLines,
          footerLineStyles: _currentFooterStyles,
          template: _mainTemplate,
          itemDiscountDisplay: _itemDiscountDisplay,
        );
      } else {
        final printerName = _localPrinterCtrl.text.trim();
        if (printerName.isEmpty) {
          throw Exception('Select an installed receipt printer first.');
        }
        await LocalPrinterService.instance.testReceipt(
          printerName: printerName,
          shopName: _shopNameCtrl.text.trim().isNotEmpty ? _shopNameCtrl.text.trim() : 'CounterIQ',
          shopAddress: _shopAddressCtrl.text.trim().isEmpty ? null : _shopAddressCtrl.text.trim(),
          shopPhone: _shopPhoneCtrl.text.trim().isEmpty ? null : _shopPhoneCtrl.text.trim(),
          sections: _mainTemplate.sections,
          paperWidth: _mainPaperCode,
          footerLines: _currentFooterLines,
          footerLineStyles: _currentFooterStyles,
          copyLabel: 'RECEIPT PRINTER TEST',
          invoiceHeading: _invoiceHeadingCtrl.text.trim().isEmpty ? 'SALES INVOICE' : _invoiceHeadingCtrl.text.trim(),
          showLogo: _printLogoEnabled && _mainTemplate.isCustomerFacing,
          logoData: _printLogoData,
          showQr: _qrCodeEnabled && _mainTemplate.isCustomerFacing,
          qrUrl: _qrUrlCtrl.text.trim().isEmpty ? null : _qrUrlCtrl.text.trim(),
          qrCaption: _qrCaptionCtrl.text.trim(),
          template: _mainTemplate,
          itemDiscountDisplay: _itemDiscountDisplay,
        );
      }
      _showMessage(_mainTemplate.isPaged ? 'Test invoice sent — check the printer.' : 'Test ticket sent — check the printer.');
    } catch (e) {
      _showMessage('Test print failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testSecondaryPrint() async {
    if (_activeConnection == 'none') {
      _showMessage('Choose Network or This computer for the main printer first.');
      return;
    }

    setState(() => _testingSecondary = true);
    try {
      if (_activeConnection == 'network') {
        final ip = _secondaryNetworkIpCtrl.text.trim();
        if (ip.isEmpty) {
          throw Exception("Enter the secondary printer's network address first.");
        }
        final port = int.tryParse(_secondaryNetworkPortCtrl.text.trim()) ?? 9100;
        await _service.validateTestDestination(
          activeConnection: 'network',
          networkIp: ip,
          networkPort: port,
        );
        await ThermalPrinterService.instance.testPrintNetwork(
          printerIp: ip,
          port: port,
          shopName: _shopNameCtrl.text.trim().isNotEmpty
              ? _shopNameCtrl.text.trim()
              : 'CounterIQ',
          paperWidth: _secondaryTemplate.paperWidthCode,
          receiptHeader: _secondaryHeaderCtrl.text.trim().isEmpty
              ? 'KITCHEN COPY'
              : _secondaryHeaderCtrl.text.trim(),
          footerLines: _currentFooterLines,
          footerLineStyles: _currentFooterStyles,
          itemDiscountDisplay: _itemDiscountDisplay,
        );
      } else {
        final printerName = _secondaryLocalPrinterCtrl.text.trim();
        if (printerName.isEmpty) {
          throw Exception('Select an installed secondary printer first.');
        }
        await LocalPrinterService.instance.testReceipt(
          printerName: printerName,
          shopName: _shopNameCtrl.text.trim().isNotEmpty
              ? _shopNameCtrl.text.trim()
              : 'CounterIQ',
          shopAddress: _shopAddressCtrl.text.trim().isEmpty
              ? null
              : _shopAddressCtrl.text.trim(),
          shopPhone: _shopPhoneCtrl.text.trim().isEmpty ? null : _shopPhoneCtrl.text.trim(),
          sections: _secondaryTemplate.sections,
          paperWidth: _secondaryTemplate.paperWidthCode,
          footerLines: _currentFooterLines,
          footerLineStyles: _currentFooterStyles,
          receiptHeader: _secondaryHeaderCtrl.text.trim().isEmpty
              ? 'KITCHEN COPY'
              : _secondaryHeaderCtrl.text.trim(),
          copyLabel: 'SECONDARY PRINTER TEST',
          itemDiscountDisplay: _itemDiscountDisplay,
        );
      }
      _showMessage('Secondary printer test ticket sent.');
    } catch (e) {
      _showMessage('Secondary printer test failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testingSecondary = false);
    }
  }

  PrinterConfig _barcodeConfigFromForm() {
    return PrinterConfig(
      barcodeAddonActive: true,
      barcodePermissionGranted: true,
      barcodeAccessGranted: true,
      barcodePrintEnabled: true,
      barcodeConnection: _barcodeConnection,
      barcodeLocalPrinterName: _barcodeLocalPrinterCtrl.text.trim().isEmpty
          ? null
          : _barcodeLocalPrinterCtrl.text.trim(),
      barcodeNetworkIp: _barcodeNetworkIpCtrl.text.trim().isEmpty
          ? null
          : _barcodeNetworkIpCtrl.text.trim(),
      barcodeNetworkPort: int.tryParse(_barcodeNetworkPortCtrl.text.trim()) ?? 9100,
      barcodePrinterLanguage: _barcodeLanguage,
      barcodeLabelWidthMm: double.tryParse(_barcodeWidthCtrl.text.trim()) ?? 50,
      barcodeLabelHeightMm: double.tryParse(_barcodeHeightCtrl.text.trim()) ?? 30,
      barcodeLabelGapMm: double.tryParse(_barcodeGapCtrl.text.trim()) ?? 2,
      barcodeDpi: _barcodeDpi,
      barcodeOrientation: _barcodeOrientation,
      barcodeCurrency: _selectedBranchCurrency,
      barcodeShowName: _barcodeShowName,
      barcodeShowValue: _barcodeShowValue,
      barcodeShowPrice: _barcodeShowPrice,
      barcodeShowVariantDetails: _barcodeShowVariantDetails,
      barcodeLabelLines: _barcodeLabelLines,
      // The shop-name line reads this, so a preview shows the real shop name
      // as it is currently typed rather than a blank row.
      shopName: _shopNameCtrl.text.trim(),
    );
  }

  // ── barcode label designer ──────────────────────────────────────────────

  void _setBarcodeLines(List<BarcodeLabelLine> lines) {
    for (final entry in _barcodeLines) {
      entry.dispose();
    }
    _barcodeLines
      ..clear()
      ..addAll(lines.map((line) => _LabelLineEntry(_barcodeLineSeq++, line)));
  }

  void _updateBarcodeLine(int index, BarcodeLabelLine line) {
    setState(() => _barcodeLines[index].line = line);
  }

  /// Fields already on the label. Everything except a free-text line is a
  /// single value on the product, so it is offered only once.
  Set<BarcodeLabelField> get _usedBarcodeFields => _barcodeLines
      .map((e) => e.line.field)
      .where((f) => f != BarcodeLabelField.customText)
      .toSet();

  List<BarcodeLabelField> get _addableBarcodeFields => BarcodeLabelField.values
      .where((f) => !_usedBarcodeFields.contains(f))
      .toList();

  void _addBarcodeLine(BarcodeLabelField field) {
    setState(() {
      _barcodeLines.add(
        _LabelLineEntry(
          _barcodeLineSeq++,
          BarcodeLabelLine(
            field: field,
            label: _defaultLabelWord(field),
            size: field == BarcodeLabelField.salePrice
                ? BarcodeLabelTextSize.large
                : BarcodeLabelTextSize.normal,
          ),
        ),
      );
    });
  }

  /// A starting prefix word so a newly added line reads as a sentence
  /// immediately. Every one of these is editable — a shop printing in Urdu or
  /// Arabic simply types over them.
  String _defaultLabelWord(BarcodeLabelField field) {
    switch (field) {
      case BarcodeLabelField.price:
        return 'Price:';
      case BarcodeLabelField.discount:
        return 'Discount:';
      case BarcodeLabelField.salePrice:
        return 'Now:';
      case BarcodeLabelField.sku:
        return 'SKU:';
      default:
        return '';
    }
  }

  Widget _buildBarcodeLabelDesigner() {
    final addable = _addableBarcodeFields;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Label content',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(
                  () => _setBarcodeLines(
                    BarcodeLabelLine.fromLegacyFlags(
                      showName: true,
                      showVariantDetails: true,
                      showValue: true,
                      showPrice: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Drag to reorder. The prefix word is yours to write — in English, '
              'Urdu, Arabic or anything else. Lines with nothing to print are '
              'skipped automatically, so a discount line only appears on '
              'products that actually have a discount.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_barcodeLines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No lines yet. Add one below.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _barcodeLines.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = _barcodeLines.removeAt(oldIndex);
                  _barcodeLines.insert(newIndex, moved);
                });
              },
              itemBuilder: (context, index) => _buildBarcodeLineRow(index),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<BarcodeLabelField>(
              enabled: addable.isNotEmpty,
              onSelected: _addBarcodeLine,
              itemBuilder: (_) => addable
                  .map(
                    (field) => PopupMenuItem(
                      value: field,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            field.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            field.hint,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: addable.isEmpty ? AppTheme.border : AppTheme.primary,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 18,
                      color:
                          addable.isEmpty ? AppTheme.textMuted : AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      addable.isEmpty ? 'All lines added' : 'Add line',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: addable.isEmpty
                            ? AppTheme.textMuted
                            : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeLineRow(int index) {
    final entry = _barcodeLines[index];
    final line = entry.line;
    final field = line.field;

    return Padding(
      key: ValueKey(entry.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator_rounded,
                    size: 20, color: AppTheme.textMuted),
              ),
            ),
            Checkbox(
              value: line.enabled,
              onChanged: (v) =>
                  _updateBarcodeLine(index, line.copyWith(enabled: v ?? false)),
            ),
            SizedBox(
              width: 128,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    field.title,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  if (field == BarcodeLabelField.discount ||
                      field == BarcodeLabelField.salePrice)
                    const Text(
                      'discounted items only',
                      style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: field.supportsLabelWord
                  ? TextField(
                      controller: entry.controller,
                      textDirection: _looksRtl(entry.controller.text)
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: field.labelWordIsContent
                            ? 'Text to print'
                            : 'Prefix word',
                        hintText: field.labelWordIsContent
                            ? 'e.g. Exchange within 7 days'
                            : 'optional',
                      ),
                      onChanged: (v) => _updateBarcodeLine(
                        index,
                        line.copyWith(label: v),
                      ),
                    )
                  : Text(
                      field.hint,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                    ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<BarcodeLabelTextSize>(
                value: line.size,
                isDense: true,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Size'),
                items: BarcodeLabelTextSize.values
                    .map((size) => DropdownMenuItem(
                          value: size,
                          child: Text(size.title,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: field.isGraphic
                    ? null
                    : (v) => _updateBarcodeLine(
                          index,
                          line.copyWith(size: v ?? BarcodeLabelTextSize.normal),
                        ),
              ),
            ),
            IconButton(
              tooltip: 'Remove line',
              onPressed: () => setState(() {
                _barcodeLines.removeAt(index).dispose();
              }),
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors the renderer's script check so the prefix-word field reads
  /// right-to-left while an Urdu or Arabic word is being typed.
  static bool _looksRtl(String value) {
    for (final rune in value.runes) {
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF) ||
          (rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _testBarcodePrint() async {
    if (!_barcodePermissionGranted) {
      _showMessage('You need Print Barcode Labels permission to configure or test barcode printing.');
      return;
    }
    if (!_barcodeAddonActive) {
      _showMessage('Activate the Barcode Label Printing add-on for this branch first.');
      return;
    }
    if (_barcodeConnection == 'local' && _barcodeLocalPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Select an installed barcode printer first.');
      return;
    }
    if (_barcodeConnection == 'network' && _barcodeNetworkIpCtrl.text.trim().isEmpty) {
      _showMessage('Enter the barcode printer network address first.');
      return;
    }
    setState(() => _testingBarcode = true);
    try {
      await BarcodeLabelPrinterService.instance.testPrint(_barcodeConfigFromForm());
      _showMessage('Barcode test label sent.');
    } catch (e) {
      _showMessage('Barcode test failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testingBarcode = false);
    }
  }

  Future<void> _previewBarcodeLabel() async {
    if (!_barcodePermissionGranted) {
      _showMessage('You need Print Barcode Labels permission to configure barcode printing.');
      return;
    }
    if (!_barcodeAddonActive) {
      _showMessage('Activate the Barcode Label Printing add-on for this branch first.');
      return;
    }
    final config = _barcodeConfigFromForm();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 620,
          height: 560,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.preview_rounded, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Barcode Label Preview',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PdfPreview(
                      // A sample that exercises every line type, including
                      // the discount-only ones, so the design is fully visible
                      // before it reaches a printer.
                      build: (_) => BarcodeLabelPrinterService.instance.buildLabelsPdf(
                        config: config,
                        productName: 'Classic T-Shirt',
                        variantDetails: 'Black / M',
                        barcode: '123456789012',
                        price: 1250,
                        sku: 'TS-BLK-M',
                        discount: 10,
                        discountType: 'percentage',
                      ),
                      initialPageFormat: BarcodeLabelPrinterService.instance.pageFormat(config),
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      allowPrinting: false,
                      allowSharing: false,
                      useActions: false,
                      pdfFileName: 'barcode-label-preview.pdf',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openPreview(InvoiceTemplate template, {String? receiptHeader}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceTemplatePreviewScreen(
          templates: receiptHeader == null
              ? _templates
              : _templates.where((t) => t.isSecondaryEligible).toList(),
          initialTemplate: template,
          shopName: _shopNameCtrl.text.trim().isNotEmpty ? _shopNameCtrl.text.trim() : 'My Shop',
          shopAddress: _shopAddressCtrl.text.trim().isEmpty ? null : _shopAddressCtrl.text.trim(),
          shopPhone: _shopPhoneCtrl.text.trim().isEmpty ? null : _shopPhoneCtrl.text.trim(),
          footerLines: _currentFooterLines,
          footerLineStyles: _currentFooterStyles,
          receiptHeader: receiptHeader,
          invoicePaperSize: _invoicePaperSize,
          thermalPaperSize: _thermalPaperSize,
          invoiceHeading: _invoiceHeadingCtrl.text.trim().isEmpty ? 'SALES INVOICE' : _invoiceHeadingCtrl.text.trim(),
          showLogo: _printLogoEnabled && template.isCustomerFacing,
          logoData: _printLogoData,
          showQr: _qrCodeEnabled && template.isCustomerFacing,
          qrUrl: _qrUrlCtrl.text.trim().isEmpty ? null : _qrUrlCtrl.text.trim(),
          qrCaption: _qrCaptionCtrl.text.trim(),
          itemDiscountDisplay: _itemDiscountDisplay,
          devCreditEnabled: receiptHeader == null && _devCreditEnabled,
          devCreditText: _devCreditTextCtrl.text.trim().isEmpty
              ? 'Powered by A Developers'
              : _devCreditTextCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.hasPermission('manage-printer-settings')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Printer Settings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to manage printer settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Settings')),
      body: _loadingBranches
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                auth.isMasterAdmin ? _buildBranchPicker() : _buildOwnBusinessPanel(),
                const SizedBox(height: 14),
                if (_loadingConfig)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _buildShopInfoPanel(),
                  const SizedBox(height: 14),
                  _buildConnectionPanel(),
                  const SizedBox(height: 14),
                  _buildTemplatePanel(),
                  const SizedBox(height: 14),
                  _buildInvoiceBrandingPanel(),
                  const SizedBox(height: 14),
                  _buildWhatsAppInvoicePanel(),
                  const SizedBox(height: 14),
                  _buildFooterLinesPanel(),
                  const SizedBox(height: 14),
                  if (auth.isMasterAdmin) ...[
                    _buildDevCreditPanel(),
                    const SizedBox(height: 14),
                  ],
                  _buildSecondaryPanel(),
                  const SizedBox(height: 14),
                  _buildBarcodePanel(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Saving...' : 'Save Settings'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildOwnBusinessPanel() {
    final branch = context.watch<BranchProvider>();
    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Business printer settings',
            subtitle: 'You can configure printer and invoice settings only for your assigned business.',
            icon: Icons.store_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_rounded),
            title: Text(branch.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Currency: ${branch.currency}'),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchPicker() {
    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Which business is this for?',
            subtitle: 'Printer and receipt settings are isolated for each business.',
            icon: Icons.store_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            value: _selectedBranchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Business',
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
            items: _branches
                .map((business) => DropdownMenuItem<int>(
                      value: business['id'] as int,
                      child: Text((business['name'] ?? 'Business #${business['id']}').toString()),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedBranchId = value);
              _loadConfigFor(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShopInfoPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Shop details on the receipt',
            icon: Icons.storefront_rounded,
            color: AppTheme.teal,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _shopNameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Shop name',
              prefixIcon: Icon(Icons.badge_rounded),
              helperText: 'Bilingual supported: English | العربية',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shopAddressCtrl,
            decoration: const InputDecoration(
              labelText: 'Address',
              prefixIcon: Icon(Icons.location_on_rounded),
              helperText: 'Use | to separate English and Arabic when both are needed.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shopPhoneCtrl,
            decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.call_rounded)),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Receipt printer',
            subtitle: 'Choose where sale receipts print to.',
            icon: Icons.print_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'none', label: Text('PDF only'), icon: Icon(Icons.picture_as_pdf_rounded)),
              ButtonSegment(value: 'network', label: Text('Network'), icon: Icon(Icons.wifi_rounded)),
              ButtonSegment(value: 'local', label: Text('This computer'), icon: Icon(Icons.dvr_rounded)),
            ],
            selected: {_activeConnection},
            onSelectionChanged: (set) => setState(() => _activeConnection = set.first),
          ),
          const SizedBox(height: 16),
          if (_activeConnection == 'none')
            const Text(
              'Every sale will show a PDF preview to print or share instead of going straight to a thermal printer.',
              style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
          if (_activeConnection == 'network') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _networkIpCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Printer IP address',
                      hintText: 'e.g. 192.168.1.50',
                      prefixIcon: Icon(Icons.wifi_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _networkPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Most thermal WiFi/LAN printers listen on port 9100.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testPrint,
                icon: _testing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_rounded),
                label: Text(_testing ? 'Sending test ticket...' : 'Send Test Print'),
              ),
            ),
          ],
          if (_activeConnection == 'local') ...[
            _buildLocalPrinterSelector(
              controller: _localPrinterCtrl,
              label: _mainTemplate.isPaged ? 'Installed invoice printer' : 'Installed receipt printer',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testPrint,
                icon: _testing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_rounded),
                label: Text(_testing ? 'Sending test ticket...' : 'Send Test Print'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Uint8List? _decodedPrintLogo() {
    final raw = (_printLogoData ?? '').trim();
    if (raw.isEmpty) return null;
    final comma = raw.indexOf(',');
    if (comma <= 0 || comma >= raw.length - 1) return null;
    try {
      return base64Decode(raw.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPrintLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage('Could not read the selected image.');
        return;
      }
      if (bytes.length > 1024 * 1024) {
        _showMessage('Please use a logo smaller than 1 MB.');
        return;
      }
      final ext = (file.extension ?? '').toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      setState(() {
        _printLogoData = 'data:$mime;base64,${base64Encode(bytes)}';
        _printLogoEnabled = true;
      });
    } catch (e) {
      _showMessage('Could not load logo: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _removePrintLogo() {
    setState(() {
      _printLogoData = null;
      _printLogoEnabled = false;
    });
  }

  Widget _buildInvoiceBrandingPanel() {
    final logoBytes = _decodedPrintLogo();
    final hasLogo = logoBytes != null;
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Invoice branding & customer QR',
            subtitle: 'Shared customer-facing print options. Kitchen/secondary and barcode labels stay clean.',
            icon: Icons.branding_watermark_rounded,
            color: AppTheme.primary,
          ),
          if (_mainTemplate.isPaged || _whatsAppTemplate.isPaged) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _invoicePaperSize,
                    decoration: const InputDecoration(
                      labelText: 'Paged invoice paper size',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'a4', child: Text('A4')),
                      DropdownMenuItem(value: 'a5', child: Text('A5')),
                      DropdownMenuItem(value: 'letter', child: Text('Letter')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _invoicePaperSize = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _invoiceHeadingCtrl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Invoice heading',
                      hintText: 'SALES INVOICE',
                      prefixIcon: Icon(Icons.title_rounded),
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            if (_activeConnection == 'network') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: .08),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: .3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppTheme.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('Paged invoice templates use the Windows/PDF page renderer. Choose "This computer" for direct A4/A5/Letter printing.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _printLogoEnabled,
            onChanged: (value) => setState(() => _printLogoEnabled = value),
            title: const Text('Show business logo', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Shown on customer-facing main receipts/invoices when enabled.'),
          ),
          Row(
            children: [
              if (hasLogo)
                Container(
                  width: 76,
                  height: 58,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.memory(
                    logoBytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _pickPrintLogo,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(hasLogo ? 'Change logo' : 'Upload logo'),
              ),
              if (hasLogo) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _removePrintLogo,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _qrCodeEnabled,
            onChanged: (value) => setState(() => _qrCodeEnabled = value),
            title: const Text('Show customer QR code', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Use a review, website, WhatsApp, menu or feedback URL. Not printed on secondary/kitchen copies.'),
          ),
          if (_qrCodeEnabled) ...[
            const SizedBox(height: 6),
            TextFormField(
              controller: _qrUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'QR URL',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _qrCaptionCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'QR caption (optional)',
                hintText: 'Scan to review us',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
                counterText: '',
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _insertWhatsAppField(String placeholder) {
    final text = _whatsAppMessageCtrl.text;
    final selection = _whatsAppMessageCtrl.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : start;
    final next = text.replaceRange(start, end, placeholder);
    _whatsAppMessageCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + placeholder.length),
    );
    setState(() {});
  }

  String get _whatsAppMessagePreview {
    final shopName = _shopNameCtrl.text.trim().isEmpty
        ? 'Sample Store'
        : _shopNameCtrl.text.trim();
    return WhatsAppMessageTemplateService.render(
      template: _whatsAppMessageCtrl.text,
      showCustomerBalance: _whatsAppShowCustomerBalance,
      values: {
        'customer_name': 'Aziz',
        'customer_code': 'C.4421',
        'invoice_no': 'INV-20260823-0001',
        'invoice_amount': '1,000.00',
        'amount_paid': '0.00',
        'invoice_balance': '1,000.00',
        'customer_balance': '1,000.00',
        'business_name': shopName,
        'date': '23/08/2026',
        'currency': _selectedBranchCurrency,
        'attachment_format': _whatsAppInvoiceFormat.label,
      },
    );
  }

  Widget _buildWhatsAppInvoicePanel() {
    final scheme = Theme.of(context).colorScheme;
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'WhatsApp invoice',
            subtitle:
                'Configure the attachment and customer message for this business.',
            icon: Icons.chat_rounded,
            color: Color(0xFF128C7E),
          ),
          const SizedBox(height: 14),
          const Text(
            'Attachment format',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SegmentedButton<WhatsAppInvoiceFormat>(
            segments: const [
              ButtonSegment(
                value: WhatsAppInvoiceFormat.pdf,
                label: Text('PDF'),
                icon: Icon(Icons.picture_as_pdf_rounded),
              ),
              ButtonSegment(
                value: WhatsAppInvoiceFormat.jpg,
                label: Text('JPG'),
                icon: Icon(Icons.image_rounded),
              ),
            ],
            selected: {_whatsAppInvoiceFormat},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              setState(() => _whatsAppInvoiceFormat = selection.first);
            },
          ),
          const SizedBox(height: 10),
          Text(
            _whatsAppInvoiceFormat == WhatsAppInvoiceFormat.pdf
                ? 'PDF keeps the original invoice file exactly as generated.'
                : 'JPG uses the same invoice renderer and converts each PDF page to a high-quality image. Multi-page invoices create one JPG per page.',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<InvoiceTemplate>(
            value: _whatsAppTemplate,
            decoration: const InputDecoration(
              labelText: 'WhatsApp invoice template',
              prefixIcon: Icon(Icons.receipt_long_rounded),
              helperText:
                  'Independent from the Primary and Secondary printer templates.',
            ),
            items: _templates
                .where((template) => template.isCustomerFacing)
                .map(
                  (template) => DropdownMenuItem(
                    value: template,
                    child: Text(template.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _whatsAppTemplate = value);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openPreview(_whatsAppTemplate),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Preview WhatsApp template'),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Message template',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 5),
          const Text(
            'Write the message once and insert fields where CounterIQ should add sale or customer values automatically.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _whatsAppMessageCtrl,
            minLines: 8,
            maxLines: 14,
            maxLength: 4000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Enter the WhatsApp invoice message...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Insert field',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: WhatsAppMessageTemplateService.supportedFields
                .map(
                  (field) => ActionChip(
                    label: Text(field.label),
                    onPressed: () => _insertWhatsAppField(field.placeholder),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _whatsAppShowCustomerBalance,
            onChanged: (value) =>
                setState(() => _whatsAppShowCustomerBalance = value),
            title: const Text(
              'Show customer balance',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'When enabled, {{customer_balance}} uses the customer\'s authoritative trade-ledger balance after the sale. When disabled, any line containing that field is removed from the WhatsApp message.',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Message preview',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .75),
              ),
            ),
            child: SelectableText(
              _whatsAppMessagePreview.isEmpty
                  ? 'Your configured WhatsApp message will appear here.'
                  : _whatsAppMessagePreview,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_done_rounded, size: 16, color: AppTheme.textMuted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'The attachment format, invoice template, message template and balance privacy choice are saved per business. Every CounterIQ client using this business uses the same WhatsApp configuration.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Invoice template',
            subtitle: 'Choose the customer-facing thermal receipt or paged office invoice layout.',
            icon: Icons.receipt_long_rounded,
            color: AppTheme.teal,
          ),
          const SizedBox(height: 14),
          ..._templates.map((t) => _TemplateOptionTile(
                template: t,
                selected: _mainTemplate == t,
                onSelected: () => setState(() => _mainTemplate = t),
                onPreview: () => _openPreview(t),
              )),
          const SizedBox(height: 12),
          DropdownButtonFormField<ItemDiscountDisplay>(
            value: _itemDiscountDisplay,
            decoration: const InputDecoration(
              labelText: 'Item discount display',
              helperText: 'Compact keeps thermal receipts short. Detailed adds a separate discount line. Hidden prints only the final line amount.',
            ),
            items: ItemDiscountDisplay.values
                .map((mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(mode.label),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _itemDiscountDisplay = value);
            },
          ),
          if (_mainTemplate.usesConfigurableThermalWidth ||
              _whatsAppTemplate.usesConfigurableThermalWidth) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _thermalPaperSize,
              decoration: const InputDecoration(
                labelText: 'Arabic thermal paper width',
                prefixIcon: Icon(Icons.straighten_rounded),
                helperText: 'The same Arabic-first receipt layout adapts to 58 mm or 80 mm thermal rolls.',
              ),
              items: const [
                DropdownMenuItem(value: 'mm58', child: Text('58 mm thermal roll')),
                DropdownMenuItem(value: 'mm80', child: Text('80 mm thermal roll')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _thermalPaperSize = value);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooterLinesPanel() {
    String alignmentLabel(ReceiptFooterAlignment value) {
      switch (value) {
        case ReceiptFooterAlignment.left:
          return 'Left';
        case ReceiptFooterAlignment.center:
          return 'Center';
        case ReceiptFooterAlignment.right:
          return 'Right';
      }
    }

    String sizeLabel(ReceiptFooterTextSize value) {
      switch (value) {
        case ReceiptFooterTextSize.small:
          return 'Small';
        case ReceiptFooterTextSize.normal:
          return 'Normal';
        case ReceiptFooterTextSize.large:
          return 'Large';
      }
    }

    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnterpriseSectionHeader(
            title: 'Receipt footer',
            subtitle:
                'Format each line independently. Drag rows to control the print order.',
            icon: Icons.notes_rounded,
            color: AppTheme.navy,
            trailing: TextButton.icon(
              onPressed: _footerCtrls.length >= 10 ? null : _addFooterLine,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add line'),
            ),
          ),
          const SizedBox(height: 10),
          if (_footerCtrls.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.textMuted),
                  SizedBox(width: 8),
                  Text(
                    'No footer lines — tap "Add line" to add one.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _footerCtrls.length,
              onReorder: _reorderFooterLine,
              itemBuilder: (context, i) {
                final style = _footerStyles[i];
                return Container(
                  key: ObjectKey(_footerCtrls[i]),
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.fromLTRB(9, 9, 7, 9),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: TextFormField(
                              controller: _footerCtrls[i],
                              maxLength: 100,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Line ${i + 1}',
                                hintText: 'e.g. Thank you, visit again!',
                                counterText: '',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          IconButton(
                            onPressed: () => _removeFooterLine(i),
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              color: AppTheme.danger,
                            ),
                            tooltip: 'Remove this line',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 30, right: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<ReceiptFooterAlignment>(
                                value: style.alignment,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: 'Alignment',
                                  isDense: true,
                                ),
                                items: ReceiptFooterAlignment.values
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(alignmentLabel(value)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _footerStyles[i] = style.copyWith(
                                      alignment: value,
                                    );
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<ReceiptFooterTextSize>(
                                value: style.size,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: 'Text size',
                                  isDense: true,
                                ),
                                items: ReceiptFooterTextSize.values
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(sizeLabel(value)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _footerStyles[i] = style.copyWith(size: value);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilterChip(
                              label: const Text('Bold'),
                              selected: style.bold,
                              onSelected: (selected) {
                                setState(() {
                                  _footerStyles[i] = style.copyWith(bold: selected);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (_footerHasUnsupportedEmoji) ...[
            const SizedBox(height: 3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: .08),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: .3),
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                'Emoji detected. Thermal/PDF receipt fonts may not support emoji, so CounterIQ removes those symbols when printing to prevent square boxes.',
                style: TextStyle(
                  color: AppTheme.warning,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 5),
          const Text(
            'English and Arabic text are preserved. Alignment, bold and size apply to the matching footer line on receipt and invoice templates.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevCreditPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Software credit (Master Admin)',
            subtitle:
                'A small credit line for the software itself, printed under the shop\'s own footer. Only Master Admin can see or change this.',
            icon: Icons.verified_rounded,
            color: AppTheme.navy,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _devCreditEnabled,
            onChanged: (value) => setState(() => _devCreditEnabled = value),
            title: const Text('Show on this branch\'s invoices/receipts', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Appears in small text below the shop\'s own footer on customer-facing templates. Never shown on the kitchen ticket.'),
          ),
          if (_devCreditEnabled) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _devCreditTextCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Credit text',
                hintText: 'Powered by A Developers',
                prefixIcon: Icon(Icons.copyright_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondaryPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _secondaryEnabled,
            onChanged: (v) => setState(() => _secondaryEnabled = v),
            title: const Text('Enable Secondary Printer', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Send a second receipt or operational copy to another printer.'),
          ),
          if (_secondaryEnabled) ...[
            const SizedBox(height: 8),
            const Text('Secondary printer template', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ..._templates.where((t) => t.isSecondaryEligible).map((t) => _TemplateOptionTile(
                  template: t,
                  selected: _secondaryTemplate == t,
                  onSelected: () => setState(() => _secondaryTemplate = t),
                  onPreview: () => _openPreview(
                    t,
                    receiptHeader: _secondaryHeaderCtrl.text.trim().isEmpty
                        ? 'KITCHEN COPY'
                        : _secondaryHeaderCtrl.text.trim(),
                  ),
                  dense: true,
                )),
            const SizedBox(height: 12),
            TextFormField(
              controller: _secondaryHeaderCtrl,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Secondary receipt header',
                hintText: 'e.g. KITCHEN COPY, PACKING COPY, BAR COPY',
                prefixIcon: Icon(Icons.title_rounded),
                helperText: 'Printed prominently at the top of every secondary receipt.',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            if (_activeConnection == 'network') ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _secondaryNetworkIpCtrl,
                      decoration: const InputDecoration(labelText: 'Secondary printer IP', prefixIcon: Icon(Icons.wifi_rounded)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _secondaryNetworkPortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testingSecondary ? null : _testSecondaryPrint,
                  icon: _testingSecondary
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(_testingSecondary ? 'Sending...' : 'Send Test Print to Secondary Printer'),
                ),
              ),
            ] else if (_activeConnection == 'local') ...[
              _buildLocalPrinterSelector(
                controller: _secondaryLocalPrinterCtrl,
                label: 'Installed secondary printer',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testingSecondary ? null : _testSecondaryPrint,
                  icon: _testingSecondary
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(_testingSecondary ? 'Sending...' : 'Send Test Print to Secondary Printer'),
                ),
              ),
            ]
            else
              const Text(
                'Choose a network or local main printer above first.',
                style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarcodePanel() {
    if (_selectedBranchId == null || !_barcodeAddonActive) {
      final hasBranch = _selectedBranchId != null;
      return EnterprisePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EnterpriseSectionHeader(
              title: 'Barcode Printer',
              subtitle: 'Barcode Label Printing is a business add-on.',
              icon: Icons.qr_code_2_rounded,
              color: AppTheme.purple,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning.withOpacity(.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasBranch
                          ? 'Activate Barcode Label Printing for this business from Business Subscriptions before configuring a barcode printer.'
                          : 'Select a business first. Barcode printer configuration is business-specific.',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!_barcodePermissionGranted) {
      return EnterprisePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EnterpriseSectionHeader(
              title: 'Barcode Printer',
              subtitle: 'Barcode Label Printing is active for this business.',
              icon: Icons.qr_code_2_rounded,
              color: AppTheme.purple,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning.withOpacity(.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: AppTheme.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You need Print Barcode Labels permission to configure barcode-printer settings.',
                      style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Barcode Printer',
            subtitle: 'Configure product labels independently from receipt printers.',
            icon: Icons.qr_code_2_rounded,
            color: AppTheme.purple,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.success.withOpacity(.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_rounded, color: AppTheme.success, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Barcode Label Printing add-on is active. Saving this configuration makes it operational for users with Print Barcode Labels permission.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
            const Text('Connection', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dialog', label: Text('System dialog'), icon: Icon(Icons.print_outlined)),
                ButtonSegment(value: 'local', label: Text('Installed printer'), icon: Icon(Icons.dvr_rounded)),
                ButtonSegment(value: 'network', label: Text('Direct network'), icon: Icon(Icons.lan_rounded)),
              ],
              selected: {_barcodeConnection},
              onSelectionChanged: (values) {
                setState(() {
                  _barcodeConnection = values.first;
                  _barcodeLanguage = _barcodeConnection == 'network' ? 'zpl' : 'driver';
                });
              },
            ),
            const SizedBox(height: 14),
            if (_barcodeConnection == 'dialog')
              const Text(
                'The application creates an exact-size PDF label and opens the operating-system print dialog. '
                'This is the safest fallback for unknown printer models.',
                style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
            if (_barcodeConnection == 'local') ...[
              _buildLocalPrinterSelector(
                controller: _barcodeLocalPrinterCtrl,
                label: 'Installed barcode printer',
              ),
            ],
            if (_barcodeConnection == 'network') ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _barcodeNetworkIpCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Barcode printer IP address',
                        hintText: 'e.g. 192.168.1.60',
                        prefixIcon: Icon(Icons.lan_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeNetworkPortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _barcodeLanguage,
                decoration: const InputDecoration(
                  labelText: 'Printer command language',
                  prefixIcon: Icon(Icons.code_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'zpl', child: Text('ZPL — Zebra and compatible printers')),
                  DropdownMenuItem(value: 'tspl', child: Text('TSPL — TSC and compatible printers')),
                ],
                onChanged: (value) => setState(() => _barcodeLanguage = value ?? 'zpl'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use direct network mode only when the printer documentation confirms ZPL or TSPL support.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 18),
            const Text('Label size and calibration', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in const [(40.0, 25.0), (50.0, 30.0), (58.0, 40.0), (100.0, 50.0)])
                  ActionChip(
                    label: Text('${preset.$1.toInt()} × ${preset.$2.toInt()} mm'),
                    onPressed: () => setState(() {
                      _barcodeWidthCtrl.text = _numberText(preset.$1);
                      _barcodeHeightCtrl.text = _numberText(preset.$2);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _barcodeWidthCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Width (mm)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeHeightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Height (mm)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeGapCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Gap (mm)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _barcodeDpi,
                    decoration: const InputDecoration(labelText: 'Resolution'),
                    items: const [203, 300, 600]
                        .map((dpi) => DropdownMenuItem(value: dpi, child: Text('$dpi DPI')))
                        .toList(),
                    onChanged: (value) => setState(() => _barcodeDpi = value ?? 203),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _barcodeOrientation,
                    decoration: const InputDecoration(labelText: 'Orientation'),
                    items: const [
                      DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
                      DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
                    ],
                    onChanged: (value) => setState(() => _barcodeOrientation = value ?? 'portrait'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Currency (from branch)'),
                    child: Text(_selectedBranchCurrency, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildBarcodeLabelDesigner(),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(.045),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withOpacity(.16)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.description_outlined, size: 18, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A4 and A5 barcode cut sheets are selected at print time. CounterIQ fills the whole page using this configured label size, adds cut guides, and lets the user choose the configured barcode printer or any local/system printer.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _previewBarcodeLabel,
                    icon: const Icon(Icons.preview_rounded),
                    label: const Text('Preview Label'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingBarcode ? null : _testBarcodePrint,
                    icon: _testingBarcode
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.qr_code_2_rounded),
                    label: Text(_testingBarcode ? 'Sending test label...' : 'Print Test Barcode Label'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TemplateOptionTile extends StatelessWidget {
  final InvoiceTemplate template;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onPreview;
  final bool dense;

  const _TemplateOptionTile({
    required this.template,
    required this.selected,
    required this.onSelected,
    required this.onPreview,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppTheme.primary : AppTheme.border, width: selected ? 1.6 : 1),
        color: selected ? AppTheme.primary.withOpacity(.06) : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelected,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (!dense) ...[
                      const SizedBox(height: 2),
                      Text(
                        template.description,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Preview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the barcode label designer.
///
/// The design itself is a plain list of [BarcodeLabelLine]; this adds the two
/// things a reorderable, editable list needs and the model should not carry: a
/// stable identity for the drag animation, and a text controller so the prefix
/// word keeps its cursor position while the branch types.
class _LabelLineEntry {
  final int id;
  BarcodeLabelLine line;
  final TextEditingController controller;

  _LabelLineEntry(this.id, this.line)
      : controller = TextEditingController(text: line.label);

  void dispose() => controller.dispose();
}
