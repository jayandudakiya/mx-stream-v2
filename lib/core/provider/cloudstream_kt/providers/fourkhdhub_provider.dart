import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../cs_domains.dart';
import '../cs_dom.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';
import '../extractors/packed_host_extractor.dart';

/// 4KHDHub — dual-audio and Hindi 1080p/4K, with per-episode links for series.
///
/// Ported from `FourKHDHub.kt` (HindiProviders). Unlike the WordPress index
/// sites this one has real structure, so both movie and series link extraction
/// is a direct read of the markup:
///
/// ```
/// <div class="download-item">…<div class="download-link"><a href="hubcloud…">
/// <div class="episode-item">
///   <div class="episode-number">S01</div>
///   <div class="episode-download-item">
///     <div class="episode-file-title">Show.S01E01.1080p…mkv</div>
///     <span class="badge-psa">Episode-01</span><span class="badge-size">2.44 GB</span>
///     <div class="episode-links"><a href="hubcloud…">…<a href="hubdrive…">
/// ```
///
/// Series pages carry both season packs (in `download-item`) and per-episode
/// files (in `episode-item`); only the latter become episodes, because a pack
/// is one archive rather than something the player can open.
class FourKHdHubProvider implements CsMainApi {
  @override
  Future<String> get mainUrl => CsDomains.resolve('4khdhub');

  @override
  String get providerKey => '4khdhub';

  @override
  String get name => '4KHDHub';

  @override
  String get lang => 'hi';

  @override
  Set<TvType> get supportedTypes => {TvType.movie, TvType.tvSeries, TvType.anime};

  @override
  List<CsMainPageEntry> get mainPage => mainPageOf(const {
        'category/hindi-movies': 'Hindi Movies',
        'category/movies': 'Latest Movies',
        'category/series': 'Latest Series',
        'category/anime': 'Anime',
        'category/2160p-HDR': '4K HDR',
        'category/netflix': 'Netflix',
        'category/amazon_prime_video': 'Amazon Prime',
        'category/jiohotstar': 'JioHotstar',
        'category/english-movies': 'English Movies',
        'category/korean-series': 'Korean Series',
      });

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async {
    final base = await mainUrl;
    final res = await app.get('$base/${request.data}/page/$page', referer: base);
    if (!res.isOk) return const [];
    return _cards(res.document, base);
  }

  @override
  Future<List<CsSearchResponse>> search(String query) async {
    final base = await mainUrl;
    final res = await app.get(
      '$base/?s=${Uri.encodeQueryComponent(query)}',
      referer: base,
    );
    if (!res.isOk) return const [];
    return _cards(res.document, base);
  }

  List<CsSearchResponse> _cards(dom.Document doc, String base) => doc
      .select('div.card-grid a')
      .map((card) {
        final title = card.selectFirst('h3')?.textTrim;
        final href = card.attr('href');
        // Nav chrome sits in the same grid; only item pages have a title.
        if (title == null || title.isEmpty || href.isEmpty) return null;
        if (href.contains('/category/')) return null;

        final formats = card.select('span.movie-card-format').eachText.join(' ');
        return CsSearchResponse(
          name: title,
          url: fixUrl(href, base),
          type: href.contains('-series-') ? TvType.tvSeries : TvType.movie,
          posterUrl: fixUrlNull(card.selectFirst('img')?.imageAttr, base),
          quality: getSearchQuality('$formats $title'),
        );
      })
      .whereType<CsSearchResponse>()
      .toList();

  @override
  Future<CsLoadResponse?> load(String url) async {
    final base = await mainUrl;
    final res = await app.get(url, referer: base);
    if (!res.isOk) return null;
    final doc = res.document;

    final title = doc.selectFirst('h1.page-title')?.textTrim ?? '';
    if (title.isEmpty) return null;

    final poster = fixUrlNull(
      doc.selectFirst('meta[property="og:image"]')?.attr('content'),
      base,
    );
    final tags = doc.select('div.mt-2 span.badge').eachText;
    final episodes = _episodes(doc);
    final isSeries = episodes.isNotEmpty || url.contains('-series-');

    return CsLoadResponse(
      name: title,
      url: url,
      type: isSeries ? TvType.tvSeries : TvType.movie,
      dataUrl: jsonEncode(_movieLinks(doc)),
      episodes: episodes,
      posterUrl: poster,
      backgroundPosterUrl: poster,
      plot: doc.selectFirst('div.content-section p.mt-4')?.textTrim,
      year: int.tryParse(
        RegExp(r'\((\d{4})\)').firstMatch(title)?.group(1) ??
            RegExp(r'\b(19|20)\d{2}\b').firstMatch(title)?.group(0) ??
            '',
      ),
      tags: tags,
      trailerUrl: doc.selectFirst('#trailer-btn')?.attr('data-trailer-url'),
    );
  }

