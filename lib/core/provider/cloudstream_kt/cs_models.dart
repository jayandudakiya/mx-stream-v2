/// The response/value types a Kotlin CloudStream provider returns, transcribed
/// to Dart so a ported `search`/`load`/`loadLinks` keeps the same shape.
///
/// Kotlin builds these through `newMovieSearchResponse { ... }` DSL blocks;
/// Dart has no receiver-lambda builders, so these are plain constructors with
/// named optional fields — the same information, one call instead of two.
library;

import 'cs_types.dart';

/// `SearchResponse` — one row in a search or main-page listing.
class CsSearchResponse {
  CsSearchResponse({
    required this.name,
    required this.url,
    required this.type,
    this.posterUrl,
    this.quality,
    this.year,
    this.posterHeaders,
  });

  /// Title as the site prints it (still a release string on the index sites —
  /// the adapter cleans it for display and keeps this as the source label).
  final String name;

  /// What `load(url)` will be called with. Usually the detail-page URL, but a
  /// provider may pack its own payload here (CloudStream does the same).
  final String url;
  final TvType type;
  final String? posterUrl;
  final SearchQuality? quality;
  final int? year;
  final Map<String, String>? posterHeaders;
}

/// `Episode` — one playable entry inside a [CsLoadResponse].
class CsEpisode {
  CsEpisode({
    required this.data,
    this.name,
    this.season,
    this.episode,
    this.posterUrl,
    this.description,
    this.date,
    this.rating,
    this.runtimeMinutes,
  });

  /// Opaque payload handed back to [CsMainApi.loadLinks]. A URL, a packed key
  /// or a JSON blob — whatever the provider needs; nothing else interprets it.
  final String data;
  final String? name;
  final int? season;
  final int? episode;
  final String? posterUrl;
  final String? description;
  final String? date;
  final double? rating;
  final int? runtimeMinutes;
}

/// `LoadResponse` — the detail page. One class rather than Kotlin's
/// Movie/TvSeries pair; [episodes] being empty is what makes it a movie, and
/// [dataUrl] is then the single payload `loadLinks` receives.
class CsLoadResponse {
  CsLoadResponse({
    required this.name,
    required this.url,
    required this.type,
    this.dataUrl,
    this.episodes = const [],
    this.posterUrl,
    this.backgroundPosterUrl,
    this.plot,
    this.year,
    this.tags = const [],
    this.actors = const [],
    this.rating,
    this.durationMinutes,
    this.imdbId,
    this.tmdbId,
    this.trailerUrl,
    this.recommendations = const [],
  });

  final String name;

  /// The detail page's own URL — the stable identity the app keys history,
  /// My List and resume position on.
  final String url;
  final TvType type;

  /// Movie payload for `loadLinks`. Ignored when [episodes] is non-empty.
  final String? dataUrl;
  final List<CsEpisode> episodes;
  final String? posterUrl;
  final String? backgroundPosterUrl;
  final String? plot;
  final int? year;
  final List<String> tags;
  final List<String> actors;

  /// 0–10.
  final double? rating;
  final int? durationMinutes;
  final String? imdbId;
  final int? tmdbId;
  final String? trailerUrl;
  final List<CsSearchResponse> recommendations;

  bool get isSeries => episodes.isNotEmpty;
}

/// `SubtitleFile`.
class CsSubtitleFile {
  CsSubtitleFile({required this.lang, required this.url});
  final String lang;
  final String url;
}

/// `ExtractorLink` — one playable mirror.
class CsExtractorLink {
  CsExtractorLink({
    required this.source,
    required this.name,
    required this.url,
    this.referer,
    this.quality = Qualities.unknown,
    this.type = ExtractorLinkType.inferType,
    this.headers = const {},
    this.qualityLabel,
  });

  /// Extractor family that produced this (e.g. `HubCloud`) — grouping only.
  final String source;

  /// Row label in the player's source sheet.
  final String name;
  final String url;
  final String? referer;

  /// [Qualities] ladder value; drives ordering and the quality chip.
  final int quality;
  final ExtractorLinkType type;
  final Map<String, String> headers;

  /// Free-text quality when the site names it better than the ladder can
  /// (`1080p WEB-DL [1.9 GB]`). Falls back to [Qualities.label] when null.
  final String? qualityLabel;
}

/// One `mainPageOf(...)` entry: the path fragment plus the row's display name.
class CsMainPageEntry {
  const CsMainPageEntry(this.data, this.name);

  /// Passed back to `getMainPage` as `request.data`.
  final String data;
  final String name;
}

/// `MainPageRequest`.
class CsMainPageRequest {
  const CsMainPageRequest({required this.name, required this.data});
  final String name;
  final String data;
}

/// Sugar mirroring Kotlin's `mainPageOf("path" to "Name", ...)`.
List<CsMainPageEntry> mainPageOf(Map<String, String> entries) =>
    entries.entries.map((e) => CsMainPageEntry(e.key, e.value)).toList();
