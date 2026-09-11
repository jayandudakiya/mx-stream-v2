/// MovieBox — a JSON API rather than a site to scrape.
///
/// Implemented against `docs/MovieBox-Tui/src/providers/moviebox/` (a Rust
/// client) and verified against the live API. It implements [CsMainApi], the
/// same contract the ported CloudStream providers use, so it reaches the app
/// through the existing `CsProviderAdapter` — the detail screen, the player,
/// history and search need nothing new.
///
/// Three things about this API that the shape of the code would not otherwise
/// explain:
///
///  * **The `url` in `play-info` is usually NOT the film.** For most subjects it
///    is a deprecation-notice clip on `macdn.aoneroom.com/other/…`. The real
///    stream is a DASH manifest whose location is encoded in the CloudFront
///    policy inside `signCookie` — see [_playableFrom]. Playing the obvious
///    field gets you a 30-second notice video instead of the movie.
///  * **Playback needs the signed cookie and a Referer.** Both are attached to
///    every link as headers; the player forwards them to media_kit.
///  * **A season is its own subject.** Search returns "Breaking Bad [Hindi] S5"
///    and "…S4" as separate rows sharing one `subjectId`, so the season number
///    lives in the title, and the episode list comes from `season-info`.
library;

import 'dart:convert';

import '../cloudstream_kt/cs_main_api.dart';
import '../cloudstream_kt/cs_models.dart';
import '../cloudstream_kt/cs_types.dart';
import '../cloudstream_kt/cs_utils.dart';
import 'moviebox_client.dart';

/// What `loadLinks` is handed: which subject, and which episode of it.
///
/// Encoded as JSON because the API addresses an episode by three values, and
/// the adapter's payload is a single opaque string.
class _Payload {
  const _Payload(this.subjectId, this.season, this.episode);

  factory _Payload.decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        return _Payload(
          (map['id'] ?? '').toString(),
          (map['se'] as num?)?.toInt() ?? 0,
          (map['ep'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // A bare subject id — a movie, from an older stored payload.
    }
    return _Payload(raw, 0, 0);
  }

  final String subjectId;

  /// 0/0 for a movie: the API's own "no episode" form.
  final int season;
  final int episode;

  String encode() =>
      jsonEncode({'id': subjectId, 'se': season, 'ep': episode});
}

class MovieBoxProvider implements CsMainApi {
  MovieBoxProvider({MovieBoxClient? client})
      : _client = client ?? MovieBoxClient();

  final MovieBoxClient _client;

  /// The site users know this catalogue by. Nothing is fetched from it — every
  /// request goes to the signed API — but the app shows a source's site in
  /// "open in browser", and an empty one hides that action.
  @override
  Future<String> get mainUrl async => 'https://moviebox.ph';

  @override
  String get providerKey => 'moviebox';

  @override
  String get name => 'MovieBox';

  /// The catalogue is multi-language (its titles carry `[Hindi]`, `[Tamil]`
  /// tags), so no single code is honest. `en` is the neutral default the source
  /// picker groups under.
  @override
  String get lang => 'en';

  @override
  Set<TvType> get supportedTypes => {TvType.movie, TvType.tvSeries};

  /// The app's Home rows come from the operating tabs. Tab 2 is the movie/TV
  /// home the mobile client opens on.
  @override
  List<CsMainPageEntry> get mainPage => mainPageOf(const {'2': 'Featured'});

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async {
    final data = await _client.get(
      '/wefeed-mobile-bff/tab-operating'
      '?page=$page&tabId=${Uri.encodeQueryComponent(request.data)}&version=',
    );
    if (data is! Map) return const [];

    // The tab is a list of heterogeneous blocks (banner, ranked lists, plain
    // rows); every one that carries subjects contributes its subjects, and the
    // rest are skipped rather than special-cased.
    final out = <CsSearchResponse>[];
    final seen = <String>{};
    final items = data['items'];
    if (items is! List) return const [];
    for (final block in items) {
      if (block is! Map) continue;
      for (final subject in _subjectsIn(block)) {
        final row = _toSearchResponse(subject);
        if (row != null && seen.add(row.url)) out.add(row);
      }
    }
    return out;
  }

  /// Subjects reachable from one home block, wherever the block keeps them.
  Iterable<Map<String, dynamic>> _subjectsIn(Map block) sync* {
    for (final key in const ['subjects', 'groups']) {
      final value = block[key];
      if (value is! List) continue;
      for (final entry in value) {
        if (entry is Map && entry.containsKey('subjectId')) {
          yield entry.cast<String, dynamic>();
        } else if (entry is Map) {
          // A group wraps its own subject list.
          final nested = entry['subjects'];
          if (nested is List) {
            for (final s in nested) {
              if (s is Map) yield s.cast<String, dynamic>();
            }
          }
        }
      }
    }
  }

