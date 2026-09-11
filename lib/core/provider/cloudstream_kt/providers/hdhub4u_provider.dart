import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../cs_domains.dart';
import '../cs_dom.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_spec.dart';
import '../cs_types.dart';
import '../cs_utils.dart';
import '../extractors/packed_host_extractor.dart';

/// HDHub4u — Bollywood, Hindi-dubbed Hollywood and South Indian, plus web
/// series.
///
/// Ported from `HDhub4uProvider.kt` (HindiProviders). Three things about the
/// live site that the Kotlin does not say and that cost the provider entirely
/// if missed:
///
///  * **Search is a stale index.** `search.pingora.fyi` answers correctly but
///    its `permalink` values still name a domain retired months ago
///    (`new1.hdhub4u.af`, which no longer resolves). Only the path is usable —
///    the host is replaced with the live one via [CsDomains.rehost].
///  * **`xla=s4t` is required.** Without that cookie the site serves an
///    interstitial instead of the page.
///  * **Season packs are `.zip`.** A season page that offers only pack links
///    yields no episodes rather than one fake episode that fails at the player;
///    per-episode pages (an `EPiSODE N` heading followed by one `<h4>` of links
///    per quality) are parsed properly.
class HdHub4uProvider extends CsSpecApi {
  HdHub4uProvider({CsSourceSpec? spec}) : super(spec ?? _default);

  static const CsSourceSpec _default = CsSourceSpec(
    engineId: CsEngineId.hdhub4u,
    key: 'hdhub4u',
    name: 'HDHub4u',
  );

  @override
  Set<TvType> get supportedTypes => {TvType.movie, TvType.tvSeries, TvType.anime};

  static const Map<String, String> _headers = {
    'Cookie': 'xla=s4t',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
  };

  static const String _searchApi =
      'https://search.pingora.fyi/collections/post/documents/search';

  @override
  List<CsMainPageEntry> get builtInMainPage => mainPageOf(const {
        '': 'Latest',
        'category/hindi-dubbed/': 'Hindi Dubbed',
        'category/bollywood-movies/': 'Bollywood',
        'category/south-hindi-movies/': 'South (Hindi Dubbed)',
        'category/hollywood-movies/': 'Hollywood',
        'category/web-series/': 'Web Series',
      });

  /// A clone site keeps the theme but rarely the exact category slugs, so a
  /// user-added source gets only the rows that are part of the layout itself.
  @override
  List<CsMainPageEntry> get familyMainPage => mainPageOf(const {
        '': 'Latest',
        'category/bollywood-movies/': 'Bollywood',
        'category/hollywood-movies/': 'Hollywood',
        'category/web-series/': 'Web Series',
      });

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async {
    final base = await mainUrl;
    final res = await app.get(
      '$base/${request.data}page/$page/',
      headers: _headers,
      referer: base,
    );
    if (!res.isOk) return const [];
    return _parseListing(res.document, base);
  }

  /// The archive/search markup, shared by [getMainPage] and [_searchOnSite].
  List<CsSearchResponse> _parseListing(dom.Document doc, String base) => doc
      .select('.recent-movies > li.thumb')
      .map((post) {
        final raw = post.selectFirst('figcaption a p')?.textTrim ??
            post.selectFirst('figcaption')?.textTrim ??
            '';
        final href = post.select('figure a').eachAttr('href').firstOrNull ?? '';
        if (raw.isEmpty || href.isEmpty) return null;
        return CsSearchResponse(
          name: raw,
          url: fixUrl(href, base),
          type: _looksLikeSeries(raw) ? TvType.tvSeries : TvType.movie,
          posterUrl: fixUrlNull(post.selectFirst('figure img')?.imageAttr, base),
          quality: getSearchQuality(raw),
        );
      })
      .whereType<CsSearchResponse>()
      .toList();

  @override
  Future<List<CsSearchResponse>> search(String query) async {
    // The hosted index below is hdhub4u's OWN catalogue. A clone added as a
    // custom source is not in it, and querying it anyway would show the real
    // site's results — with links into the real site — under the custom
    // source's name. So a custom source only ever searches its own site.
    if (!spec.isCustom) {
      final viaIndex = await _searchIndex(query);
      if (viaIndex.isNotEmpty) return viaIndex;
    }
    return _searchOnSite(query);
  }

  /// WordPress' own `?s=` search. Slower and fuzzier than the index, but it is
  /// the only thing that works for a clone — and the fallback for when the
  /// index is down.
  Future<List<CsSearchResponse>> _searchOnSite(String query) async {
    final base = await mainUrl;
    final res = await app.get(
      '$base/?s=${Uri.encodeQueryComponent(query)}',
      headers: _headers,
      referer: base,
    );
    if (!res.isOk) return const [];
    return _parseListing(res.document, base);
  }

