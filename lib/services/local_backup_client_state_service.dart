import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/backend_config.dart';
import 'offline_invoice_seq_service.dart';
import 'offline_license_service.dart';
import 'offline_sales_queue_service.dart';

class ClientRestoreResult {
  final bool applied;
  final bool licenseRestored;
  final String? licenseNote;

  const ClientRestoreResult({
    required this.applied,
    required this.licenseRestored,
    this.licenseNote,
  });
}

/// Owns the small amount of local Flutter state that is not stored in the
/// authoritative CounterIQ SQLite backend database.
///
/// Disposable catalog caches and authentication/session preferences are
/// intentionally excluded. The backup contains only disaster-recovery state:
/// pending offline sales, offline invoice sequences/device identity, and the
/// installed public `.ciqlic` license file.
class LocalBackupClientStateService {
  LocalBackupClientStateService._();

  static final instance = LocalBackupClientStateService._();

  Future<String> createStagingSnapshot() async {
    _requireLocalWindows();
    final root = _counterIQRoot();
    final stagingRoot = Directory(p.join(root.path, 'backup-client-staging'));
    await stagingRoot.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final staging = Directory(p.join(stagingRoot.path, 'client-$stamp-$pid'));
    await staging.create(recursive: true);

    try {
      // Close the two SQLite files briefly so the copy is a complete committed
      // file rather than a live WAL/journal snapshot. Both services lazily
      // reopen on their next use.
      await OfflineSalesQueueService.instance.closeForBackupRestore();
      await OfflineInvoiceSeqService.instance.closeForBackupRestore();

      final support = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(support.path, 'databases'));
      final outDbDir = Directory(p.join(staging.path, 'databases'));
      await outDbDir.create(recursive: true);
      // Use SQLite's own VACUUM INTO snapshot mechanism instead of a raw
      // file copy. This remains consistent even if a background task opens
      // the queue again while the backup is being prepared, and it folds any
      // committed WAL state into the standalone backup database.
      await _snapshotSQLiteIfExists(
        File(p.join(dbDir.path, 'offline_sales_queue.db')),
        File(p.join(outDbDir.path, 'offline_sales_queue.db')),
      );
      await _snapshotSQLiteIfExists(
        File(p.join(dbDir.path, 'offline_invoice_seq.db')),
        File(p.join(outDbDir.path, 'offline_invoice_seq.db')),
      );

      final licensing = Directory(p.join(support.path, 'licensing'));
      final license = File(p.join(licensing.path, 'counteriq-${BackendConfig.mode}.ciqlic'));
      if (await license.exists()) {
        final outLicenseDir = Directory(p.join(staging.path, 'licensing'));
        await outLicenseDir.create(recursive: true);
        await license.copy(p.join(outLicenseDir.path, p.basename(license.path)));
      }

      final prefs = await SharedPreferences.getInstance();
      final clientState = <String, dynamic>{
        'format_version': 1,
        'offline_device_key': prefs.getString('offline_device_key'),
      };
      await File(p.join(staging.path, 'client_state.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(clientState),
        flush: true,
      );
      return staging.path;
    } catch (_) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> cleanupStaging(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    final root = p.normalize(p.join(_counterIQRoot().path, 'backup-client-staging'));
    final candidate = p.normalize(path);
    if (!_isWithin(root, candidate)) return;
    final dir = Directory(candidate);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<ClientRestoreResult> applyPendingRestore() async {
    _requireLocalWindows();
    final pending = Directory(p.join(_counterIQRoot().path, 'restore-client-pending'));
    if (!await pending.exists()) {
      return const ClientRestoreResult(applied: false, licenseRestored: false);
    }

    await OfflineSalesQueueService.instance.closeForBackupRestore();
    await OfflineInvoiceSeqService.instance.closeForBackupRestore();

    final support = await getApplicationSupportDirectory();
    final destinationDbDir = Directory(p.join(support.path, 'databases'));
    await destinationDbDir.create(recursive: true);

    for (final name in const ['offline_sales_queue.db', 'offline_invoice_seq.db']) {
      final source = File(p.join(pending.path, 'databases', name));
      if (!await source.exists()) continue;
      final destination = File(p.join(destinationDbDir.path, name));
      await _removeSQLiteFamily(destination.path);
      final temp = File('${destination.path}.restore-tmp');
      if (await temp.exists()) await temp.delete();
      await source.copy(temp.path);
      await temp.rename(destination.path);
    }

    final clientStateFile = File(p.join(pending.path, 'client_state.json'));
    if (await clientStateFile.exists()) {
      try {
        final decoded = jsonDecode(await clientStateFile.readAsString());
        if (decoded is Map) {
          final deviceKey = decoded['offline_device_key']?.toString().trim();
          if (deviceKey != null && RegExp(r'^[A-Fa-f0-9]{8}$').hasMatch(deviceKey)) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('offline_device_key', deviceKey.toUpperCase());
          }
        }
      } catch (_) {
        // The critical business database has already been restored. A damaged
        // optional client-state JSON must not undo it; the sequence service can
        // generate a fresh device key if necessary.
      }
    }

    bool licenseRestored = false;
    String? licenseNote;
    final backupLicense = File(
      p.join(pending.path, 'licensing', 'counteriq-${BackendConfig.mode}.ciqlic'),
    );
    if (await backupLicense.exists()) {
      final check = await OfflineLicenseService.verifyLicenseFile(backupLicense);
      if (check.isValid) {
        final install = await OfflineLicenseService.installLicenseFromPath(backupLicense.path);
        licenseRestored = install.isValid;
      } else {
        licenseNote =
            'The backup license belongs to another device or is no longer valid. '
            'Your current CounterIQ activation was kept unchanged.';
      }
    }

    await pending.delete(recursive: true);
    return ClientRestoreResult(
      applied: true,
      licenseRestored: licenseRestored,
      licenseNote: licenseNote,
    );
  }

  Directory _counterIQRoot() {
    final home = Platform.environment['USERPROFILE']?.trim();
    if (home == null || home.isEmpty) {
      throw StateError('Windows USERPROFILE is unavailable.');
    }
    return Directory(p.join(home, 'CounterIQData'));
  }

  void _requireLocalWindows() {
    if (!BackendConfig.isLocalHost || !Platform.isWindows) {
      throw UnsupportedError('This client-state backup operation is available only on the local CounterIQ host PC.');
    }
  }

  static Future<void> _snapshotSQLiteIfExists(File source, File destination) async {
    if (!await source.exists()) return;
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();

    final db = await openDatabase(source.path);
    try {
      // SQLite string literal escaping for an absolute Windows path.
      final target = destination.path.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$target'");
    } finally {
      await db.close();
    }
  }

  static Future<void> _copyIfExists(File source, File destination) async {
    if (!await source.exists()) return;
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
  }

  static Future<void> _removeSQLiteFamily(String path) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  static bool _isWithin(String root, String candidate) {
    if (candidate == root) return true;
    final prefix = root.endsWith(p.separator) ? root : '$root${p.separator}';
    return candidate.startsWith(prefix);
  }
}