  @override
  Future<List<CsSearchResponse>> search(String query) async {
    final data = await _client.post(
      '/wefeed-mobile-bff/subject-api/search/v2',
      {'keyword': query, 'page': 1, 'perPage': 15, 'subjectType': 0},
    );
    if (data is! Map) return const [];

    final results = data['results'];
    if (results is! List) return const [];

    final out = <CsSearchResponse>[];
    final seen = <String>{};
    for (final topic in results) {
      if (topic is! Map) continue;
      final subjects = topic['subjects'];
      if (subjects is! List) continue;
      for (final subject in subjects) {
        if (subject is! Map) continue;
        final row = _toSearchResponse(subject.cast<String, dynamic>());
        // Seasons of one show share a subjectId and differ only by title, so
        // the key is both — dropping either would lose every season but one.
        if (row != null && seen.add('${row.url}|${row.name}')) out.add(row);
      }
    }
    return out;
  }

  CsSearchResponse? _toSearchResponse(Map<String, dynamic> subject) {
    final id = (subject['subjectId'] ?? '').toString();
    final title = (subject['title'] ?? '').toString();
    if (id.isEmpty || title.isEmpty) return null;

    final type = _typeOf(subject);
    return CsSearchResponse(
      name: title,
      // `load` needs the season the row names, and the API cannot be asked for
      // it later — two rows differing only by season share one subjectId.
      url: _detailUrl(id, _seasonInTitle(title)),
      type: type,
      posterUrl: _coverUrl(subject),
      year: _yearOf(subject),
      quality: getSearchQuality(title),
    );
  }

  static TvType _typeOf(Map<String, dynamic> subject) {
    final raw = subject['subjectType'] ?? subject['stype'];
    final value = raw is num ? raw.toInt() : int.tryParse('$raw');
    return value == 2 ? TvType.tvSeries : TvType.movie;
  }

