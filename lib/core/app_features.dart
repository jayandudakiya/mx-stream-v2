/// Build-time feature switches.
///
/// These exist so a feature whose backend isn't live yet can be taken off the
/// screen WITHOUT deleting its code: every screen, cubit, service and table
/// mapping stays exactly where it is, and one const flips it all back on.
abstract final class AppFeatures {
  /// Supabase-backed accounts and everything that hangs off them:
  ///
  /// * sign in / sign up / profile / password reset / logout,
  /// * cross-device library sync (My List, Watch + Read history, categories),
  /// * TV ↔ phone pairing (account pairing *and* the tracker QR relay),
  /// * Watch Party rooms,
  /// * cloud backup / restore.
  ///
  /// While this is `false` the app is **local-only**: nothing calls Supabase,
  /// `Supabase.initialize` never runs, and every store falls back to the
  /// local-only branch it already had for the signed-out case. My List, watch
  /// history and categories keep working entirely out of Hive.
  ///
  /// Local-first features that merely *rendered* behind a sign-in gate (My
  /// List's empty state, Continue Watching) are ungated while this is off —
  /// with no way to sign in, gating them would hide them forever.
  ///
  /// Turn back on with `--dart-define=CLOUD_ACCOUNTS=true` (or `.env`) once the
  /// backend is ready; nothing else needs changing.
  static const bool cloudAccounts = bool.fromEnvironment(
    'CLOUD_ACCOUNTS',
  );
}
