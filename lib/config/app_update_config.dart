import 'backend_config.dart';

/// Build-time configuration for the CounterIQ Windows updater.
///
/// Example Host build defines:
///   --dart-define=COUNTERIQ_APP_VERSION=1.0.9
///   --dart-define=COUNTERIQ_UPDATE_MANIFEST_URL=https://.../host/latest.json
///
/// The manifest URL is intentionally empty by default. This keeps development
/// builds from contacting a production update channel accidentally.
class AppUpdateConfig {
  static const String currentVersion = String.fromEnvironment(
    'COUNTERIQ_APP_VERSION',
    defaultValue: '1.0.8',
  );

  static const String manifestUrl = String.fromEnvironment(
    'COUNTERIQ_UPDATE_MANIFEST_URL',
    defaultValue: '',
  );

  static const String channel = String.fromEnvironment(
    'COUNTERIQ_UPDATE_CHANNEL',
    defaultValue: 'stable',
  );

  static String get packageType => BackendConfig.isLocalClient ? 'client' : 'host';

  static bool get isEnabled => manifestUrl.trim().isNotEmpty;
}
