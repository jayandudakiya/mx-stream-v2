import 'dart:convert';

import '../cs_extractor.dart';
import '../cs_http.dart';
import '../cs_main_api.dart';

import '../cs_utils.dart';
import 'packed_host_extractor.dart';

/// GDMirrorbot and its white-labels (`streams.iqsmartgames.com`,
/// `gdmirrorbot.nl`, …) — the mirror hub MultiMovies puts behind its
/// "gdmirror" player option.
///
/// It is a hub, not a player: one call fans out to half a dozen real hosts
/// (StreamHG, EarnVids, RpmShare, UpnShare, StreamP2P, Byse), each of which is
/// then resolved by whichever extractor claims it. That fan-out is the reason
/// this provider still yields Hindi audio when any single mirror is dead.
///
/// Two details that are not obvious from the Kotlin and cost a whole provider
/// if missed:
///  * the file API rejects the request without a `Referer` naming the embed
///    page it was called from (`{"error":"Invalid dg"}`);
///  * series use a different endpoint (`myseriesapi`, with `season`/`epname`)
///    from movies (`mymovieapi`), and the movie endpoint answers "Invalid ID"
///    for a series id rather than failing loudly.
class GdMirrorExtractor extends CsExtractor {
  @override
  String get name => 'GDMirror';

  @override
  bool get requiresReferer => true;

  @override
  List<String> get hostPatterns =>
      const ['gdmirrorbot', 'iqsmartgames', 'gdmirror', 'embedhelper'];

  /// How many of the releases the API lists to resolve. Each one costs a
  /// fan-out, and the top entries are the highest-quality rips.
  static const int _maxReleases = 2;

  @override
  Future<CsLinkResult> getUrl(String url, {String? referer}) async {
    final page = await app.get(url, referer: referer);
    if (!page.isOk) return CsLinkResult.empty;

    final host = _playerHost(page.text, url);
    final slugs = await _fileSlugs(page.text, url);
    if (slugs.isEmpty) return CsLinkResult.empty;

    var result = CsLinkResult.empty;
    for (final sid in slugs.take(_maxReleases)) {
      result = result + await _resolveSid(sid, host, url);
    }
    return result;
  }

  String _playerHost(String body, String url) {
    final playerBase =
        RegExp(r'player_base\s*=\s*"([^"]+)"').firstMatch(body)?.group(1);
    if (playerBase != null && playerBase.isNotEmpty) return getBaseUrl(playerBase);
    return getBaseUrl(url);
  }

  /// The release list for this title, newest/best first.
  Future<List<String>> _fileSlugs(String body, String url) async {
    // Hubs without a `key=` embed the slug in the path instead of behind an API.
    if (!url.contains('key=')) {
      final slug = url.split('embed/').last.split('?').first;
      return slug.isEmpty ? const [] : [slug];
    }

    final finalId = RegExp(r'FinalID\s*=\s*"([^"]+)"').firstMatch(body)?.group(1);
    final myKey = RegExp(r'myKey\s*=\s*"([^"]+)"').firstMatch(body)?.group(1);
    if (finalId == null || myKey == null) return const [];

    final idType =
        RegExp(r'idType\s*=\s*"([^"]+)"').firstMatch(body)?.group(1) ?? 'imdbid';
    final apiBase =
        RegExp(r'api_url\s*=\s*"([^"]+)"').firstMatch(body)?.group(1) ?? getBaseUrl(url);
    final season = RegExp(r'\bseason\s*=\s*"([^"]+)"').firstMatch(body)?.group(1);
    final epname = RegExp(r'\bepname\s*=\s*"([^"]+)"').firstMatch(body)?.group(1);

    final apiUrl = (season != null && epname != null)
        ? '$apiBase/myseriesapi?$idType=$finalId'
            '&season=$season&epname=${Uri.encodeComponent(epname)}&key=$myKey'
        : '$apiBase/mymovieapi?$idType=$finalId&key=$myKey';

    final res = await app.get(
      apiUrl,
      referer: url,
      headers: {'Origin': getBaseUrl(url)},
    );
    if (!res.isOk) return const [];

    try {
      final json = jsonDecode(res.text);
      if (json is! Map || json['success'] != true) return const [];
      final data = json['data'];
      if (data is! List) return const [];
      return [
        for (final entry in data)
          if (entry is Map && entry['fileslug'] is String && (entry['fileslug'] as String).isNotEmpty)
            entry['fileslug'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// One release slug → every mirror the hub knows for it, resolved.
  Future<CsLinkResult> _resolveSid(String sid, String host, String referer) async {
    final res = await app.post(
      '$host/embedhelper.php',
      data: {'sid': sid},
      referer: referer,
      headers: {'Origin': host},
    );
    if (!res.isOk) return CsLinkResult.empty;

    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(res.text);
      if (decoded is! Map<String, dynamic>) return CsLinkResult.empty;
      root = decoded;
    } catch (_) {
      return CsLinkResult.empty;
    }

    final siteUrls = root['siteUrls'];
    if (siteUrls is! Map) return CsLinkResult.empty;
    final friendly = root['siteFriendlyNames'];

    // `mresult` is either an object or the same object base64-encoded.
    Map? mresult;
    final raw = root['mresult'];
    if (raw is Map) {
      mresult = raw;
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(csBase64Decode(raw));
        if (decoded is Map) mresult = decoded;
      } catch (_) {
        mresult = null;
      }
    }
    if (mresult == null) return CsLinkResult.empty;

    final targets = <({String label, String url})>[];
    for (final key in siteUrls.keys) {
      if (!mresult.containsKey(key)) continue;
      final base = siteUrls[key]?.toString();
      final path = mresult[key]?.toString();
      if (base == null || path == null || base.isEmpty || path.isEmpty) continue;
      targets.add((
        label: (friendly is Map ? friendly[key]?.toString() : null) ?? key.toString(),
        url: '${base.replaceAll(RegExp(r'/$'), '')}/${path.replaceAll(RegExp(r'^/'), '')}',
      ));
    }
    if (targets.isEmpty) return CsLinkResult.empty;

    final batches = await amap<({String label, String url}), CsLinkResult>(
      targets,
      (t) async {
        try {
          return await resolveEmbed(t.url, referer: referer);
        } catch (_) {
          return CsLinkResult.empty;
        }
      },
      concurrency: 4,
    );

    var out = CsLinkResult.empty;
    for (final b in batches) {
      out = out + b;
    }
    return out;
  }
}
