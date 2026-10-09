import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/whatsapp_icon.dart';

/// Centred pop-up showing the bill before it is saved.
///
/// The dialog owns no sale logic. The three actions are supplied by the sale
/// screen:
///  * [onSave]     – save the sale; returns true when saved, then the dialog
///                   closes.
///  * [onPrint]    – save (if not yet saved) and print; the dialog stays open.
///  * [onWhatsApp] – save (if not yet saved) and share on WhatsApp; the dialog
///                   stays open.
class SalePreviewDialog extends StatefulWidget {
  final Uint8List pdfBytes;
  final PdfPageFormat pageFormat;
  final bool Function() isSaved;
  final Future<bool> Function() onSave;
  final Future<void> Function() onPrint;
  final Future<void> Function() onWhatsApp;

  const SalePreviewDialog({
    super.key,
    required this.pdfBytes,
    required this.pageFormat,
    required this.isSaved,
    required this.onSave,
    required this.onPrint,
    required this.onWhatsApp,
  });

  @override
  State<SalePreviewDialog> createState() => _SalePreviewDialogState();
}

class _SalePreviewDialogState extends State<SalePreviewDialog> {
  String? _busyAction;

  bool get _busy => _busyAction != null;

  Future<void> _run(String name, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busyAction = name);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _save() => _run('save', () async {
        final saved = await widget.onSave();
        if (saved && mounted) Navigator.of(context).pop();
      });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final saved = widget.isSaved();
    return PopScope(
      // Do not let the dialog be dismissed mid-save.
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        saved ? 'Bill Preview — saved' : 'Bill Preview',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Container(
                  color: AppTheme.surfaceSoft,
                  child: PdfPreview(
                    build: (_) async => widget.pdfBytes,
                    initialPageFormat: widget.pageFormat,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    useActions: false,
                    pdfFileName: 'bill-preview.pdf',
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busyAction == 'save'
                            ? const _BtnSpinner()
                            : const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run('whatsapp', widget.onWhatsApp),
                        icon: _busyAction == 'whatsapp'
                            ? const _BtnSpinner(dark: true)
                            : const WhatsAppIcon(size: 18),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _run('print', widget.onPrint),
                        icon: _busyAction == 'print'
                            ? const _BtnSpinner(dark: true)
                            : const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BtnSpinner extends StatelessWidget {
  final bool dark;
  const _BtnSpinner({this.dark = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: dark ? AppTheme.primary : Colors.white,
        ),
      );
}
