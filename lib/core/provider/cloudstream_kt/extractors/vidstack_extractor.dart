import '../cs_extractor.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';

/// VidStack-family players (`rpmshare`, `upnshare`, `streamp2p`, `vidcloud`) —
/// the ones whose page is a shell and whose stream comes from
/// `/api/v1/video?id=<hash>` as an AES/CBC hex blob.
///
/// The key is fixed in the player bundle; the IV is one of two, so both are
/// tried. Kotlin throws when neither works — here a failed decrypt returns no
/// links, because this is one mirror among several and the others should still
/// be offered.
class VidStackExtractor extends CsExtractor {
  @override
  String get name => 'VidStack';

  @override
  bool get requiresReferer => true;

  @override
  List<String> get hostPatterns => const [
        'rpmhub',
        'p2pplay',
        'uns.bio',
        'upnshare',
        'rpmshare',
        'streamp2p',
        'vidcloud.upns',
        'cloudy.upns',
        'vidstack',
      ];

  static const String _key = 'kiemtienmua911ca';
  static const List<String> _ivs = ['1234567890oiuytr', '0123456789abcdef'];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    // `https://host/#/abc123` → `abc123`.
    final hash = url.split('#').last.split('/').last;
    if (hash.isEmpty) return CsLinkResult.empty;
    final base = getBaseUrl(url);

    final res = await app.get(
      '$base/api/v1/video?id=$hash',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0',
      },
      referer: url,
    );
    if (!res.isOk) return CsLinkResult.empty;

    final encoded = res.text.trim();
    if (encoded.isEmpty || encoded.startsWith('{')) return CsLinkResult.empty;

    String? decrypted;
    for (final iv in _ivs) {
      decrypted = aesDecryptHex(encoded, _key, iv);
      if (decrypted != null && decrypted.contains('source')) break;
      decrypted = null;
    }
    if (decrypted == null) return CsLinkResult.empty;

    final source = RegExp(r'"source":"(.*?)"')
        .firstMatch(decrypted)
        ?.group(1)
        ?.replaceAll(r'\/', '/');
    if (source == null || source.isEmpty) return CsLinkResult.empty;

    return CsLinkResult(
      links: [
        CsExtractorLink(
          source: name,
          name: '$name · ${Uri.tryParse(url)?.host ?? ''}',
          url: source,
          referer: url,
          headers: {'Referer': url, 'Origin': base},
          quality: Qualities.p1080,
          type: source.contains('.m3u8')
              ? ExtractorLinkType.m3u8
              : ExtractorLinkType.inferType,
        ),
      ],
      subtitles: _subtitles(decrypted, base),
    );
  }

  List<CsSubtitleFile> _subtitles(String decrypted, String base) {
    final section =
        RegExp(r'"subtitle":\{(.*?)\}', dotAll: true).firstMatch(decrypted)?.group(1);
    if (section == null) return const [];
    return [
      for (final m in RegExp(r'"([^"]+)":\s*"([^"]+)"').allMatches(section))
        if (m.group(2)!.isNotEmpty)
          CsSubtitleFile(
            lang: m.group(1)!,
            url: fixUrl(m.group(2)!.split('#').first.replaceAll(r'\/', '/'), base),
          ),
    ];
  }
}
