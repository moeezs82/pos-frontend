import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/backend_config.dart';

class BackendStartupException implements Exception {
  final String message;

  const BackendStartupException(this.message);

  @override
  String toString() => message;
}

/// Ensures the backend selected for this CounterIQ build is available before
/// Flutter starts authentication or other API bootstrap work.
///
/// Local HOST builds may launch the bundled Windows sidecar. Local CLIENT
/// builds connect to the host PC over LAN and must never launch another SQLite
/// backend on the client machine.
class BackendStartupService {
  static final Uri _healthUri = Uri.parse(BackendConfig.healthUrl);
  static final Uri _runtimeUri = Uri.parse(BackendConfig.runtimeUrl);

  static const Duration _healthRequestTimeout = BackendConfig.isServer
      ? Duration(seconds: 5)
      : Duration(seconds: 2);
  static const Duration _startupTimeout = Duration(seconds: 45);
  static const Duration _restoreStartupTimeout = Duration(minutes: 5);
  static const Duration _pollInterval = Duration(milliseconds: 250);

  const BackendStartupService._();

  static Future<void> ensureReady() async {
    try {
      BackendConfig.validate();
    } on StateError catch (error) {
      throw BackendStartupException(error.message.toString());
    }

    if (BackendConfig.isServer) {
      await _ensureServerReady();
      return;
    }

    if (BackendConfig.isLocalClient) {
      await _ensureLANClientReady();
      return;
    }

    await _ensureLocalHostReady();
  }

  static Future<void> _ensureServerReady() async {
    if (await _isHealthy()) return;

    throw BackendStartupException(
      'CounterIQ could not connect to the server.\n\n'
      'Server: ${BackendConfig.origin}\n\n'
      'Check the internet connection and make sure the CounterIQ server is running, '
      'then try again.',
    );
  }

  static Future<void> _ensureLANClientReady() async {
    if (!await _isHealthy()) {
      throw BackendStartupException(
        'CounterIQ could not reach the local host PC.\n\n'
        'Host: ${BackendConfig.origin}\n\n'
        'Make sure the host PC is powered on, CounterIQ Host is running, both PCs are '
        'on the same network, and Windows Firewall allows TCP port 8080 on the host.',
      );
    }
    await _requireDesktopRuntime(requireLAN: true);
  }

  static Future<void> _ensureLocalHostReady({
    Duration startupTimeout = _startupTimeout,
  }) async {
    // Reuse an already-running compatible desktop backend. Do not silently
    // accept an arbitrary `go run ./cmd/api` process just because /up is 200.
    if (await _isHealthy()) {
      await _requireDesktopRuntime(
        requireLAN: BackendConfig.localHostLanEnabled,
      );
      return;
    }

    if (!Platform.isWindows) {
      throw const BackendStartupException(
        'CounterIQ local backend auto-start is supported on Windows only.',
      );
    }

    final appDirectory = File(Platform.resolvedExecutable).parent.path;
    final backendPath = p.join(
      appDirectory,
      'backend',
      'counteriq-backend.exe',
    );

    if (!File(backendPath).existsSync()) {
      throw BackendStartupException(
        'CounterIQ backend was not found.\n\nExpected file:\n$backendPath\n\n'
        'During development, start the Go backend manually with:\n'
        'go run ./cmd/api desktop${BackendConfig.localHostLanEnabled ? ' --lan' : ''}',
      );
    }

    final args = <String>['desktop'];
    if (BackendConfig.localHostLanEnabled) args.add('--lan');

    try {
      await Process.start(
        backendPath,
        args,
        workingDirectory: p.dirname(backendPath),
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw BackendStartupException(
        'CounterIQ could not start its local backend.\n\n${error.message}',
      );
    }

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy()) {
        await _requireDesktopRuntime(
          requireLAN: BackendConfig.localHostLanEnabled,
        );
        return;
      }
      await Future<void>.delayed(_pollInterval);
    }

