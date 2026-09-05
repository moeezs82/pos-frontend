import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportPdfExportOptions {
  final String paperSize;
  final String orientation;

  const ReportPdfExportOptions({
    required this.paperSize,
    required this.orientation,
  });
}

const _paperSizePreferenceKey = 'reports_pdf_paper_size';
const _orientationPreferenceKey = 'reports_pdf_orientation';
const _paperSizes = <String>{'a4', 'a5'};
const _orientations = <String>{'auto', 'portrait', 'landscape'};

Future<ReportPdfExportOptions?> showReportPdfExportDialog(
  BuildContext context, {
  String? reportTitle,
}) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Preference storage is convenience only; PDF export must remain usable.
  }
  if (!context.mounted) return null;

  var paperSize = (prefs?.getString(_paperSizePreferenceKey) ?? 'a4').trim().toLowerCase();
  if (!_paperSizes.contains(paperSize)) paperSize = 'a4';

  var orientation = (prefs?.getString(_orientationPreferenceKey) ?? 'auto').trim().toLowerCase();
  if (!_orientations.contains(orientation)) orientation = 'auto';

  final selected = await showDialog<ReportPdfExportOptions>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded),
            SizedBox(width: 10),
            Text('Export PDF'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reportTitle != null && reportTitle.trim().isNotEmpty) ...[
                Text(
                  reportTitle.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<String>(
                value: paperSize,
                decoration: const InputDecoration(
                  labelText: 'Paper size',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'a4', child: Text('A4  •  210 × 297 mm')),
                  DropdownMenuItem(value: 'a5', child: Text('A5  •  148 × 210 mm')),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => paperSize = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: orientation,
                decoration: const InputDecoration(
                  labelText: 'Orientation',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.screen_rotation_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto  •  Recommended')),
                  DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
                  DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => orientation = value);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Auto selects portrait or landscape based on the report width. Forced orientations are always respected.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(
              ReportPdfExportOptions(
                paperSize: paperSize,
                orientation: orientation,
              ),
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export PDF'),
          ),
        ],
      ),
    ),
  );

  if (selected == null) return null;

  // Keep the last confirmed choice on this device. Failure to persist a UI
  // preference must never block a report export.
  if (prefs != null) {
    try {
      await prefs.setString(_paperSizePreferenceKey, selected.paperSize);
      await prefs.setString(_orientationPreferenceKey, selected.orientation);
    } catch (_) {}
  }

  return selected;
}
