import 'parsed_release_title.dart';

/// Converts a raw provider release string into a clean, structured
/// [ParsedReleaseTitle] suitable for TMDB search.
///
/// Ported verbatim from MXStream's `services/metadata/title_normalizer.dart`.
///
/// The pipeline is pure Dart — no network calls, no Flutter dependency.
/// It is the mirror image of `StreamTitleParser`: where that parser *extracts*
/// resolution/codec/audio tags, this normalizer *removes* them and exposes
/// the clean title.
///
/// **Order of steps matters — do not reorder.**
class TitleNormalizer {
  TitleNormalizer._();

  // ─── Compiled regex constants ────────────────────────────────────────────

  /// Tokens that, when present in the tail after a delimiter, indicate the
  /// tail is quality/noise rather than part of the title.
  static final _qualityToken = RegExp(
    r'(480p|720p|1080p|2160p|4K|UHD|WEB-?DL|WEB-?Rip|Blu-?Ray|BD-?Rip|BR-?Rip|'
    r'HDRip|HD-?Rip|DVDRip|DVD-?Rip|Remux|'
    r'Dual[\s.]Audio|Multi[\s.]Audio|Complete|x264|x265|HEVC|H\.265|H\.264)',
    caseSensitive: false,
  );

  /// Words that, immediately after a delimiter (`:`, `|`, `–`), mean the
  /// delimiter separates the title from noise rather than from a real subtitle.
  ///
  /// This is deliberately a *starts-with* test. Testing the whole tail for a
  /// quality token instead would truncate legitimate titles — every release
  /// string ends in quality tags, so `Mission: Impossible – Dead Reckoning
  /// (2023) WEB-DL 720p` would collapse to `Mission: Impossible` and then match
  /// the wrong film on TMDB.
  static final _noiseTailStart = RegExp(
    r'^[\s]*(Dual[\s.]?Audio|Multi[\s.]?Audio|480p|720p|1080p|2160p|4K|UHD|'
    r'WEB[\s.-]?DL|WEB[\s.-]?Rip|Blu-?Ray|BD-?Rip|BR-?Rip|HDRip|HD-?Rip|DVDRip|'
    r'Remux|x264|x265|HEVC|H\.26[45]|Season|Complete|'
    r'Hindi|English|Tamil|Telugu|Korean|Japanese|'
    r'Download|Watch|Free|Prime\s*Video|Amazon|Netflix|Disney)',
    caseSensitive: false,
  );

  /// Parenthesised year: `(2026)`.
  static final _parenYear =
      RegExp(r'\(\s*((?:19|20)\d{2})\s*\)');

  /// Bare year that follows title words: e.g. ` 2026 ` surrounded by spaces/end.
  static final _bareYear =
      RegExp(r'(?<!\d)((?:19|20)\d{2})(?!\d)');

  /// Season *and* episode in one token: `S01E05`, `S1 E5`, `S01.E05`.
  ///
  /// Tried before the season-only patterns because [_seasonShort] deliberately
  /// refuses to match the `S01` of an `S01E05` — without this the whole token
  /// survived into the clean title and `Naruto S01E05` was searched verbatim.
  static final _seasonEpisode = RegExp(
    r'\bS(\d{1,2})\s*[.\-_]?\s*E(\d{1,3})\b',
    caseSensitive: false,
  );

  /// Spelled-out season, single or ranged: `(Season 3)`, `Season 3`,
  /// `(Season 1 - 16)`, `Seasons 1 to 5`, `Season 2 & 3`.
  ///
  /// The word boundary before `Seasons?` is load-bearing, and a bare `S`
  /// alternative must never be added here. Without `\b`, the trailing `s` of an
  /// ordinary word matches: `Bad Boys 2` parsed as season 2 of `Bad Boy`,
  /// `Cars 3` as season 3 of `Car`, and `Ocean's 8` as season 8. Every `S`-form
  /// is handled by [_seasonShort], which carries the lookahead that keeps
  /// `S01E05` intact.
  static final _seasonParen = RegExp(
    r'\(?\s*\bSeasons?\s*(\d{1,2})'
    r'(?:\s*(?:[-–&,+]|to)\s*(?:Seasons?\s*)?\d{1,2})*\s*\)?',
    caseSensitive: false,
  );