  Future<List<CsSearchResponse>> _searchIndex(String query) async {
    final res = await app.get(
      _searchApi,
      params: {
        'q': query,
        'query_by': 'post_title,category',
        'query_by_weights': '4,2',
        'sort_by': 'sort_by_date:desc',
        'limit': '20',
        'highlight_fields': 'none',
        'use_cache': 'true',
        'page': '1',
      },
      headers: _headers,
      referer: await mainUrl,
    );
    if (!res.isOk) return const [];

    final hits = res.jsonMap['hits'];
    if (hits is! List) return const [];

    final out = <CsSearchResponse>[];
    for (final hit in hits) {
      if (hit is! Map) continue;
      final doc = hit['document'];
      if (doc is! Map) continue;
      final title = (doc['post_title'] ?? '').toString();
      final permalink = (doc['permalink'] ?? '').toString();
      if (title.isEmpty || permalink.isEmpty) continue;

      out.add(
        CsSearchResponse(
          name: title,
          // The index's host is stale; only its path is trustworthy.
          url: await CsDomains.rehost(permalink, providerKey),
          type: _looksLikeSeries(title) ? TvType.tvSeries : TvType.movie,
          posterUrl: (doc['post_thumbnail'] ?? '').toString().isEmpty
              ? null
              : doc['post_thumbnail'].toString(),
          quality: getSearchQuality(title),
        ),
      );
    }
    return out;
  }

  static bool _looksLikeSeries(String title) => RegExp(
        r'\bseason\b|\bS\d{1,2}\b|\bepisodes?\b|web[- ]series',
        caseSensitive: false,
      ).hasMatch(title);

  @override
  Future<CsLoadResponse?> load(String url) async {
    final base = await mainUrl;
    final res = await app.get(url, headers: _headers, referer: base);
    if (!res.isOk) return null;
    final doc = res.document;

    final title = doc.selectFirst('h1.page-title')?.textTrim ??
        doc.selectFirst('meta[property="og:title"]')?.attr('content') ??
        '';
    if (title.isEmpty) return null;

    final poster = fixUrlNull(
          doc.selectFirst('main.page-body img.aligncenter')?.imageAttr,
          base,
        ) ??
        fixUrlNull(doc.selectFirst('meta[property="og:image"]')?.attr('content'), base);
    final tags = doc.select('.page-meta em').eachText;
    final imdbUrl = doc
        .select('a')
        .map((a) => a.attr('href'))
        .where((h) => h.contains('imdb.com/title/'))
        .firstOrNull;
    final imdbId = imdbUrl == null
        ? null
        : RegExp(r'tt\d{7,9}').firstMatch(imdbUrl)?.group(0);
    final seasonNumber = int.tryParse(
      RegExp(r'Season\s*(\d+)', caseSensitive: false).firstMatch(title)?.group(1) ?? '',
    );

    final episodes = _episodes(doc, seasonNumber ?? 1);
    final isSeries = episodes.isNotEmpty || _looksLikeSeries(title);

    return CsLoadResponse(
      name: title,
      url: url,
      type: isSeries ? TvType.tvSeries : TvType.movie,
      dataUrl: jsonEncode(_movieLinks(doc)),
      episodes: episodes,
      posterUrl: poster,
      backgroundPosterUrl: poster,
      plot: doc.selectFirst('.kno-rdesc span')?.textTrim,
      year: int.tryParse(
        RegExp(r'\((\d{4})\)').firstMatch(title)?.group(1) ?? '',
      ),
      tags: tags,
      imdbId: imdbId,
    );
  }

  /// Hosts that actually serve a file. Anything else on these pages is a
  /// cross-promo link to a sister site, and following those turns one movie
  /// into a directory listing of somebody else's catalogue.
  static final RegExp _fileHost =
      RegExp(r'hubcloud|hubdrive|hubcdn|hdstream4u|hubstream|hblinks|gofile|pixeldrain');

  /// Gate hosts whose `?id=` payload has to be unwrapped before the real link
  /// appears. The host name rotates, so the `?id=` shape is the test.
  static bool _isGate(String url) => url.contains('?id=');

  List<Map<String, String>> _movieLinks(dom.Document doc) {
    final out = <Map<String, String>>[];
    final seen = <String>{};
    for (final heading in doc.select('h3, h4, h5')) {
      final label = heading.textTrim;
      if (!RegExp(r'480|720|1080|2160|4K', caseSensitive: false).hasMatch(label)) {
        continue;
      }
      for (final a in heading.select('a')) {
        final href = a.attr('href');
        if (href.isEmpty || !href.startsWith('http')) continue;
        if (!_fileHost.hasMatch(href) && !_isGate(href)) continue;
        if (!seen.add(href)) continue;
        out.add({'label': label, 'url': href});
      }
    }
    return out;
  }

