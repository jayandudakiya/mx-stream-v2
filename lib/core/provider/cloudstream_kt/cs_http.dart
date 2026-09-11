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

import 'dart:async';
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

  /// The URL this response was requested from. NOT the post-redirect URL when
  /// redirects were followed automatically — `package:http` reports the
  /// response against the original request, so code that needs the settled
  /// location must follow hops itself with `allowRedirects: false` (see
  /// [CsHttpClient.resolveRedirect] and `CsDomains._probe`).
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

/// How this layer reaches the app's Cloudflare solver.
///
/// The solver is a native WebView behind a MethodChannel, which only exists
/// inside the Flutter app — and everything here bar the adapter is deliberately
/// Flutter-free so `tool/cs_live_check.dart` can run the providers under plain
/// `dart run`. So the transport asks for a clearance through this interface and
/// the app installs the real one at boot ([CsHttpClient.cloudflare]); with none
/// installed, requests go out bare and a challenged site simply fails, exactly
/// as before.
///
/// The implementation that matters (`cs_cloudflare_gate.dart`) delegates to the
/// SAME per-host clearance cache the JS provider engine uses, so a site cleared
/// by either engine is cleared for both, and neither pops a second solver.
abstract class CsCloudflareGate {
  /// The clearance held for [host] right now, or null when there is none.
  ({String cookie, String? ua})? clearance(String host);

  /// Solve the challenge at [url] and return the resulting clearance.
  ///
  /// [staleClearanceSent] says the request that got challenged already carried
  /// a clearance — which means that one is expired and must be dropped before
  /// re-solving, rather than trusted and replayed.
  Future<({String cookie, String? ua})?> solve(
    String url,
    String host, {
    required bool staleClearanceSent,
  });

  /// True while a passive multi-source search sweep is running. A challenge hit
  /// during one must NOT pop the blocking solver — the user did not ask to
  /// verify anything, they typed in a search box — so the request just fails
  /// and the source is absent from that sweep.
  bool get suppressed;

  /// Called instead of [solve] when a challenge lands during a suppressed
  /// sweep, so the app can record that this source *would* work once verified
  /// rather than leaving it looking simply empty.
  void noteSuppressedChallenge(String host, String url);
}

/// Marks the stretches of work that are a passive search sweep rather than
/// something the user asked for directly.
///
/// The JS provider engine does the same with a flag set around every `search`
/// call (`_suppressCfSolve` in `provider_manager.dart`) and the Kotlin side with
/// `CfClearance.searchDepth`. Cross-source search fans out over every provider
/// at once, so this is a depth counter, not a boolean: the sweep is over only
/// when the last source's search returns.
class CsSearchScope {
  CsSearchScope._();

  static const Object _sourceIdKey = #csSearchSourceId;

  static int _depth = 0;

  /// True while at least one search is in flight.
  static bool get active => _depth > 0;

  /// The source id whose search this code is running inside, so a challenge
  /// met during the sweep can be attributed to the right source. A Zone value
  /// rather than a static field because the sweep runs every source at once —
  /// a single "current source" would name whichever one happened to be last.
  static String? get currentSourceId =>
      Zone.current[_sourceIdKey] as String?;

