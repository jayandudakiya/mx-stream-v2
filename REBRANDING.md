# OrcaBox rebrand — what changed, and what only you can finish

This app began as **Zangetsu**, briefly shipped as **MXStream**, and is now
**OrcaBox**. The rename is done throughout the codebase — identity, package
names, channels, deep links, strings, docs, tests. What is **not** done is
everything that lives on someone else's servers or accounts. A find/replace
cannot move those, and this pass deliberately did not fake them.

Everything outstanding is listed under [Before you publish](#before-you-publish),
ordered by how much damage it does if it ships as-is.

---

## Done

### Identity

| Thing | Was | Now |
| --- | --- | --- |
| Display name (Android/iOS/tvOS) | MXStream | OrcaBox |
| Android `applicationId` | `com.mxstream.app` | `com.orcabox.app` |
| Android `namespace` | `com.spyou.watch_app` | `com.orcabox.app` |
| Kotlin package tree | `com/spyou/watch_app/` | `com/orcabox/app/` |
| iOS/tvOS bundle id | `com.mxstream.app` | `com.orcabox.app` |
| Dart package | `mxstream` | `orcabox` |
| Product name constant | `kAppName = 'MXStream'` | `kAppName = 'OrcaBox'` |
| Method/event channels | `zangetsu/…`, `com.spyou.watch_app/…` | `orcabox/…`, `com.orcabox.app/…` |
| Deep-link scheme | `mxstream://` + `zangetsu://` | `orcabox://` only |
| UI strings (9 locales) | "MXStream…" | "OrcaBox…" |
| Backup file name / token | `mxstream-backup-*.json` | `orcabox-backup-*.json` |
| Download folder | `Download/MXStream` | `Download/OrcaBox` |

### Original-author identity removed from the app

The upstream author's name, avatar and GitHub links are gone from everything
that ships or runs:

* `_DeveloperRow` — the "Lead Developer" card on the About screen — is deleted.
* `kCoreTeam` and `kFixedCommunity` (`core/ui/team_section.dart`) are now empty,
  so the Contributors page is driven entirely by `kAppRepo`'s own GitHub
  contributors. The "Team" heading hides itself when nothing is pinned.
* `kExcludedFromCommunity` is empty; bots are still filtered on payload `type`.
* `CLA.md` (a contributor agreement between the upstream author and
  contributors) is deleted, along with the two `CONTRIBUTING.md` links to it.
* `flows/Zangetsu_Adaptation_Roadmap.md` — fork-adaptation planning — deleted.
* The upstream `*-providers` repo pointer is dropped from `CONTRIBUTING.md`.

### Attribution kept, deliberately

`LICENSE` is **byte-identical to upstream** and must stay that way. It is
GPL-3.0 plus additional terms under GPLv3 Section 7, and those terms are not
optional for a fork:

* **Term A** grants no right to use the Zangetsu name, logo, icon or branding —
  which is why the rename was required, not merely wanted.
* **Term B** requires this build be marked prominently as a modified, unofficial
  fork, distinct from the original.
* **Term C** requires a clearly visible credit to the original project and its
  author, with a link to the original repository, in at least one of: the
  About/Credits screen, the README, or the NOTICE file.

Terms B and C are satisfied in **`NOTICE.md`** and the README's
"License & Attribution" section — deliberately *not* in the app UI, so the
running app carries no third-party personal identity. Do not delete those two
blocks; everything else about the branding is yours.

`LICENSE-Apache-2.0.txt` stays too — Aniyomi/Tachiyomi-derived extension-loading
code under `android/app/src/main/kotlin/com/orcabox/app/aniyomi/` keeps its
original Apache-2.0 headers.

### Compatibility shims added

Renames that would otherwise have broken existing installs:

* `backup_payload.dart` accepts `mxstream` and `zangetsu` app tokens on **read**
  (writes only emit `orcabox`), so backups users already hold still restore.
* `backup_file.dart` also scans `Download/MXStream` and `Download/Zangetsu` when
  listing local backups on TV.

### Deliberately left alone

* **`kAppId = 'watch_app'`** — not a brand string. Every published provider-repo
  manifest declares this token and the repo guard checks it; changing it would
  make the app reject every existing source repo. It is never shown to a user.
* **`com.lagradost.cloudstream3`** namespace — CloudStream `.cs3` extensions
  resolve these classes by name. Renaming it breaks every extension.
* **`eu.kanade.tachiyomi`** namespace — same, for Aniyomi/Mihon extensions.
* **`zmode` / `zmode_prefs`** — the internal token for what the UI calls
  "OrcaBox Mode". The prefs keys are persisted user settings; renaming them
  silently resets everyone's mode and source choices. Comments and UI strings
  were rebranded; the storage keys were not. Rename them only behind a
  migration.

---

## Before you publish

### 1. The app still runs on the upstream author's backends

`lib/core/environment.dart` points at infrastructure that is not yours:

* **Appwrite** project `6a1ed44f0029b50bccde`
* **Supabase** project `eogwzrlfoercfwcfwlmv` (+ its anon key)
* **AniList** client `43052`, **MyAnimeList** client, **Simkl** client + secret
* **`orcabox.online`** — a placeholder written by the rename. The real value was
  `zangetsu.online`, which you do not own. **You do not own `orcabox.online`
  either** — buy it, or point `siteBaseUrl` at a domain you do own.

Shipping this means every OrcaBox account, watch history and backup is written
into someone else's database, and every tracker login runs under their OAuth
apps, which they can revoke or rotate at any time. Stand up your own Appwrite
and Supabase projects, register your own AniList/MAL/Simkl apps, and point
`Environment` at your own domain.

### 2. Tracker sign-in is inert until step 1 is done

`Environment.trackerRedirectScheme` is now `'orcabox'`, and the `zangetsu://`
intent filters are gone from `AndroidManifest.xml` and `Info.plist`. That is the
correct end state, but the OAuth apps in step 1 still have `zangetsu://…`
registered as their redirect URI — so **AniList / MAL / Simkl sign-in will fail
until you register your own apps** with `orcabox://anilist-auth`,
`orcabox://mal-auth` and `orcabox://simkl-auth`.

Your share/pair pages must redirect to `orcabox://open` and `orcabox://pair` to
match. If you would rather not break sign-in before the new OAuth apps exist,
temporarily re-add the old `<data android:scheme="zangetsu" …>` filters — but
that is a stopgap, and it puts the upstream brand back in your manifest.

### 3. Repo-owned features point at `kAppRepo`

`kAppRepo` in `lib/core/app_config.dart` is `jayandudakiya8100/mx-stream-app`,
and five features derive from it: the **in-app updater** (GitHub Releases), the
**announcements feed**, the **contributors list**, the **downloadable subtitle
fonts** (`assets/fonts/`) and the **Discord presence icon**.

Left pointing at the existing repo on purpose — it works today. If you rename
the GitHub repo to `orcabox`, change `kAppRepo` in that one place and make sure
the new repo's default branch still has `announcements.json` and `assets/fonts/`.
Whoever owns this repo can push an APK and an on-launch message to every
install, so it must always be a repo you control.

The README badges and clone URL were updated to this same repo; they will need
the same one-line change if you rename it.

### 4. Community links, donations and the Discord application

The upstream project's endpoints have been **blanked, not renamed** — a
find/replace would only have invented dead handles, and the originals sent real
users and real money to someone else. Every entry point is gated on its value
being non-empty, so filling one in switches its UI back on with no other change:

| Constant | File | Gates |
| --- | --- | --- |
| `kDiscordInviteUrl` | `core/app_config.dart` | Settings → Discord tile, launch community sheet (via `kHasDiscord`) |
| `_telegramUrl` | `features/settings/settings_about.dart` | Settings → Telegram tile |
| `_telegramUrl` | `features/community/community_sheet.dart` | Launch sheet's Telegram button |
| `_bmcUrl`, `_paypalUrl`, `_upiId` | `features/settings/donate_screen.dart` | Each donate button, and the whole Support entry (via `DonateScreen.isConfigured`) |

The launch community sheet suppresses itself entirely while no link is set, so
it won't burn its one-shot "seen" flag on an empty prompt.

Still yours to do:

* `DiscordConfig.applicationId` — **upstream's Discord application**. Rich
  Presence shows the name registered on *that application*, so it will display
  the old brand no matter what `kAppName` says. Create your own, paste its id.
* `_websiteUrl` in `settings_about.dart` — `orcabox.online` placeholder.

### 5. Signing, stores and Firebase

* Generate a new upload/signing key for `com.orcabox.app`; the old key is tied
  to the previous identity.
* `com.orcabox.app` becomes permanent on your first Play upload — it can never
  be changed afterwards. Make sure it is what you want before you publish.
* Regenerate `google-services.json` / `GoogleService-Info.plist` against a
  Firebase project registered to `com.orcabox.app` if you use Firebase.
* Play Console requires identity and address verification, and the developer
  name is shown publicly on the listing. Decide personal vs organization
  up front — switching later is painful.
* The app is **GPL-3.0** (CloudStream is copyleft), so the source must remain
  available to anyone you distribute a binary to.

### 6. Assets — done, with one gap

All launcher and branding artwork is now the OrcaBox orca mark, derived from
`orcabox-logo/full-logo-no-bg.png` (the only supplied file with a real alpha
channel) cropped to the mark alone, so no wordmark rides along into an icon.

Replaced: `assets/icon/{app_icon,logo_mark,preview_default}.png` +
`preview_classic.webp`, all 20 Android mipmaps across 5 densities, all 21 iOS
AppIcon sizes, and the full tvOS brand set — which was still the **original
Zangetsu katana artwork, wordmark included**, on both icon stacks and both Top
Shelf images. `@color/ic_launcher_bg` moved from the old cream `#F4E9D3` to
`#0B0B0F` to match the mark and the launch window.

The old `assets/icon/*.png` files were JPEGs with a `.png` extension; the
replacements are real PNGs.

**Gap:** the Android 13+ themed-icon `<monochrome>` layer
(`ic_launcher_classic_fg`) is a desaturated copy of the full mark. Android tints
monochrome layers by alpha alone and ignores colour, so a detailed mark renders
as a filled blob. A proper themed icon needs a purpose-drawn single-shape
silhouette — that is design work, not a conversion, and was deliberately not
faked here.
