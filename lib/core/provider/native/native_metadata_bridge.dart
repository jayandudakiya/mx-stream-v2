import 'package:dio/dio.dart';


import '../../di/injector.dart';
import '../../metadata/metadata_enrichment.dart';
import '../../metadata/tmdb.dart';
import '../../models/media_detail.dart';
import 'internal/title_normalizer.dart';

/// Hybrid metadata: scraper titles in, catalogue metadata out.
///
/// MXStream v1's arrangement, kept intact — the provider stays the authority on
/// what is playable, and TMDB is only asked to describe it:
///
///  1. Home/Search/My List map straight from the provider, so what is listed is
///     exactly what can be played.
///  2. Opening a card lands on the provider's own [MediaDetail]. This class
///     then cleans the release title (`Download The Runner (2026) Dual Audio
///     1080p WEB-DL…` → `The Runner`, 2026, series?) via [TitleNormalizer],
///     matches it on TMDB and merges the description, artwork, genres, year and
///     rating over the provider's sparse fields.
///  3. Play is untouched. `url`, `sourceId` and `episodes` are never rewritten,
///     so `getVideoSources` still resolves through the provider's raw data.
///
/// Every failure degrades to the provider's own detail — no key, no network, no
/// match, a rate limit: the page still opens with what the scraper gave us.
class NativeMetadataBridge {
  NativeMetadataBridge._();

  /// Keyed by provider detail url. Enrichment is a network round-trip and the
  /// detail screen rebuilds freely (tab switches, tracker sheets), so the
  /// answer is remembered for the session rather than re-fetched per build.
  static final Map<String, MediaDetail> _cache = {};

  /// Titles TMDB had nothing for. Remembered so a miss costs one lookup per
  /// session instead of one per visit.
  static final Set<String> _misses = {};

  static const String _imgBase = 'https://image.tmdb.org/t/p';

