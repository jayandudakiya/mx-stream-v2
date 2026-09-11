import 'dart:convert';
import 'dart:developer' as developer;

import 'package:html/dom.dart' as dom;

import '../cs_dom.dart';
import '../cs_extractor.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';
import '../cs_models.dart';
import '../cs_types.dart';
import '../cs_utils.dart';

/// Driveseed / Driveleech — the locker UHDMovies funnels into once the hrefli
/// gate has been passed.
///
/// A file page lists up to five ways to get the same file; each is a different
/// hop, so they are resolved in parallel and every one that answers becomes its
/// own row in the player's source sheet.
class DriveseedExtractor extends CsExtractor {
  @override
  String get name => 'Driveseed';

  @override
  List<String> get hostPatterns =>
      const ['driveseed.', 'driveleech.', 'video-seed.', 'video-leech.'];

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    final base = getBaseUrl(url);

    // `r?key=` pages are a JS redirect stub, not the file page.
    var pageUrl = url;
    if (url.contains('r?key=')) {
      final stub = await app.get(url);
      final path = _between(stub.text, 'replace("', '")');
      if (path == null || path.isEmpty) return CsLinkResult.empty;
      pageUrl = fixUrl(path, base);
    }

    final res = await app.get(pageUrl, referer: referer);
    if (!res.isOk) return CsLinkResult.empty;

    // Driveseed started requiring an account for file pages: the mirror list is
    // replaced by a "Login to Download" button. Verified against every button on
    // a live UHDMovies post — all six file pages answer 200 and all six are
    // gated, so this is the site's policy, not a per-file quirk, and it breaks
    // the upstream Kotlin plugin the same way.
    //
    // Called out explicitly instead of falling through to "no buttons matched",
    // because the two look identical from the outside and only one of them is
    // something a selector fix could ever recover.
    if (_isLoginWalled(res.text)) {
      developer.log(
        'file page requires login, no mirrors available: $pageUrl',
        name: 'Driveseed',
      );
      return CsLinkResult.empty;
    }

    final doc = res.document;

    final rawName = (doc.selectFirst('li.list-group-item')?.textTrim ?? '')
        .replaceFirst('Name : ', '')
        .trim();
    final size = (doc.select('li.list-group-item').length > 2
            ? doc.select('li.list-group-item')[2].textTrim
            : '')
        .replaceFirst('Size : ', '')
        .trim();
    final quality = getIndexQuality(rawName, fallback: Qualities.p1080);
    final label = [
      if (rawName.isNotEmpty) '[${cleanFileName(rawName)}]',
      if (size.isNotEmpty) '[$size]',
    ].join();

    final buttons = doc
        .select('div.text-center a')
        .where((a) => a.attr('href').isNotEmpty)
        .toList();

    final links = await amapSafe<dom.Element, CsExtractorLink>(
      buttons,
      (a) async {
        final href = fixUrl(a.attr('href'), base);
        final text = a.textTrim.toLowerCase();
        String? resolved;
        String server;

        if (text.contains('instant download')) {
          server = 'Instant';
          resolved = await _instant(href);
        } else if (text.contains('resume cloud')) {
          server = 'ResumeCloud';
          resolved = await _resumeCloud(href);
        } else if (text.contains('resume worker bot')) {
          server = 'ResumeBot';
          resolved = await _resumeBot(href);
        } else if (text.contains('direct links')) {
          final direct = await _directLinks(href);
          return direct
              .map((l) => _link('CF Direct', l, quality, size, label))
              .toList();
        } else if (text.contains('cloud download')) {
          server = 'Cloud';
          resolved = href;
        } else {
          return const <CsExtractorLink>[];
        }

        if (resolved == null || !resolved.startsWith('http')) {
          return const <CsExtractorLink>[];
        }
        return [_link(server, resolved, quality, size, label)];
      },
      concurrency: 5,
    );

