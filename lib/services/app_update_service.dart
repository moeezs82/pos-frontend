import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/app_update_config.dart';
import 'sha256_file_service.dart';

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);

  @override
  String toString() => message;
}

class UpdateManifest {
  final String product;
  final String channel;
  final String packageType;
  final String version;
  final bool mandatory;
  final String? minimumSupportedVersion;
  final Uri downloadUri;
  final String sha256;
  final List<String> releaseNotes;

  const UpdateManifest({
    required this.product,
    required this.channel,
    required this.packageType,
    required this.version,
    required this.mandatory,
    required this.minimumSupportedVersion,
    required this.downloadUri,
    required this.sha256,
    required this.releaseNotes,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final product = json['product']?.toString().trim() ?? '';
    final channel = json['channel']?.toString().trim() ?? '';
    final packageType = json['package_type']?.toString().trim().toLowerCase() ?? '';
    final version = json['version']?.toString().trim() ?? '';
    final minimum = json['minimum_supported_version']?.toString().trim();
    final rawUrl = json['download_url']?.toString().trim() ?? '';
    final sha256 = json['sha256']?.toString().trim().toLowerCase() ?? '';
    final notesRaw = json['release_notes'];

    if (product.toLowerCase() != 'counteriq') {
      throw const AppUpdateException('The update manifest is not for CounterIQ.');
    }
    if (channel != AppUpdateConfig.channel) {
      throw AppUpdateException(
        'The update manifest channel "$channel" does not match this ${AppUpdateConfig.channel} build.',
      );
    }
    if (packageType != AppUpdateConfig.packageType) {
      throw AppUpdateException(
        'The update package is for "$packageType", but this installation is "${AppUpdateConfig.packageType}".',
      );
    }
    _Version.parse(version);
    if (minimum != null && minimum.isNotEmpty) _Version.parse(minimum);

    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.isAbsolute || uri.scheme.toLowerCase() != 'https') {
      throw const AppUpdateException('The update download URL must be a valid HTTPS URL.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const AppUpdateException('The update manifest contains an invalid SHA-256 value.');
    }

    final notes = notesRaw is List
        ? notesRaw
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return UpdateManifest(
      product: product,
      channel: channel,
      packageType: packageType,
      version: version,
      mandatory: json['mandatory'] == true,
      minimumSupportedVersion: minimum == null || minimum.isEmpty ? null : minimum,
      downloadUri: uri,
      sha256: sha256,
      releaseNotes: notes,
    );
  }
}

class UpdateCheckResult {
  final UpdateManifest manifest;
  final bool isUpdateAvailable;
  final bool isMandatory;

  const UpdateCheckResult({
    required this.manifest,
    required this.isUpdateAvailable,
    required this.isMandatory,
  });
}

class UpdateDownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const UpdateDownloadProgress(this.receivedBytes, this.totalBytes);

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

class AppUpdateService {
  static const Duration _manifestTimeout = Duration(seconds: 8);
  static const Duration _downloadTimeout = Duration(minutes: 20);

  const AppUpdateService._();