  /// Compact season, single or ranged: `S03`, `S3`, `S1-S3`, `S1 to S3`.
  ///
  /// The trailing `(?![0-9E])` is what stops `S01E05` being read as season 1
  /// with a stray `E05` left in the title.
  static final _seasonShort = RegExp(
    r'\bS(\d{1,2})(?:\s*(?:[-–&,+]|to)\s*S?(\d{1,2}))*(?![0-9E])',
    caseSensitive: false,
  );

  /// Language block: `{Hindi-English}`.
  static final _langBlock = RegExp(r'\{([^}]*)\}');

  /// Parenthetical noise tags: `(ORG)`, `(Uncut)`, `(Remastered)`.
  static final _parenNoise = RegExp(
    r'\((?:ORG|Uncut|Remastered|Hindi[\s.-]*Dubbed|Dual[\s.-]*Audio|Multi[\s.-]*Audio|Clean[\s.-]*Audio|Dubbed)[^)]*\)',
    caseSensitive: false,
  );

  /// OTT platform tags.
  static final _ottTag = RegExp(
    r'\b(Prime\s*Video|Amazon\s*Prime|Netflix|Disney\+?|Hotstar|Zee5|SonyLIV|'
    r'JioCinema|Apple\s*TV\+?|MX\s*Player|AMZN|NF|DSNP|MX\s*Original)\b',
    caseSensitive: false,
  );

  /// Bracketed sizes: `[455MB]`, `[1.1GB]`.
  static final _bracketedContent = RegExp(r'\[[^\]]*\]');

  /// Series markers anywhere in a title.
  ///
  /// The short-form `S1` / `S01` / `S01E02` cases matter as much as the word
  /// "Season": the home carousel labels a show `The Gentlemen (S1 + S2)` while
  /// the shelf card for the same show reads `The Gentlemen (Season 1 - 2) …`,
  /// and both must classify as a series.
  static final _seriesMarker = RegExp(
    r'(\b(Season|Seasons|Series|Complete|Episode\s*\d+|EP\s*\d+|E\d{2,})\b'
    r'|\bS\d{1,2}\s*E\d{1,3}\b'
    r'|\bS\d{1,2}\b)',
    caseSensitive: false,
  );

  /// Whether [title] looks like a series rather than a film.
  ///
  /// This is the single classifier for provider listings — every provider
  /// listing parser must use it, because different parts of a provider's page
  /// carry different amounts of the release string for the same title, and a
  /// disagreement here sends the user to the wrong detail page.
  static bool looksLikeSeries(String title) => _seriesMarker.hasMatch(title);

  /// Series check for a listing entry, using the link as well as the label.
  ///
  /// A carousel label is often just `Lanterns` or `Lanterns (2026)` with no
  /// season marker at all, while the link behind it still reads
  /// `…/download-lanterns-season-1-…`. Checking both catches those.
  ///
  /// This remains a *best-effort* signal. The provider's own detail page is the
  /// only authority on type — see the self-correcting redirect in
  /// `_MovieDetailPageState._fetchMovieDetails`, which is what guarantees
  /// correctness when a listing gives away nothing.
  static bool looksLikeSeriesItem(String title, String url) =>
      looksLikeSeries(title) || looksLikeSeries(Uri.tryParse(url)?.path ?? url);

  /// Trailing noise words to strip from the cleaned title.
  static final _trailingNoise = RegExp(
    r'\b(Download|Full\s*Movie|Watch\s*Online|Complete|Dual\s*Audio|'
    r'Multi\s*Audio|Hindi\s*Dubbed|Dubbed|ORG|Anime\s*Series|Anime|ESubs?|'
    r'Uncut|Remastered|'
    // "WEB Series" / "WEB DL" must be listed before the bare "Series"
    // alternative, otherwise "…Amazon Prime WEB Series 480p" leaves a stray
    // "WEB" behind. Bare "WEB" is never stripped on its own — that would
    // mangle real titles such as "Charlotte's Web".
    r'WEB[\s.-]*Series|WEB[\s.-]*DL|WEB[\s.-]*Rip|HD[\s.-]*Rip|'
    r'Series|Episode\s*\d+|EP\s*\d+(-\d+)?|'
    r'VegaMovies|RogMovies|MoviesDrive|FilmyZilla|FilmyWap|Telegram|'
    r'mkvcage|bolly4u|worldfree4u|khatrimaza|9xmovies|'
    r'Blu-?Ray|BR-?Rip|BD-?Rip|WEB-?Rip|DVDRip|'
    // language names that appear as standalone noise after S-number stripping:
    r'Hindi|English|Tamil|Telugu|Korean|Japanese|Spanish|French|German|'
    r'Bengali|Punjabi|Kannada|Malayalam|Marathi)\b',
    caseSensitive: false,
  );

