import 'package:html/dom.dart' as dom;

import '../cs_dom.dart';
import '../cs_extractor.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';

/// HubCloud and the two lockers that funnel into it — the link layer behind
/// HDHub4u and 4KHDHub.
///
/// Shape as of this port: a `/drive/<id>` page carries `a#download` pointing at
/// a `hubcloud.php` host page, and that page lists one button per mirror
/// (FSL, 10Gbps, Download File, BuzzServer, Pixeldrain, …). The buttons are
/// matched on their visible text because the class names change between
/// mirrors while the labels do not.
///
/// This is deliberately a separate class from the app's existing
/// `VCloudExtractor`: that one is VegaMovies/RogMovies' V-Cloud flow and is
/// left exactly as it is, so nothing about those two providers can change.
class HubCloudExtractor extends CsExtractor {
  @override
  String get name => 'HubCloud';

  @override
  List<String> get hostPatterns => const ['hubcloud.', 'hubcloud/', 'gamerxyt.com'];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    final base = getBaseUrl(url);
    final host = await _hostPage(url, base);
    if (host == null) return CsLinkResult.empty;

    final page = await app.get(host, referer: url);
    if (!page.isOk) return CsLinkResult.empty;
    final doc = page.document;

    final header = doc.selectFirst('div.card-header')?.textTrim ?? '';
    final size = doc.selectFirst('i#size')?.textTrim ?? '';
    final quality = getIndexQuality(header, fallback: Qualities.p1080);
    final label = _label(header, size);

    final buttons = doc
        .select('a')
        .where((a) => a.attr('class').contains('btn') && a.attr('href').isNotEmpty)
        .toList();

    final links = await amapSafe<dom.Element, CsExtractorLink>(
      buttons,
      (a) => _fromButton(a.attr('href'), a.textTrim, quality, label),
      concurrency: 6,
    );
    return CsLinkResult(links: links);
  }

  /// Step one: `/drive/<id>` → the `hubcloud.php` page that lists mirrors.
  /// A URL that already IS that page is passed straight through.
  Future<String?> _hostPage(String url, String base) async {
    if (url.contains('hubcloud.php')) return url;
    final res = await app.get(url);
    if (!res.isOk) return null;
    final doc = res.document;

    final direct = doc.selectFirst('#download')?.attr('href') ?? '';
    if (direct.isNotEmpty) return fixUrl(direct, base);

    // Older mirrors hide the same target behind `atob(atob('…'))` or a bare
    // `var url = '…'` instead of an anchor.
    for (final script in doc.select('script')) {
      final body = script.text;
      final double = RegExp(
        '''atob\\s*\\(\\s*atob\\s*\\(\\s*['"]([^'"]+)['"]\\s*\\)\\s*\\)''',
      ).firstMatch(body);
      if (double != null) {
        final decoded = csBase64Decode(csBase64Decode(double.group(1)!));
        if (decoded.startsWith('http') || decoded.startsWith('/')) {
          return fixUrl(decoded, base);
        }
      }
      final bare = RegExp(
        '''var\\s+url\\s*=\\s*['"](https?://[^'"]+)['"]''',
      ).firstMatch(body);
      if (bare != null) return bare.group(1);
    }
    return null;
  }

  Future<List<CsExtractorLink>> _fromButton(
    String href,
    String text,
    int quality,
    String label,
  ) async {
    CsExtractorLink link(String server, String url) => CsExtractorLink(
          source: name,
          name: '$name · $server $label',
          url: url,
          quality: quality,
          qualityLabel: _qualityLabel(quality, label),
          type: ExtractorLinkType.inferType,
        );

    final t = text.toLowerCase();

    if (t.contains('fsl server')) return [link('FSL Server', href)];
    if (t.contains('fslv2')) return [link('FSLv2', href)];
    if (t.contains('s3 server')) return [link('S3 Server', href)];
    if (t.contains('mega server')) return [link('Mega Server', href)];
    if (t.contains('download file')) return [link('Direct', href)];

    if (t.contains('pixeldra') || t.contains('pixel')) {
      final pixelBase = getBaseUrl(href);
      final id = href.split('/').last.split('?').first;
      final url = href.toLowerCase().contains('download')
          ? href
          : '$pixelBase/api/file/$id?download';
      return [link('Pixeldrain', url)];
    }

    if (t.contains('buzzserver') || t.contains('buzz server')) {
      // `hx-redirect` only exists on the un-followed response — following the
      // redirect loses the very header this needs.
      final res = await app.get(
        '$href/download',
        referer: href,
        allowRedirects: false,
      );
      final hx = res.headers['hx-redirect'] ?? '';
      if (hx.isEmpty) return const [];
      return [link('BuzzServer', hx.startsWith('http') ? hx : '${getBaseUrl(href)}$hx')];
    }

    if (t.contains('10gbps') || t.contains('server : 10')) {
      final resolved = await _tenGbps(href);
      return resolved == null ? const [] : [link('10Gbps', resolved)];
    }

    // Telegram hand-offs open an app, not a stream; anything else unrecognised
    // goes to the registry in case another extractor claims it.
    if (t.contains('telegram')) return const [];
    final nested = await loadExtractor(href);
    return nested.links;
  }

  /// The 10Gbps button redirects one or more times and finally parks the real
  /// file behind a `link=` query parameter.
  Future<String?> _tenGbps(String href) async {
    if (href.contains('link=')) return Uri.decodeFull(href.split('link=').last);
    var current = href;
    for (var i = 0; i < 4; i++) {
      final res = await app.get(current, allowRedirects: false);
      final loc = res.headers['location'];
      if (loc == null || loc.isEmpty) return null;
      if (loc.contains('link=')) return Uri.decodeFull(loc.split('link=').last);
      current = loc.startsWith('http')
          ? loc
          : Uri.parse(current).resolve(loc).toString();
    }
    return null;
  }

  static String _label(String header, String size) {
    final name = header.isEmpty ? '' : cleanFileName(header);
    final parts = [
      if (name.isNotEmpty) '[$name]',
      if (size.isNotEmpty) '[$size]',
    ];
    return parts.join('');
  }

  static String _qualityLabel(int quality, String label) {
    final size = RegExp(r'\[([\d.]+\s*[KMGT]B)\]').firstMatch(label)?.group(1);
    final q = Qualities.label(quality);
    return size == null ? q : '$q · $size';
  }
}

