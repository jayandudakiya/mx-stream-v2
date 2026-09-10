import '../cs_domains.dart';
import '../cs_dom.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';
import '../extractors/packed_host_extractor.dart';

/// MultiMovies — Hindi-dubbed movies, series, anime and cartoons.
///
/// Ported from `MultiMoviesProvider.kt` (HindiProviders). It is a DooPlay
/// WordPress theme, so listing and detail parsing is transcribed directly; two
/// things had to change because the live site has moved on from the Kotlin:
///
///  * **Type detection.** Kotlin tests `href.contains("Movie")` — capital M,
///    which no URL on this site has ever contained, so every result was typed
///    as a series. The real signal is the `/movies/` vs `/tvshows/` path.
///  * **The player hosts.** Kotlin registers a fixed list of extractors
///    (`multimovies.cloud`, `dhcplay`, `server1.uns.bio`, …). The site now
///    hands out an entirely different set, and rotates it, so links go through
///    [resolveEmbed], which falls back to a generic unpack for hosts nothing
///    claims yet.
///
/// Season/episode numbers come from the episode permalink's `-<season>x<ep>`
/// suffix rather than Kotlin's positional `mapIndexed`, which mis-numbers any
/// show whose seasons are not listed in order.
class MultiMoviesProvider implements CsMainApi {
  @override
  Future<String> get mainUrl => CsDomains.resolve('multimovies');

  @override
  String get providerKey => 'multimovies';

  @override
  String get name => 'MultiMovies';

  @override
  String get lang => 'hi';

  @override
  Set<TvType> get supportedTypes =>
      {TvType.movie, TvType.tvSeries, TvType.anime, TvType.animeMovie, TvType.cartoon};

  @override
  List<CsMainPageEntry> get mainPage => mainPageOf(const {
        'trending/': 'Trending',
        'genre/hindi-dubbed/': 'Hindi Dubbed',
        'genre/bollywood-movies/': 'Bollywood Movies',
        'genre/anime-hindi/': 'Anime (Hindi)',
        'genre/anime-movies/': 'Anime Movies',
        'genre/south-indian/': 'South Indian',
        'genre/hollywood/': 'Hollywood',
        'genre/netflix/': 'Netflix',
        'genre/amazon-prime/': 'Amazon Prime',
        'genre/disney-hotstar/': 'JioHotstar',
        'genre/zee-5/': 'Zee5',
        'genre/sony-liv/': 'SonyLIV',
        'genre/k-drama/': 'K-Drama',
        'genre/cartoon-network/': 'Cartoon Network',
        'genre/punjabi/': 'Punjabi',
      });

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async {
    final base = await mainUrl;
    final url = page == 1
        ? '$base/${request.data}'
        : '$base/${request.data}page/$page/';
    final res = await app.get(url, referer: base);
    if (!res.isOk) return const [];

    final doc = res.document;
    final articles = [
      ...doc.select('div.items > article'),
      ...doc.select('#archive-content > article'),
    ];
    return articles
        .map((e) => _toSearchResult(e, base))
        .whereType<CsSearchResponse>()
        .toList();
  }

  CsSearchResponse? _toSearchResult(dynamic article, String base) {
    final anchor = article.selectFirst('div.data > h3 > a') ??
        article.selectFirst('h3 > a') ??
        article.selectFirst('a');
    if (anchor == null) return null;
    final title = anchor.textTrim;
    final href = fixUrl(anchor.attr('href'), base);
    if (title.isEmpty || href.isEmpty) return null;

    final poster = article.selectFirst('div.poster > img')?.imageAttr ??
        article.selectFirst('img')?.imageAttr;
    final qualityText = article.selectFirst('div.poster > div.mepo > span')?.textTrim;

    return CsSearchResponse(
      name: title,
      url: href,
      type: _typeFor(href),
      posterUrl: fixUrlNull(poster, base),
      quality: getSearchQuality(qualityText),
    );
  }

  /// `/tvshows/` and `/episodes/` are series; everything else is a movie.
  TvType _typeFor(String url) {
    final u = url.toLowerCase();
    return (u.contains('/tvshows/') || u.contains('/episodes/'))
        ? TvType.tvSeries
        : TvType.movie;
  }

