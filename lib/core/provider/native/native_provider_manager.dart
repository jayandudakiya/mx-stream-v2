import 'package:flutter/foundation.dart';

import '../base_provider.dart';
import '../cloudstream_kt/cs_adapter.dart';
import '../cloudstream_kt/cs_providers.dart';
import '../cloudstream_kt/custom_source_store.dart';
import '../moviebox/moviebox_provider.dart';
import 'native_provider_adapter.dart';

/// Holds the built-in native movie providers (`native:*` source ids) — the
/// movie twin of `MihonManager`/`AniyomiManager`, except these are always
/// pre-installed rather than user-added from a repo (per the "auto-install /
/// pre-install" requirement carried over from OrcaBox: a user should never
/// see a manual install screen just to get Hollywood/Bollywood browsing).
///
/// Three engines feed it, all presenting the same `BaseProvider` contract:
///  * VegaMovies/RogMovies, OrcaBox's original hand-written Dart scrapers;
///  * the providers ported from Kotlin CloudStream through
///    `lib/core/provider/cloudstream_kt/` (MultiMovies, HDHub4u, UHDMovies,
///    4KHDHub);
///  * the user's own sources from Settings → Custom sources, which are those
///    same ported engines pointed at a base URL they supplied.
///
/// The originals are listed first so nothing about their ordering, ids or
/// behaviour changes as ported providers are added alongside them.
///
/// A [ChangeNotifier] because the custom half is editable at runtime: adding or
/// removing a source has to reach the source picker and the search fan-out
/// without an app restart.
class NativeProviderManager extends ChangeNotifier {
  NativeProviderManager({CustomSourceStore? customSources})
      : _customSources = customSources {
    registerAll([
      VegaMoviesAdapter(),
      RogMoviesAdapter(),
      // MovieBox is not a scraper: it is a signed JSON API with direct CDN
      // streams (`lib/core/provider/moviebox/`). It presents the same
      // `CsMainApi` the ported providers do, so it arrives here through the
      // same adapter and needs nothing of its own downstream.
      CsProviderAdapter(MovieBoxProvider()),
      ...buildCloudStreamProviders(
        customSpecs: [
          for (final source in customSources?.enabled ?? const [])
            source.toSpec(),
        ],
      ),
    ]);
    for (final source in customSources?.enabled ?? const []) {
      _builtFrom[source.sourceId] = source;
    }
    customSources?.addListener(syncCustomSources);
  }

  final CustomSourceStore? _customSources;

  final Map<String, BaseProvider> _sources = {};

  /// Which stored definition each registered custom provider was built from.
  ///
  /// Kept beside the provider rather than wrapping it: the repository routes
  /// Home-row paging with `p is CsProviderAdapter` (source_repository.dart), and
  /// the detail screen and source switcher make similar type checks, so a custom
  /// source has to BE the same adapter type a built-in one is — not a decorator
  /// around it.
  final Map<String, CustomSource> _builtFrom = {};

  /// All registered native providers (`native:*` source ids).
  List<BaseProvider> get all => _sources.values.toList();

  /// Resolves a provider by its `native:<id>` identifier, or null when not
  /// registered.
  BaseProvider? get(String sourceId) => _sources[sourceId];

  /// The stored definition behind a custom source id, or null for a built-in.
  CustomSource? customSourceFor(String sourceId) => _builtFrom[sourceId];

  void register(BaseProvider provider) {
    _sources[provider.sourceId] = provider;
  }

  void registerAll(List<BaseProvider> providers) {
    for (final p in providers) {
      _sources[p.sourceId] = p;
    }
  }

  /// Brings the registered custom providers back in line with the store, after
  /// the user adds, edits, enables, disables or deletes one.
  ///
  /// Providers whose definition changed are rebuilt rather than mutated: an
  /// adapter caches the detail pages and link payloads it has already fetched,
  /// and those belong to the base URL it fetched them from. Sources the edit did
  /// not touch keep their instance, and so their warm cache.
  void syncCustomSources() {
    final store = _customSources;
    if (store == null) return;

    final wanted = {for (final s in store.enabled) s.sourceId: s};
    var changed = false;

    // Drop custom providers that were deleted or switched off.
    for (final id in _sources.keys.toList()) {
      if (!_isCustomId(id) || wanted.containsKey(id)) continue;
      _sources.remove(id);
      _builtFrom.remove(id);
      changed = true;
    }

    // Add what is missing, and replace anything whose definition moved.
    for (final entry in wanted.entries) {
      final previous = _builtFrom[entry.key];
      if (previous != null && _sameProvider(previous, entry.value)) continue;
      _sources[entry.key] =
          buildCustomCloudStreamProvider(entry.value.toSpec());
      _builtFrom[entry.key] = entry.value;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  static bool _isCustomId(String sourceId) =>
      sourceId.startsWith('native:custom_');

  /// True when two definitions would produce an identical provider, so the live
  /// one can be left alone.
  ///
  /// The name is part of this even though it changes no request: an adapter's
  /// `displayName` is read from the spec it was built with, so keeping the old
  /// instance after a rename would leave the old label in the source picker.
  /// A rebuild costs only a warm page cache.
  static bool _sameProvider(CustomSource a, CustomSource b) =>
      a.baseUrl == b.baseUrl &&
      a.engineId == b.engineId &&
      a.lang == b.lang &&
      a.name == b.name &&
      mapEquals(a.rows, b.rows);
}