  List<Map<String, String>> _movieLinks(dom.Document doc) {
    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final item in doc.select('div.download-item')) {
      final label = item.selectFirst('div.episode-number')?.textTrim ??
          item.selectFirst('div.download-file-title')?.textTrim ??
          '';
      for (final a in item.select('a')) {
        final href = a.attr('href');
        if (!href.startsWith('http') || !seen.add(href)) continue;
        out.add({'label': label, 'url': href});
      }
    }
    return out;
  }

  static final RegExp _episodeBadge =
      RegExp(r'Episode[-\s]?(\d+)', caseSensitive: false);
  static final RegExp _seasonLabel = RegExp(r'S(\d{1,2})', caseSensitive: false);

  List<CsEpisode> _episodes(dom.Document doc) {
    final grouped = <String, List<Map<String, String>>>{};
    final titles = <String, String>{};

    for (final block in doc.select('div.episode-item')) {
      final season = int.tryParse(
            _seasonLabel
                    .firstMatch(block.selectFirst('div.episode-number')?.textTrim ?? '')
                    ?.group(1) ??
                '',
          ) ??
          1;

      for (final item in block.select('div.episode-download-item')) {
        final fileTitle = item.selectFirst('div.episode-file-title')?.textTrim ?? '';
        final badge = item.selectFirst('span.badge-psa')?.textTrim ?? '';
        final size = item.selectFirst('span.badge-size')?.textTrim ?? '';
        final episode = int.tryParse(_episodeBadge.firstMatch(badge)?.group(1) ?? '') ??
            int.tryParse(
              RegExp(r'S\d{1,2}E(\d{1,3})', caseSensitive: false)
                      .firstMatch(fileTitle)
                      ?.group(1) ??
                  '',
            );
        // A `download-item` inside a season block with no episode badge is the
        // season pack, which belongs to no episode.
        if (episode == null) continue;

        final key = '$season-$episode';
        titles.putIfAbsent(key, () => fileTitle);
        for (final a in item.select('div.episode-links a')) {
          final href = a.attr('href');
          if (!href.startsWith('http')) continue;
          grouped.putIfAbsent(key, () => []).add({
            'label': [fileTitle, size].where((s) => s.isNotEmpty).join(' · '),
            'url': href,
          });
        }
      }
    }

    final out = <CsEpisode>[];
    grouped.forEach((key, links) {
      final parts = key.split('-');
      final episode = int.tryParse(parts[1]) ?? 1;
      out.add(
        CsEpisode(
          data: jsonEncode(links),
          name: 'Episode $episode',
          season: int.tryParse(parts[0]) ?? 1,
          episode: episode,
        ),
      );
    });
    out.sort((a, b) => (a.season ?? 1) != (b.season ?? 1)
        ? (a.season ?? 1).compareTo(b.season ?? 1)
        : (a.episode ?? 1).compareTo(b.episode ?? 1));
    return out;
  }

  @override
  Future<CsLinkResult> loadLinks(String data) async {
    List<Map<String, dynamic>> entries;
    try {
      final decoded = jsonDecode(data);
      entries = decoded is List
          ? decoded.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
          : [
              {'label': '', 'url': data},
            ];
    } catch (_) {
      entries = [
        {'label': '', 'url': data},
      ];
    }
    if (entries.isEmpty) return CsLinkResult.empty;

    final base = await mainUrl;
    final batches = await amap<Map<String, dynamic>, CsLinkResult>(
      entries,
      (e) async {
        final url = (e['url'] ?? '').toString();
        if (url.isEmpty) return CsLinkResult.empty;
        try {
          return await resolveEmbed(url, referer: base);
        } catch (_) {
          return CsLinkResult.empty;
        }
      },
      concurrency: 4,
    );

    var out = CsLinkResult.empty;
    for (final b in batches) {
      out = out + b;
    }
    return out;
  }
}
