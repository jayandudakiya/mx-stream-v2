import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'internal/native_base_provider.dart';
import 'internal/native_models.dart';
import 'internal/series_page_parser.dart';
import 'internal/title_normalizer.dart';
import 'provider_config.dart';
import 'extractors/vcloud_extractor.dart';

/// Bollywood / desi OTT native scraper — same architecture as
/// [VegaMoviesProvider], ported verbatim from MXStream's
/// `functions/fetchers/providers/RogMovies/rogmovies_provider.dart`.
class RogMoviesProvider implements NativeBaseProvider {
  @override
  String get name => 'RogMovies';

  @override
  String get lang => 'hi';

  Future<String> _getBaseUrl() async {
    return await ProviderConfig.resolveBaseUrl('rogmovies');
  }

  @override
  Future<List<ProviderSearchItem>> getMainPage({String category = 'home', int page = 1}) async {
    final baseUrl = await _getBaseUrl();

    // Verified URL patterns from RogMovies website
    final routes = {
      'home': '/page/$page/',
      'latest': '/page/$page/',
      'bollywood': '/category/bollywood/page/$page/',
      'hindi': '/category/bollywood/page/$page/',
      'regional': '/category/regional/page/$page/',
      'netflix': '/category/web-series/netflix/page/$page/',
      'prime': '/category/web-series/amazon-prime-video/page/$page/',
      'hotstar': '/category/web-series/disney-plus-hotstar/page/$page/',
      'jiohotstar': '/category/web-series/disney-plus-hotstar/page/$page/',
      'sony': '/category/web-series/sonyliv/page/$page/',
      'zee5': '/category/web-series/zee5/page/$page/',
      'minitv': '/category/web-series/amazon-minitv/page/$page/',
      'altbalaji': '/category/web-series/altbalaji/page/$page/',
      'mxoriginal': '/category/web-series/mx-original/page/$page/',
    };

    final lowerCat = category.toLowerCase().trim();
    final targetUrl = '$baseUrl${routes[lowerCat] ?? routes['home']}';

    try {
      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {'User-Agent': ProviderConfig.defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final document = parser.parse(response.body);
      final results = <ProviderSearchItem>[];

      // RogMovies uses same structure as VegaMovies: div.movies-grid > a
      final gridLinks = document.querySelectorAll('div.movies-grid > a');

      if (gridLinks.isNotEmpty) {
        for (var el in gridLinks) {
          var href = el.attributes['href'] ?? '';
          final img = el.querySelector('img');
          var rawTitle = img?.attributes['alt'] ?? '';
          var title = rawTitle.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '').trim();
          var poster = img?.attributes['src'] ?? '';
          if (!poster.contains('https:')) poster = img?.attributes['data-src'] ?? poster;

          if (!href.startsWith('http') && href.isNotEmpty) href = '$baseUrl$href';

          if (title.isNotEmpty && href.isNotEmpty) {
            final isSeries = TitleNormalizer.looksLikeSeriesItem(title, href);
            results.add(ProviderSearchItem(
              title: title,
              url: href,
              poster: poster,
              type: isSeries ? 'series' : 'movie',
            ));
          }
        }
        return results;
      }

      // Fallback: WordPress article layout
      final articles = document.querySelectorAll('article.post, div.blog-item, div.post-item, .hsl-slide');

      for (var article in articles) {
        final aTag = article.querySelector('a');
        final imgTag = article.querySelector('img');
        final titleTag = article.querySelector('.entry-title, h2, h3, .hsl-title a, a');

        var href = aTag?.attributes['href'] ?? '';
        var title = titleTag?.text.trim() ?? aTag?.attributes['title'] ?? '';
        title = title.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '').trim();
        var poster = imgTag?.attributes['src'] ?? imgTag?.attributes['data-src'] ?? '';

        if (!href.startsWith('http') && href.isNotEmpty) {
          href = '$baseUrl$href';
        }

        if (title.isNotEmpty && href.isNotEmpty) {
          final isSeries = TitleNormalizer.looksLikeSeriesItem(title, href);
          results.add(ProviderSearchItem(
            title: title,
            url: href,
            poster: poster,
            type: isSeries ? 'series' : 'movie',
          ));
        }
      }
      return results;
    } catch (_) {
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

    // 1. Try search.php JSON endpoint (same as VegaMovies)
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

    // 2. Try HTML WordPress search endpoint
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
      // original — where RogmoviesProvider inherits load() from VegaMovies and
      // so uses exactly the same check. Only when the page has no heading we
      // recognise do we fall back to reading the release title.
      final isSeries = pageDeclaresSeries(document) ??
          (title.toLowerCase().contains('season') ||
              title.toLowerCase().contains('series') ||
              url.toLowerCase().contains('season'));

      final img = document.querySelector('div.entry-content img, article img');
      final poster = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';

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

  /// Extract movie download sources (same pattern as VegaMovies)
  Future<List<NativeVideoSource>> _extractMovieSources(dynamic document) async {
    final List<NativeVideoSource> sources = [];
    final linkUrls = <String>[];

    // Find buttons/anchors pointing to VCloud/HubCloud
    final directAnchors = document.querySelectorAll('div.entry-content a, p > a, h3 + p a, h4 + p a');
    for (var a in directAnchors) {
      final href = a.attributes['href'];
      final text = a.text;
      if (href != null && href.isNotEmpty) {
        if (href.contains('vcloud') ||
            href.contains('hubcloud') ||
            text.contains('V-Cloud') ||
            text.contains('Download') ||
            text.contains('G-Direct') ||
            text.contains('V-Drive')) {
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
              } else if (text.contains('4K') ||
                  text.contains('2160p') ||
                  linkUrl.contains('2160p') ||
                  linkUrl.contains('4K')) {
                resLabel = '2160p 4K';
              }
              sources.add(NativeVideoSource(resolution: resLabel, url: targetHref));
            }
          }
        }
      } catch (_) {}
    });

    await Future.wait(tasks);
    return sources;
  }

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
      episodes.add(EpisodeInfo(season: s, episode: e, name: 'Episode $e', sources: sources));
    });

    episodes.sort((a, b) {
      if (a.season != b.season) return a.season.compareTo(b.season);
      return a.episode.compareTo(b.episode);
    });

    return episodes;
  }

  static final RegExp _episodeRangeRegex =
      RegExp(r'Episodes?\s*(\d+)\s*(?:-|–|to)\s*(\d+)', caseSensitive: false);
  static final RegExp _singleEpisodeRegex =
      RegExp(r'Episodes?\s*0*(\d+)\b', caseSensitive: false);

  /// Download pages under a quality heading that could contain [episodeNumber],
  /// each paired with the episode its first link corresponds to. RogMovies
  /// splits long seasons across "Episode 01-08" style buttons, so the offset
  /// matters when indexing into the page's links.
  List<({String url, int startEpisode})> _episodeTargets(
    dom.Element tag,
    int episodeNumber,
  ) {
    final targets = <({String url, int startEpisode})>[];
    var sawEpisodeMarker = false;

    for (final a in headingAnchors(tag)) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final text = a.text.trim();
      final lower = text.toLowerCase();
      if (lower.contains('zip') || lower.contains('batch')) continue;

      final range = _episodeRangeRegex.firstMatch(text);
      if (range != null) {
        sawEpisodeMarker = true;
        final start = int.tryParse(range.group(1)!) ?? 1;
        final end = int.tryParse(range.group(2)!) ?? 1;
        if (episodeNumber >= start && episodeNumber <= end) {
          targets.add((url: href, startEpisode: start));
        }
        continue;
      }

      final single = _singleEpisodeRegex.firstMatch(text);
      if (single != null) {
        sawEpisodeMarker = true;
        if ((int.tryParse(single.group(1)!) ?? 0) == episodeNumber) {
          targets.add((url: href, startEpisode: episodeNumber));
        }
      }
    }

    if (targets.isEmpty && !sawEpisodeMarker) {
      final fallback = unilinkFor(tag);
      if (fallback != null) targets.add((url: fallback, startEpisode: 1));
    }
    return targets;
  }

  /// Load sources for a specific episode (used by TV detail page)
  Future<List<NativeVideoSource>> loadEpisodeSources(String url, int seasonNumber, int episodeNumber) async {
    final sources = <NativeVideoSource>[];
    try {
      final res = await http.get(
        Uri.parse(url),
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

      final tasks = <Future<void>>[];

      for (final tag in wanted) {
        final resolution = resolutionOfHeading(tag);

        for (final target in _episodeTargets(tag, episodeNumber)) {
          tasks.add(() async {
            try {
              final doc2Res = await http.get(
                Uri.parse(target.url),
                headers: {'User-Agent': ProviderConfig.defaultUserAgent},
              ).timeout(const Duration(seconds: 20));
              if (doc2Res.statusCode != 200) return;

              final links = episodeLinks(parser.parse(doc2Res.body));
              final index = episodeNumber - target.startEpisode;
              if (index >= 0 && index < links.length) {
                final href = links[index];
                if (!sources.any((s) => s.url == href)) {
                  sources.add(NativeVideoSource(resolution: resolution, url: href));
                }
              }
            } catch (_) {}
          }());
        }
      }

      await Future.wait(tasks);
    } catch (_) {}
    return sources;
  }

  /// Direct parallel stream extractor for a TV series episode
  Future<List<StreamLink>> fetchEpisodeStreams(
    String seriesTitle,
    int seasonNumber,
    int episodeNumber, {
    String? seriesUrl,
  }) async {
    String? targetUrl = seriesUrl;
    if (targetUrl == null || targetUrl.isEmpty) {
      final results = await search(seriesTitle);
      if (results.isEmpty) return [];
      targetUrl = results.first.url;
    }

    final sources = await loadEpisodeSources(targetUrl, seasonNumber, episodeNumber);
    if (sources.isEmpty) return [];

    final tasks = sources.map((s) => extractStream(s.url));
    final streamBatches = await Future.wait(tasks);
    return streamBatches.expand((x) => x).toList();
  }

  /// Fetch all stream links for a movie by title
  Future<List<StreamLink>> fetchMovieStreams(String movieTitle) async {
    final results = await search(movieTitle);
    if (results.isEmpty) return [];

    final details = await loadDetails(results.first.url);
    if (details == null || details.sources.isEmpty) return [];

    final tasks = details.sources.map((s) => extractStream(s.url));
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