  /// Returns [detail] with catalogue metadata merged in, or [detail] unchanged.
  static Future<MediaDetail> enrich(MediaDetail detail) async {
    if (Tmdb.apiKey.isEmpty) return detail;

    final cached = _cache[detail.url];
    if (cached != null) return cached;
    if (_misses.contains(detail.url)) return detail;

    try {
      final parsed = TitleNormalizer.parse(
        detail.title,
        // The provider already classified this: a series detail carries
        // episodes. Trusting that beats re-guessing from the title, which is
        // what sent single-season shows to TMDB's movie namespace.
        providerIsSeries: detail.episodes.length > 1,
      );
      if (parsed.cleanTitle.trim().isEmpty) return detail;

      final enrichment = sl<MetadataEnrichment>();
      var isTv = parsed.isSeries;
      int? tmdbId;

      // The scrapers publish an IMDb link on every detail page, and `/find`
      // maps it onto TMDB exactly — no fuzzy matching, no year tiebreak, no
      // landing on a remake. It also reports the namespace as fact, which
      // fixes the single-season series that the title alone reads as a movie.
      final imdbId = detail.imdbId;
      if (imdbId != null && imdbId.isNotEmpty) {
        final found = await enrichment.resolveTmdbExternal(imdbId);
        if (found != null) {
          tmdbId = found.id;
          isTv = found.isTv;
        }
      }
      // No IMDb id, or TMDB does not know it: fall back to the title ladder.
      tmdbId ??= await enrichment.resolveTmdbId(
        parsed.cleanTitle,
        parsed.year?.toString(),
        isTv,
      );
      if (tmdbId == null) {
        _misses.add(detail.url);
        return detail;
      }

      final dio = sl<Dio>();
      final res = await dio.get<dynamic>(
        'https://api.themoviedb.org/3/${isTv ? 'tv' : 'movie'}/$tmdbId',
        // `videos` rides along on the call we were already making, so the
        // official trailer key arrives with the overview and artwork instead
        // of costing a second, weaker search later.
        queryParameters: const {'append_to_response': 'credits,videos'},
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      final data = res.data;
      // `validateStatus` lets every non-5xx through, and TMDB answers a 429
      // rate limit with a JSON body — a Map, so a shape check alone treats it
      // as a hit and merges an empty record. Requiring the id confirms this is
      // an actual title payload; anything else is a failure, and a failure is
      // NOT cached as a miss so it retries once the limit clears.
      if (data is! Map || data['id'] == null) return detail;
      final m = Map<String, dynamic>.from(data);

      final merged = _merge(detail, m, parsed.cleanTitle, tmdbId, isTv);
      _cache[detail.url] = merged;
      return merged;
    } catch (_) {
      // Never let a metadata problem stop a title from opening.
      return detail;
    }
  }

  /// Provider-owned fields (url, sourceId, episodes, type) are copied through
  /// untouched; only descriptive ones are filled. TMDB values win over the
  /// scraper's, which are a page's worth of HTML at best — except artwork,
  /// where the provider's poster is kept when TMDB has none.
  static MediaDetail _merge(
    MediaDetail detail,
    Map<String, dynamic> m,
    String cleanTitle,
    int tmdbId,
    bool isTv,
  ) {
    String? img(String? path) => (path == null || path.isEmpty)
        ? null
        : '$_imgBase/w500$path';
    String? wide(String? path) => (path == null || path.isEmpty)
        ? null
        : '$_imgBase/w1280$path';

    final overview = (m['overview'] as String?)?.trim();
    final date = ((isTv ? m['first_air_date'] : m['release_date']) as String?)
        ?.trim();
    final genres = (m['genres'] as List?)
            ?.whereType<Map>()
            .map((g) => (g['name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    final vote = (m['vote_average'] as num?)?.toDouble();
    final runtime = isTv
        ? ((m['episode_run_time'] as List?)?.whereType<num>().firstOrNull)
            ?.toInt()
        : (m['runtime'] as num?)?.toInt();
    final cast = (m['credits'] is Map ? (m['credits']['cast'] as List?) : null)
            ?.whereType<Map>()
            .take(20)
            .map((c) => (c['name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];

    return detail.copyWith(
      // The clean title is what the user came looking for; the release string
      // stays available on the item that opened this page.
      title: cleanTitle.isEmpty ? detail.title : cleanTitle,
      description: (overview != null && overview.isNotEmpty)
          ? overview
          : detail.description,
      cover: img(m['poster_path'] as String?) ?? detail.cover,
      banner: wide(m['backdrop_path'] as String?) ?? detail.banner,
      genres: genres.isNotEmpty ? genres : detail.genres,
      cast: cast.isNotEmpty ? cast : detail.cast,
      year: (date != null && date.length >= 4)
          ? date.substring(0, 4)
          : detail.year,
      score: vote != null && vote > 0 ? (vote * 10).round() : detail.score,
      durationMins: runtime ?? detail.durationMins,
      format: isTv ? 'TV' : 'Movie',
      tmdbId: tmdbId,
      tmdbIsTv: isTv,
      trailerId: _trailerKey(m) ?? detail.trailerId,
      // Nothing below is ours to change — playback depends on them.
      // url / sourceId / episodes / type stay as the provider set them.
    );
  }

  /// The official YouTube trailer key from an `append_to_response=videos`
  /// payload, or null. Prefers a Trailer over a Teaser over any other YouTube
  /// video, which is the same order [TrailerService] applies — a Teaser is
  /// worth showing, a behind-the-scenes clip is not what the button promises.
  static String? _trailerKey(Map<String, dynamic> m) {
    final videos = m['videos'];
    final results = (videos is Map) ? videos['results'] : null;
    if (results is! List) return null;

    final youtube = results
        .whereType<Map>()
        .where((v) => v['site']?.toString() == 'YouTube')
        .where((v) => (v['key']?.toString() ?? '').isNotEmpty)
        .toList();
    if (youtube.isEmpty) return null;

    for (final type in ['Trailer', 'Teaser']) {
      for (final v in youtube) {
        if (v['type']?.toString() == type) return v['key'].toString();
      }
    }
    return youtube.first['key'].toString();
  }

  /// Drops the session caches. Exposed for tests and for a "refresh metadata"
  /// action; normal browsing never calls it.
  static void clearCache() {
    _cache.clear();
    _misses.clear();
  }
}
