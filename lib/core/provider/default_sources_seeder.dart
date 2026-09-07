import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'cloudstream_provider.dart';
import 'native/provider_config.dart';

/// Installs the default source set on first launch, so a fresh install can
/// browse and play without anyone visiting Providers first.
///
/// OrcaBox v1 had nothing to install — its providers were compiled in — and
/// this app inherited the opposite default: everything comes from a repo, and
/// an untouched install has zero sources and an empty Home. This closes that
/// gap without giving up the repo system: the built-in native providers
/// (VegaMovies / RogMovies) are always there, and the Megix repo is added on
/// top for everything else.
///
/// Runs ONCE, tracked by a flag in `app_prefs`, so a user who deliberately
/// removes the repo does not get it pushed back on the next launch.
class DefaultSourcesSeeder {
  DefaultSourcesSeeder._();

  /// Megix (Hindi & English) — a `manifestVersion: 2` CloudStream repo whose
  /// `pluginLists` points at the CSX `plugins.json` catalog. The native host
  /// resolves the manifest and its plugin list; we only hand it the URL.
  static const String repoUrl =
      'https://raw.githubusercontent.com/SaurabhKaperwan/CSX/builds/CS.json';

  static const String _boxName = 'app_prefs';
  static const String _seededKey = 'seededDefaultRepo';

  /// Adds [repoUrl] and installs the plugins it advertises. Best-effort and
  /// non-fatal by construction: every failure path leaves the app exactly as
  /// it was, because the native providers already give it working sources.
  ///
  /// Call this OFF the splash path (fire-and-forget with a timeout). It makes
  /// several network round-trips, and a blocked or slow network must never be
  /// able to hold the loading screen.
  static Future<void> seed({
    CloudStreamManager? manager,
    bool installPlugins = true,
  }) async {
    // addRepo/installPlugin are Android-only channel calls (no-ops elsewhere),
    // so there is nothing to seed on iOS/tvOS/desktop.
    if (!Platform.isAndroid) return;

    Box? box;
    try {
      box = Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : null;
      if (box?.get(_seededKey) == true) return;
    } catch (_) {
      // No prefs box (a test, a wiped install mid-boot) — seeding once more is
      // harmless, so carry on rather than skipping.
    }

    final mgr = manager ?? CloudStreamManager();

    try {
      // Warm the dynamic domain table the native providers resolve against
      // (urls.json). Doing it here means the first Home load doesn't pay for
      // the lookup, and a failure just leaves the bundled fallbacks in place.
      unawaited(ProviderConfig.fetchDynamicUrls());

      if (!mgr.hasRepo(repoUrl)) {
        final advertised = await mgr.addRepo(repoUrl);
        debugPrint('[seed] added default repo: $advertised plugins advertised');
      }

      if (installPlugins) {
        final group = mgr.repoGroups.firstWhere(
          (g) => g.url == repoUrl,
          orElse: () => const CsRepoGroup(
            url: '',
            name: '',
            owner: '',
            catalog: [],
            sources: [],
          ),
        );
        // Sequential, not parallel: each install is a download plus a native
        // dex load, and firing thirty at once on a phone's connection is how
        // you get half of them failing.
        for (final plugin in group.catalog) {
          try {
            await mgr.installPlugin(plugin, repoUrl: repoUrl);
          } catch (e) {
            // One bad plugin must not stop the rest — the same rule the
            // registry's loadAll follows.
            debugPrint('[seed] ${plugin.internalName} failed: $e');
          }
        }
        debugPrint('[seed] installed ${group.catalog.length} plugin(s)');
      }

      await box?.put(_seededKey, true);
    } catch (e) {
      // Deliberately NOT marked as seeded: a network failure should be retried
      // on the next launch, unlike a user's deliberate removal.
      debugPrint('[seed] default repo seeding failed: $e');
    }
  }

  /// Lets the user re-run seeding after removing the repo on purpose (a
  /// "restore default sources" action). Not called during normal boot.
  static Future<void> resetSeededFlag() async {
    if (!Hive.isBoxOpen(_boxName)) return;
    await Hive.box(_boxName).delete(_seededKey);
  }
}

