import '../base_provider.dart';
import 'cs_adapter.dart';
import 'cs_engines.dart';
import 'cs_spec.dart';

/// The registration point for the CloudStream→Dart layer — Kotlin's
/// `@CloudstreamPlugin class …Plugin : BasePlugin { registerMainAPI(...) }`,
/// collapsed into one place because these providers ship with the app rather
/// than being installed from a repo.
///
/// Two kinds of source come out of here and they are otherwise identical:
///
///  * the built-in four ([builtInCsSpecs]), whose domains keep resolving
///    through the remote manifests;
///  * whatever the user added under Settings → Custom sources, which pin their
///    own base URL and run one of the same engines against it.
///
/// Nothing downstream can tell them apart: both arrive as `native:` sources
/// through [CsProviderAdapter], the same way VegaMovies and RogMovies do, so
/// the repository, the source picker, the detail screen and the player need no
/// knowledge of either.
/// Every ported CloudStream provider, adapted to this app's `BaseProvider`.
///
/// [customSpecs] are the user's own sources, read from `CustomSourceStore` at
/// boot and passed in rather than read here — this file stays free of storage
/// so it can be exercised with a hand-made list in tests.
///
/// Ordering is the order they appear in the source picker and in cross-source
/// search: the built-in Hindi-dubbed catalogues lead, and the user's own
/// sources follow in the order they added them.
List<BaseProvider> buildCloudStreamProviders({
  List<CsSourceSpec> customSpecs = const [],
}) {
  registerCsExtractors();
  return [
    for (final spec in builtInCsSpecs) CsProviderAdapter(buildCsApi(spec)),
    for (final spec in customSpecs) CsProviderAdapter(buildCsApi(spec)),
  ];
}

/// One user-added source, built the same way the built-ins are. Used when a
/// source is added or edited at runtime, so the new provider is live without an
/// app restart.
BaseProvider buildCustomCloudStreamProvider(CsSourceSpec spec) {
  registerCsExtractors();
  return CsProviderAdapter(buildCsApi(spec));
}
