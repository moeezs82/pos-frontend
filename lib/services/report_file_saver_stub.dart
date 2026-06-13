import 'dart:typed_data';

Future<String> saveReportFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  throw UnsupportedError('File saving is not supported on this platform.');
}
