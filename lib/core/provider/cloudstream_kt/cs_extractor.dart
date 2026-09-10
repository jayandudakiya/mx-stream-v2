import 'cs_main_api.dart';

/// Dart twin of `com.lagradost.cloudstream3.utils.ExtractorApi`, plus the
/// registry behind Kotlin's `loadExtractor(url, ...)`.
///
/// Kotlin dispatches on `mainUrl` host equality; the file lockers in this
/// space rotate TLDs weekly (`hubcloud.cx` → `.lol` → `.art`), so dispatch
/// here is on [hostPatterns] — substrings matched against the whole URL — and
/// a provider never has to be re-released just because a mirror moved.
abstract class CsExtractor {
  /// Family name, used to label the source rows this extractor produces.
  String get name;

  /// Lower-case substrings; a URL containing any of them routes here.
  List<String> get hostPatterns;

  /// True when this extractor needs the embedding page's URL as Referer.
  bool get requiresReferer => false;

  Future<CsLinkResult> getUrl(String url, {String? referer});
}

/// Host-pattern → extractor lookup, shared by every ported provider.
class CsExtractorRegistry {
  CsExtractorRegistry._();

  static final CsExtractorRegistry instance = CsExtractorRegistry._();

  final List<CsExtractor> _extractors = [];

  List<CsExtractor> get all => List.unmodifiable(_extractors);

  void register(CsExtractor e) {
    // Registration is idempotent so a provider's own `registerAll` can run on
    // every construction without stacking duplicates (which would double every
    // source row in the player sheet).
    if (_extractors.any((x) => x.name == e.name)) return;
    _extractors.add(e);
  }

  void registerAll(Iterable<CsExtractor> list) => list.forEach(register);

  CsExtractor? forUrl(String url) {
    final lower = url.toLowerCase();
    for (final e in _extractors) {
      if (e.hostPatterns.any(lower.contains)) return e;
    }
    return null;
  }
}

/// `loadExtractor(url, referer, ...)` — resolve one embed/locker URL through
/// whichever registered extractor claims it.
///
/// Returns [CsLinkResult.empty] rather than throwing for an unclaimed host or a
/// failed extraction: a provider offers many mirrors and one dead host must not
/// cost the user the others.
Future<CsLinkResult> loadExtractor(String url, {String? referer}) async {
  if (url.isEmpty) return CsLinkResult.empty;
  final extractor = CsExtractorRegistry.instance.forUrl(url);
  if (extractor == null) return CsLinkResult.empty;
  try {
    return await extractor.getUrl(url, referer: referer);
  } catch (_) {
    return CsLinkResult.empty;
  }
}
