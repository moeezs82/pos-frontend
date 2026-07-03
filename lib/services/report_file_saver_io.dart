import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';

import 'report_save_exceptions.dart';

/// Desktop/mobile implementation used by [saveReportFile].
///
/// Previously this silently wrote the file to a guessed folder
/// (`$HOME/Downloads`, falling back to a private temp directory on Android)
/// and never opened it. That made exports look like they "did nothing" or
/// "wouldn't open". This version:
///   1. Always asks the user where to save via a native "Save As" dialog
///      (`file_picker`, which uses Android's Storage Access Framework, so no
///      broad storage permission is required).
///   2. Opens the saved file automatically with the OS default handler.
Future<String> saveReportFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  // On Android/iOS, file_picker writes `bytes` directly to the location the
  // user picks (via SAF on Android) and returns that path/URI. On desktop
  // platforms, saveFile only returns the chosen destination path — the bytes
  // still need to be written by us below.
  final isMobile = Platform.isAndroid || Platform.isIOS;

  final destination = await FilePicker.platform.saveFile(
    dialogTitle: 'Save report as',
    fileName: safeName,
    bytes: isMobile ? bytes : null,
  );

  if (destination == null) {
    throw const ReportSaveCancelledException();
  }

  if (!isMobile) {
    final file = File(destination);
    await file.writeAsBytes(bytes, flush: true);
  }

  try {
    await OpenFile.open(destination);
  } catch (_) {
    // Opening is best-effort. The file has already been saved successfully,
    // so we don't want a failure to launch a viewer to look like an export
    // failure.
  }

  return destination;
}