  @override
  Future<List<CsSearchResponse>> search(String query) async {
    final base = await mainUrl;
    final res = await app.get(
      '$base/?s=${Uri.encodeQueryComponent(query)}',
      referer: base,
    );
    if (!res.isOk) return const [];

    return res.document
        .select('div.result-item')
        .map((item) {
          final anchor = item.selectFirst('div.details > div.title > a') ??
              item.selectFirst('div.title > a');
          if (anchor == null) return null;
          final href = fixUrl(anchor.attr('href'), base);
          final title = anchor.textTrim;
          if (href.isEmpty || title.isEmpty) return null;

          // The thumbnail's `span` says "Movie" or "TV" — trusted over the
          // path when present, because a series' search row can link to an
          // episode permalink.
          final badge = item.selectFirst('div.thumbnail > a > span')?.textTrim ?? '';
          final type = badge.toLowerCase().contains('movie')
              ? TvType.movie
              : badge.isEmpty
                  ? _typeFor(href)
                  : TvType.tvSeries;

          return CsSearchResponse(
            name: title,
            url: href,
            type: type,
            posterUrl: fixUrlNull(item.selectFirst('img')?.imageAttr, base),
            year: int.tryParse(
              RegExp(r'\b(19|20)\d{2}\b')
                      .firstMatch(item.selectFirst('span.year')?.textTrim ?? '')
                      ?.group(0) ??
                  '',
            ),
          );
        })
        .whereType<CsSearchResponse>()
        .toList();
  }

  @override
  Future<CsLoadResponse?> load(String url) async {
    final base = await mainUrl;
    final res = await app.get(url, referer: base);
    if (!res.isOk) return null;
    final doc = res.document;

    final rawTitle = doc.selectFirst('div.sheader > div.data > h1')?.textTrim ??
        doc.selectFirst('h1')?.textTrim;
    if (rawTitle == null || rawTitle.isEmpty) return null;

    final poster = fixUrlNull(
          doc.selectFirst('div.poster > img')?.imageAttr,
          base,
        ) ??
        fixUrlNull(
          doc.selectFirst('meta[property="og:image"]')?.attr('content'),
          base,
        );

    final tags = doc.select('div.sgeneros > a').eachText;
    final year = int.tryParse(
      RegExp(r'\b(19|20)\d{2}\b')
              .firstMatch(doc.selectFirst('span.date')?.textTrim ?? '')
              ?.group(0) ??
          '',
    );
    final plot = doc.selectFirst('#info div.wp-content p')?.textTrim ??
        doc.selectFirst('div.wp-content p')?.textTrim;
    final rating = double.tryParse(
      doc.selectFirst('span.dt_rating_vgs')?.textTrim ?? '',
    );
    final duration = int.tryParse(
      RegExp(r'\d+')
              .firstMatch(doc.selectFirst('span.runtime')?.textTrim ?? '')
              ?.group(0) ??
          '',
    );
    final actors = doc.select('div.person div.name a').eachText;

    final episodes = _episodes(doc, base);
    final isSeries = episodes.isNotEmpty || url.toLowerCase().contains('/tvshows/');

    return CsLoadResponse(
      name: rawTitle,
      url: url,
      type: isSeries ? TvType.tvSeries : TvType.movie,
      // A movie's payload is its own page — `loadLinks` re-reads the player
      // list from it.
      dataUrl: url,
      episodes: episodes,
      posterUrl: poster,
      backgroundPosterUrl: poster,
      plot: plot,
      year: year,
      tags: tags,
      actors: actors,
      rating: rating,
      durationMinutes: duration,
    );
  }

  static final RegExp _permalinkSeasonEpisode = RegExp(r'-(\d+)x(\d+)/?$');

