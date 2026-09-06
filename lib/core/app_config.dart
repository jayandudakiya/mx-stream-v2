/// Single source of truth for the product name — shown wherever the UI names
/// the app, and the value to change if the product is ever renamed again.
const String kAppName = 'MXStream';

/// Running app version shown in Settings/About. Populated from the real build
/// (PackageInfo) at boot so it never goes stale; this literal is just the
/// pre-boot fallback.
String kAppVersion = '2.0.0';

/// Stable application id embedded in default provider-repo manifests and
/// checked by the repo guard so a manga-only (Sozo) repo can't be added.
///
/// NOT a brand string — deliberately left at its original value through the
/// MXStream rename. Every published provider-repo manifest declares this token,
/// so changing it makes the repo guard reject every existing repo (users could
/// no longer install any source). It is never shown to the user.
const String kAppId = 'watch_app';

/// Manifest schema version this app speaks. Repos below this are rejected.
const int kManifestSchemaVersion = 2;

/// The app's own GitHub repository, as `owner/name`.
///
/// One constant because SIX different features used to hardcode the upstream
/// (pre-rebrand) repo independently: the in-app updater, the About screen's
/// GitHub link, the contributors list, the announcements feed, the
/// downloadable subtitle fonts, and the Discord rich-presence icon. Two of
/// those (updater, announcements) let whoever owns the repo push code and
/// messages to every install, so they must always name a repo we own.
///
/// Change this in ONE place if the repo is ever moved or renamed. The releases
/// the updater offers, and the `assets/fonts/` + `announcements.json` it
/// fetches, all have to exist on this repo's default branch.
const String kAppRepo = 'jayandudakiya8100/mx-stream-app';

/// Browsable URL for [kAppRepo] — the About screen's "source code" link.
const String kAppRepoUrl = 'https://github.com/$kAppRepo';

/// Raw-file base for [kAppRepo]'s default branch (trailing slash).
const String kAppRepoRawBase =
    'https://raw.githubusercontent.com/$kAppRepo/main/';

/// Community Discord invite. Lived in two places (the launch community sheet
/// and Settings → About) and drifted — the sheet's copy went stale and expired.
/// One const now, so refreshing the invite is a single edit here.
///
/// REBRAND TODO (see REBRANDING.md): this is still the upstream project's
/// invite. Replace it with MXStream's own server before release — shipping it
/// as-is points MXStream users at someone else's community.
const String kDiscordInviteUrl = 'https://discord.gg/938JJBn44';

/// Developer announcements feed (a plain JSON file in the public app repo).
/// The app READS this on launch to show in-app announcements — never writes.
/// Edit + push that file to broadcast a message to every user.
///
/// Points at MXStream's own repo: whoever controls this file controls what
/// every install shows on launch, so it must never be a repo we don't own.
/// `announcements.json` in the repo root is the file it serves; a missing file
/// simply means no announcements (AnnouncementService swallows the 404).
const String kAnnouncementsUrl = '${kAppRepoRawBase}announcements.json';

/// TMDB API key for movie/TV trailer lookups (TrailerService). Anime trailers
/// use AniList and need no key. Supply via `--dart-define=TMDB_API_KEY=...`,
/// or paste a literal default below. When empty, movie/TV trailers are
/// gracefully disabled (the Trailer button simply never appears for them).
const String kTmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: '',
);
