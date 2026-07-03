import 'dart:typed_data';

import 'report_file_saver_stub.dart'
    if (dart.library.html) 'report_file_saver_web.dart'
    if (dart.library.io) 'report_file_saver_io.dart';

export 'report_save_exceptions.dart';

/// Prompts the user (on desktop/mobile) to choose a save location for
/// [bytes], writes the file, and then opens it with the OS default handler.
///
/// Throws [ReportSaveCancelledException] if the user dismisses the save
/// dialog without picking a location. On web the file is downloaded via the
/// browser and opened automatically by the browser's own download UI.
Future<String> saveReportFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  return saveReportFileImpl(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}