  static Future<UpdateCheckResult?> checkForUpdate() async {
    if (!Platform.isWindows || !AppUpdateConfig.isEnabled) return null;

    final manifestUri = Uri.tryParse(AppUpdateConfig.manifestUrl.trim());
    if (manifestUri == null ||
        !manifestUri.isAbsolute ||
        manifestUri.scheme.toLowerCase() != 'https') {
      throw const AppUpdateException(
        'COUNTERIQ_UPDATE_MANIFEST_URL must be a valid HTTPS URL.',
      );
    }

    final cacheBustedManifestUri = manifestUri.replace(
      queryParameters: <String, String>{
        ...manifestUri.queryParameters,
        '_counteriq_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    try {
      final response = await http.get(
        cacheBustedManifestUri,
        headers: const {
          'Cache-Control': 'no-cache, no-store, max-age=0',
          'Pragma': 'no-cache',
        },
      ).timeout(_manifestTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException(
          'Update server returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppUpdateException('The update manifest has an invalid format.');
      }

      final manifest = UpdateManifest.fromJson(decoded);
      final current = _Version.parse(AppUpdateConfig.currentVersion);
      final latest = _Version.parse(manifest.version);
      final updateAvailable = latest.compareTo(current) > 0;

      var mandatory = manifest.mandatory;
      final minimum = manifest.minimumSupportedVersion;
      if (minimum != null && minimum.isNotEmpty) {
        mandatory = mandatory || current.compareTo(_Version.parse(minimum)) < 0;
      }

      return UpdateCheckResult(
        manifest: manifest,
        isUpdateAvailable: updateAvailable,
        isMandatory: updateAvailable && mandatory,
      );
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException('The update check timed out.');
    } on FormatException {
      throw const AppUpdateException('The update manifest contains invalid JSON.');
    } on SocketException {
      throw const AppUpdateException('CounterIQ could not reach the update server.');
    } on Object catch (error) {
      throw AppUpdateException('Update check failed: $error');
    }
  }

  static Future<File> downloadAndVerify(
    UpdateManifest manifest, {
    required void Function(UpdateDownloadProgress progress) onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw const AppUpdateException('CounterIQ automatic updates are supported on Windows only.');
    }

    final tempRoot = Directory(p.join(Directory.systemTemp.path, 'CounterIQ', 'updates'));
    await tempRoot.create(recursive: true);

    final safeVersion = manifest.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final finalFile = File(p.join(
      tempRoot.path,
      'CounterIQ-${manifest.packageType[0].toUpperCase()}${manifest.packageType.substring(1)}-Setup-$safeVersion.exe',
    ));
    final partialFile = File('${finalFile.path}.part');

    await _deleteIfExists(partialFile);
    await _deleteIfExists(finalFile);

    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', manifest.downloadUri)
        ..headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request).timeout(_manifestTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException(
          'Update download returned HTTP ${response.statusCode}.',
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = partialFile.openWrite();

      await response.stream.timeout(_downloadTimeout).forEach((chunk) {
        sink!.add(chunk);
        received += chunk.length;
        onProgress(UpdateDownloadProgress(received, total));
      });
      await sink.flush();
      await sink.close();
      sink = null;

      if (received <= 0) {
        throw const AppUpdateException('The downloaded installer is empty.');
      }

      final actualHash = await Sha256FileService.hashFile(partialFile);
      if (actualHash.toLowerCase() != manifest.sha256.toLowerCase()) {
        await _deleteIfExists(partialFile);
        throw const AppUpdateException(
          'CounterIQ could not verify the downloaded update. The SHA-256 checksum does not match.',
        );
      }

      await partialFile.rename(finalFile.path);
      return finalFile;
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      await _deleteIfExists(partialFile);
      throw const AppUpdateException('The update download timed out. Please try again.');
    } on SocketException {
      await _deleteIfExists(partialFile);
      throw const AppUpdateException('The update download was interrupted by a network error.');
    } on Object catch (error) {
      await _deleteIfExists(partialFile);
      throw AppUpdateException('CounterIQ could not download the update: $error');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
    }
  }

  static Future<void> launchInstaller(File installer) async {
    if (!Platform.isWindows) {
      throw const AppUpdateException('CounterIQ automatic updates are supported on Windows only.');
    }
    if (!await installer.exists()) {
      throw const AppUpdateException('The verified CounterIQ installer could not be found.');
    }

    try {
      await Process.start(
        installer.path,
        const <String>[
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/AUTOUPDATE',
        ],
        workingDirectory: installer.parent.path,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw AppUpdateException(
        'CounterIQ could not start the update installer. ${error.message}',
      );
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _Version implements Comparable<_Version> {
  final List<int> parts;

  const _Version._(this.parts);

  factory _Version.parse(String raw) {
    final normalized = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d+){1,3}$').hasMatch(normalized)) {
      throw AppUpdateException(
        'Invalid CounterIQ version "$raw". Expected a numeric version such as 1.0.9.',
      );
    }
    return _Version._(
      normalized.split('.').map(int.parse).toList(growable: false),
    );
  }

  @override
  int compareTo(_Version other) {
    final length = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var i = 0; i < length; i++) {
      final left = i < parts.length ? parts[i] : 0;
      final right = i < other.parts.length ? other.parts[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }
}