    throw const BackendStartupException(
      'CounterIQ local backend did not become ready in time. '
      'Close CounterIQ and try again.',
    );
  }

  /// Used after the authoritative desktop backend accepts a verified restore.
  ///
  /// The Go desktop runtime performs an in-process restart and the listener can
  /// disappear for only a few hundred milliseconds. Requiring Flutter to first
  /// observe `/up` become unavailable caused a tight health-check loop when the
  /// outage happened between polls. Instead, wait briefly and probe the stronger
  /// `/api/v1/runtime` readiness signal with progressive backoff.
  static Future<void> waitForRestoreRestart() async {
    if (!BackendConfig.isLocal || !Platform.isWindows) {
      throw const BackendStartupException(
        'Backup restore restart is available only in the local Windows edition.',
      );
    }

    final requireLAN =
        BackendConfig.isLocalClient || BackendConfig.localHostLanEnabled;
    final deadline = DateTime.now().add(_restoreStartupTimeout);

    // The backend intentionally waits 350 ms after sending the restore response
    // before requesting its in-process restart. Wait long enough that the first
    // probe cannot accidentally accept the pre-restore runtime as ready.
    await Future<void>.delayed(const Duration(seconds: 1));

    var delay = const Duration(milliseconds: 500);
    const maxDelay = Duration(seconds: 1);

    while (DateTime.now().isBefore(deadline)) {
      final info = await _tryRuntimeInfo(
        timeout: const Duration(seconds: 1),
      );
      if (info != null) {
        final desktop = info['desktop'] == true;
        final driver = info['driver']?.toString().toLowerCase();
        final lan = info['desktop_lan'] == true;

        if (!desktop || driver != 'sqlite') {
          throw BackendStartupException(
            'CounterIQ came back online after the restore, but the service at '
            '${BackendConfig.origin} is not the expected local desktop runtime.',
          );
        }
        if (requireLAN && !lan) {
          throw BackendStartupException(
            'CounterIQ came back online after the restore in single-PC mode.\n\n'
            'The shared host must run in LAN mode.',
          );
        }
        return;
      }

      await Future<void>.delayed(delay);
      final nextMs = (delay.inMilliseconds * 1.6).round();
      delay = Duration(
        milliseconds:
            nextMs > maxDelay.inMilliseconds ? maxDelay.inMilliseconds : nextMs,
      );
    }

    throw BackendStartupException(
      'CounterIQ did not come back online after the restore.\n\n'
      'Backend: ${BackendConfig.origin}\n\n'
      'On the host PC, check that the CounterIQ backend is still running.',
    );
  }

  static Future<void> _requireDesktopRuntime({required bool requireLAN}) async {
    final info = await _runtimeInfo();
    final desktop = info['desktop'] == true;
    final driver = info['driver']?.toString().toLowerCase();
    final lan = info['desktop_lan'] == true;

    if (!desktop || driver != 'sqlite') {
      throw BackendStartupException(
        'The service at ${BackendConfig.origin} is not the CounterIQ local desktop host.\n\n'
        'Start the backend with:\n'
        'go run ./cmd/api desktop${requireLAN ? ' --lan' : ''}',
      );
    }
    if (requireLAN && !lan) {
      throw BackendStartupException(
        'The CounterIQ desktop backend is running in single-PC mode.\n\n'
        'For a shared two-PC installation, restart it with:\n'
        'go run ./cmd/api desktop --lan',
      );
    }
  }

  static Future<Map<String, dynamic>?> _tryRuntimeInfo({
    required Duration timeout,
  }) async {
    try {
      final response = await http.get(_runtimeUri).timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      return decoded;
    } on Object {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _runtimeInfo() async {
    try {
      final response = await http.get(_runtimeUri).timeout(_healthRequestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    } on BackendStartupException {
      rethrow;
    } on Object {
      // Fall through to the upgrade/incorrect-runtime error below.
    }
    throw BackendStartupException(
      'CounterIQ reached ${BackendConfig.origin}, but that backend does not expose '
      'the required local-runtime information. Make sure the frontend and backend '
      'are from the same CounterIQ build.',
    );
  }

  static Future<bool> _isHealthy() async {
    try {
      final response = await http.get(_healthUri).timeout(_healthRequestTimeout);
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    }
  }
}
