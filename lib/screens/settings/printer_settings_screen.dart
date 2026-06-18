import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/printer_config_service.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/providers/auth_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Master-admin only: configure where receipts actually print to (a
/// network ESC/POS printer, or a printer installed on this computer), per
/// branch or as a global default, and test the connection before trusting
/// it for real sales.
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
  bool _testingKitchen = false;

  List<Map<String, dynamic>> _branches = [];
  int? _selectedBranchId; // null = global default

  // Form state
  final _shopNameCtrl = TextEditingController();
  final _shopAddressCtrl = TextEditingController();
  final _shopPhoneCtrl = TextEditingController();
  final _networkIpCtrl = TextEditingController();
  final _networkPortCtrl = TextEditingController(text: '9100');
  final _localPrinterCtrl = TextEditingController();
  final _kitchenNetworkIpCtrl = TextEditingController();
  final _kitchenNetworkPortCtrl = TextEditingController(text: '9100');
  final _kitchenLocalPrinterCtrl = TextEditingController();

  String _activeConnection = 'none'; // none | network | local
  bool _kitchenEnabled = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final token = auth.token!;
    _service = PrinterConfigService(token: token);
    _common = CommonService(token: token);
    if (auth.isMasterAdmin) {
      _loadBranches();
    } else {
      _loadingBranches = false;
    }
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _shopAddressCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _networkIpCtrl.dispose();
    _networkPortCtrl.dispose();
    _localPrinterCtrl.dispose();
    _kitchenNetworkIpCtrl.dispose();
    _kitchenNetworkPortCtrl.dispose();
    _kitchenLocalPrinterCtrl.dispose();
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

  Future<void> _loadConfigFor(int? branchId) async {
    setState(() => _loadingConfig = true);
    try {
      // The settings screen always wants the row for the branch being
      // edited, not "my own branch" — list it out of the full set fetched
      // for the master-admin view.
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
    setState(() {
      _shopNameCtrl.text = config.shopName ?? '';
      _shopAddressCtrl.text = config.shopAddress ?? '';
      _shopPhoneCtrl.text = config.shopPhone ?? '';
      _activeConnection = config.activeConnection;
      _networkIpCtrl.text = config.networkIp ?? '';
      _networkPortCtrl.text = (config.networkPort).toString();
      _localPrinterCtrl.text = config.localPrinterName ?? '';
      _kitchenEnabled = config.kitchenPrintEnabled;
      _kitchenNetworkIpCtrl.text = config.kitchenNetworkIp ?? '';
      _kitchenNetworkPortCtrl.text = (config.kitchenNetworkPort).toString();
      _kitchenLocalPrinterCtrl.text = config.kitchenLocalPrinterName ?? '';
    });
  }

  Future<void> _save() async {
    if (_activeConnection == 'network' && _networkIpCtrl.text.trim().isEmpty) {
      _showMessage('Enter the printer\'s network address.');
      return;
    }
    if (_activeConnection == 'local' && _localPrinterCtrl.text.trim().isEmpty) {
      _showMessage('Enter the local printer name.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.savePrinterConfig(
        branchId: _selectedBranchId,
        shopName: _shopNameCtrl.text.trim(),
        shopAddress: _shopAddressCtrl.text.trim(),
        shopPhone: _shopPhoneCtrl.text.trim(),
        activeConnection: _activeConnection,
        networkIp: _networkIpCtrl.text.trim().isEmpty ? null : _networkIpCtrl.text.trim(),
        networkPort: int.tryParse(_networkPortCtrl.text.trim()) ?? 9100,
        localPrinterName: _localPrinterCtrl.text.trim().isEmpty ? null : _localPrinterCtrl.text.trim(),
        kitchenPrintEnabled: _kitchenEnabled,
        kitchenNetworkIp: _kitchenNetworkIpCtrl.text.trim().isEmpty ? null : _kitchenNetworkIpCtrl.text.trim(),
        kitchenNetworkPort: int.tryParse(_kitchenNetworkPortCtrl.text.trim()) ?? 9100,
        kitchenLocalPrinterName: _kitchenLocalPrinterCtrl.text.trim().isEmpty ? null : _kitchenLocalPrinterCtrl.text.trim(),
      );

      if (!mounted) return;
      _showMessage('Printer settings saved.');

      // If we just saved settings for the current device's own branch,
      // refresh the live config so the next sale uses them immediately.
      if (mounted) {
        // ignore: use_build_context_synchronously
        final token = context.read<AuthProvider>().token;
        if (token != null) context.read<PrinterConfigProvider>().refresh(token);
      }
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint() async {
    if (_activeConnection != 'network') {
      _showMessage('Test print currently supports network printers. Save local printer settings and try a real sale to test that path.');
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

  Future<void> _testKitchenPrint() async {
    final ip = _kitchenNetworkIpCtrl.text.trim();
    if (ip.isEmpty) {
      _showMessage('Enter the kitchen printer\'s network address first.');
      return;
    }
    final port = int.tryParse(_kitchenNetworkPortCtrl.text.trim()) ?? 9100;

    setState(() => _testingKitchen = true);
    try {
      await _service.validateTestDestination(
        activeConnection: 'network',
        networkIp: ip,
        networkPort: port,
      );
      await ThermalPrinterService.instance.testPrintNetwork(
        printerIp: ip,
        port: port,
        shopName: 'Kitchen Printer Test',
      );
      _showMessage('Kitchen test ticket sent.');
    } catch (e) {
      _showMessage('Kitchen test failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _testingKitchen = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                  _buildKitchenPanel(),
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
              'Most thermal WiFi/LAN printers listen on port 9100. Find the IP from the printer\'s self-test page or network settings.',
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
                      'Printing to a printer installed on this computer isn\'t wired up yet — '
                      'sales will fall back to the PDF preview until that\'s finished. '
                      'A network printer (above) works today.',
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

  Widget _buildKitchenPanel() {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _kitchenEnabled,
            onChanged: (v) => setState(() => _kitchenEnabled = v),
            title: const Text('Print a second copy', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Send the same receipt to a back/kitchen printer too.'),
          ),
          if (_kitchenEnabled) ...[
            const SizedBox(height: 8),
            if (_activeConnection == 'network') ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _kitchenNetworkIpCtrl,
                      decoration: const InputDecoration(labelText: 'Kitchen printer IP', prefixIcon: Icon(Icons.wifi_rounded)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _kitchenNetworkPortCtrl,
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
                  onPressed: _testingKitchen ? null : _testKitchenPrint,
                  icon: _testingKitchen
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(_testingKitchen ? 'Sending...' : 'Send Test Print to Kitchen'),
                ),
              ),
            ] else if (_activeConnection == 'local')
              TextFormField(
                controller: _kitchenLocalPrinterCtrl,
                decoration: const InputDecoration(labelText: 'Kitchen printer name', prefixIcon: Icon(Icons.dvr_rounded)),
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
}
