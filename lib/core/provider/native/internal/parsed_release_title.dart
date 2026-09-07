/// Value object produced by [TitleNormalizer]. Ported verbatim from
/// OrcaBox's `services/metadata/parsed_release_title.dart`.
///
/// All fields except [cleanTitle] and [rawTitle] may be null when the
/// information was not present in the release string.
class ParsedReleaseTitle {
  /// The clean, search-ready title — e.g. `'The Runner'`.
  final String cleanTitle;

  /// The original, unmodified release string — kept for display and debugging.
  final String rawTitle;

  /// Release year extracted from the title, e.g. `2026`.
  final int? year;

  /// Season number for series, e.g. `1` for `Season 1` / `S01`.
  final int? season;

  /// Whether this release is a series (season/series/EP markers found, or the
  /// provider already told us via `isSeries`).
  final bool isSeries;

  /// Languages extracted from the `{Hindi-English}` style block.
  final List<String> languages;

  /// OTT platform tag, e.g. `'Prime Video'`, `'Netflix'`, or null.
  final String? ottTag;

  const ParsedReleaseTitle({
    required this.cleanTitle,
    required this.rawTitle,
    this.year,
    this.season,
    required this.isSeries,
    this.languages = const [],
    this.ottTag,
  });

  @override
  String toString() =>
      'ParsedReleaseTitle(cleanTitle: $cleanTitle, year: $year, '
      'season: $season, isSeries: $isSeries, languages: $languages, '
      'ottTag: $ottTag)';
}
