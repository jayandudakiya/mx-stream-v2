/// Public backend configuration. These are NOT secrets — the project URL and
/// anon key ship in every Supabase client app. Auth uses email/password
/// sessions; the service-role key is never embedded here.
///
/// Supabase is the only backend. The Appwrite project and the account-migration
/// bridge it existed for were removed (see NOTES.md task 16): OrcaBox is a new
/// project with no legacy accounts to import, so every user registers directly
/// into Supabase.
class Environment {
  // Supabase project URL + anon (public) key. Supplied at build time via
  // --dart-define / --dart-define-from-file so a staging build needs no edit.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Base of the OrcaBox website (landing + reset + the share "open" page).
  ///
  /// Supplied at build time via `--dart-define-from-file=.env` (`SITE_BASE_URL`)
  /// so the deployed site can move without a code change. The default is only
  /// a fallback for a build that forgets the define — a real build should
  /// always pass one. No trailing slash: the derived URLs add their own.
  static const String siteBaseUrl = String.fromEnvironment(
    'SITE_BASE_URL',
    defaultValue: 'https://orcabox.vercel.app',
  );

  /// Password-reset landing. Supabase drives the reset (via the auth `site_url`,
  /// which points at this same page); the AuthCubit calls
  /// `resetPasswordForEmail`.
  static const String passwordResetUrl = '$siteBaseUrl/';

  /// Share links point here. The page opens the app if installed (via the
  /// [openLinkScheme] scheme below), otherwise offers the download. Its domain
  /// must be allow-listed as a Supabase auth redirect URL.
  static const String siteOpenUrl = '$siteBaseUrl/open/';

  /// TV pairing page on the website. Used when someone opens a shared/https
  /// pair link in a browser; the page can hand off to the app via
  /// `orcabox://pair`. App-facing TV QRs encode the deeplink directly.
  static const String sitePairUrl = '$siteBaseUrl/pair/';

  /// The "open" page redirects to `orcabox://open?…`; an installed app catches
  /// it (see [OpenLinkService] + the Android manifest intent-filter).
  static const String openLinkScheme = trackerRedirectScheme; // 'orcabox'
  static const String openLinkHost = 'open';
  static const String pairLinkHost = 'pair';


  // ── Tracker OAuth ──────────────────────────────────────────────────────────
  // All redirects share the orcabox:// scheme; each has its own host with a
  // matching Android intent-filter. Neither remaining tracker needs a client
  // secret: AniList uses the implicit grant and MAL uses PKCE.
  static const String trackerRedirectScheme = 'orcabox';

  // AniList — implicit grant (token in URL fragment, 1-year, no secret).
  static const String anilistClientId = String.fromEnvironment(
    'ANILIST_CLIENT_ID',
  );
  static const String anilistRedirectHost = 'anilist-auth';
  static String get anilistRedirectUri =>
      '$trackerRedirectScheme://$anilistRedirectHost';

  // MyAnimeList — OAuth2 PKCE (plain), no client secret. Supplied at build time
  // like every other client id, so no account-specific value sits in the repo.
  static const String malClientId = String.fromEnvironment('MAL_CLIENT_ID');
  static const String malRedirectHost = 'mal-auth';
  static String get malRedirectUri =>
      '$trackerRedirectScheme://$malRedirectHost';


  // Back-compat alias (older AniList code referenced this name).
  static const String anilistRedirectScheme = trackerRedirectScheme;
}