  /// A per-episode page reads:
  /// ```
  /// <h4>EPiSODE 1</h4>
  /// <h4>720p – <a>Drive</a> | <a>Instant</a> | <a>WATCH</a></h4>
  /// <h4>1080p – <a>Drive</a> | <a>Instant</a></h4>
  /// <hr>
  /// ```
  /// so an episode owns every following heading until the next episode
  /// heading. Season-pack-only pages have no such headings and yield nothing —
  /// their links are `.zip` archives, which are not playable.
  List<CsEpisode> _episodes(dom.Document doc, int season) {
    final headings = doc.select('h2, h3, h4, h5');
    final byEpisode = <int, List<Map<String, String>>>{};

    int? episodeNumberOf(dom.Element el) {
      // Only a heading that is JUST a label — a heading carrying links is a
      // quality row belonging to the episode above it.
      if (el.select('a').isNotEmpty) return null;
      final text = el.textTrim;
      final m = RegExp(r'\bEPi?SODE\s*[-–]?\s*(\d+)', caseSensitive: false).firstMatch(text) ??
          RegExp(r'\bEP\s*[-–]?\s*(\d+)', caseSensitive: false).firstMatch(text);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    for (var i = 0; i < headings.length; i++) {
      final ep = episodeNumberOf(headings[i]);
      if (ep == null) continue;

      for (var j = i + 1; j < headings.length; j++) {
        if (episodeNumberOf(headings[j]) != null) break;
        final label = headings[j].textTrim;
        for (final a in headings[j].select('a')) {
          final href = a.attr('href');
          if (href.isEmpty || !href.startsWith('http')) continue;
          if (!_fileHost.hasMatch(href) && !_isGate(href)) continue;
          byEpisode.putIfAbsent(ep, () => []).add({
            'label': '$label ${a.textTrim}'.trim(),
            'url': href,
          });
        }
      }
    }

    final out = byEpisode.entries
        .map(
          (e) => CsEpisode(
            data: jsonEncode(e.value),
            name: 'Episode ${e.key}',
            season: season,
            episode: e.key,
          ),
        )
        .toList();
    out.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
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

    final batches = await amap<Map<String, dynamic>, CsLinkResult>(
      entries,
      (e) async {
        final url = (e['url'] ?? '').toString();
        if (url.isEmpty) return CsLinkResult.empty;
        try {
          final target = _isGate(url) ? await unwrapGate(url) : url;
          if (target == null || target.isEmpty) return CsLinkResult.empty;
          // The gate often lands on an hblinks index rather than a file page.
          if (target.contains('hblinks')) return _fromHbLinks(target);
          return await resolveEmbed(target, referer: await mainUrl);
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

  /// An hblinks page is a menu of lockers for one file — resolve them all so a
  /// dead HubCloud still leaves HubCdn and HubDrive on the sheet.
  Future<CsLinkResult> _fromHbLinks(String url) async {
    final res = await app.get(url, headers: _headers);
    if (!res.isOk) return CsLinkResult.empty;
    final links = res.document
        .select('a')
        .map((a) => a.attr('href'))
        .where((h) => h.startsWith('http') && _fileHost.hasMatch(h))
        .toSet()
        .toList();
    final batches = await amap<String, CsLinkResult>(
      links,
      (l) => resolveEmbed(l, referer: url),
      concurrency: 4,
    );
    var out = CsLinkResult.empty;
    for (final b in batches) {
      out = out + b;
    }
    return out;
  }
}

/// HDHub4u's `?id=` gate, ported from the Kotlin `getRedirectLinks`.
///
/// The page hides its payload in `s('o','…')` / `ck('_wp_http_N','…')` calls;
/// concatenating those and running base64 → base64 → ROT13 → base64 yields a
/// JSON object whose `o` field is the real destination. Some variants leave `o`
/// empty and instead expect a round-trip through `blog_url?re=<data>`.
///
/// Kotlin calls the ROT13 step `pen()` and, confusingly, names its base64
/// *decode* helper `encode()` — both are decodes here.
Future<String?> unwrapGate(String url) async {
  try {
    final res = await app.get(url, headers: HdHub4uProvider._headers);
    if (!res.isOk) return null;

    final combined = StringBuffer();
    final pattern = RegExp(r"""s\('o','([A-Za-z0-9+/=]+)'|ck\('_wp_http_\d+','([^']+)'""");
    for (final m in pattern.allMatches(res.text)) {
      combined.write(m.group(1) ?? m.group(2) ?? '');
    }
    if (combined.isEmpty) return null;

    final decoded = csBase64Decode(
      rot13(csBase64Decode(csBase64Decode(combined.toString()))),
    );
    if (decoded.isEmpty) return null;

    final json = jsonDecode(decoded);
    if (json is! Map) return null;

    final direct = csBase64Decode((json['o'] ?? '').toString()).trim();
    if (direct.startsWith('http')) return direct;

    final blogUrl = (json['blog_url'] ?? '').toString().trim();
    final payload = csBase64Decode((json['data'] ?? '').toString()).trim();
    if (blogUrl.isEmpty || payload.isEmpty) return null;

    final second = await app.get('$blogUrl?re=$payload', headers: HdHub4uProvider._headers);
    final body = second.document.selectFirst('body')?.textTrim ?? '';
    return body.startsWith('http') ? body : null;
  } catch (_) {
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