  static String? _coverUrl(Map<String, dynamic> subject) {
    final cover = subject['cover'];
    if (cover is Map) {
      final url = cover['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    final flat = subject['cover'] ?? subject['image'] ?? subject['poster'];
    return flat is String && flat.isNotEmpty ? flat : null;
  }

  static int? _yearOf(Map<String, dynamic> subject) {
    final date = (subject['releaseDate'] ?? subject['year'] ?? '').toString();
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(date);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  /// The season a search row names, e.g. `Breaking Bad [Hindi] S5` → 5.
  /// Null for a row that names none (a movie, or a show's only season).
  static int? _seasonInTitle(String title) {
    final match =
        RegExp(r'\bS(?:eason\s*)?(\d{1,2})\b', caseSensitive: false)
            .firstMatch(title);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // ── Detail identity ───────────────────────────────────────────────────────
  //
  // The app keys history, My List and resume position on the detail "url", so
  // it has to be stable and to distinguish two seasons of one show. There is no
  // web URL to use (this is an API), so a synthetic one carries both parts.

  static String _detailUrl(String subjectId, int? season) =>
      season == null || season <= 0
          ? 'moviebox://subject/$subjectId'
          : 'moviebox://subject/$subjectId/s$season';

  static ({String id, int? season}) _parseDetailUrl(String url) {
    final match = RegExp(r'^moviebox://subject/([^/]+)(?:/s(\d+))?$')
        .firstMatch(url.trim());
    if (match == null) return (id: url.trim(), season: null);
    return (
      id: match.group(1)!,
      season: match.group(2) == null ? null : int.tryParse(match.group(2)!),
    );
  }

  @override
  Future<CsLoadResponse?> load(String url) async {
    final parsed = _parseDetailUrl(url);
    final subjectId = parsed.id;
    if (subjectId.isEmpty) return null;

    final data = await _client
        .get('/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId');
    if (data is! Map) return null;

    final subject = _subjectOf(data);
    final title = (subject['title'] ?? '').toString();
    if (title.isEmpty) return null;

    final isSeries = _typeOf(subject) == TvType.tvSeries;
    final episodes = isSeries
        ? await _episodes(subjectId, parsed.season ?? _seasonInTitle(title) ?? 1)
        : const <CsEpisode>[];

    return CsLoadResponse(
      name: title,
      url: url,
      type: isSeries ? TvType.tvSeries : TvType.movie,
      // A movie plays from the subject itself; for a series this is unused
      // (the adapter takes each episode's own payload).
      dataUrl: _Payload(subjectId, 0, 0).encode(),
      episodes: episodes,
      posterUrl: _coverUrl(subject),
      backgroundPosterUrl: _coverUrl(subject),
      plot: _nullIfEmpty((subject['description'] ?? '').toString()),
      year: _yearOf(subject),
      tags: _tags(subject),
      durationMinutes: _durationMinutes(subject),
      rating: _rating(subject),
    );
  }

  /// `get` answers with the subject at the top level on some hosts and nested
  /// under `subject` on others.
  static Map<String, dynamic> _subjectOf(Map data) {
    final nested = data['subject'];
    if (nested is Map) return nested.cast<String, dynamic>();
    return data.cast<String, dynamic>();
  }

  static List<String> _tags(Map<String, dynamic> subject) {
    final genre = (subject['genre'] ?? '').toString();
    if (genre.trim().isEmpty) return const [];
    return genre
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
  }

  /// `"3h 1m"` → 181.
  static int? _durationMinutes(Map<String, dynamic> subject) {
    final raw = (subject['duration'] ?? '').toString();
    if (raw.trim().isEmpty) return null;
    final hours = RegExp(r'(\d+)\s*h').firstMatch(raw);
    final minutes = RegExp(r'(\d+)\s*m').firstMatch(raw);
    if (hours == null && minutes == null) return int.tryParse(raw.trim());
    return (int.tryParse(hours?.group(1) ?? '0') ?? 0) * 60 +
        (int.tryParse(minutes?.group(1) ?? '0') ?? 0);
  }

  static double? _rating(Map<String, dynamic> subject) {
    final raw = subject['imdbRatingValue'] ?? subject['rating'] ?? subject['score'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw');
  }

  /// The episode list for one season, from `season-info`.
  ///
  /// The API reports how many episodes a season has (`maxEp`) rather than
  /// listing them, so the entries are generated — there is nothing else to read.
  /// A VIP-gated season still lists every episode: whether a given one plays is
  /// decided by `play-info`, and hiding them here would misreport the show.
  Future<List<CsEpisode>> _episodes(String subjectId, int season) async {
    final data = await _client
        .get('/wefeed-mobile-bff/subject-api/season-info?subjectId=$subjectId');
    if (data is! Map) return const [];

    final seasons = data['seasons'];
    if (seasons is! List) return const [];

    Map? match;
    for (final entry in seasons) {
      if (entry is! Map) continue;
      final se = (entry['se'] as num?)?.toInt();
      if (se == season) {
        match = entry;
        break;
      }
      match ??= entry; // fall back to the first season the show has
    }
    if (match == null) return const [];

    final resolvedSeason = (match['se'] as num?)?.toInt() ?? season;
    final maxEp = (match['maxEp'] as num?)?.toInt() ?? 0;
    if (maxEp <= 0) return const [];

    return [
      for (var ep = 1; ep <= maxEp; ep++)
        CsEpisode(
          data: _Payload(subjectId, resolvedSeason, ep).encode(),
          name: 'Episode $ep',
          season: resolvedSeason,
          episode: ep,
        ),
    ];
  }

  // ── Links ─────────────────────────────────────────────────────────────────

  @override
  Future<CsLinkResult> loadLinks(String data) async {
    final payload = _Payload.decode(data);
    if (payload.subjectId.isEmpty) return CsLinkResult.empty;

    final query = payload.season > 0 && payload.episode > 0
        ? '?subjectId=${payload.subjectId}&se=${payload.season}&ep=${payload.episode}'
        : '?subjectId=${payload.subjectId}';

    final info =
        await _client.get('/wefeed-mobile-bff/subject-api/play-info/v2$query');
    if (info is! Map) return CsLinkResult.empty;

    final streams = info['streams'];
    if (streams is! List) return CsLinkResult.empty;

    final links = <CsExtractorLink>[];
    String? resourceId;

    for (final entry in streams) {
      if (entry is! Map) continue;
      final stream = entry.cast<String, dynamic>();
      resourceId ??= (stream['id'] ?? '').toString();

      final signCookie = (stream['signCookie'] ?? '').toString();
      final url = _playableFrom(stream, signCookie);
      if (url == null) continue;

      final resolutions = (stream['resolutions'] ??
              info['displayResolutions'] ??
              '1080,720,480')
          .toString();
      final heights = resolutions
          .split(',')
          .map((r) => int.tryParse(r.trim()))
          .whereType<int>()
          .toList();
      final isDash = url.endsWith('.mpd') ||
          (stream['format'] ?? '').toString().toUpperCase() == 'DASH';
      final multiRes = isDash || heights.length > 1;
      final best = heights.isEmpty
          ? Qualities.p1080
          : heights.reduce((a, b) => a > b ? a : b);

      final codec = (stream['codecName'] ?? stream['format'] ?? '')
          .toString()
          .toUpperCase();
      final size = _sizeLabel(stream['size']);

      links.add(
        CsExtractorLink(
          source: name,
          name: [
            name,
            if (multiRes) 'Multi-Res' else '${best}p',
            if (codec.isNotEmpty) codec,
            ?size,
          ].join(' · '),
          url: url,
          // Both are required for playback: the CDN checks the signed cookie,
          // and rejects a request without the referer the app client sends.
          referer: 'https://sportslive.wine',
          headers: {
            if (signCookie.isNotEmpty) 'Cookie': _cleanCookie(signCookie),
          },
          quality: best,
          qualityLabel: multiRes
              ? 'Auto (up to ${best}p)${size == null ? '' : ' · $size'}'
              : '${best}p${size == null ? '' : ' · $size'}',
          type: isDash ? ExtractorLinkType.dash : ExtractorLinkType.video,
        ),
      );
    }

    final subtitles = await _subtitles(payload.subjectId, resourceId);
    return CsLinkResult(links: links, subtitles: subtitles);
  }

  /// The URL that actually plays.
  ///
  /// `stream.url` is only usable when it is not one of the deprecation-notice
  /// clips the API hands out in place of most films. The real stream is the
  /// DASH manifest named by the CloudFront policy inside the signed cookie, so
  /// that is preferred whenever it can be read.
  static String? _playableFrom(Map<String, dynamic> stream, String signCookie) {
    final fromPolicy = dashManifestFromPolicy(signCookie);
    if (fromPolicy != null) return fromPolicy;

    final url = (stream['url'] ?? '').toString();
    if (!url.startsWith('http')) return null;
    return isDeprecationNoticeUrl(url) ? null : url;
  }

  static String? _sizeLabel(Object? raw) {
    final bytes = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 2)} '
        '${units[unit]}';
  }

  /// `a=b; c=d` from the API's `a=b;c=d;` — the trailing separator and the
  /// missing spaces are both rejected by some HTTP clients.
  static String _cleanCookie(String raw) => raw
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join('; ');

  Future<List<CsSubtitleFile>> _subtitles(
    String subjectId,
    String? resourceId,
  ) async {
    if (resourceId == null || resourceId.isEmpty) return const [];
    try {
      final data = await _client.get(
        '/wefeed-mobile-bff/subject-api/get-ext-captions'
        '?subjectId=$subjectId&resourceId=$resourceId',
      );
      final list = data is Map ? (data['list'] ?? data['captions']) : data;
      if (list is! List) return const [];
      final out = <CsSubtitleFile>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final url = (entry['url'] ?? entry['captionUrl'] ?? '').toString();
        if (!url.startsWith('http')) continue;
        final lang = (entry['lanName'] ?? entry['lan'] ?? entry['language'] ?? '')
            .toString();
        out.add(CsSubtitleFile(lang: lang.isEmpty ? 'Unknown' : lang, url: url));
      }
      return out;
    } catch (_) {
      // Subtitles are a bonus; a film with none must still play.
      return const [];
    }
  }

  static String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

/// True for the placeholder clips the API returns instead of a stream.
///
/// Kept in step with the Rust client's list. The `macdn…/other/` rule is the
/// one that matters in practice: it is what `play-info.url` holds for most
/// subjects, and playing it shows a notice video instead of the film.
bool isDeprecationNoticeUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('1c7de0bd3393702d9191801f15f88f8d') ||
      lower.contains('9a0461bc39da389663bf3dbb17091d3f') ||
      lower.contains('/notice.mp4') ||
      lower.contains('notice') ||
      (lower.contains('macdn.aoneroom.com') && lower.contains('/other/'));
}

/// The DASH manifest a CloudFront signed cookie authorises.
///
/// `CloudFront-Policy` is URL-safe base64 with a non-standard alphabet
/// (`-_~` for `+=/`); inside it, `Statement[0].Resource` is the directory the
/// signature covers, and `index.mpd` within it is the manifest.
String? dashManifestFromPolicy(String signCookie) {
  for (final part in signCookie.split(';')) {
    final trimmed = part.trim();
    if (!trimmed.startsWith('CloudFront-Policy=')) continue;

    var normalized = trimmed
        .substring('CloudFront-Policy='.length)
        .trim()
        .replaceAll('-', '+')
        .replaceAll('_', '=')
        .replaceAll('~', '/');
    normalized += '=' * ((4 - normalized.length % 4) % 4);

    try {
      final decoded = jsonDecode(utf8.decode(base64.decode(normalized)));
      if (decoded is! Map) continue;
      final statement = decoded['Statement'];
      if (statement is! List || statement.isEmpty) continue;
      final first = statement.first;
      if (first is! Map) continue;
      final resource = (first['Resource'] ?? '').toString();
      var base = resource;
      while (base.endsWith('*') || base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      if (base.startsWith('http')) return '$base/index.mpd';
    } catch (_) {
      continue;
    }
  }
  return null;
}
