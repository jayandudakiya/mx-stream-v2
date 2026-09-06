import '../../models/episode.dart';
import '../../models/home_section.dart';
import '../../models/media_detail.dart';
import '../../models/media_item.dart';
import '../../models/provider_info.dart';
import '../../models/video_source.dart';
import '../base_provider.dart';
import 'internal/native_models.dart';
import 'provider_config.dart';
import 'rogmovies_provider.dart';
import 'vega_movies_provider.dart';

/// Bridges MXStream's native movie-provider engine (4-method
/// `NativeBaseProvider` contract: `getMainPage` / `search` / `loadDetails` /
/// `extractStream`, `internal/native_base_provider.dart`) onto this app's
/// richer CloudStream/anime-shaped `BaseProvider` contract (`getHome` /
/// `popular` / `search` / `getDetail` / `getEpisodes` / `getVideoSources`).
///
/// A series episode has no single canonical page — VegaMovies/RogMovies
/// expose one download link PER quality per episode, resolved on demand via
/// `loadEpisodeSources(seriesUrl, season, episode)` — so [Episode.url] here is
/// a synthetic key (`'<seriesUrl>::s<season>e<episode>'`) that
/// [getVideoSources] decodes back into that call. A movie has no such
/// ambiguity: its single [Episode.url] is just the detail page's own url.
abstract class _NativeMovieAdapterBase implements BaseProvider {
  static final RegExp _episodeKey = RegExp(r'^(.*)::s(\d+)e(\d+)$');
  static const Duration _detailsCacheTtl = Duration(minutes: 10);

  final Map<String, ({DateTime at, ProviderMediaDetails details})>
  _detailsCache = {};

  /// The provider key used with [ProviderConfig.resolveBaseUrl] (e.g.
  /// `'vegamovies'`) — for [getInfo] only.
  String get providerConfigKey;

  Future<List<ProviderSearchItem>> _getMainPage({
    required String category,
    required int page,
  });

  Future<List<ProviderSearchItem>> _search(String query, {required int page});

  Future<ProviderMediaDetails?> _loadDetails(String url);

  Future<List<NativeVideoSource>> _loadEpisodeSources(
    String seriesUrl,
    int season,
    int episode,
  );

  Future<List<StreamLink>> _extractStream(String url);

  String get _lang;

  /// Named Home rows for this channel: `(category key for getMainPage,
  /// display title)`.
  List<({String key, String title})> get homeSections;

  @override
  Future<ProviderInfo> getInfo() async {
    final baseUrl = await ProviderConfig.resolveBaseUrl(providerConfigKey);
    return ProviderInfo(
      name: displayName,
      lang: _lang,
      baseUrl: baseUrl,
      type: ProviderType.movie,
    );
  }

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) async {
    final sections = <HomeSection>[];
    for (final row in homeSections) {
      final items = await _getMainPage(category: row.key, page: 1)
          .then((r) => r.map(_toMediaItem).toList())
          .catchError((_) => <MediaItem>[]);
      if (items.isNotEmpty) sections.add(HomeSection(title: row.title, items: items));
    }
    return sections.isEmpty ? null : sections;
  }

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) async {
    final items = await _getMainPage(category: 'home', page: page);
    return items.map(_toMediaItem).toList();
  }

  @override
  Future<List<MediaItem>> search(String query, int page, {String category = ''}) async {
    final items = await _search(query, page: page);
    return items.map(_toMediaItem).toList();
  }

  Future<ProviderMediaDetails?> _detailsFor(String url) async {
    final cached = _detailsCache[url];
    if (cached != null && DateTime.now().difference(cached.at) < _detailsCacheTtl) {
      return cached.details;
    }
    final details = await _loadDetails(url);
    if (details != null) {
      _detailsCache[url] = (at: DateTime.now(), details: details);
    }
    return details;
  }

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) async {
    final details = await _detailsFor(url);
    if (details == null) {
      return MediaDetail(id: url, title: '', url: url, type: ProviderType.movie, sourceId: sourceId);
    }

    final isSeries = details.type == 'series';
    final episodes = isSeries
        ? details.episodes.map((e) => _toEpisode(url, e)).toList()
        : [Episode(id: url, title: 'Movie', number: 1, url: url)];

    final imdbId = RegExp(r'tt\d{7,9}').firstMatch(details.imdbUrl)?.group(0);

    return MediaDetail(
      id: url,
      title: details.title,
      cover: details.poster.isEmpty ? null : details.poster,
      banner: details.background.isEmpty ? null : details.background,
      url: url,
      description: details.plot.isEmpty ? null : details.plot,
      episodes: episodes,
      year: details.year?.toString(),
      type: ProviderType.movie,
      sourceId: sourceId,
      imdbId: imdbId,
    );
  }

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) async {
    final detail = await getDetail(url, category: category);
    return detail.episodes;
  }

  @override
  Future<List<VideoSource>> getVideoSources(String episodeUrl, {bool fast = false}) async {
    final match = _episodeKey.firstMatch(episodeUrl);
    List<NativeVideoSource> candidates;
    if (match != null) {
      final seriesUrl = match.group(1)!;
      final season = int.parse(match.group(2)!);
      final episode = int.parse(match.group(3)!);
      candidates = await _loadEpisodeSources(seriesUrl, season, episode);
    } else {
      final details = await _detailsFor(episodeUrl);
      candidates = details?.sources ?? const [];
    }
    if (candidates.isEmpty) return const [];

    final batches = await Future.wait(
      candidates.map((c) => _extractStream(c.url).catchError((_) => <StreamLink>[])),
    );
    return batches.expand((s) => s).map(_toVideoSource).toList();
  }

  MediaItem _toMediaItem(ProviderSearchItem item) => MediaItem(
    id: item.url,
    title: item.title,
    cover: item.poster.isEmpty ? null : item.poster,
    url: item.url,
    type: ProviderType.movie,
    sourceId: sourceId,
  );

  Episode _toEpisode(String seriesUrl, EpisodeInfo info) {
    final key = '$seriesUrl::s${info.season}e${info.episode}';
    return Episode(
      id: key,
      title: info.name,
      number: info.episode.toDouble(),
      url: key,
      season: info.season,
      thumbnail: info.poster,
      description: info.description,
    );
  }

  VideoSource _toVideoSource(StreamLink link) => VideoSource(
    url: link.streamUrl,
    quality: link.quality,
    label: link.name,
    container: link.isHls ? SourceContainer.hls : SourceContainer.mp4,
  );
}

