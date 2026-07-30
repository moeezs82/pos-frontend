import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class BackendStartupException implements Exception {
  final String message;

  const BackendStartupException(this.message);

  @override
  String toString() => message;
}

/// Ensures the local CounterIQ backend is available before Flutter starts
/// authentication or other API bootstrap work.
class BackendStartupService {
  static final Uri _healthUri = Uri.parse('http://127.0.0.1:8080/up');

  static const Duration _healthRequestTimeout = Duration(seconds: 1);
  static const Duration _startupTimeout = Duration(seconds: 45);
  static const Duration _pollInterval = Duration(milliseconds: 300);

  const BackendStartupService._();

  static Future<void> ensureReady() async {
    // Reuse an already-running backend. This also avoids duplicate sidecars.
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
      'CounterIQ backend did not become ready in time. '
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