/// HubDrive — a one-hop wrapper whose success button points into HubCloud.
class HubDriveExtractor extends CsExtractor {
  @override
  String get name => 'HubDrive';

  @override
  List<String> get hostPatterns => const ['hubdrive.'];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    final res = await app.get(url, referer: referer);
    if (!res.isOk) return CsLinkResult.empty;
    final href = res.document
            .selectFirst('.btn.btn-primary.btn-user.btn-success1.m-1')
            ?.attr('href') ??
        res.document
            .select('a')
            .where((a) => a.attr('class').contains('btn-success'))
            .map((a) => a.attr('href'))
            .firstWhere((h) => h.isNotEmpty, orElse: () => '');
    if (href.isEmpty) return CsLinkResult.empty;
    return loadExtractor(href, referer: 'HubDrive');
  }
}

/// HubCdn — a base64 `r=` parameter wrapping an HLS URL after `link=`.
class HubCdnExtractor extends CsExtractor {
  @override
  String get name => 'HubCdn';

  @override
  List<String> get hostPatterns => const ['hubcdn.'];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    final res = await app.get(url, referer: referer);
    if (!res.isOk) return CsLinkResult.empty;
    final encoded = RegExp(r'r=([A-Za-z0-9+/=]+)').firstMatch(res.text)?.group(1);
    if (encoded == null || encoded.isEmpty) return CsLinkResult.empty;
    final decoded = csBase64Decode(encoded);
    final stream = decoded.contains('link=') ? decoded.split('link=').last : decoded;
    if (!stream.startsWith('http')) return CsLinkResult.empty;
    return CsLinkResult(
      links: [
        CsExtractorLink(
          source: name,
          name: name,
          url: stream,
          referer: url,
          quality: getIndexQuality(url, fallback: Qualities.p1080),
          type: stream.contains('.m3u8')
              ? ExtractorLinkType.m3u8
              : ExtractorLinkType.inferType,
        ),
      ],
    );
  }
}
