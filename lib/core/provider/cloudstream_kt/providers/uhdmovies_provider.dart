import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../cs_domains.dart';
import '../cs_dom.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';
import '../extractors/driveseed_extractor.dart';
import '../extractors/packed_host_extractor.dart';

/// UHDMovies — dual-audio (Hindi + English) 1080p and 4K.
///
/// Ported from `UHDmoviesProvider.kt` (HindiProviders). The listing and detail
/// scraping is a direct transcription; the link extraction is not, and here is
/// why.
///
/// Kotlin selects episode links with `p:has(a:contains(Episode))` — Jsoup
/// selectors Dart's CSS engine does not implement. Rather than approximate
/// them, this walks `div.entry-content` in document order and carries the most
/// recent `<pre>`/`<p>` text as the quality context for the buttons beneath it,
/// which is how the page is actually laid out:
///
/// ```
/// <pre>2160p Web-DL</pre>
/// <p>Show.Name.S01.2160p.WEB-DL[Hindi + English] [7.5GB/E]</p>
/// <p><a class="maxbutton…">Episode 1</a> <a …>Episode 2</a> … <a …>Zip / Pack</a></p>
/// ```
///
/// Zip/Pack buttons are dropped: they resolve to a `.zip` of the season, which
/// cannot be streamed and would otherwise appear as a playable source that
/// fails at the player.
class UhdMoviesProvider implements CsMainApi {
  @override
  Future<String> get mainUrl => CsDomains.resolve('uhdmovies');

  @override
  String get providerKey => 'uhdmovies';

  @override
  String get name => 'UHDMovies';

  @override
  String get lang => 'hi';

  @override
  Set<TvType> get supportedTypes => {TvType.movie, TvType.tvSeries};

  @override
  List<CsMainPageEntry> get mainPage => mainPageOf(const {
        '': 'Latest',
        'movies/dual-audio-movies/': 'Dual Audio (Hindi)',
        'movies/': 'Movies',
        'tv-shows/': 'TV Shows',
        'web-series/': 'Web Series',
        'tv-shows/netflix/': 'Netflix',
        'amazon-prime/': 'Amazon Prime',
        'movies/collection-movies/': 'Collections',
      });

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async {
    final base = await mainUrl;
    final url = page == 1 ? '$base/${request.data}' : '$base/${request.data}page/$page/';
    final res = await app.get(url, referer: base);
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
      .select('article.gridlove-post')
      .map((article) {
        final raw = (article.selectFirst('h1.sanket') ??
                article.selectFirst('h1') ??
                article.selectFirst('h2'))
            ?.textTrim;
        if (raw == null || raw.isEmpty) return null;
        final title = raw.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '');
        final href = fixUrl(
          article.selectFirst('div.entry-image > a')?.attr('href') ??
              article.selectFirst('a')?.attr('href') ??
              '',
          base,
        );
        if (href.isEmpty) return null;

        return CsSearchResponse(
          name: title,
          url: href,
          type: _looksLikeSeries(title) ? TvType.tvSeries : TvType.movie,
          posterUrl: fixUrlNull(article.selectFirst('img')?.imageAttr, base),
          quality: getSearchQuality(title),
        );
      })
      .whereType<CsSearchResponse>()
      .toList();

  static bool _looksLikeSeries(String title) =>
      RegExp(r'\bseason\b|\bS\d{1,2}\b|\bepisode\b', caseSensitive: false)
          .hasMatch(title);

  @override
  Future<CsLoadResponse?> load(String url) async {
    final base = await mainUrl;
    final res = await app.get(url, referer: base);
    if (!res.isOk) return null;
    final doc = res.document;

    final rawTitle = (doc.selectFirst('h1.entry-title') ?? doc.selectFirst('h1'))
            ?.textTrim
            .replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '') ??
        '';
    if (rawTitle.isEmpty) return null;

    final poster = fixUrlNull(
          doc.selectFirst('div.entry-content p img')?.imageAttr,
          base,
        ) ??
        fixUrlNull(doc.selectFirst('meta[property="og:image"]')?.attr('content'), base);
    final year = int.tryParse(
      RegExp(r'\((\d{4})\)').firstMatch(rawTitle)?.group(1) ?? '',
    );
    final tags = doc.select('div.entry-category > a.gridlove-cat').eachText;
    final imdb = RegExp(r'tt\d{7,9}').firstMatch(res.text)?.group(0);

    final buttons = _buttons(doc);
    final episodes = _episodesFrom(buttons);
    final isSeries = episodes.isNotEmpty || _looksLikeSeries(rawTitle);

    // Movie payload: every quality button on the page, as a JSON list of
    // `{label, url}` — `loadLinks` resolves them in parallel so each quality
    // becomes its own row.
    final movieLinks = buttons
        .where((b) => b.episode == null && !b.isPack)
        .map((b) => {'label': b.label, 'url': b.href})
        .toList();

