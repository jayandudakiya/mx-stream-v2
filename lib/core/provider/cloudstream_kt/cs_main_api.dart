import 'cs_models.dart';
import 'cs_types.dart';

/// Dart twin of `com.lagradost.cloudstream3.MainAPI`.
///
/// A provider ported from a `.cs3` file implements exactly this: the same four
/// entry points with the same responsibilities, so the Kotlin body can be
/// transcribed rather than redesigned. `cs_adapter.dart` is what turns one of
/// these into a `BaseProvider` the rest of the app already knows how to drive.
abstract class CsMainApi {
  /// Live base URL. Async because every one of these sites moves domain
  /// regularly and the real value comes from a remote manifest — Kotlin hides
  /// that behind `runBlocking` at class-init, which Dart neither has nor wants.
  Future<String> get mainUrl;

  /// Stable id fragment. The app-facing source id is `native:<providerKey>`,
  /// so this must never change once shipped — history, My List and resume
  /// positions are all keyed on it.
  String get providerKey;

  String get name;

  /// ISO code the site's audio is in, mostly `hi` here.
  String get lang;

  Set<TvType> get supportedTypes;

  /// Rows for the Home screen, in display order.
  List<CsMainPageEntry> get mainPage;

  /// One main-page row. [request].data is the entry's path fragment.
  Future<List<CsSearchResponse>> getMainPage(int page, CsMainPageRequest request);

  Future<List<CsSearchResponse>> search(String query);

  /// The detail page. Null when the page cannot be read at all — the caller
  /// degrades to an empty detail rather than throwing at the UI.
  Future<CsLoadResponse?> load(String url);

  /// Resolves one episode's (or movie's) payload into playable mirrors.
  /// [data] is whatever this provider put in [CsEpisode.data] /
  /// [CsLoadResponse.dataUrl] — nothing outside the provider interprets it.
  ///
  /// Kotlin streams results through a callback so the UI can show mirrors as
  /// they land; here the whole list is returned once, because this app's
  /// `BaseProvider.getVideoSources` is itself a single Future.
  Future<CsLinkResult> loadLinks(String data);
}

/// What [CsMainApi.loadLinks] produces: the playable mirrors plus any subtitle
/// tracks found alongside them.
class CsLinkResult {
  const CsLinkResult({this.links = const [], this.subtitles = const []});

  final List<CsExtractorLink> links;
  final List<CsSubtitleFile> subtitles;

  static const CsLinkResult empty = CsLinkResult();

  CsLinkResult operator +(CsLinkResult other) => CsLinkResult(
        links: [...links, ...other.links],
        subtitles: [...subtitles, ...other.subtitles],
      );
}
