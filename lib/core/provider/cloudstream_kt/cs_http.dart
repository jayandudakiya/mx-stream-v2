/// Dart stand-in for CloudStream's `com.lagradost.cloudstream3.app` — the
/// networking object every Kotlin provider calls. Keeping the same surface
/// (`app.get(url, headers: ..., referer: ...)` returning something with
/// `.text` and `.document`) is what lets a `.cs3` provider be transcribed
/// almost line-for-line instead of rewritten.
///
/// Differences from Kotlin, all deliberate:
///  * No `parsed<T>()` — Dart has no reified generics, so callers use
///    [CsResponse.json] and read the map.
///  * `documentLarge` is an alias for [CsResponse.document]; the Kotlin split
///    exists only to raise Jsoup's body-size cap, which Dart's parser lacks.
///  * Cookies are remembered per host in a process-wide jar so the multi-step
///    form flows (hrefli, driveseed's resume bot) work without the caller
///    threading a jar through by hand.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

const String csDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// A single HTTP response, shaped like Kotlin's `NiceResponse`.
class CsResponse {
  CsResponse({
    required this.code,
    required this.text,
    required this.url,
    required this.headers,
    required this.cookies,
  });

  final int code;
  final String text;

  /// Final URL after redirects — providers use it to learn the live domain.
  final String url;
  final Map<String, String> headers;
  final Map<String, String> cookies;

  bool get isOk => code >= 200 && code < 400;

  dom.Document? _doc;

  /// Parsed DOM. Cached: several ported providers call `.document` repeatedly
  /// on one response and re-parsing a 300 KB index page each time is wasteful.
  dom.Document get document => _doc ??= html_parser.parse(text);

  /// Kotlin alias — same thing here (see the class doc).
  dom.Document get documentLarge => document;

  /// Decoded JSON, or null when the body is not JSON.
  dynamic get json {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// [json] as a map, or an empty map — saves a cast at every call site.
  Map<String, dynamic> get jsonMap {
    final j = json;
    return j is Map<String, dynamic> ? j : const {};
  }
}

/// Cookies remembered per host across calls, so multi-step flows keep session.
class _CookieJar {
  final Map<String, Map<String, String>> _byHost = {};

  Map<String, String> forHost(String host) => _byHost[host] ?? const {};

  void store(String host, Iterable<String> setCookieHeaders) {
    if (setCookieHeaders.isEmpty) return;
    final bucket = _byHost.putIfAbsent(host, () => {});
    for (final raw in setCookieHeaders) {
      // A Set-Cookie line is `name=value; Path=/; HttpOnly` — only the first
      // pair is the cookie, the rest are attributes.
      for (final part in raw.split(RegExp(r',(?=[^;]+?=)'))) {
        final pair = part.split(';').first.trim();
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        bucket[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
      }
    }
  }
}

/// The `app` object. Use the [app] top-level instance.
class CsHttpClient {
  CsHttpClient._();

  final _CookieJar _jar = _CookieJar();
  final http.Client _client = http.Client();

  static const Duration _defaultTimeout = Duration(seconds: 20);

  Map<String, String> _buildHeaders({
    Map<String, String>? headers,
    String? referer,
    Map<String, String>? cookies,
    required Uri uri,
    String? contentType,
  }) {
    // Lower-cased keys throughout so a caller-supplied `User-Agent` replaces
    // the default rather than being sent alongside it.
    final out = <String, String>{'user-agent': csDefaultUserAgent};
    if (contentType != null) out['content-type'] = contentType;
    if (referer != null && referer.isNotEmpty) out['referer'] = referer;

    final merged = <String, String>{..._jar.forHost(uri.host), ...?cookies};
    if (merged.isNotEmpty) {
      out['cookie'] = merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    headers?.forEach((k, v) => out[k.toLowerCase()] = v);
    return out;
  }

  CsResponse _wrap(http.Response r) {
    final host = r.request?.url.host;
    if (host != null) {
      final sc = r.headers['set-cookie'];
      if (sc != null) _jar.store(host, [sc]);
    }
    return CsResponse(
      code: r.statusCode,
      text: r.body,
      url: r.request?.url.toString() ?? '',
      headers: r.headers,
      cookies: host == null ? const {} : _jar.forHost(host),
    );
  }

  Uri _uri(String url, Map<String, String>? params) {
    final u = Uri.parse(url);
    if (params == null || params.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...params});
  }

  /// `app.get(...)`. With [allowRedirects] false the response carries the 3xx
  /// status and its `location`/`hx-redirect` headers — several extractors read
  /// exactly those and get nothing once the redirect has been followed.
  Future<CsResponse> get(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? params,
    Map<String, String>? cookies,
    String? referer,
    bool allowRedirects = true,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = _uri(url, params);
    final h = _buildHeaders(
      headers: headers,
      referer: referer,
      cookies: cookies,
      uri: uri,
    );
    if (allowRedirects) {
      final r = await _client.get(uri, headers: h).timeout(timeout);
      return _wrap(r);
    }
    final req = http.Request('GET', uri)..followRedirects = false;
    req.headers.addAll(h);
    final streamed = await _client.send(req).timeout(timeout);
    final r = await http.Response.fromStream(streamed);
    return _wrap(r);
  }

  /// `app.post(...)`. Exactly one body form is used, in this order:
  /// [json] (a JSON object body), [data] (url-encoded form), [body] (raw).
  Future<CsResponse> post(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? params,
    Map<String, String>? cookies,
    Map<String, String>? data,
    Object? json,
    String? body,
    String? referer,
    bool allowRedirects = true,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = _uri(url, params);
    String? payload;
    String? contentType;
    if (json != null) {
      payload = jsonEncode(json);
      contentType = 'application/json; charset=utf-8';
    } else if (data != null) {
      payload = data.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      contentType = 'application/x-www-form-urlencoded';
    } else if (body != null) {
      payload = body;
    }
    final h = _buildHeaders(
      headers: headers,
      referer: referer,
      cookies: cookies,
      uri: uri,
      contentType: contentType,
    );
    if (allowRedirects) {
      final r = await _client.post(uri, headers: h, body: payload).timeout(timeout);
      return _wrap(r);
    }
    final req = http.Request('POST', uri)..followRedirects = false;
    req.headers.addAll(h);
    if (payload != null) req.body = payload;
    final streamed = await _client.send(req).timeout(timeout);
    final r = await http.Response.fromStream(streamed);
    return _wrap(r);
  }

  /// Follows `Location` hops by hand and returns the final URL without
  /// downloading a body — the "10Gbps"/`link=` redirect probe several
  /// extractors do.
  Future<String?> resolveRedirect(String url, {int maxHops = 6}) async {
    var current = url;
    for (var i = 0; i < maxHops; i++) {
      try {
        final r = await get(current, allowRedirects: false);
        final loc = r.headers['location'];
        if (loc == null || loc.isEmpty) return current;
        current = loc.startsWith('http')
            ? loc
            : Uri.parse(current).resolve(loc).toString();
      } catch (_) {
        return current;
      }
    }
    return current;
  }
}

/// The shared `app` instance ported providers call.
final CsHttpClient app = CsHttpClient._();
