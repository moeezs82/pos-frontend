/// Build-time backend configuration for CounterIQ.
///
/// CounterIQ has two commercial editions (`local` and `server`). The local
/// edition can be deployed in two roles without changing its license edition:
///
///   Host PC (owns SQLite + uploaded files, can share over LAN)
///   --dart-define=COUNTERIQ_BACKEND_MODE=local
///   --dart-define=COUNTERIQ_LOCAL_ROLE=host
///   --dart-define=COUNTERIQ_LOCAL_HOST_LAN=true
///
///   Client PC (connects to the Host PC over the trusted LAN)
///   --dart-define=COUNTERIQ_BACKEND_MODE=local
///   --dart-define=COUNTERIQ_LOCAL_ROLE=client
///   --dart-define=COUNTERIQ_LOCAL_SERVER_ORIGIN=http://192.168.1.50:8080
///
/// The server/cloud edition remains:
///   --dart-define=COUNTERIQ_BACKEND_MODE=server
///   --dart-define=COUNTERIQ_SERVER_ORIGIN=https://example.com
class BackendConfig {
  static const String mode = String.fromEnvironment(
    'COUNTERIQ_BACKEND_MODE',
    defaultValue: 'local',
  );

  static const String localRole = String.fromEnvironment(
    'COUNTERIQ_LOCAL_ROLE',
    defaultValue: 'host',
  );

  static const bool localHostLanEnabled = bool.fromEnvironment(
    'COUNTERIQ_LOCAL_HOST_LAN',
    defaultValue: false,
  );

  static const String _loopbackOrigin = 'http://127.0.0.1:8080';

  static const String _localServerOrigin = String.fromEnvironment(
    'COUNTERIQ_LOCAL_SERVER_ORIGIN',
    defaultValue: _loopbackOrigin,
  );

  /// Server origin is fixed into the server build. There is intentionally no
  /// runtime setting for clients to change it.
  static const String _serverOrigin = String.fromEnvironment(
    'COUNTERIQ_SERVER_ORIGIN',
    defaultValue: 'https://145.223.118.86:18443',
  );

  static const bool isLocal = mode == 'local';
  static const bool isServer = mode == 'server';
  static const bool isLocalHost = isLocal && localRole == 'host';
  static const bool isLocalClient = isLocal && localRole == 'client';

  static const String origin = isServer
      ? _serverOrigin
      : (isLocalClient ? _localServerOrigin : _loopbackOrigin);

  static const String apiBaseUrl = '$origin/api/v1';
  static const String healthUrl = '$origin/up';
  static const String runtimeUrl = '$origin/api/v1/runtime';

  static const String startupMessage = isServer
      ? 'Connecting to CounterIQ Server...'
      : (isLocalClient
          ? 'Connecting to the CounterIQ host PC...'
          : 'Preparing the local database and services...');

  const BackendConfig._();

  static void validate() {
    if (!isLocal && !isServer) {
      throw StateError(
        'Invalid COUNTERIQ_BACKEND_MODE "$mode". Use "local" or "server".',
      );
    }

    if (isLocal && localRole != 'host' && localRole != 'client') {
      throw StateError(
        'Invalid COUNTERIQ_LOCAL_ROLE "$localRole". Use "host" or "client".',
      );
    }

    if (isServer) {
      _validateOrigin(_serverOrigin, 'COUNTERIQ_SERVER_ORIGIN');
    }

    if (isLocalClient) {
      _validateOrigin(_localServerOrigin, 'COUNTERIQ_LOCAL_SERVER_ORIGIN');
      final uri = Uri.parse(_localServerOrigin);
      if (uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '::1') {
        throw StateError(
          'COUNTERIQ_LOCAL_SERVER_ORIGIN points to this client PC. '
          'Use the LAN IP address of the CounterIQ host PC, for example '
          'http://192.168.1.50:8080.',
        );
      }
    }
  }

  static void _validateOrigin(String value, String key) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError(
        'Invalid $key "$value". Use a complete http:// or https:// origin.',
      );
    }
  }
}