  List<CsEpisode> _episodes(dynamic doc, String base) {
    final out = <CsEpisode>[];
    for (final li in doc.select('#seasons ul.episodios li')) {
      final anchor = li.selectFirst('div.episodiotitle > a');
      if (anchor == null) continue;
      final href = fixUrl(anchor.attr('href'), base);
      if (href.isEmpty) continue;

      // `…-2x7/` → season 2, episode 7. `div.numerando` ("2 - 7") is the
      // fallback for the handful of themes that rewrite permalinks.
      var season = 1;
      var episode = out.length + 1;
      final fromUrl = _permalinkSeasonEpisode.firstMatch(href);
      if (fromUrl != null) {
        season = int.tryParse(fromUrl.group(1)!) ?? 1;
        episode = int.tryParse(fromUrl.group(2)!) ?? episode;
      } else {
        final numerando = li.selectFirst('div.numerando')?.textTrim ?? '';
        final parts = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(numerando);
        if (parts != null) {
          season = int.tryParse(parts.group(1)!) ?? 1;
          episode = int.tryParse(parts.group(2)!) ?? episode;
        }
      }

      out.add(
        CsEpisode(
          data: href,
          name: anchor.textTrim,
          season: season,
          episode: episode,
          posterUrl: fixUrlNull(li.selectFirst('div.imagen img')?.imageAttr, base),
          date: li.selectFirst('span.date')?.textTrim,
        ),
      );
    }
    out.sort((a, b) => (a.season ?? 1) != (b.season ?? 1)
        ? (a.season ?? 1).compareTo(b.season ?? 1)
        : (a.episode ?? 1).compareTo(b.episode ?? 1));
    return out;
  }

  @override
  Future<CsLinkResult> loadLinks(String data) async {
    final base = await mainUrl;
    final res = await app.get(data, referer: base);
    if (!res.isOk) return CsLinkResult.empty;

    final options = res.document
        .select('ul#playeroptionsul li')
        .map((li) => (
              post: li.attr('data-post'),
              nume: li.attr('data-nume'),
              type: li.attr('data-type'),
            ))
        .where((o) =>
            o.post.isNotEmpty && o.nume.isNotEmpty && o.nume != 'trailer')
        .toList();
    if (options.isEmpty) return CsLinkResult.empty;

    final batches = await amap<dynamic, CsLinkResult>(
      options,
      (o) async {
        try {
          final embed = await _embedUrl(base, o.post, o.nume, o.type);
          if (embed == null || embed.isEmpty) return CsLinkResult.empty;
          // A YouTube option is the trailer under another name.
          if (embed.contains('youtube') || embed.contains('youtu.be')) {
            return CsLinkResult.empty;
          }
          return await _resolve(embed, base);
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

  /// The DooPlay ajax endpoint: player index → embed URL.
  Future<String?> _embedUrl(
    String base,
    String post,
    String nume,
    String type,
  ) async {
    final res = await app.post(
      '$base/wp-admin/admin-ajax.php',
      data: {
        'action': 'doo_player_ajax',
        'post': post,
        'nume': nume,
        'type': type.isEmpty ? 'movie' : type,
      },
      referer: base,
      headers: {'X-Requested-With': 'XMLHttpRequest'},
    );
    if (!res.isOk) return null;

    String? embed;
    final json = res.json;
    if (json is Map && json['embed_url'] is String) {
      embed = json['embed_url'] as String;
    } else {
      embed = RegExp(r'"embed_url"\s*:\s*"([^"]+)"')
          .firstMatch(res.text)
          ?.group(1)
          ?.replaceAll(r'\/', '/');
    }
    if (embed == null || embed.isEmpty) return null;

    // The field is HTML-escaped inside the JSON (`&amp;` between query
    // parameters), and an un-unescaped `&amp;s=1` is a different request.
    embed = const HtmlUnescape().convert(embed).trim();
    // Some options wrap the URL in an <iframe> string rather than sending it bare.
    final iframe = RegExp('''src=["']([^"']+)["']''').firstMatch(embed);
    if (iframe != null) embed = iframe.group(1)!;
    return embed;
  }

  /// One embed URL → playable links. `deaddrive`-style pages are a second
  /// server list rather than a player, so they are expanded first.
  Future<CsLinkResult> _resolve(String embed, String base) async {
    if (embed.contains('deaddrive')) {
      final page = await app.get(embed, referer: base);
      if (!page.isOk) return CsLinkResult.empty;
      final servers = page.document
          .select('ul.list-server-items > li')
          .map((li) => li.attr('data-video'))
          .where((v) => v.isNotEmpty)
          .toList();
      final batches = await amap<String, CsLinkResult>(
        servers,
        (s) => resolveEmbed(fixUrl(s, base), referer: base),
        concurrency: 3,
      );
      var out = CsLinkResult.empty;
      for (final b in batches) {
        out = out + b;
      }
      return out;
    }
    return resolveEmbed(embed, referer: base);
  }
}

/// The handful of HTML entities these JSON fields actually contain. Pulling in
/// a package for five replacements would be the wrong trade.
class HtmlUnescape {
  const HtmlUnescape();

  String convert(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
