import 'dart:io';
import 'dart:typed_data';

Future<String> saveReportFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final dir = await _bestDownloadDirectory();
  await dir.create(recursive: true);
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Directory> _bestDownloadDirectory() async {
  final env = Platform.environment;
  final home = env['USERPROFILE'] ?? env['HOME'];
  if (home != null && home.trim().isNotEmpty) {
    final downloads = Directory('$home${Platform.pathSeparator}Downloads');
    if (await downloads.exists()) return downloads;
    return downloads;
  }
  return Directory.systemTemp;
}
