import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'internal/native_base_provider.dart';
import 'internal/native_models.dart';
import 'internal/series_page_parser.dart';
import 'internal/title_normalizer.dart';
import 'provider_config.dart';
import 'extractors/vcloud_extractor.dart';

/// Hollywood / OTT / anime native scraper, ported verbatim (behaviour-for-
/// behaviour) from OrcaBox's
/// `functions/fetchers/providers/VegaMovies/vega_movies_provider.dart`.
///
/// Wrapped for this app's `BaseProvider` contract by
/// `native_provider_adapter.dart` — this class itself stays untouched from
/// its v1 form so the two apps' scraping behaviour never drifts apart.
class VegaMoviesProvider implements NativeBaseProvider {
  @override
  String get name => 'VegaMovies';

  @override
  String get lang => 'hi';

  Future<String> _getBaseUrl() async {
    return await ProviderConfig.resolveBaseUrl('vegamovies');
  }

  @override
  Future<List<ProviderSearchItem>> getMainPage({String category = 'home', int page = 1}) async {
    final baseUrl = await _getBaseUrl();

    final searchQueries = {
      'bollywood': 'Bollywood',
      'hindi': 'Bollywood',
    };

    final lowerCat = category.toLowerCase().trim();
    if (searchQueries.containsKey(lowerCat)) {
      return search(searchQueries[lowerCat]!, page: page);
    }

    final routes = {
      'home': '/page/$page/',
      'latest': '/page/$page/',
      'hollywood': '/page/$page/',
      'anime': '/anime-series/page/$page/',
      'animation': '/anime-series/page/$page/',
      'animationworld': '/anime-series/page/$page/',
      'appletv': '/web-series/apple-tv/page/$page/',
      'netflix': '/web-series/netflix/page/$page/',
      'prime': '/web-series/amazon-prime-video/page/$page/',
      'minitv': '/web-series/amazon-minitv/page/$page/',
      'hotstar': '/web-series/disneyplus-hotstar/page/$page/',
      'disney': '/web-series/disneyplus/page/$page/',
      'turkish': '/turkish-series/page/$page/',
      'chinese': '/chinese-series/page/$page/',
      'discovery': '/web-series/discovery-plus/page/$page/',
      'wwe': '/wwe/page/$page/',
      'adult': '/adult/page/$page/',
      'korean': '/korean-series/page/$page/',
      'kdrama': '/korean-series/page/$page/',
    };

    final targetUrl = '$baseUrl${routes[lowerCat] ?? routes['home']}';

    try {
      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final document = parser.parse(response.body);
      final results = <ProviderSearchItem>[];
      final elements = document.querySelectorAll('div.movies-grid > a, article.post, div.post-item');

      for (var el in elements) {
        var href = el.attributes['href'] ?? el.querySelector('a')?.attributes['href'] ?? '';
        final img = el.querySelector('img');
        if (img == null) continue;

        final rawTitle = img.attributes['alt'] ?? el.querySelector('.entry-title, h2, h3')?.text ?? '';
        final title = rawTitle.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '').trim();

        String poster = img.attributes['src'] ?? '';
        if (!poster.contains('https:')) {
          poster = img.attributes['data-src'] ?? poster;
        }

        if (href.isNotEmpty && !href.startsWith('http')) {
          href = '$baseUrl$href';
        }

        if (title.isNotEmpty && href.isNotEmpty) {
          final type = TitleNormalizer.looksLikeSeriesItem(title, href) ? 'series' : 'movie';
          results.add(ProviderSearchItem(title: title, url: href, poster: poster, type: type));
        }
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  Future<List<ProviderSearchItem>> getTrendingSlider() async {
    final baseUrl = await _getBaseUrl();
    try {
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final document = parser.parse(response.body);
      final results = <ProviderSearchItem>[];
      final elements = document.querySelectorAll('.hsl-slide');

      for (var el in elements) {
        final aTag = el.querySelector('a');
        if (aTag == null) continue;
        var href = aTag.attributes['href'] ?? '';

        final img = el.querySelector('img');
        if (img == null) continue;

        final titleElem = el.querySelector('.hsl-title a') ?? el.querySelector('.hsl-title');
        final rawTitle = titleElem?.text.trim() ?? img.attributes['alt'] ?? '';
        final title = rawTitle.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '').trim();

        String poster = img.attributes['src'] ?? '';
        if (!poster.contains('https:')) {
          poster = img.attributes['data-src'] ?? poster;
        }

        if (href.isNotEmpty && !href.startsWith('http')) {
          href = '$baseUrl$href';
        }

        if (title.isNotEmpty && href.isNotEmpty) {
          final type = TitleNormalizer.looksLikeSeriesItem(title, href) ? 'series' : 'movie';
          results.add(ProviderSearchItem(title: title, url: href, poster: poster, type: type));
        }
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<ProviderSearchItem>> search(String query, {int page = 1}) async {
    final baseUrl = await _getBaseUrl();
    final List<ProviderSearchItem> results = [];
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return results;

    // 1. Try search.php JSON endpoint first
    try {
      final searchApiUrl = '$baseUrl/search.php?q=${Uri.encodeComponent(cleanQuery)}';
      final response = await http.get(
        Uri.parse(searchApiUrl),
        headers: {
          'User-Agent': ProviderConfig.defaultUserAgent,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = json.decode(response.body);
        if (decoded is Map && decoded.containsKey('hits') && decoded['hits'] is List) {
          final hits = decoded['hits'] as List;
          for (var hit in hits) {
            final doc = hit['document'] ?? {};
            final title = (doc['title'] ?? doc['post_title'] ?? doc['name'] ?? hit['highlight']?['title']?['value'] ?? '').toString();
            final permalink = (doc['permalink'] ?? doc['url'] ?? '').toString();

            // Fix: VegaMovies search.php uses 'post_thumbnail' for images
            final poster = (doc['post_thumbnail'] ?? doc['image_url'] ?? doc['poster'] ?? doc['image'] ?? '').toString();

            if (permalink.isNotEmpty) {
              final fullUrl = permalink.startsWith('http') ? permalink : '$baseUrl$permalink';
              final isSeries = title.toLowerCase().contains('season') ||
                  title.toLowerCase().contains('series') ||
                  title.toLowerCase().contains('s0');
              results.add(ProviderSearchItem(
                title: title,
                url: fullUrl,
                poster: poster,
                type: isSeries ? 'series' : 'movie',
              ));
            }
          }
        }
      }
    } catch (_) {}

    if (results.isNotEmpty) return results;

    // 2. Try HTML WordPress Search endpoint
    try {
      final htmlSearchUrl = '$baseUrl/page/$page/?s=${Uri.encodeComponent(cleanQuery)}';
      final response = await http.get(
        Uri.parse(htmlSearchUrl),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final articles = document.querySelectorAll('article.post, div.post-item, div.blog-item');

        for (var article in articles) {
          final aTag = article.querySelector('a');
          final imgTag = article.querySelector('img');
          final titleTag = article.querySelector('.entry-title, h2, h3, a');

          final itemUrl = aTag?.attributes['href'] ?? '';
          final title = titleTag?.text.trim() ?? '';
          final poster = imgTag?.attributes['src'] ?? imgTag?.attributes['data-src'] ?? '';

          if (itemUrl.isNotEmpty && title.isNotEmpty) {
            final isSeries = title.toLowerCase().contains('season') ||
                title.toLowerCase().contains('series') ||
                title.toLowerCase().contains('s0');
            results.add(ProviderSearchItem(
              title: title,
              url: itemUrl,
              poster: poster,
              type: isSeries ? 'series' : 'movie',
            ));
          }
        }
      }
    } catch (_) {}

    // 3. If still empty and query had season/extra terms, clean title and search once more
    if (results.isEmpty) {
      final simplified = cleanQuery
          .replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '')
          .replaceAll(RegExp(r'S\d+', caseSensitive: false), '')
          .replaceAll(RegExp(r'[^\w\s]', caseSensitive: false), ' ')
          .trim();
      if (simplified.isNotEmpty && simplified != cleanQuery) {
        return search(simplified, page: page);
      }
    }

    return results;
  }

  @override
  Future<ProviderMediaDetails?> loadDetails(String url, {bool skipSources = false}) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final document = parser.parse(response.body);
      final title = document.querySelector('h1.entry-title, h1')?.text.trim() ?? '';
      // The page's own synopsis heading decides this, as it does in the Kotlin
      // original. Only when the page has no heading we recognise do we fall
      // back to reading the release title, which misclassifies both ways.
      final isSeries = pageDeclaresSeries(document) ??
          (title.toLowerCase().contains('season') ||
              title.toLowerCase().contains('series') ||
              url.toLowerCase().contains('season'));

      final img = document.querySelector('div.entry-content img, article img');
      final poster = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

      // Plot
      String plot = '';
      for (var p in document.querySelectorAll('p')) {
        final text = p.text.trim();
        if (text.contains('SYNOPSIS') || text.contains('Plot') || text.contains('Storyline')) {
          plot = text;
          break;
        }
      }

      List<NativeVideoSource> movieSources = [];
      List<EpisodeInfo> seriesEpisodes = [];
      bool archiveOnly = false;

      if (!skipSources) {
        if (!isSeries) {
          movieSources = await _extractMovieSources(document);
        } else {
          seriesEpisodes = await _extractAllSeriesEpisodes(document);
          // Distinguish "this season ships only as a .zip" from "nothing found".
          if (seriesEpisodes.isEmpty) {
            archiveOnly = seriesHeadingsArePackOnly(document);
          }
        }
      }

      return ProviderMediaDetails(
        title: title,
        url: url,
        type: isSeries ? 'series' : 'movie',
        poster: poster,
        background: poster,
        plot: plot,
        rating: '',
        audioTitle: '',
        audioLanguages: [],
        tags: [],
        cast: [],
        imdbUrl: _extractImdbUrl(response.body),
        sources: movieSources,
        episodes: seriesEpisodes,
        seasonIsArchiveOnly: archiveOnly,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fast parallel movie source parser
  Future<List<NativeVideoSource>> _extractMovieSources(dynamic document) async {
    final List<NativeVideoSource> sources = [];
    final linkUrls = <String>[];

    final buttons = document.querySelectorAll('button.dwd-button, button');
    for (var btn in buttons) {
      String? href = btn.attributes['href'];
      if (href == null || href.isEmpty) {
        var parent = btn.parent;
        while (parent != null && parent.localName != 'a') {
          parent = parent.parent;
        }
        href = parent?.attributes['href'];
      }
      if (href != null && href.isNotEmpty && !linkUrls.contains(href)) {
        linkUrls.add(href);
      }
    }

    final directAnchors = document.querySelectorAll('div.entry-content a, p > a, h3 + p a, h4 + p a');
    for (var a in directAnchors) {
      final href = a.attributes['href'];
      final text = a.text;
      if (href != null && href.isNotEmpty) {
        if (href.contains('vcloud') || href.contains('hubcloud') || text.contains('V-Cloud') || text.contains('Download') || text.contains('G-Direct')) {
          if (!linkUrls.contains(href)) {
            linkUrls.add(href);
          }
        }
      }
    }

    // Resolve landing pages in parallel
    final tasks = linkUrls.map((linkUrl) async {
      try {
        final pageRes = await http.get(
          Uri.parse(linkUrl),
          headers: {'User-Agent': ProviderConfig.defaultUserAgent},
        ).timeout(const Duration(seconds: 5));

        if (pageRes.statusCode == 200) {
          final pageDoc = parser.parse(pageRes.body);
          final anchors = pageDoc.querySelectorAll('a');

          for (var a in anchors) {
            final targetHref = a.attributes['href'] ?? '';
            final text = a.text.trim();

            if (targetHref.isNotEmpty &&
                (targetHref.contains('vcloud') ||
                    targetHref.contains('hubcloud') ||
                    text.contains('V-Cloud') ||
                    text.contains('V-Drive') ||
                    text.contains('Download'))) {
              String resLabel = '720p';
              if (text.contains('480p') || linkUrl.contains('480p')) {
                resLabel = '480p';
              } else if (text.contains('1080p') || linkUrl.contains('1080p')) {
                resLabel = '1080p';
              } else if (text.contains('4K') || text.contains('2160p') || linkUrl.contains('2160p') || linkUrl.contains('4K')) {
                resLabel = '2160p 4K';
              }

              synchronizedAddSource(sources, NativeVideoSource(resolution: resLabel, url: targetHref));
            }
          }
        }
      } catch (_) {}
    });

    await Future.wait(tasks);
    return sources;
  }

  void synchronizedAddSource(List<NativeVideoSource> list, NativeVideoSource source) {
    if (!list.any((s) => s.url == source.url)) {
      list.add(source);
    }
  }

  /// Fast targeted episode source loader for a specific season and episode
  Future<List<NativeVideoSource>> loadEpisodeSources(
    String seriesUrl,
    int seasonNumber,
    int episodeNumber,
  ) async {
    final List<NativeVideoSource> sources = [];

    try {
      final res = await http.get(
        Uri.parse(seriesUrl),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) return sources;

      final headings = seriesQualityHeadings(parser.parse(res.body));
      // Single-season pages routinely omit the season marker, so only filter by
      // season when the page actually labels its headings.
      final labelled = headings.any((el) => seasonOfHeading(el) != 0);
      final wanted = (labelled && headings.any((el) => seasonOfHeading(el) == seasonNumber))
          ? headings.where((el) => seasonOfHeading(el) == seasonNumber).toList()
          : headings;

      final linkTasks = <Future<void>>[];

      for (final tag in wanted) {
        final resolution = resolutionOfHeading(tag);
        final eurl = unilinkFor(tag);
        if (eurl == null) continue;

        linkTasks.add(() async {
          try {
            final doc2Res = await http.get(
              Uri.parse(eurl),
              headers: {'User-Agent': ProviderConfig.defaultUserAgent},
            ).timeout(const Duration(seconds: 20));
            if (doc2Res.statusCode != 200) return;

            final links = episodeLinks(parser.parse(doc2Res.body));
            if (episodeNumber > 0 && episodeNumber <= links.length) {
              synchronizedAddSource(
                sources,
                NativeVideoSource(resolution: resolution, url: links[episodeNumber - 1]),
              );
            }
          } catch (_) {}
        }());
      }

      await Future.wait(linkTasks);
    } catch (_) {}

    return sources;
  }

  /// Full series episode map extractor
  Future<List<EpisodeInfo>> _extractAllSeriesEpisodes(dynamic document) async {
    final Map<String, List<NativeVideoSource>> episodesMap = {};
    final headings = seriesQualityHeadings(document);
    final labelled = headings.any((el) => seasonOfHeading(el) != 0);

    final linkTasks = <Future<void>>[];

    for (final tag in headings) {
      final resolution = resolutionOfHeading(tag);
      final realSeason = labelled ? seasonOfHeading(tag) : 1;
      final eurl = unilinkFor(tag);
      if (eurl == null) continue;

      linkTasks.add(() async {
        try {
          final doc2Res = await http.get(
            Uri.parse(eurl),
            headers: {'User-Agent': ProviderConfig.defaultUserAgent},
          ).timeout(const Duration(seconds: 20));
          if (doc2Res.statusCode != 200) return;

          final links = episodeLinks(parser.parse(doc2Res.body));
          for (var i = 0; i < links.length; i++) {
            final existing = episodesMap.putIfAbsent('$realSeason-${i + 1}', () => []);
            if (!existing.any((s) => s.url == links[i])) {
              existing.add(NativeVideoSource(resolution: resolution, url: links[i]));
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(linkTasks);

    final List<EpisodeInfo> episodes = [];
    episodesMap.forEach((key, sources) {
      final parts = key.split('-');
      final s = int.tryParse(parts[0]) ?? 1;
      final e = int.tryParse(parts[1]) ?? 1;
      episodes.add(EpisodeInfo(
        season: s,
        episode: e,
        name: 'Episode $e',
        sources: sources,
      ));
    });

    episodes.sort((a, b) {
      if (a.season != b.season) return a.season.compareTo(b.season);
      return a.episode.compareTo(b.episode);
    });

    return episodes;
  }

  /// Direct parallel stream extractor for movies
  Future<List<StreamLink>> fetchMovieStreams(String movieTitle) async {
    final results = await search(movieTitle);
    if (results.isEmpty) return [];

    final details = await loadDetails(results.first.url);
    if (details == null || details.sources.isEmpty) return [];

    final tasks = details.sources.map((s) => extractStream(s.url));
    final streamBatches = await Future.wait(tasks);
    return streamBatches.expand((x) => x).toList();
  }

  /// Direct parallel stream extractor for a TV series episode
  Future<List<StreamLink>> fetchEpisodeStreams(
    String seriesTitle,
    int seasonNumber,
    int episodeNumber,
  ) async {
    final results = await search(seriesTitle);
    if (results.isEmpty) return [];

    final sources = await loadEpisodeSources(results.first.url, seasonNumber, episodeNumber);
    if (sources.isEmpty) return [];

    final tasks = sources.map((s) => extractStream(s.url));
    final streamBatches = await Future.wait(tasks);
    return streamBatches.expand((x) => x).toList();
  }

  @override
  Future<List<StreamLink>> extractStream(String url) async {
    return await VCloudExtractor.extractVCloudStream(url);
  }

  /// Scans [html] for a bare IMDb title ID (`tt` followed by 7–9 digits) and
  /// returns a full IMDb URL if found, or an empty string otherwise.
  static String _extractImdbUrl(String html) {
    final match = RegExp(r'tt\d{7,9}').firstMatch(html);
    if (match == null) return '';
    return 'https://www.imdb.com/title/${match.group(0)}';
  }
}
