/// Kotlin CloudStream's enums, transcribed so a ported provider can keep
/// writing `TvType.Movie`, `Qualities.P1080.value` and `ExtractorLinkType.M3U8`
/// exactly as the `.cs3` source does.
///
/// Part of the CloudStream→Dart adapter layer
/// (`lib/core/provider/cloudstream_kt/`). See `cs_adapter.dart` for how a
/// [CsMainApi] built on these types reaches this app's own `BaseProvider`.
library;

/// `com.lagradost.cloudstream3.TvType`.
enum TvType {
  movie,
  tvSeries,
  anime,
  animeMovie,
  ova,
  cartoon,
  asianDrama,
  documentary,
  live,
  torrent,
  others;

  bool get isSeriesLike =>
      this == TvType.tvSeries ||
      this == TvType.anime ||
      this == TvType.cartoon ||
      this == TvType.asianDrama ||
      this == TvType.ova;
}

/// `com.lagradost.cloudstream3.SearchQuality` — the poster badge.
enum SearchQuality {
  cam('CAM'),
  camRip('CAM'),
  hdCam('HDCAM'),
  telesync('TS'),
  workPrint('WP'),
  telecine('TC'),
  hq('HQ'),
  hd('HD'),
  hdr('HDR'),
  blueRay('BluRay'),
  dvd('DVD'),
  sd('SD'),
  fourK('4K'),
  uhd('UHD'),
  sdr('SDR'),
  webRip('WEB-DL');

  const SearchQuality(this.label);
  final String label;
}

/// `com.lagradost.cloudstream3.utils.ExtractorLinkType`.
enum ExtractorLinkType { video, m3u8, dash, torrent, magnet, inferType }

/// `com.lagradost.cloudstream3.utils.Qualities` — the integer ladder providers
/// compare against. Values match Kotlin's so ported `getIndexQuality` helpers
/// keep sorting identically.
class Qualities {
  const Qualities._();

  static const int unknown = 400;
  static const int p360 = 360;
  static const int p480 = 480;
  static const int p720 = 720;
  static const int p1080 = 1080;
  static const int p1440 = 1440;
  static const int p2160 = 2160;

  /// Human label for a ladder value, for [CsExtractorLink.qualityLabel].
  static String label(int value) => switch (value) {
    p360 => '360p',
    p480 => '480p',
    p720 => '720p',
    p1080 => '1080p',
    p1440 => '1440p',
    p2160 => '4K',
    _ => 'HD',
  };
}