    return CsLinkResult(links: links);
  }

  CsExtractorLink _link(
    String server,
    String url,
    int quality,
    String size,
    String label,
  ) =>
      CsExtractorLink(
        source: name,
        name: '$name · $server $label',
        url: url,
        quality: quality,
        qualityLabel:
            size.isEmpty ? Qualities.label(quality) : '${Qualities.label(quality)} · $size',
        type: ExtractorLinkType.inferType,
      );

  /// `Instant Download` posts the `url=` token back to the host's own `/api`.
  Future<String?> _instant(String href) async {
    final host = Uri.tryParse(href)?.host;
    if (host == null || host.isEmpty) return null;
    final token = href.contains('url=') ? href.split('url=').last : '';
    if (token.isEmpty) return null;
    final res = await app.post(
      'https://$host/api',
      data: {'keys': token},
      referer: href,
      headers: {'x-token': host},
    );
    final url = _between(res.text, 'url":"', '","name');
    return url?.replaceAll(r'\/', '/');
  }

  Future<String?> _resumeCloud(String href) async {
    final res = await app.get(href);
    if (!res.isOk) return null;
    final a = res.document
        .select('a')
        .where((e) => e.attr('class').contains('btn-success'))
        .map((e) => e.attr('href'))
        .where((h) => h.startsWith('http'));
    return a.isEmpty ? null : a.first;
  }

  Future<List<String>> _directLinks(String href) async {
    final res = await app.get('$href?type=1');
    if (!res.isOk) return const [];
    return res.document
        .select('a.btn-success')
        .map((e) => e.attr('href'))
        .where((h) => h.startsWith('http'))
        .toList();
  }

  /// The worker bot hands back a signed URL only in response to a token the
  /// page embeds, posted with the session cookie it just set.
  Future<String?> _resumeBot(String href) async {
    final res = await app.get(href);
    if (!res.isOk) return null;
    final token = RegExp(r"formData\.append\('token',\s*'([a-f0-9]+)'\)")
        .firstMatch(res.text)
        ?.group(1);
    final path = RegExp(r"fetch\('/download\?id=([a-zA-Z0-9/+]+)'")
        .firstMatch(res.text)
        ?.group(1);
    if (token == null || path == null) return null;

    final base = href.split('/download').first;
    final post = await app.post(
      '$base/download?id=$path',
      data: {'token': token},
      referer: href,
      headers: {'Accept': '*/*', 'Origin': base, 'Sec-Fetch-Site': 'same-origin'},
    );
    try {
      final url = (jsonDecode(post.text) as Map)['url'];
      return url is String && url.startsWith('http') ? url : null;
    } catch (_) {
      return null;
    }
  }

  static String? _between(String source, String start, String end) {
    final i = source.indexOf(start);
    if (i < 0) return null;
    final from = i + start.length;
    final j = source.indexOf(end, from);
    return j < 0 ? null : source.substring(from, j);
  }
}

/// The `unblockedgames`/hrefli gate UHDMovies puts in front of every download
/// button: three chained form posts, a `?go=` token read back out of an inline
/// script, and a meta-refresh that finally names the Driveseed file page.
///
/// Not a [CsExtractor] — it produces a URL for one, not a playable link.
Future<String?> bypassHrefli(String url) async {
  // Typed, not `dynamic`: `selectFirst`/`select`/`attr` are extension members
  // from `cs_dom.dart`, and Dart never applies an extension to a `dynamic`
  // receiver — every call here was a runtime NoSuchMethodError, which the
  // caller's catch-all turned into "this mirror has no links".
  String? formAction(dom.Document doc) =>
      doc.selectFirst('form#landing')?.attr('action');

  Map<String, String> formData(dom.Document doc) {
    final out = <String, String>{};
    for (final input in doc.select('form#landing input')) {
      final n = input.attr('name');
      if (n.isNotEmpty) out[n] = input.attr('value');
    }
    return out;
  }

  try {
    final host = getBaseUrl(url);

    var res = await app.get(url);
    var action = formAction(res.document);
    var data = formData(res.document);
    if (action == null || action.isEmpty) return null;

    res = await app.post(action, data: data);
    action = formAction(res.document);
    data = formData(res.document);
    if (action == null || action.isEmpty) return null;

    res = await app.post(action, data: data);
    final token = RegExp(r'\?go=([^"&\s]+)').firstMatch(res.text)?.group(1);
    if (token == null) return null;

    res = await app.get('$host?go=$token', cookies: {token: data['_wp_http2'] ?? ''});
    final refresh = res.document
        .selectFirst('meta[http-equiv=refresh]')
        ?.attr('content');
    if (refresh == null || !refresh.contains('url=')) return null;
    final driveUrl = refresh.split('url=').last;

    final drive = await app.get(driveUrl);
    final i = drive.text.indexOf('replace("');
    if (i < 0) return null;
    final from = i + 'replace("'.length;
    final j = drive.text.indexOf('")', from);
    if (j < 0) return null;
    final path = drive.text.substring(from, j);
    if (path.isEmpty || path == '/404') return null;
    return fixUrl(path, getBaseUrl(driveUrl));
  } catch (_) {
    return null;
  }
}

/// True when a Driveseed/Driveleech file page is the signed-out wall rather
/// than the mirror list.
bool _isLoginWalled(String body) =>
    body.contains('/login?ref=') || body.contains('Login to Download');
