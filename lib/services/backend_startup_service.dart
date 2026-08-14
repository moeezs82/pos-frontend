import 'dart:async';
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
/// Local builds may start the bundled Windows backend sidecar. Server builds
/// only check the remote server and never search for or launch a local backend.
class BackendStartupService {
  static final Uri _healthUri = Uri.parse(BackendConfig.healthUrl);

  static const Duration _healthRequestTimeout = BackendConfig.isServer
      ? Duration(seconds: 5)
      : Duration(seconds: 1);
  static const Duration _startupTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(milliseconds: 300);

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

    await _ensureLocalReady();
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

  static Future<void> _ensureLocalReady() async {
    // Reuse an already-running local backend. This also avoids duplicate
    // sidecars when CounterIQ is opened more than once.
    if (await _isHealthy()) return;

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
        'CounterIQ backend was not found.\n\nExpected file:\n$backendPath',
      );
    }

    try {
      await Process.start(
        backendPath,
        const ['desktop'],
        workingDirectory: p.dirname(backendPath),
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw BackendStartupException(
        'CounterIQ could not start its local backend.\n\n${error.message}',
      );
    }

    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy()) return;
      await Future<void>.delayed(_pollInterval);
    }

    throw const BackendStartupException(
      'CounterIQ local backend did not become ready in time. '
      'Close CounterIQ and try again.',
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