/// Hollywood channel — VegaMovies.
class VegaMoviesAdapter extends _NativeMovieAdapterBase {
  VegaMoviesAdapter({VegaMoviesProvider? provider}) : _provider = provider ?? VegaMoviesProvider();

  final VegaMoviesProvider _provider;

  @override
  String get sourceId => 'native:vegamovies';

  @override
  String get displayName => 'VegaMovies (Hollywood)';

  @override
  String get providerConfigKey => 'vegamovies';

  @override
  String get _lang => _provider.lang;

  @override
  List<({String key, String title})> get homeSections => const [
    (key: 'home', title: 'Latest Releases'),
    (key: 'netflix', title: 'Netflix'),
    (key: 'prime', title: 'Prime Video'),
    (key: 'hotstar', title: 'Hotstar'),
    (key: 'anime', title: 'Anime'),
  ];

  @override
  Future<List<ProviderSearchItem>> _getMainPage({required String category, required int page}) =>
      _provider.getMainPage(category: category, page: page);

  @override
  Future<List<ProviderSearchItem>> _search(String query, {required int page}) =>
      _provider.search(query, page: page);

  @override
  Future<ProviderMediaDetails?> _loadDetails(String url) => _provider.loadDetails(url);

  @override
  Future<List<NativeVideoSource>> _loadEpisodeSources(String seriesUrl, int season, int episode) =>
      _provider.loadEpisodeSources(seriesUrl, season, episode);

  @override
  Future<List<StreamLink>> _extractStream(String url) => _provider.extractStream(url);
}

/// Bollywood channel — RogMovies.
class RogMoviesAdapter extends _NativeMovieAdapterBase {
  RogMoviesAdapter({RogMoviesProvider? provider}) : _provider = provider ?? RogMoviesProvider();

  final RogMoviesProvider _provider;

  @override
  String get sourceId => 'native:rogmovies';

  @override
  String get displayName => 'RogMovies (Bollywood)';

  @override
  String get providerConfigKey => 'rogmovies';

  @override
  String get _lang => _provider.lang;

  @override
  List<({String key, String title})> get homeSections => const [
    (key: 'home', title: 'Latest Bollywood'),
    (key: 'netflix', title: 'Netflix'),
    (key: 'prime', title: 'Prime Video'),
    (key: 'zee5', title: 'Zee5'),
    (key: 'hotstar', title: 'JioHotstar'),
  ];

  @override
  Future<List<ProviderSearchItem>> _getMainPage({required String category, required int page}) =>
      _provider.getMainPage(category: category, page: page);

  @override
  Future<List<ProviderSearchItem>> _search(String query, {required int page}) =>
      _provider.search(query, page: page);

  @override
  Future<ProviderMediaDetails?> _loadDetails(String url) => _provider.loadDetails(url);

  @override
  Future<List<NativeVideoSource>> _loadEpisodeSources(String seriesUrl, int season, int episode) =>
      _provider.loadEpisodeSources(seriesUrl, season, episode);

  @override
  Future<List<StreamLink>> _extractStream(String url) => _provider.extractStream(url);
}
