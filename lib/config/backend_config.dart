/// Build-time backend configuration for CounterIQ.
///
/// CounterIQ is distributed as two separate builds:
/// - local: talks to the bundled backend on 127.0.0.1 and may auto-start it.
/// - server: talks only to the configured remote CounterIQ server.
///
/// The client cannot switch modes at runtime. Select the mode when building:
///
///   --dart-define=COUNTERIQ_BACKEND_MODE=local
///
/// or:
///
///   --dart-define=COUNTERIQ_BACKEND_MODE=server
///   --dart-define=COUNTERIQ_SERVER_ORIGIN=https://145.223.118.86:18443
class BackendConfig {
  static const String mode = String.fromEnvironment(
    'COUNTERIQ_BACKEND_MODE',
    defaultValue: 'local',
  );

  static const String _localOrigin = 'http://127.0.0.1:8080';

  /// Server origin is fixed into the server build. There is intentionally no
  /// runtime setting for clients to change it.
  static const String _serverOrigin = String.fromEnvironment(
    'COUNTERIQ_SERVER_ORIGIN',
    defaultValue: 'https://145.223.118.86:18443',
  );

  static const bool isLocal = mode == 'local';
  static const bool isServer = mode == 'server';

  static const String origin = isServer ? _serverOrigin : _localOrigin;
  static const String apiBaseUrl = '$origin/api/v1';
  static const String healthUrl = '$origin/up';

  static const String startupMessage = isServer
      ? 'Connecting to CounterIQ Server...'
      : 'Preparing the local database and services...';

  const BackendConfig._();

  static void validate() {
    if (!isLocal && !isServer) {
      throw StateError(
        'Invalid COUNTERIQ_BACKEND_MODE "$mode". '
        'Use "local" or "server".',
      );
    }

    if (isServer) {
      final uri = Uri.tryParse(_serverOrigin);
      if (uri == null ||
          !uri.hasScheme ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw StateError(
          'Invalid COUNTERIQ_SERVER_ORIGIN "$_serverOrigin". '
          'Use a complete http:// or https:// origin.',
        );
      }
    }
  }
}
