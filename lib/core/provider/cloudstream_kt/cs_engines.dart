/// The engine catalogue: which site engines exist, what they look like to a
/// user picking one, and how a [CsSourceSpec] becomes a running [CsMainApi].
///
/// Kept apart from `cs_spec.dart` so a provider can depend on the spec types
/// without depending on the list of every provider. Flutter-free, like the rest
/// of this layer bar `cs_adapter.dart` and `cs_providers.dart`.
library;

import 'cs_extractor.dart';
import 'cs_main_api.dart';
import 'cs_spec.dart';
import 'cs_types.dart';
import 'extractors/driveseed_extractor.dart';
import 'extractors/gdmirror_extractor.dart';
import 'extractors/hubcloud_extractor.dart';
import 'extractors/packed_host_extractor.dart';
import 'extractors/vidstack_extractor.dart';
import 'providers/fourkhdhub_provider.dart';
import 'providers/hdhub4u_provider.dart';
import 'providers/multimovies_provider.dart';
import 'providers/uhdmovies_provider.dart';

/// How an engine is described to someone adding a custom source — they have to
/// be able to judge their site against it without reading the scraper.
class CsEngineInfo {
  const CsEngineInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.exampleSite,
    required this.supportedTypes,
  });

  final CsEngineId id;
  final String label;
  final String description;

  /// A site known to run this engine, shown as the "looks like this" hint.
  final String exampleSite;
  final Set<TvType> supportedTypes;
}

/// Every engine, in the order the Custom sources screen lists them — most
/// widely applicable first.
const List<CsEngineInfo> csEngines = [
  CsEngineInfo(
    id: CsEngineId.dooplay,
    label: 'DooPlay / WordPress',
    description:
        'Movie sites with /movies/ and /tvshows/ pages, a "?s=" search box and '
        'an embedded player list on the detail page. The most common layout.',
    exampleSite: 'multimovies.beer',
    supportedTypes: {
      TvType.movie,
      TvType.tvSeries,
      TvType.anime,
      TvType.animeMovie,
      TvType.cartoon,
    },
  ),
  CsEngineInfo(
    id: CsEngineId.hdhub4u,
    label: 'HDHub4u-style index',
    description:
        'Posts that are a flat list of quality headings with download links '
        'underneath, plus /category/… archive pages.',
    exampleSite: 'hdhub4u.cl',
    supportedTypes: {TvType.movie, TvType.tvSeries, TvType.anime},
  ),
  CsEngineInfo(
    id: CsEngineId.uhdmovies,
    label: 'UHDMovies-style download index',
    description:
        'Download indexes whose posts list quality headings linking into '
        'Driveleech / Driveseed lockers.',
    exampleSite: 'uhdmovies.autos',
    supportedTypes: {TvType.movie, TvType.tvSeries},
  ),
  CsEngineInfo(
    id: CsEngineId.fourKHdHub,
    label: '4KHDHub-style catalogue',
    description:
        'Card-grid catalogues with structured download-item / episode-item '
        'blocks on the detail page.',
    exampleSite: '4khdhub.one',
    supportedTypes: {TvType.movie, TvType.tvSeries, TvType.anime},
  ),
];

CsEngineInfo csEngineInfo(CsEngineId id) =>
    csEngines.firstWhere((e) => e.id == id);

/// Builds the running provider for a spec. The one place an engine id turns
/// into a class, so adding an engine is a case here plus its provider file.
CsMainApi buildCsApi(CsSourceSpec spec) => switch (spec.engineId) {
      CsEngineId.dooplay => MultiMoviesProvider(spec: spec),
      CsEngineId.hdhub4u => HdHub4uProvider(spec: spec),
      CsEngineId.uhdmovies => UhdMoviesProvider(spec: spec),
      CsEngineId.fourKHdHub => FourKHdHubProvider(spec: spec),
    };

/// The sources that ship with the app, in source-picker order.
///
/// All four keep resolving their domain through the manifests (`baseUrl` null):
/// every one of these sites rotates domain on a scale of weeks, and pinning a
/// URL here would mean shipping a release each time one moved.
const List<CsSourceSpec> builtInCsSpecs = [
  CsSourceSpec(
    engineId: CsEngineId.dooplay,
    key: 'multimovies',
    name: 'MultiMovies',
  ),
  CsSourceSpec(
    engineId: CsEngineId.hdhub4u,
    key: 'hdhub4u',
    name: 'HDHub4u',
  ),
  CsSourceSpec(
    engineId: CsEngineId.uhdmovies,
    key: 'uhdmovies',
    name: 'UHDMovies',
  ),
  CsSourceSpec(
    engineId: CsEngineId.fourKHdHub,
    key: '4khdhub',
    name: '4KHDHub',
  ),
];

bool _extractorsRegistered = false;

/// Extractors are shared rather than per-provider: MultiMovies' GDMirror
/// fan-out lands on the same hosts 4KHDHub links to directly, so registering
/// them once globally is both correct and cheaper.
///
/// Idempotent — safe to call from every entry point (the app's provider build,
/// the live-check harness, a test).
void registerCsExtractors() {
  if (_extractorsRegistered) return;
  _extractorsRegistered = true;
  CsExtractorRegistry.instance.registerAll([
    HubCloudExtractor(),
    HubDriveExtractor(),
    HubCdnExtractor(),
    DriveseedExtractor(),
    GdMirrorExtractor(),
    VidStackExtractor(),
    // Last: its patterns are the broadest, and a more specific extractor above
    // should win when both match.
    PackedHostExtractor(),
  ]);
}