  /// Trailing punctuation / separators.
  static final _trailingPunct = RegExp(r'[\s\-:|]+$');

  /// Leading punctuation / separators.
  static final _leadingPunct = RegExp(r'^[\s\-:|]+');

  /// Multiple whitespace collapser.
  static final _multiSpace = RegExp(r'\s{2,}');

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Parse [rawTitle] into a [ParsedReleaseTitle].
  ///
  /// Pass [providerIsSeries] = `true` / `false` when the provider already
  /// classified the item (from `ProviderSearchItem.type`); pass `null` to rely
  /// entirely on heuristics.
  static ParsedReleaseTitle parse(
    String rawTitle, {
    bool? providerIsSeries,
  }) {
    String s = rawTitle.trim();

    // ── Step 4 (early): Capture language block BEFORE any stripping ──
    // We do this first so the {..} block isn't lost when we cut at a delimiter.
    List<String> languages = const [];
    final langMatch = _langBlock.firstMatch(s);
    if (langMatch != null) {
      final inner = langMatch.group(1) ?? '';
      languages = inner
          .split(RegExp(r'[-+,/]'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      s = s.replaceFirst(langMatch.group(0)!, ' ');
    }

    // ── Step 2 (early): Capture year from the FULL string before delimiter cut ──
    // This ensures we don't lose the year when it sits in the tail after a dash.
    int? year;
    final parenYearMatchEarly = _parenYear.firstMatch(s);
    if (parenYearMatchEarly != null) {
      year = int.tryParse(parenYearMatchEarly.group(1)!);
    }

    // ── Step 5 (early): Capture OTT tag BEFORE stripping ──
    String? ottTag;
    final ottMatch = _ottTag.firstMatch(s);
    if (ottMatch != null) {
      ottTag = _normaliseOttTag(ottMatch.group(0)!);
    }

    // ── Step 1: Cut at strong delimiter only when tail is quality noise ──
    s = _cutAtQualityDelimiter(s);

    // ── Step 2: Strip year from the working string (already captured above) ──
    final parenYearMatch = _parenYear.firstMatch(s);
    if (parenYearMatch != null) {
      s = s.replaceFirst(parenYearMatch.group(0)!, ' ');
    }

    // ── Step 3: Capture and strip season ──
    // Order matters: SxxExx first (it owns both halves of the token), then the
    // spelled-out form, then the compact one.
    int? season;
    bool isSeries = providerIsSeries ?? false;

    final seasonEpisodeMatch = _seasonEpisode.firstMatch(s);
    if (seasonEpisodeMatch != null) {
      season = int.tryParse(seasonEpisodeMatch.group(1)!);
      isSeries = true;
      s = s.replaceFirst(seasonEpisodeMatch.group(0)!, ' ');
    }

    if (season == null) {
      final seasonParenMatch = _seasonParen.firstMatch(s);
      if (seasonParenMatch != null) {
        season = int.tryParse(seasonParenMatch.group(1)!);
        isSeries = true;
        s = s.replaceFirst(seasonParenMatch.group(0)!, ' ');
      } else {
        final seasonShortMatch = _seasonShort.firstMatch(s);
        if (seasonShortMatch != null) {
          season = int.tryParse(seasonShortMatch.group(1)!);
          isSeries = true;
          s = s.replaceFirst(seasonShortMatch.group(0)!, ' ');
        }
      }
    }

    // ── Step 6: Strip bracketed sizes & parenthetical noise then cut at first quality token ──
    s = s.replaceAll(_bracketedContent, ' ');
    s = s.replaceAll(_parenNoise, ' ');
    s = _cutAtFirstQualityToken(s);

    // ── Step 7: Strip OTT tag words and trailing noise words ──
    // Repeat until stable (some titles stack multiple noise words).
    if (ottMatch != null) {
      s = s.replaceAll(
        RegExp(RegExp.escape(ottMatch.group(0)!), caseSensitive: false),
        ' ',
      );
    }
    String prev;
    do {
      prev = s;
      s = s.replaceAll(_trailingNoise, ' ');
    } while (s != prev);

    // ── Step 8: Collapse whitespace, trim, clean leading/trailing punct & unclosed parens ──
    s = s
        .replaceAll(RegExp(r'[\(\[\{\)\]\}\s\-:|]+$'), '')
        .replaceAll(RegExp(r'^[\(\[\{\)\]\}\s\-:|]+'), '')
        .replaceAll(_multiSpace, ' ')
        .replaceAll(_trailingPunct, '')
        .replaceAll(_leadingPunct, '')
        .trim();

    // Strip a leading "Download " prefix (very common on VegaMovies).
    s = s.replaceFirst(RegExp(r'^Download\s+', caseSensitive: false), '').trim();

    // ── Step 9: Final isSeries heuristic ──
    if (!isSeries) {
      isSeries = (providerIsSeries == true) ||
          _seriesMarker.hasMatch(rawTitle);
    }

    // If the bare-year search is still available (no parens found), try
    // to recover it from the *cleaned* title tail so we don't strip
    // year-like numbers from real titles.
    if (year == null) {
      final bareMatch = _bareYear.allMatches(s).lastOrNull;
      if (bareMatch != null) {
        final candidate = int.tryParse(bareMatch.group(0)!);
        // Cap at "shortly in the future" rather than 2100: without this,
        // `Blade Runner 2049` and `Death Race 2000` lose their number to the
        // year field and search TMDB as `Blade Runner`.
        final maxYear = DateTime.now().year + 2;
        if (candidate != null && candidate >= 1900 && candidate <= maxYear) {
          // Only accept if it's at the very end of the string.
          if (bareMatch.end >= s.length - 1) {
            final remainder = s
                .substring(0, bareMatch.start)
                .replaceAll(_trailingPunct, '')
                .replaceAll(_leadingPunct, '')
                .trim();
            // A title that is *only* a year ("1917", "2012") keeps its number.
            if (remainder.isNotEmpty) {
              year = candidate;
              s = remainder;
            }
          }
        }
      }
    }

    return ParsedReleaseTitle(
      cleanTitle: s.isEmpty ? rawTitle.trim() : s,
      rawTitle: rawTitle,
      year: year,
      season: season,
      isSeries: isSeries,
      languages: languages,
      ottTag: ottTag,
    );
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  /// Step 1: cut at the first `:`, `|` or dash whose tail *begins* with a
  /// noise word (see [_noiseTailStart]).
  ///
  /// A title like `Mission: Impossible - Dead Reckoning (2023) English WEB-DL
  /// 720p` keeps its full name: neither the colon nor the dash is followed by
  /// noise, so only [_cutAtFirstQualityToken] trims the tail later.
  static String _cutAtQualityDelimiter(String s) {
    // --- Handle pipe `|` and em-dash `–`/`—` ---
    // Find the leftmost of these that has a quality-token tail.
    final pipeDash = RegExp(r'[|–—]');
    for (final match in pipeDash.allMatches(s)) {
      final tail = s.substring(match.end);
      if (_noiseTailStart.hasMatch(tail)) {
        s = s.substring(0, match.start).trim();
        break;
      }
    }

    // --- Handle colon `:` separately with stricter rule ---
    // Only cut when the text immediately after the colon is a noise word.
    final colonMatch = RegExp(r':').firstMatch(s);
    if (colonMatch != null) {
      final tail = s.substring(colonMatch.end);
      if (_noiseTailStart.hasMatch(tail)) {
        s = s.substring(0, colonMatch.start).trim();
      }
    }

    return s;
  }

  /// Step 6b: cut off everything from the first quality token onward.
  static String _cutAtFirstQualityToken(String s) {
    final match = _qualityToken.firstMatch(s);
    if (match == null) return s;
    return s.substring(0, match.start).trim();
  }

  /// Normalise OTT tag strings to canonical display names.
  static String _normaliseOttTag(String raw) {
    final upper = raw.toUpperCase();
    if (upper.contains('PRIME') || upper == 'AMZN') return 'Prime Video';
    if (upper == 'NF' || upper.contains('NETFLIX')) return 'Netflix';
    if (upper.contains('DISNEY') || upper == 'DSNP') return 'Disney+';
    if (upper.contains('HOTSTAR')) return 'Hotstar';
    if (upper.contains('ZEE')) return 'Zee5';
    if (upper.contains('SONY')) return 'SonyLIV';
    if (upper.contains('JIO')) return 'JioCinema';
    if (upper.contains('APPLE')) return 'Apple TV+';
    return raw.trim();
  }
}
