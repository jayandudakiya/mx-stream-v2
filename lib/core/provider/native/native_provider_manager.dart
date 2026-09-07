import '../base_provider.dart';
import 'native_provider_adapter.dart';

/// Holds the built-in native movie providers (`native:*` source ids) — the
/// movie twin of `MihonManager`/`AniyomiManager`, except these two are always
/// pre-installed rather than user-added from a repo (per the "auto-install /
/// pre-install" requirement carried over from OrcaBox: a user should never
/// see a manual install screen just to get Hollywood/Bollywood browsing).
///
/// Deliberately as small as [MihonManager] is NOT — there's no repo, no
/// update checking, no enable/disable persistence. Both providers are always
/// on; that's the whole point of "pre-install".
class NativeProviderManager {
  NativeProviderManager() {
    registerAll([VegaMoviesAdapter(), RogMoviesAdapter()]);
  }

  final Map<String, BaseProvider> _sources = {};

  /// All registered native providers (`native:*` source ids).
  List<BaseProvider> get all => _sources.values.toList();

  /// Resolves a provider by its `native:<id>` identifier, or null when not
  /// registered.
  BaseProvider? get(String sourceId) => _sources[sourceId];

  void register(BaseProvider provider) {
    _sources[provider.sourceId] = provider;
  }

  void registerAll(List<BaseProvider> providers) {
    for (final p in providers) {
      _sources[p.sourceId] = p;
    }
  }
}
