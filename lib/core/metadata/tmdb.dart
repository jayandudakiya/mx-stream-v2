/// TMDB API config. One embedded v3 key, used by every user — TMDB rate-limits
/// per-IP, not per-key, so a single key scales cleanly across all installs (the
/// same pattern other clients use). Powers movie/TV search autocomplete,
/// trailers, and cast/relations. Replaces the old keyless proxy, which died.
///
/// The key is attached to every request to [host] by a Dio interceptor wired in
/// initDependencies — individual TMDB calls don't need to pass `api_key`.
class Tmdb {
  Tmdb._();

  static const String host = 'api.themoviedb.org';
  static const String base = 'https://$host/3';

  /// TMDB v3 API key. Override per build with
  /// `--dart-define=TMDB_API_KEY=<your key>`, or point `--dart-define-from-file`
  /// at a JSON file holding it — same arrangement [Environment.supabaseUrl]
  /// uses, so a personal or staging key never has to be committed. The literal
  /// below is only the fallback for a build that defines nothing.
  ///
  /// Everything TMDB-backed degrades to the provider's own data when this is
  /// empty (see `NativeMetadataBridge.enrich`), so an unset key disables
  /// enrichment rather than breaking playback.
  static const String apiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'fab792d6c5936a7332045ca4565c7353',
  );

  /// TMDB image CDN (no key needed).
  static const String img = 'https://image.tmdb.org/t/p';
}
