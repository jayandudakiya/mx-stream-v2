/// Value types for the native (non-JS) movie provider engine, ported from
/// OrcaBox's `functions/fetchers/providers/core/models.dart`.
///
/// `VideoSource` is renamed [NativeVideoSource] here — the ecosystem-facing
/// `lib/core/models/video_source.dart` already owns that name, and these two
/// mean different things (this one is an unresolved download-page link;
/// that one is a final playable stream).
class ProviderSearchItem {
  final String title;
  final String url;
  final String poster;
  final String type; // 'movie' or 'series'

  ProviderSearchItem({
    required this.title,
    required this.url,
    required this.poster,
    required this.type,
  });
}

class NativeVideoSource {
  final String resolution;
  final String url;

  NativeVideoSource({required this.resolution, required this.url});
}

class EpisodeInfo {
  final int season;
  final int episode;
  final String name;
  final String? poster;
  final String? description;
  final List<NativeVideoSource> sources;

  EpisodeInfo({
    required this.season,
    required this.episode,
    required this.name,
    this.poster,
    this.description,
    this.sources = const [],
  });
}

class ProviderMediaDetails {
  final String title;
  final String url;
  final String type;
  final String poster;
  final String background;
  final String plot;
  final int? year;
  final String rating;
  final String audioTitle;
  final List<String> audioLanguages;
  final List<String> tags;
  final List<String> cast;
  final String imdbUrl;
  final List<NativeVideoSource> sources; // For movies
  final List<EpisodeInfo> episodes; // For series

  /// True when [episodes] is empty *because* the page publishes the season
  /// only as a complete archive (`Season 1 Complete ... [1.4GB/ZiP]`), which
  /// resolves to a single `.zip` and cannot be streamed or split into
  /// episodes. Lets the UI say that, rather than the misleading "no episodes
  /// found" — the episodes were found and deliberately rejected.
  final bool seasonIsArchiveOnly;

  ProviderMediaDetails({
    required this.title,
    required this.url,
    required this.type,
    required this.poster,
    required this.background,
    required this.plot,
    this.year,
    required this.rating,
    required this.audioTitle,
    required this.audioLanguages,
    required this.tags,
    required this.cast,
    required this.imdbUrl,
    this.sources = const [],
    this.episodes = const [],
    this.seasonIsArchiveOnly = false,
  });
}

class StreamLink {
  final String name;
  final String streamUrl;
  final String quality;
  final bool isHls;

  StreamLink({
    required this.name,
    required this.streamUrl,
    required this.quality,
    this.isHls = false,
  });
}
