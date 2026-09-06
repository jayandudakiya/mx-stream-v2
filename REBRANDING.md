# MXStream rebrand — what changed, and what only you can finish

This app began as **Zangetsu** and is now **MXStream 2.0.0**. The rename itself
is done (identity, icons, labels, strings, version). What is **not** done is
everything that lives on someone else's servers or accounts — a find/replace
cannot move those, and quietly repointing them would have broken working
features. Those are listed under [Before you publish](#before-you-publish).

---

## Done

### Identity

| Thing | Was | Now |
| --- | --- | --- |
| Display name (Android/iOS/tvOS) | Zangetsu | MXStream |
| Android `applicationId` | `com.spyou.watch_app` | `com.mxstream.app` |
| iOS/tvOS bundle id | `com.spyou.zangetsu` | `com.mxstream.app` |
| Dart package | `watch_app` | `mxstream` |
| Version | `1.9.9+11105` | `2.0.0+11106` |
| Launcher icon | Zangetsu katana / "Z" mark | MXStream mark (from v1) |
| Android TV banner | Zangetsu PNG | composed drawable, MXStream mark |
| In-app wordmark | `assets/icon/wordmark.png` | drawn as text (`core/ui/app_wordmark.dart`) |
| Product name constant | `kAppName = 'Zangetsu'` | `kAppName = 'MXStream'` |
| UI strings (8 locales) | "Zangetsu…" / "斬月" | "MXStream…" |

The splash/loading animation itself is untouched — same glow, same wipe-reveal,
same timings. Only the name it reveals changed, and it is now type rather than
artwork, so it stays sharp at any size and follows a custom accent colour.

### The duplicate-icon bug

A debug install showed **two identical launcher icons**, and uninstalling either
removed "both" — because they were one package with two launcher entries:

* `MainActivity` carries `MAIN` + `LAUNCHER` in the main manifest, because
  `flutter run` parses *that file* (not the merged APK) to find a launch
  activity, and it ignores `<activity-alias>`. Without it the tool fails with
  "package identifier or launch activity not found" on a clean checkout.
* `MainActivityClassic` (an `<activity-alias>`, the real home-screen entry that
  the icon picker flips) also shipped `enabled="true"` with its own
  `MAIN` + `LAUNCHER`.

Release already stripped the first one (`src/release/AndroidManifest.xml`), so
this only ever hit debug/profile builds. The fix does the opposite there: the
aliases are force-disabled in `src/debug/` and `src/profile/`. Result — exactly
one launcher entry per build type:

| Build | Launcher entry |
| --- | --- |
| debug / profile | `MainActivity` (aliases disabled) |
| release | the enabled alias (`MainActivity`'s filter removed) |

Known debug-only consequence: Settings → Appearance can't switch the icon in a
debug build (enabling an alias would bring the second icon back until you
reinstall). Release behaves normally.

### Deliberately left alone

These look like brand strings but are not, and changing them breaks things:

* **`kAppId = 'watch_app'`** (`lib/core/app_config.dart`) — every published
  provider-repo manifest declares this token and the repo guard checks it.
  Changing it makes the app reject every existing source repo. Never shown to
  the user.
* **Kotlin namespace `com.spyou.watch_app`** — the `applicationId` is what the
  Play Store and the device show; the namespace is an internal Java package.
  Android supports them differing. Renaming it means moving 100+ `.kt` files and
  rewriting every `MethodChannel` name on both sides for zero user-visible gain.
* **`MethodChannel` names (`zangetsu/…`, `com.spyou.watch_app/…`)** — private
  Dart↔Kotlin wire names, matched literally on both sides.
* **Hive box names, the backup format tag (`_kApp = 'zangetsu'`), cache dir
  names** — storage identifiers. Changing the backup tag would make backups
  exported from an older install unrestorable.
* **`zangetsu://` URL scheme** — still registered *alongside* the new
  `mxstream://` one. See below for why it can't just be swapped.

---

## Before you publish

Ordered by how much damage each one does if it ships as-is.

### 1. The app runs on the upstream author's backends

`lib/core/environment.dart` still points at infrastructure belonging to the
original Zangetsu developer:

* **Appwrite** project `6a1ed44f0029b50bccde`
* **Supabase** project `eogwzrlfoercfwcfwlmv` (+ its anon key)
* **AniList** client `43052`, **MyAnimeList** client `ac00694…`,
  **Simkl** client + **client secret**
* **`zangetsu.online`** — the password-reset landing, the share "open" page and
  the TV pairing page

Shipping this means every MXStream account, watch history and backup is written
into someone else's database, and every tracker login runs under their OAuth
apps. They can revoke or rotate any of it at any time, and the reset/share links
say `zangetsu.online`. Stand up your own Appwrite/Supabase projects, register
your own AniList/MAL/Simkl apps, and point `Environment` at a domain you own.

### 2. Then, and only then, retire the `zangetsu://` scheme

`Environment.trackerRedirectScheme` is still `'zangetsu'` **on purpose**. That
exact redirect URI is registered on the OAuth apps above, and the share/pair
pages on `zangetsu.online` redirect to it. Changing the constant today would
break tracker sign-in and every share link immediately.

`mxstream://` is already registered on Android and iOS, so once step 1 is done
the switch is a one-line change: set `trackerRedirectScheme = 'mxstream'`, put
`mxstream://anilist-auth` (etc.) in your own OAuth app settings, and have your
own site redirect to `mxstream://open` / `mxstream://pair`. Keep the
`zangetsu://` filters for one release so links already in the wild still open.

### 3. Repo-owned features now point at `kAppRepo`

`kAppRepo` in `lib/core/app_config.dart` is `jayandudakiya8100/mx-stream-app`,
and five features derive from it — the **in-app updater** (GitHub Releases), the
**announcements feed**, the **contributors list**, the **downloadable subtitle
fonts** (`assets/fonts/`, already in this tree) and the **Discord presence
icon**. Previously each hardcoded the upstream repo, which meant the upstream
owner could push an APK and an on-launch message to every MXStream install.

Set `kAppRepo` to whichever repo you actually publish this from, and make sure
that repo's default branch has `announcements.json` and `assets/fonts/`.

### 4. Community links and the Discord application

* `kDiscordInviteUrl` (`app_config.dart`) — upstream's Discord invite.
* `_telegramUrl` (`features/community/community_sheet.dart`,
  `features/settings/settings_about.dart`) — upstream's Telegram.
* `DiscordConfig.applicationId` — upstream's Discord application. Rich Presence
  shows the name registered on *that application*, so it will say the old brand
  no matter what `appName` says here. Create your own application and paste its
  id.
* `_websiteUrl` in `settings_about.dart` — `zangetsu.online`.

### 5. Signing, stores and Firebase

* **Same `applicationId` as MXStream v1 (`com.mxstream.app`)** — deliberate, so
  2.0.0 upgrades v1 in place instead of installing beside it. That only works if
  it is signed with **v1's keystore**; a different key gives users a
  signature-mismatch install failure. On your own device, a debug build will not
  install over a release-signed v1 — uninstall v1 first.
* **Version code** — `+11106`, above both v1 (`+3`) and the last Zangetsu build
  (`+11105`). Never reset this to `+1`: Android refuses an update whose version
  code is not higher.
* **Firebase** — no `google-services.json` is present, so the plugin is not
  applied and Firebase is inert. If you add it, register `com.mxstream.app` (the
  old id is not registered on any project you own).
* **Licensing** — unchanged and still unresolved: this app is GPL-3.0 (it
  bundles CloudStream) while the v1 code it now carries is CC BY-NC-SA 4.0
  (a Mirarr fork). Those two cannot both be satisfied in one published binary.

### 6. Cosmetic leftovers

`README.md`, `CONTRIBUTING.md`, `CLA.md`, `NOTICE.md`, `AI_POLICY.md` and the
`flows/` docs still describe Zangetsu, as do source-code comments. None of it
ships in the APK. `NOTICE.md` in particular should *keep* its CloudStream and
Aniyomi attribution — that is a license requirement, not branding.
