import 'dart:typed_data';

import 'report_file_saver_stub.dart'
    if (dart.library.html) 'report_file_saver_web.dart'
    if (dart.library.io) 'report_file_saver_io.dart';

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
