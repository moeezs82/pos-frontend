import 'dart:convert';
import 'dart:io';

import 'package:enterprise_pos/api/core/api_client.dart';
import 'package:http/http.dart' as http;

class BackupService {
  final ApiClient _client;
  final String? _token;

  BackupService({String? token})
      : _token = token,
        _client = ApiClient(token: token);

  Future<bool> recoveryAvailable() async {
    final res = await _client.get('/backups/recovery-available');
    final data = res['data'];
    if (data is Map) return data['available'] == true;
    return false;
  }

  /// Fresh-install restore is host-PC only and uses an uploaded backup rather
  /// than a local filesystem path so the same verified transport is exercised.
  Future<Map<String, dynamic>> uploadRecoveryBackup(String path) async {
    final res = await _client.uploadFile(
      '/backups/recovery-upload',
      filePath: path,
      filename: _basename(path),
      fieldName: 'file',
    );
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> restoreRecoveryUpload(String uploadToken) async {
    final res = await _client.post(
      '/backups/recovery-restore-upload',
      body: {'upload_token': uploadToken},
    );
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> status() async {
    final res = await _client.get('/backups/status');
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Creates the authoritative backup on the host and streams the verified
  /// .ciqbak directly to [destinationPath]. Streaming avoids loading a large
  /// image-heavy business backup into the Flutter process memory.
  Future<void> exportBackupToFile({
    required String destinationPath,
    String? clientStateDir,
  }) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/backups/export');
    final request = http.Request('POST', uri)
      ..headers['Accept'] = 'application/vnd.counteriq.backup'
      ..headers['Content-Type'] = 'application/json';
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.body = jsonEncode({
      if (clientStateDir != null && clientStateDir.trim().isNotEmpty)
        'client_state_dir': clientStateDir,
    });

    final tempPath = '$destinationPath.partial';
    final tempFile = File(tempPath);
    try {
      if (await tempFile.exists()) await tempFile.delete();
      final streamed = await request.send();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final bytes = await streamed.stream.toBytes();
        String? message;
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map) message = decoded['message']?.toString();
        } catch (_) {}
        throw ApiException(
          streamed.statusCode,
          message ?? 'Backup download failed: HTTP ${streamed.statusCode}',
        );
      }

      await tempFile.parent.create(recursive: true);
      final sink = tempFile.openWrite();
      try {
        await sink.addStream(streamed.stream);
        await sink.flush();
      } finally {
        await sink.close();
      }

      final destination = File(destinationPath);
      if (await destination.exists()) await destination.delete();
      await tempFile.rename(destinationPath);
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Uploads a selected .ciqbak from this workstation to the authoritative
  /// host, verifies it there, and returns an opaque short-lived restore token.
  Future<Map<String, dynamic>> uploadBackup(String path) async {
    final res = await _client.uploadFile(
      '/backups/upload',
      filePath: path,
      filename: _basename(path),
      fieldName: 'file',
    );
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> restoreUploadedBackup({
    required String uploadToken,
    String? currentClientStateDir,
  }) async {
    final res = await _client.post('/backups/restore-upload', body: {
      'upload_token': uploadToken,
      if (currentClientStateDir != null &&
          currentClientStateDir.trim().isNotEmpty)
        'client_state_dir': currentClientStateDir,
    });
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  // Legacy host-local path APIs retained for compatibility with older tools.
  Future<Map<String, dynamic>> createBackup({
    required String path,
    required String clientStateDir,
  }) async {
    final res = await _client.post('/backups/create', body: {
      'path': path,
      'client_state_dir': clientStateDir,
    });
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> inspectBackup(String path) async {
    final res = await _client.post('/backups/inspect', body: {'path': path});
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> restoreBackup({
    required String path,
    required String currentClientStateDir,
  }) async {
    final res = await _client.post('/backups/restore', body: {
      'path': path,
      'client_state_dir': currentClientStateDir,
    });
    final data = res['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }
}
