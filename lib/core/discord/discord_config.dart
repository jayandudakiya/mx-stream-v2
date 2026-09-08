import '../app_config.dart';

/// Discord Rich Presence config.
///
/// SETUP (one time): https://discord.com/developers/applications → New
/// Application → copy its **Application ID** into `DISCORD_APPLICATION_ID` in
/// `.env` (never into this file). Upload
/// a square logo under Rich Presence → Art Assets named `logo` (that's the
/// small icon). Until [applicationId] is a real id, RPC stays disabled.
class DiscordConfig {
  DiscordConfig._();

  /// Discord Application ID (Developer Portal → General Information).
  ///
  /// Supplied at build time via `--dart-define-from-file=.env`
  /// (`DISCORD_APPLICATION_ID`) — no id is baked into the repo. Unset means
  /// [configured] is false and Rich Presence stays off, which is the correct
  /// degraded state rather than announcing under someone else's application.
  ///
  /// REBRAND TODO (see REBRANDING.md): the id currently in `.env` is still the
  /// upstream project's application, so Discord shows ITS name next to
  /// whatever the user is watching, no matter what [appName] says here — the
  /// label comes from the Discord application, not from this app. Create an
  /// OrcaBox application and put its id in `.env` before release.
  static const String applicationId = String.fromEnvironment(
    'DISCORD_APPLICATION_ID',
  );

  /// Rich-Presence art-asset key for a named portal upload (optional). We
  /// prefer [appLogoUrl] via the external-assets API so browsing doesn't
  /// fall back to Discord's question-mark placeholder when `logo` isn't
  /// uploaded in the Developer Portal.
  static const String appLogoAsset = 'logo';

  /// Public square app icon Discord can proxy (same file as the launcher).
  /// Served from our own repo (see [kAppRepo]) so the presence card can't show
  /// another project's logo.
  static const String appLogoUrl = '${kAppRepoRawBase}assets/icon/app_icon.png';

  static const String appName = 'OrcaBox';

  /// Discord API base (v10).
  static const String api = 'https://discord.com/api/v10';

  static const String gatewayUrl =
      'wss://gateway.discord.gg/?v=10&encoding=json';

  /// True once a real Application ID has been set.
  static bool get configured =>
      applicationId.length >= 17 && applicationId != '0';
}
