# Plan: pre-installed providers, v1 channels, direct play, detail fixes

> **STATUS — Phases 0-4 implemented, analyzer-clean, needs on-device testing.**
> Phase 0's three questions are answered in place below. What landed:
> title cleaning at the adapter (the direct-play root cause), first-launch repo
> seeding, channel→source wiring on the mode bar, and the movie/episode detail
> fixes. What is NOT verified: any of it on a real device — the seeder and the
> CloudStream install path are Android-only channel calls that cannot run in a
> desktop test. Start the next session by installing a fresh build and walking
> the checklist in Phase 5.

Written at the end of the rebrand session. Ordered so each phase is shippable on
its own. Phase 0 is investigation only and must come first — two of the bugs
below have a root cause I have not yet confirmed, and guessing wrong would send
Phase 3 into the wrong file.

---

## Phase 0 — Confirm three things first (do not skip)

1. **Which detail screen is actually rendering.** The screenshot shows a source
   chip ("VegaMovies (Hollywood)"), a raw release title with a **Wrong title?**
   link, and Play disabled until a title is picked. That is metadata-first
   ("Z Mode") behaviour — the page starts from a catalogue title and then asks a
   source to match it — not source-first. Read `lib/features/detail/detail_screen.dart`
   and `lib/features/detail/cubit/detail_cubit.dart` and establish which path
   ran: `sl<CatalogueRouter>()` (Z Mode) or `SourceRepository.detail()` (source).
   **This decides where Phase 3 and Phase 4 land.** If it is Z Mode, the
   `NativeMetadataBridge` hook added in `native_provider_adapter.getDetail` is
   NOT on the path the screenshot took, and my earlier "one hook covers every
   screen" claim holds only for the source-first path.
2. **Which ecosystem `CS.json` belongs to.** It is a _CloudStream_ repo
   (`manifestVersion: 2`, `pluginLists` → `plugins.json`), so it installs under
   Providers → **CloudStream**, not under "OrcaBox providers" (which is the
   built-in JS ecosystem and is legitimately empty now). The screenshot showing
   "OrcaBox providers → No providers installed" may therefore be correct and
   not the bug. Verify what `ProviderReposRegistry.addRepo` accepts vs what
   `CloudStreamManager` installs.
3. **Whether `native:vegamovies` / `native:rogmovies` appear in the picker at
   all.** They are registered and always-on, so "0 sources ready · Active:
   allanime" suggests the counter only counts JS/CS sources and the active
   source is still a stale `allanime` id. Check `_rawSources` inclusion and what
   `ActiveSourceCubit` restored.

---

## Phase 1 — Pre-install the provider set at first launch

**Goal:** a fresh install has working sources with no visit to Providers.

- Add a first-launch seed step in `lib/core/di/injector.dart`, after
  `ProviderRegistry.init()` / `CloudStreamManager.init()`, guarded by a
  `seededDefaultRepo` flag in the `app_prefs` box so it runs once and a user who
  deliberately removes a repo does not get it re-added.
- Seed order:
  1. `ProviderReposRegistry.addRepo('https://raw.githubusercontent.com/SaurabhKaperwan/CSX/builds/CS.json')`
     — resolves to `pluginLists: [.../builds/plugins.json]`.
  2. Fetch that `plugins.json` and install the Hindi/English plugins through the
     existing CloudStream install path (`CloudStreamManager` / `RepoManager`).
- Do it **off the splash critical path** (fire-and-forget with a timeout, like
  the existing Aniyomi/Mihon boot steps) so a blocked network cannot trap the
  loading screen. Report progress into the Providers screen's own counter.
- `native:vegamovies` / `native:rogmovies` need no install step — they are
  compiled in. If the Providers screen's "sources ready" count ignores them,
  fix the count rather than adding a fake install record.

**Live-domain resolution:** already implemented for the native providers —
`lib/core/provider/native/provider_config.dart` reads
`https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json`
with bundled fallbacks and a 5-minute failure cooldown. Pre-warm it in the same
seed step (`ProviderConfig.fetchDynamicUrls()`) so the first Home load does not
pay the lookup. CloudStream plugins resolve their own domains internally — do
not try to inject `urls.json` into them.

**Done when:** fresh install → Providers shows the Megix repo installed with a
non-zero source count, and Home loads without the user opening Providers.

---

## Phase 2 — Home channels, v1 behaviour

Port from v1 `lib/homePage/homePage.dart` (channel state at line 79 onward) into
`lib/features/home/home_screen.dart` + `cubit/home_cubit.dart`:

- Channel state `'hollywood' | 'bollywood'` (the screenshot already shows
  Anime/Hollywood/Bollywood pills — keep Anime as-is).
- Channel → source: **Hollywood → `native:vegamovies`**, **Bollywood →
  `native:rogmovies`**.
- Per-channel shelves from v1's category keys, which the adapters already
  expose via `homeSections`:
  - Hollywood: Latest Releases, Netflix, Prime Video, Hotstar, Anime
  - Bollywood: Latest Bollywood, Netflix, Prime Video, Zee5, JioHotstar
- Keep v1's two in-memory caches (`_channelShelvesCache`, `_channelHeroCache`)
  so switching channels is instant and does not refetch.
- Hero carousel per channel from `getTrendingSlider()` (already ported on both
  providers, currently unused by the adapter — expose it or call it directly).
- Horizontal shelf pagination: v1's `MovieShelfSection` pattern —
  `maxScrollExtent - 200` triggers `popular(page: n+1)`.

**Done when:** tapping Hollywood/Bollywood swaps the rows to that provider's
content instantly on second visit, and rows paginate horizontally.

---

## Phase 3 — Direct play (the actual blocker)

Today Play is disabled until the user picks a title in the **Pick the right
title** sheet. It must play immediately, with that sheet as an override.

- Depending on Phase 0's answer:
  - **Source-first path:** the provider's detail already _is_ the title, so no
    matching step should exist. Make Play resolve
    `getVideoSources(episode.url)` directly.
  - **Z Mode path:** auto-bind the top provider search result instead of
    waiting for a manual pick — reuse `bestTitleMatch()` in
    `lib/core/models/media_item.dart`, and record the binding in the existing
    binding store so it is remembered.
- Consider porting v1's confidence scoring from
  `mx-stream-app/lib/services/metadata/metadata_resolver.dart`
  (`_tokenSetRatio` / `_levenshteinRatio`, accept ≥ 0.80, partial ≥ 0.65):
  auto-bind above the accept threshold, and only surface "Wrong title?" as a
  hint below it. That is exactly how v1 avoided a manual step.
- **Keep the Wrong title? sheet.** It is genuinely good — it just must stop
  being mandatory. It is also the fallback when confidence is low.

**Done when:** open any Home card → Play works on first tap, and Wrong title?
still lets the user re-bind.

---

## Phase 4 — Detail screen: movie shown as a 1-episode series

A movie renders "1 Episode", a "Download E1" button and an Episodes tab.

- Cause is in my adapter: `native_provider_adapter.dart` `getDetail` synthesises
  a single `Episode(title: 'Movie')` for movies, because `getVideoSources` needs
  an episode url to resolve against and CloudStream's own host does the same.
- Fix at the UI layer, not by removing the synthetic episode (playback needs
  it): in `detail_screen.dart`, when the detail is a movie — single episode
  whose `url == detail.url`, or `format == 'Movie'` from the bridge — hide the
  Episodes tab and the episode count, and label the download "Download" rather
  than "Download E1".
- Add a cheap `isMovie` signal to `MediaDetail` (or derive it in one helper used
  by both places) so the check is not duplicated per widget.
- While there: the meta line reads "2026 · 95m · 1 Episode · Completed" —
  "Completed" comes from `MediaStatus`, which the native adapter never sets.
  Either set it honestly or omit the segment for native sources.

**Done when:** a movie shows Play + Download and no Episodes tab; a series is
unchanged.

---

## Phase 5 — Verify

- `flutter analyze` — expect the 159-issue pre-existing baseline, no new errors.
- `flutter test` — baseline is 117 failures on this desktop host, all from a
  missing `quickjs_c_bridge.dll` plus stale expectations (`mode_bar_test` wants
  a "Movie/TV" mode the enum lacks, `source_languages_test` wants `eo`). Any
  _new_ failure is real.
- On device: fresh install (uninstall first — `applicationId` is now
  `com.orcabox.app`) → sources seeded → Hollywood/Bollywood rows load → card →
  Play on first tap → a movie has no Episodes tab.

---

## Notes carried forward

- `--dart-define=TMDB_API_KEY=…` is required for the metadata bridge to enrich
  anything; with an empty key it silently no-ops and detail pages show scraper
  data only.
- `REBRANDING.md` still lists the un-finished infrastructure items (Appwrite,
  Supabase, tracker OAuth apps, Discord/Telegram links, signing key) and the
  unresolved GPL-3.0 vs CC BY-NC-SA licence conflict. None of that is blocked by
  the work above, and all of it blocks release.