  static Future<T> run<T>(Future<T> Function() body, {String? sourceId}) async {
    _depth++;
    try {
      if (sourceId == null) return await body();
      return await runZoned(body, zoneValues: {_sourceIdKey: sourceId});
    } finally {
      _depth--;
    }
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

  /// The app's Cloudflare solver, installed at boot. Null in the live-check
  /// harness and in tests, where requests simply go out unprotected.
  ///
  /// Note the `solveCloudflare` argument on [get] and [post]: a caller that is
  /// *deciding whether to use a host at all* (the domain probe in `CsDomains`)
  /// must pass false. Solving there pops a verification WebView for a domain
  /// about to be rejected, and — worse — can turn the challenged response into
  /// a 200, which reads as "this domain works" and pins the source to the one
  /// host that needed solving.
  CsCloudflareGate? cloudflare;

  static const Duration _defaultTimeout = Duration(seconds: 20);

  /// Builds the header map, and reports whether a Cloudflare clearance went
  /// out with it — the retry path needs to know, because being challenged
  /// while carrying a clearance means that clearance is dead.
  ({Map<String, String> headers, bool sentClearance}) _buildHeaders({
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

    // Applied AFTER the caller's headers, deliberately: a cf_clearance cookie
    // is bound to the exact User-Agent that solved it, so the solving UA has
    // to win over a provider-set one (HDHub4u sends its own) or Cloudflare
    // rejects the mismatch and we solve forever.
    final clearance = cloudflare?.clearance(uri.host);
    if (clearance == null) return (headers: out, sentClearance: false);
    _applyClearance(out, clearance);
    return (headers: out, sentClearance: true);
  }

  void _applyClearance(
    Map<String, String> headers,
    ({String cookie, String? ua}) clearance,
  ) {
    final existing = headers['cookie'];
    headers['cookie'] = (existing == null || existing.isEmpty)
        ? clearance.cookie
        : '$existing; ${clearance.cookie}';
    final ua = clearance.ua;
    if (ua != null && ua.isNotEmpty) headers['user-agent'] = ua;
  }

  /// True when a response is a Cloudflare interstitial rather than real
  /// content. Same criteria as the JS engine's detector in
  /// `provider_manager.dart`, so both engines agree on what a challenge is.
  bool _isChallenge(CsResponse res) {
    if (res.code != 403 && res.code != 503) return false;
    final server = (res.headers['server'] ?? '').toLowerCase();
    final body = res.text.toLowerCase();
    return server.contains('cloudflare') ||
        body.contains('just a moment') ||
        body.contains('challenge-platform') ||
        body.contains('cf-chl') ||
        body.contains('enable javascript and cookies');
  }

  /// One challenged response → at most one solve and one replay.
  ///
  /// Returns the original response untouched when there is no gate, when the
  /// response is not a challenge, when a passive search is in flight, or when
  /// the solve yields nothing. Never throws: a site we cannot clear must cost
  /// the user that source, not the whole screen.
  Future<CsResponse> _retryAfterSolve(
    CsResponse res,
    Uri uri,
    Map<String, String> headers,
    bool sentClearance,
    Future<CsResponse> Function(Map<String, String> headers) send,
  ) async {
    final gate = cloudflare;
    if (gate == null || !_isChallenge(res)) return res;
    if (gate.suppressed) {
      gate.noteSuppressedChallenge(uri.host, uri.toString());
      return res;
    }
    try {
      final clearance = await gate.solve(
        uri.toString(),
        uri.host,
        staleClearanceSent: sentClearance,
      );
      if (clearance == null) return res;
      final retryHeaders = Map<String, String>.from(headers);
      _applyClearance(retryHeaders, clearance);
      return await send(retryHeaders);
    } catch (_) {
      return res;
    }
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
    bool solveCloudflare = true,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = _uri(url, params);
    final built = _buildHeaders(
      headers: headers,
      referer: referer,
      cookies: cookies,
      uri: uri,
    );

    Future<CsResponse> send(Map<String, String> h) async {
      if (allowRedirects) {
        return _wrap(await _client.get(uri, headers: h).timeout(timeout));
      }
      final req = http.Request('GET', uri)..followRedirects = false;
      req.headers.addAll(h);
      final streamed = await _client.send(req).timeout(timeout);
      return _wrap(await http.Response.fromStream(streamed));
    }

    final res = await send(built.headers);
    if (!solveCloudflare) return res;
    return _retryAfterSolve(res, uri, built.headers, built.sentClearance, send);
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
    final built = _buildHeaders(
      headers: headers,
      referer: referer,
      cookies: cookies,
      uri: uri,
      contentType: contentType,
    );

    Future<CsResponse> send(Map<String, String> h) async {
      if (allowRedirects) {
        return _wrap(
          await _client.post(uri, headers: h, body: payload).timeout(timeout),
        );
      }
      final req = http.Request('POST', uri)..followRedirects = false;
      req.headers.addAll(h);
      if (payload != null) req.body = payload;
      final streamed = await _client.send(req).timeout(timeout);
      return _wrap(await http.Response.fromStream(streamed));
    }

    final res = await send(built.headers);
    return _retryAfterSolve(res, uri, built.headers, built.sentClearance, send);
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
