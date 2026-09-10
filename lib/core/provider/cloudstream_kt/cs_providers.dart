import '../base_provider.dart';
import 'cs_adapter.dart';
import 'cs_extractor.dart';
import 'extractors/driveseed_extractor.dart';
import 'extractors/gdmirror_extractor.dart';
import 'extractors/hubcloud_extractor.dart';
import 'extractors/packed_host_extractor.dart';
import 'extractors/vidstack_extractor.dart';
import 'providers/fourkhdhub_provider.dart';
import 'providers/hdhub4u_provider.dart';
import 'providers/multimovies_provider.dart';
import 'providers/uhdmovies_provider.dart';

/// The registration point for the CloudStream→Dart layer — Kotlin's
/// `@CloudstreamPlugin class …Plugin : BasePlugin { registerMainAPI(...) }`,
/// collapsed into one place because these providers ship with the app rather
/// than being installed from a repo.
///
/// Adding a provider is two lines: write its `CsMainApi`, then list it in
/// [buildCloudStreamProviders]. Nothing in the repository, the source picker,
/// the detail screen or the player needs to change — [CsProviderAdapter]
/// already presents it as a `native:` source like VegaMovies and RogMovies.
class CloudStreamKt {
  CloudStreamKt._();

  static bool _extractorsRegistered = false;

  /// Extractors are shared: MultiMovies' GDMirror fan-out lands on the same
  /// hosts 4KHDHub links to directly, so they are registered once globally
  /// rather than per provider.
  static void registerExtractors() {
    if (_extractorsRegistered) return;
    _extractorsRegistered = true;
    CsExtractorRegistry.instance.registerAll([
      HubCloudExtractor(),
      HubDriveExtractor(),
      HubCdnExtractor(),
      DriveseedExtractor(),
      GdMirrorExtractor(),
      VidStackExtractor(),
      // Last: its patterns are the broadest, and a more specific extractor
      // above should win when both match.
      PackedHostExtractor(),
    ]);
  }
}

/// Every ported CloudStream provider, adapted to this app's `BaseProvider`.
///
/// Ordering is the order they appear in the source picker and in cross-source
/// search, so the Hindi-dubbed catalogues lead.
List<BaseProvider> buildCloudStreamProviders() {
  CloudStreamKt.registerExtractors();
  return [
    CsProviderAdapter(MultiMoviesProvider()),
    CsProviderAdapter(HdHub4uProvider()),
    CsProviderAdapter(UhdMoviesProvider()),
    CsProviderAdapter(FourKHdHubProvider()),
  ];
}
