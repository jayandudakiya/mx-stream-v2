import '../cs_extractor.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';

/// The StreamWish / StreamHG / EarnVids / VidHide / Filemoon family — every
/// player whose page hides `sources:[{file:"…m3u8"}]` inside a Dean Edwards
/// `eval(function(p,a,c,k,e,d){…})` block.
///
/// Kotlin ships a subclass per host (`Asnwish`, `CdnwishCom`, `Strwishcom`,
/// `Dhcplay`, `server2`, …) purely to declare a `mainUrl`. That does not
/// survive contact with reality here: MultiMovies rotates its mirror hosts
/// faster than a release cycle, and a host this file has never heard of is the
/// normal case, not the exception. So there is one extractor, it matches the
/// families it knows, and [resolveEmbed] hands it anything the registry could
/// not place — the unpack either finds a stream or it does not.
class PackedHostExtractor extends CsExtractor {
  @override
  String get name => 'Stream';

  @override
  bool get requiresReferer => true;

  @override
  List<String> get hostPatterns => const [
        'wish', // streamwish / asnwish / cdnwish / strwish / awish / mwish
        'filemoon',
        'vidhide',
        'streamhg',
        'hanerix',
        'smoothpre',
        'earnvids',
        'dhcplay',
        'animezia',
        'multimovies.cloud',
        'vidmoly',
        'filelions',
        'streamruby',
        'rubystm',
        'lulustream',
        'do7go',
      ];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) =>
      extractFromPage(url, referer: referer, sourceName: name);

  /// Fetches [url] and mines it for a playable stream: unpack first, then a
  /// direct scan, because plenty of these pages carry both a decoy plain URL
  /// and the real one inside the packed block.
  static Future<CsLinkResult> extractFromPage(
    String url, {
    String? referer,
    String sourceName = 'Stream',
  }) async {
    final res = await app.get(url, referer: referer ?? url);
    if (!res.isOk) return CsLinkResult.empty;

    final unpacked = unpackJs(res.text);
    final haystack = unpacked == null ? res.text : '${res.text}\n$unpacked';

    final streams = _findStreams(haystack);
    if (streams.isEmpty) return CsLinkResult.empty;

    final origin = getBaseUrl(url);
    final title = RegExp(r'<title[^>]*>([^<]*)<', caseSensitive: false)
            .firstMatch(res.text)
            ?.group(1)
            ?.trim() ??
        '';
    final quality = getIndexQuality(title, fallback: Qualities.p1080);
    final host = Uri.tryParse(url)?.host ?? sourceName;

    return CsLinkResult(
      links: [
        for (final s in streams)
          CsExtractorLink(
            source: sourceName,
            name: '$sourceName · $host',
            url: s,
            referer: url,
            // These CDNs check both, and reject the request without them.
            headers: {'Referer': url, 'Origin': origin},
            quality: quality,
            type: s.contains('.m3u8')
                ? ExtractorLinkType.m3u8
                : ExtractorLinkType.inferType,
          ),
      ],
      subtitles: _findSubtitles(haystack),
    );
  }

  static final RegExp _m3u8 =
      RegExp(r'''https?://[^"'\s\\]+\.m3u8[^"'\s\\]*''');
  static final RegExp _mp4 = RegExp(r'''https?://[^"'\s\\]+\.mp4[^"'\s\\]*''');
  static final RegExp _file =
      RegExp(r'''["']?file["']?\s*:\s*["']([^"']+)["']''');

  static List<String> _findStreams(String text) {
    final out = <String>{};
    for (final m in _m3u8.allMatches(text)) {
      out.add(m.group(0)!);
    }
    if (out.isEmpty) {
      for (final m in _mp4.allMatches(text)) {
        out.add(m.group(0)!);
      }
    }
    if (out.isEmpty) {
      for (final m in _file.allMatches(text)) {
        final v = m.group(1)!;
        if (v.startsWith('http')) out.add(v);
      }
    }
    // Poster/thumbnail sprites live in the same blob and are not playable.
    out.removeWhere((u) => u.contains('/thumb') || u.endsWith('.jpg') || u.endsWith('.png'));
    return out.toList();
  }

  static final RegExp _track = RegExp(
    r'''file\s*:\s*["']([^"']+\.(?:vtt|srt))["'][^}]*?label\s*:\s*["']([^"']+)["']''',
  );

  static List<CsSubtitleFile> _findSubtitles(String text) => [
        for (final m in _track.allMatches(text))
          CsSubtitleFile(lang: m.group(2)!, url: m.group(1)!),
      ];
}

/// Resolve an embed URL through the registry, falling back to a generic
/// unpack-and-scan when no registered extractor claims the host.
///
/// This is what the providers call instead of [loadExtractor] directly: the
/// multi-embed sites hand out hosts that did not exist when this was written,
/// and refusing to look at them would mean a provider that silently returns no
/// sources the week a mirror is renamed.
Future<CsLinkResult> resolveEmbed(String url, {String? referer}) async {
  if (url.isEmpty) return CsLinkResult.empty;
  final claimed = CsExtractorRegistry.instance.forUrl(url);
  if (claimed != null) {
    try {
      return await claimed.getUrl(url, referer: referer);
    } catch (_) {
      return CsLinkResult.empty;
    }
  }
  try {
    return await PackedHostExtractor.extractFromPage(url, referer: referer);
  } catch (_) {
    return CsLinkResult.empty;
  }
}
