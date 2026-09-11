/// Single source of truth for the product name — shown wherever the UI names
/// the app, and the value to change if the product is ever renamed again.
const String kAppName = String.fromEnvironment(
  'APP_NAME',
  defaultValue: 'OrcaBox',
);

/// Running app version shown in Settings/About. Populated from the real build
/// (PackageInfo) at boot so it never goes stale; this literal is just the
/// pre-boot fallback.
String kAppVersion = const String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.1',
);

/// Stable application id embedded in default provider-repo manifests and
/// checked by the repo guard so a manga-only (Sozo) repo can't be added.
///
/// NOT a brand string — deliberately left at its original value through the
/// OrcaBox rename. Every published provider-repo manifest declares this token,
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
/// Supplied at build time via `--dart-define-from-file=.env` (`APP_REPO`) so a
/// fork does not have to patch source to point at its own repo. The default is
/// only a fallback for a build that forgets the define. The releases the updater
/// offers, and the `assets/fonts/` + `announcements.json` it fetches, all have
/// to exist on this repo's default branch.
const String kAppRepo = String.fromEnvironment(
  'APP_REPO',
  defaultValue: 'orcabox21/orcabox-releases',
);

/// Browsable URL for [kAppRepo] — the About screen's "source code" link.
const String kAppRepoUrl = 'https://github.com/$kAppRepo';

/// Raw-file base for [kAppRepo]'s default branch (trailing slash).
const String kAppRepoRawBase =
    'https://raw.githubusercontent.com/$kAppRepo/main/';

/// Community Discord invite. Lived in two places (the launch community sheet
/// and Settings → About) and drifted — the sheet's copy went stale and expired.
/// One const now, so refreshing the invite is a single edit here.
///
/// Supplied at build time via `--dart-define-from-file=.env`
/// (`DISCORD_INVITE_URL`); empty until OrcaBox has its own server. It
/// previously held the upstream project's invite, which would have pointed
/// OrcaBox users at someone else's community. Every Discord entry point checks
/// [kHasDiscord] first, so setting that one key in `.env` turns them all back
/// on.
const String kDiscordInviteUrl = String.fromEnvironment(
  'DISCORD_INVITE_URL',
);

/// [kDiscordInviteUrl] as something `launchUrl` can actually open.
///
/// Discord shows invites as a bare code ("abc123") as often as a full link, and
/// a bare code reaches `Uri.parse` as a relative URI with no scheme — which
/// launches nothing and gives no error the user can act on. So a value with no
/// scheme is read as an invite code and expanded to its discord.gg link.
String get kDiscordInviteLink {
  final v = kDiscordInviteUrl.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  // Accept 'discord.gg/xyz' as well as a naked 'xyz' invite code.
  if (v.startsWith('discord.gg/') || v.startsWith('discord.com/')) {
    return 'https://$v';
  }
  return 'https://discord.gg/$v';
}

/// Whether a community Discord is configured — gates the Settings tile and the
/// launch community sheet.
bool get kHasDiscord => kDiscordInviteUrl.trim().isNotEmpty;

/// Official Telegram channel. Supplied at build time via
/// `--dart-define-from-file=.env` (`TELEGRAM_URL`); empty hides every Telegram
/// entry point, exactly like [kDiscordInviteUrl] does for Discord. The
/// pre-rebrand value was the upstream project's channel.
const String kTelegramUrl = String.fromEnvironment('TELEGRAM_URL');

/// Whether a Telegram channel is configured.
bool get kHasTelegram => kTelegramUrl.isNotEmpty;

// ── Support / donations ──────────────────────────────────────────────────────
// All three come from `.env` and are empty by default. Every option on the
// Support screen hides itself while its own value is blank, and the Settings
// entry point disappears when all three are — the previous values pointed at
// the upstream author's accounts, so shipping a literal here would send
// OrcaBox donations to someone else.

/// Buy Me a Coffee profile URL.
const String kDonateBmcUrl = String.fromEnvironment('DONATE_BMC_URL');

/// PayPal donation URL.
const String kDonatePaypalUrl = String.fromEnvironment('DONATE_PAYPAL_URL');

/// UPI VPA (India), e.g. `name@bank` — an id, not a URL.
const String kDonateUpiId = String.fromEnvironment('DONATE_UPI_ID');

/// Developer announcements feed (a plain JSON file in the public app repo).
/// The app READS this on launch to show in-app announcements — never writes.
/// Edit + push that file to broadcast a message to every user.
///
/// Points at OrcaBox's own repo: whoever controls this file controls what
/// every install shows on launch, so it must never be a repo we don't own.
/// `announcements.json` in the repo root is the file it serves; a missing file
/// simply means no announcements (AnnouncementService swallows the 404).
const String kAnnouncementsUrl = '${kAppRepoRawBase}announcements.json';

// The TMDB API key lives on `Tmdb.apiKey` (core/metadata/tmdb.dart), which is
// what the Dio interceptor actually reads. A second `kTmdbApiKey` const used to
// sit here declaring the SAME `TMDB_API_KEY` dart-define but defaulting to
// empty, and nothing ever read it — so a build that set the define looked
// configured from here while the real key came from somewhere else entirely.
// One constant, in the file that owns the rest of the TMDB config.
