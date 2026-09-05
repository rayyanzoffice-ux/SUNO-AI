/// Production configuration values that must survive a plain
/// `flutter build apk --release` without `--dart-define`.
///
/// The relay URL is intentionally checked in because it is a public endpoint
/// (the Edge Function verifies its own Firebase service-account secrets).
abstract final class AppConfig {
  /// Default Supabase Edge Function URL for the FCM alert relay.
  ///
  /// Override at compile time with:
  ///   --dart-define=SUNO_ALERT_RELAY_URL=https://.../send-alert
  static const String _defaultAlertRelayUrl =
      'https://uxqthxlgcyybbrpmfevk.supabase.co/functions/v1/send-alert';

  static const String _envRelayUrl = String.fromEnvironment(
    'SUNO_ALERT_RELAY_URL',
  );

  /// Resolved alert relay URL. Falls back to the checked-in production URL
  /// when no compile-time environment value is supplied.
  static String get alertRelayUrl =>
      _envRelayUrl.trim().isEmpty ? _defaultAlertRelayUrl : _envRelayUrl;
}