    return CsLoadResponse(
      name: rawTitle,
      url: url,
      type: isSeries ? TvType.tvSeries : TvType.movie,
      dataUrl: jsonEncode(movieLinks),
      episodes: episodes,
      posterUrl: poster,
      backgroundPosterUrl: poster,
      plot: doc.selectFirst('div.entry-content p')?.textTrim,
      year: year,
      tags: tags,
      imdbId: imdb,
    );
  }

  /// One download button, with the quality heading that was above it.
  ///
  /// [episode] is null on a movie page; [isPack] marks the season `.zip`.
  static ({String label, String href, int? season, int? episode, bool isPack})
      _button(String label, String href, int? season, int? episode, bool isPack) =>
          (label: label, href: href, season: season, episode: episode, isPack: isPack);

  List<({String label, String href, int? season, int? episode, bool isPack})>
      _buttons(dom.Document doc) {
    final out = <({String label, String href, int? season, int? episode, bool isPack})>[];
    final content = doc.selectFirst('div.entry-content');
    if (content == null) return out;

    // Walk in document order, remembering the last non-link text as context.
    var context = '';
    void visit(dom.Element el) {
      final tag = el.localName;
      if (tag == 'a') {
        final cls = el.attr('class');
        if (!cls.contains('maxbutton')) return;
        final href = el.attr('href');
        if (href.isEmpty || !href.startsWith('http')) return;

        final text = el.textTrim;
        final isPack = RegExp(r'zip|pack|batch', caseSensitive: false).hasMatch(text) ||
            RegExp(r'zip', caseSensitive: false).hasMatch(el.attr('title'));
        final ep = int.tryParse(
          RegExp(r'Episode\s*(\d+)', caseSensitive: false).firstMatch(text)?.group(1) ??
              RegExp(r'\bEP[-\s]?(\d+)', caseSensitive: false).firstMatch(text)?.group(1) ??
              '',
        );
        final season = int.tryParse(
          RegExp(r'Season\s*(\d+)', caseSensitive: false).firstMatch(context)?.group(1) ??
              RegExp(r'\bS(\d{1,2})\b').firstMatch(context)?.group(1) ??
              '',
        );
        out.add(_button(context.trim(), href, season, ep, isPack));
        return;
      }

      if (tag == 'pre' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
        final t = el.textTrim;
        if (t.isNotEmpty) context = t;
      } else if (tag == 'p' && el.select('a').isEmpty) {
        final t = el.textTrim;
        // The release line under the quality heading names the audio and size;
        // both belong on the source row, so they are appended, not replaced.
        if (t.isNotEmpty) context = context.isEmpty ? t : '$context — $t';
      }
      for (final child in el.children) {
        visit(child);
      }
    }

    for (final child in content.children) {
      visit(child);
    }
    return out;
  }

  List<CsEpisode> _episodesFrom(
    List<({String label, String href, int? season, int? episode, bool isPack})> buttons,
  ) {
    // (season, episode) → the same episode at every quality the page offers.
    final grouped = <String, List<Map<String, String>>>{};
    for (final b in buttons) {
      if (b.episode == null || b.isPack) continue;
      final key = '${b.season ?? 1}-${b.episode}';
      grouped.putIfAbsent(key, () => []).add({'label': b.label, 'url': b.href});
    }

    final out = <CsEpisode>[];
    grouped.forEach((key, links) {
      final parts = key.split('-');
      out.add(
        CsEpisode(
          data: jsonEncode(links),
          name: 'Episode ${parts[1]}',
          season: int.tryParse(parts[0]) ?? 1,
          episode: int.tryParse(parts[1]) ?? 1,
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
      if (decoded is! List) return CsLinkResult.empty;
      entries = decoded.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    } catch (_) {
      // A bare URL — the shape `load` used before this provider packed a list.
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
          // Every button on this site is behind the hrefli gate; anything else
          // is passed straight to the registry.
          final target = _isGated(url) ? await bypassHrefli(url) : url;
          if (target == null || target.isEmpty) return CsLinkResult.empty;
          final result = await resolveEmbed(target);
          return _relabel(result, (e['label'] ?? '').toString());
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

  static bool _isGated(String url) =>
      url.contains('unblockedgames') || url.contains('hrefli') || url.contains('?sid=');

  /// Puts the page's own quality heading on each row, so the source sheet
  /// distinguishes `2160p Web-DL` from `1080p x264` instead of showing the
  /// locker's filename twice.
  CsLinkResult _relabel(CsLinkResult result, String label) {
    if (label.isEmpty || result.links.isEmpty) return result;
    final quality = getQualityFromString(label);
    final short = label.split('—').first.trim();
    return CsLinkResult(
      links: [
        for (final l in result.links)
          CsExtractorLink(
            source: l.source,
            name: '$short · ${l.name}',
            url: l.url,
            referer: l.referer,
            quality: quality == Qualities.unknown ? l.quality : quality,
            type: l.type,
            headers: l.headers,
            qualityLabel: l.qualityLabel,
          ),
      ],
      subtitles: result.subtitles,
    );
  }
}
