import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/screens/settings/invoice_template_preview_screen.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
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
  final _barcodeLocalPrinterCtrl = TextEditingController();
  final _barcodeNetworkIpCtrl = TextEditingController();
  final _barcodeNetworkPortCtrl = TextEditingController(text: '9100');
  final _barcodeWidthCtrl = TextEditingController(text: '50');
  final _barcodeHeightCtrl = TextEditingController(text: '30');
  final _barcodeGapCtrl = TextEditingController(text: '2');

  String _activeConnection = 'none';
  bool _secondaryEnabled = false;
  bool _barcodeEnabled = false;
  String _barcodeConnection = 'dialog';
  String _barcodeLanguage = 'driver';
  int _barcodeDpi = 203;
  String _barcodeOrientation = 'portrait';
  bool _barcodeShowName = true;
  bool _barcodeShowValue = true;
  bool _barcodeShowPrice = true;
  List<Printer> _installedPrinters = [];
  InvoiceTemplate _mainTemplate = InvoiceTemplate.standard;
  InvoiceTemplate _secondaryTemplate = InvoiceTemplate.kitchen;
  List<InvoiceTemplate> _templates = InvoiceTemplate.values;

  // Footer lines — each string is one printed line
  final List<TextEditingController> _footerCtrls = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final token = auth.token!;
    _service = PrinterConfigService(token: token);
    _common = CommonService(token: token);
    _loadTemplates();
    if (auth.isMasterAdmin) {
      _loadBranches();
      _loadInstalledPrinters();
    } else {
      _loadingBranches = false;
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
    _barcodeLocalPrinterCtrl.dispose();
    _barcodeNetworkIpCtrl.dispose();
    _barcodeNetworkPortCtrl.dispose();
    _barcodeWidthCtrl.dispose();
    _barcodeHeightCtrl.dispose();
    _barcodeGapCtrl.dispose();
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
      setState(() => _branches = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _branches = []);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
    await _loadConfigFor(_selectedBranchId);
  }

  Future<void> _loadInstalledPrinters() async {
    if (_loadingPrinters) return;
    setState(() => _loadingPrinters = true);
    try {
      final printers = await Printing.listPrinters();
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
      final all = await _service.getAllPrinterSettings();
      final match = all.where((c) => c.branchId == branchId).toList();
      final config = match.isNotEmpty ? match.first : const PrinterConfig();
      _applyToForm(config);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load settings: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
      _applyToForm(const PrinterConfig());
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
    for (final line in config.footerLines) {
      _footerCtrls.add(TextEditingController(text: line));
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
      _mainTemplate = config.mainInvoiceTemplate;
      _secondaryTemplate = config.secondaryInvoiceTemplate;
      _barcodeEnabled = config.barcodePrintEnabled;
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
      _barcodeShowName = config.barcodeShowName;
      _barcodeShowValue = config.barcodeShowValue;
      _barcodeShowPrice = config.barcodeShowPrice;
    });
  }

  String _numberText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

  List<String> get _currentFooterLines =>
      _footerCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  String get _selectedBranchCurrency {
    if (_selectedBranchId == null) return 'KD';
    for (final branch in _branches) {
      if (branch['id'] == _selectedBranchId) {
        final value = branch['currency']?.toString().trim();
        return value == null || value.isEmpty ? 'KD' : value;
      }
    }
    return 'KD';
  }

  void _addFooterLine() {
    setState(() => _footerCtrls.add(TextEditingController()));
  }

  void _removeFooterLine(int index) {
    setState(() {
      _footerCtrls[index].dispose();
      _footerCtrls.removeAt(index);
    });
  }

  Future<void> _save() async {
    final barcodeWidth = double.tryParse(_barcodeWidthCtrl.text.trim());
    final barcodeHeight = double.tryParse(_barcodeHeightCtrl.text.trim());
    final barcodeGap = double.tryParse(_barcodeGapCtrl.text.trim());
    final barcodePort = int.tryParse(_barcodeNetworkPortCtrl.text.trim());

    if (_activeConnection == 'network' && _networkIpCtrl.text.trim().isEmpty) {
      _showMessage('Enter the printer\'s network address.');
      return;
    }
    if (_activeConnection == 'local' && _localPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Enter the local printer name.');
      return;
    }
    if (_barcodeEnabled && _barcodeConnection == 'local' && _barcodeLocalPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Select an installed printer for barcode labels.');
      return;
    }
    if (_barcodeEnabled && _barcodeConnection == 'network') {
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
    if (_barcodeEnabled &&
        (barcodeWidth == null || barcodeWidth < 15 || barcodeWidth > 200 ||
            barcodeHeight == null || barcodeHeight < 10 || barcodeHeight > 200 ||
            barcodeGap == null || barcodeGap < 0 || barcodeGap > 20)) {
      _showMessage('Enter a valid label size (15–200 mm wide, 10–200 mm high, gap 0–20 mm).');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.savePrinterConfig(
        branchId: _selectedBranchId,
        shopName: _shopNameCtrl.text.trim(),
        shopAddress: _shopAddressCtrl.text.trim(),
        shopPhone: _shopPhoneCtrl.text.trim(),
        footerLines: _currentFooterLines,
        activeConnection: _activeConnection,
        networkIp: _networkIpCtrl.text.trim().isEmpty ? null : _networkIpCtrl.text.trim(),
        networkPort: int.tryParse(_networkPortCtrl.text.trim()) ?? 9100,
        localPrinterName: _localPrinterCtrl.text.trim().isEmpty ? null : _localPrinterCtrl.text.trim(),
        mainInvoiceTemplate: _mainTemplate,
        secondaryPrintEnabled: _secondaryEnabled,
        secondaryNetworkIp: _secondaryNetworkIpCtrl.text.trim().isEmpty ? null : _secondaryNetworkIpCtrl.text.trim(),
        secondaryNetworkPort: int.tryParse(_secondaryNetworkPortCtrl.text.trim()) ?? 9100,
        secondaryLocalPrinterName: _secondaryLocalPrinterCtrl.text.trim().isEmpty ? null : _secondaryLocalPrinterCtrl.text.trim(),
        secondaryInvoiceTemplate: _secondaryTemplate,
        barcodePrintEnabled: _barcodeEnabled,
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
      );

      if (!mounted) return;
      _showMessage('Printer settings saved.');

      final token = context.read<AuthProvider>().token;
      if (token != null) context.read<PrinterConfigProvider>().refresh(token);
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint() async {
    if (_activeConnection != 'network') {
      _showMessage('Test print currently supports network printers.');
      return;
    }
    final ip = _networkIpCtrl.text.trim();
    if (ip.isEmpty) {
      _showMessage('Enter the printer\'s network address first.');
      return;
    }
    final port = int.tryParse(_networkPortCtrl.text.trim()) ?? 9100;

    setState(() => _testing = true);
    try {
      await _service.validateTestDestination(
        activeConnection: 'network',
        networkIp: ip,
        networkPort: port,
      );
      await ThermalPrinterService.instance.testPrintNetwork(
        printerIp: ip,
        port: port,
        shopName: _shopNameCtrl.text.trim().isNotEmpty ? _shopNameCtrl.text.trim() : 'Test Print',
      );
      _showMessage('Test ticket sent — check the printer.');
    } catch (e) {
      _showMessage('Test print failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testSecondaryPrint() async {
    final ip = _secondaryNetworkIpCtrl.text.trim();
    if (ip.isEmpty) {
      _showMessage('Enter the secondary printer\'s network address first.');
      return;
    }
    final port = int.tryParse(_secondaryNetworkPortCtrl.text.trim()) ?? 9100;

    setState(() => _testingSecondary = true);
    try {
      await _service.validateTestDestination(
        activeConnection: 'network',
        networkIp: ip,
        networkPort: port,
      );
      await ThermalPrinterService.instance.testPrintNetwork(
        printerIp: ip,
        port: port,
        shopName: 'Secondary Printer Test',
      );
      _showMessage('Secondary printer test ticket sent.');
    } catch (e) {
      _showMessage('Secondary printer test failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testingSecondary = false);
    }
  }

  PrinterConfig _barcodeConfigFromForm() {
    return PrinterConfig(
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
    );
  }

  Future<void> _testBarcodePrint() async {
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openPreview(InvoiceTemplate template) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceTemplatePreviewScreen(
          templates: _templates,
          initialTemplate: template,
          shopName: _shopNameCtrl.text.trim().isNotEmpty ? _shopNameCtrl.text.trim() : 'My Shop',
          shopAddress: _shopAddressCtrl.text.trim().isEmpty ? null : _shopAddressCtrl.text.trim(),
          shopPhone: _shopPhoneCtrl.text.trim().isEmpty ? null : _shopPhoneCtrl.text.trim(),
          footerLines: _currentFooterLines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isMasterAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Printer Settings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Only master admin can manage printer settings.',
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
                _buildBranchPicker(),
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
                  _buildFooterLinesPanel(),
                  const SizedBox(height: 14),
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

  Widget _buildBranchPicker() {
    return EnterprisePanel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseSectionHeader(
            title: 'Which branch is this for?',
            subtitle: 'Each branch can have its own printer, or fall back to the global default.',
            icon: Icons.store_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            value: _selectedBranchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Branch',
              prefixIcon: Icon(Icons.account_tree_rounded),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Global default (used when a branch has no printer of its own)')),
              ..._branches.map((b) => DropdownMenuItem<int?>(
                    value: b['id'] as int?,
                    child: Text((b['name'] ?? 'Branch #${b['id']}').toString()),
                  )),
            ],
            onChanged: (v) {
              setState(() => _selectedBranchId = v);
              _loadConfigFor(v);
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
            decoration: const InputDecoration(labelText: 'Shop name', prefixIcon: Icon(Icons.badge_rounded)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shopAddressCtrl,
            decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on_rounded)),
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
            TextFormField(
              controller: _localPrinterCtrl,
              decoration: const InputDecoration(
                labelText: 'Local printer name',
                hintText: 'Exact name as it appears in this computer\'s printer list',
                prefixIcon: Icon(Icons.dvr_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.warning.withOpacity(.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Local printer support is not wired up yet — sales fall back to PDF preview. '
                      'A network printer works today.',
                      style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            subtitle: 'Which layout the main receipt prints with.',
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
        ],
      ),
    );
  }

  Widget _buildFooterLinesPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnterpriseSectionHeader(
            title: 'Receipt footer',
            subtitle: 'Each line prints centred at the bottom of every receipt.',
            icon: Icons.format_align_center_rounded,
            color: AppTheme.navy,
            trailing: TextButton.icon(
              onPressed: _addFooterLine,
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
                  Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textMuted),
                  SizedBox(width: 8),
                  Text('No footer lines — tap "Add line" to add one.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            ...List.generate(_footerCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _footerCtrls[i],
                        decoration: InputDecoration(
                          labelText: 'Line ${i + 1}',
                          hintText: 'e.g. Thank you, visit again!',
                          prefixIcon: const Icon(Icons.short_text_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _removeFooterLine(i),
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: AppTheme.danger),
                      tooltip: 'Remove this line',
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          const Text(
            'Tip: you can add your WiFi password, social media handles, or any message for your customers.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
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
            ..._templates.map((t) => _TemplateOptionTile(
                  template: t,
                  selected: _secondaryTemplate == t,
                  onSelected: () => setState(() => _secondaryTemplate = t),
                  onPreview: () => _openPreview(t),
                  dense: true,
                )),
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
            ] else if (_activeConnection == 'local')
              TextFormField(
                controller: _secondaryLocalPrinterCtrl,
                decoration: const InputDecoration(labelText: 'Secondary printer name', prefixIcon: Icon(Icons.dvr_rounded)),
              )
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
    final printerNames = _installedPrinters
        .map((p) => p.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final currentPrinter = _barcodeLocalPrinterCtrl.text.trim();
    if (currentPrinter.isNotEmpty && !printerNames.contains(currentPrinter)) {
      printerNames.add(currentPrinter);
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _barcodeEnabled,
            onChanged: (v) => setState(() => _barcodeEnabled = v),
            title: const Text('Enable barcode label printing', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Product-management users can print labels for products that have a barcode.'),
          ),
          if (_barcodeEnabled) ...[
            const SizedBox(height: 10),
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
              if (printerNames.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: currentPrinter.isEmpty ? null : currentPrinter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Installed printer',
                    prefixIcon: const Icon(Icons.print_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh installed printers',
                      onPressed: _loadingPrinters ? null : _loadInstalledPrinters,
                      icon: _loadingPrinters
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  items: printerNames.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                  onChanged: (value) => setState(() => _barcodeLocalPrinterCtrl.text = value ?? ''),
                )
              else
                TextFormField(
                  controller: _barcodeLocalPrinterCtrl,
                  decoration: InputDecoration(
                    labelText: 'Installed printer name',
                    hintText: 'Install the manufacturer driver, then refresh',
                    prefixIcon: const Icon(Icons.print_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh installed printers',
                      onPressed: _loadingPrinters ? null : _loadInstalledPrinters,
                      icon: _loadingPrinters
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Works with USB, LAN, Wi-Fi, and Bluetooth printers exposed through an installed Windows driver. '
                'If this queue is unavailable at print time, the system dialog opens automatically.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Product name'),
                  selected: _barcodeShowName,
                  onSelected: (v) => setState(() => _barcodeShowName = v),
                ),
                FilterChip(
                  label: const Text('Barcode value'),
                  selected: _barcodeShowValue,
                  onSelected: (v) => setState(() => _barcodeShowValue = v),
                ),
                FilterChip(
                  label: const Text('Price'),
                  selected: _barcodeShowPrice,
                  onSelected: (v) => setState(() => _barcodeShowPrice = v),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testingBarcode ? null : _testBarcodePrint,
                icon: _testingBarcode
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_2_rounded),
                label: Text(_testingBarcode ? 'Sending test label...' : 'Print Test Barcode Label'),
              ),
            ),
          ],
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
