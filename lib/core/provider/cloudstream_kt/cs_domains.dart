import 'dart:convert';
import 'dart:developer' as developer;

import '../native/provider_config.dart';
import 'cs_http.dart';
import 'cs_utils.dart';

/// Live base-URL resolution for the ported CloudStream providers.
///
/// Every one of these sites rotates domain on a scale of weeks, and the Kotlin
/// plugins each read a remote manifest at load time. Two manifests are in play
/// (the plugin repos disagree on both the URL and the key casing), so this
/// consults, in order:
///
///  1. phisher's `domains.json` — keys like `HDHUB4u`, `MultiMovies`;
///  2. this app's existing [ProviderConfig], which already owns SaurabhKaperwan's
///     `urls.json` plus its own bundled fallbacks, its in-flight collapsing and
///     its post-failure backoff — reused rather than re-implemented so the two
///     engines cannot drift onto different domains for the same site;
///  3. [_bundled] below, for the keys neither manifest carries.
///
/// Lookups are case-insensitive because the manifests are not consistent.
class CsDomains {
  CsDomains._();

  static const String _phisherManifest =
      'https://raw.githubusercontent.com/phisher98/TVVVV/refs/heads/main/domains.json';

  /// Last-resort domains, current as of the port. Only ever consulted when
  /// both manifests are unreachable — several ISPs block raw.githubusercontent
  /// on broadband — so a blocked resolver degrades to "possibly stale" rather
  /// than to an empty base URL and a malformed request.
  static const Map<String, String> _bundled = {
    'multimovies': 'https://multimovies.beer',
    'hdhub4u': 'https://new5.hdhub4u.cl',
    'uhdmovies': 'https://uhdmovies.autos',
    '4khdhub': 'https://4khdhub.one',
    'hubcloud': 'https://hubcloud.cx',
    'hubdrive': 'https://hubdrive.tips',
    'driveseed': 'https://driveseed.org',
    'gdflix': 'https://new3.gdflix.io',
  };

  /// Other domains each site is known to answer on, tried in order when the
  /// manifest's pick does not respond.
  ///
  /// The manifests go stale in a specific way: they are updated when a site
  /// announces a move, not when a domain stops working. As of this writing
  /// `MultiMovies` is listed as `multimovies.makeup`, which answers every
  /// request with a Cloudflare block page, while `multimovies.beer` serves the
  /// site normally. Without this list that source is simply dead, and no amount
  /// of Cloudflare solving fixes it — the block is not a solvable challenge.
  ///
  /// Drawn from `url-sources.json`, which carries several domains per site.
  static const Map<String, List<String>> _alternates = {
    'multimovies': [
      'https://multimovies.beer',
      'https://multimovies.motorcycles',
      'https://multimovies.casa',
      'https://multimovies.makeup',
    ],
    'hdhub4u': ['https://new5.hdhub4u.cl', 'https://new4.hdhub4u.cl'],
    'uhdmovies': ['https://uhdmovies.autos'],
    '4khdhub': ['https://4khdhub.one'],
  };

  static Map<String, String> _cache = {};
  static Future<Map<String, String>>? _inFlight;
  static DateTime? _lastFailure;
  static const Duration _failureCooldown = Duration(minutes: 5);

  /// Domains that answered, per key, with when they were probed.
  static final Map<String, ({DateTime at, String url})> _aliveCache = {};
  static final Map<String, Future<String>> _aliveInFlight = {};

  /// Long enough that a session costs one probe per source, short enough that
  /// a site coming back does not stay written off for the whole app run.
  static const Duration _aliveTtl = Duration(minutes: 30);

  static Future<Map<String, String>> _phisherDomains() async {
    if (_cache.isNotEmpty) return _cache;
    final failedAt = _lastFailure;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _failureCooldown) {
      return _cache;
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    final fetch = () async {
      try {
        final res = await app.get(
          _phisherManifest,
          timeout: const Duration(seconds: 12),
        );
        if (res.code == 200) {
          final decoded = jsonDecode(res.text);
          if (decoded is Map) {
            _cache = {
              for (final e in decoded.entries)
                e.key.toString().toLowerCase(): e.value.toString(),
            };
            _lastFailure = null;
            return _cache;
          }
        }
        _lastFailure = DateTime.now();
      } catch (e) {
        _lastFailure = DateTime.now();
        // `dart:developer` rather than `debugPrint`: everything under
        // `cloudstream_kt/` except the adapter is deliberately Flutter-free, so
        // `tool/cs_live_check.dart` can exercise the providers and extractors
        // against the live sites with a plain `dart run`.
        developer.log('phisher manifest unavailable: $e', name: 'CsDomains');
      }
      return _cache;
    }();

    _inFlight = fetch;
    try {
      return await fetch;
    } finally {
      _inFlight = null;
    }
  }

  /// The live base URL for [key] (`'multimovies'`, `'hdhub4u'`, …), without a
  /// trailing slash. Never empty — a total resolver failure still returns the
  /// bundled domain.
  static Future<String> resolve(String key) async {
    final k = key.toLowerCase();

    final phisher = await _phisherDomains();
    final fromPhisher = phisher[k];
    if (fromPhisher != null && fromPhisher.isNotEmpty) return _trim(fromPhisher);

    // ProviderConfig already returns its own bundled fallback when the
    // manifest it owns is unreachable, so an empty answer here means "this key
    // is unknown to it", not "the network is down".
    final fromApp = await ProviderConfig.resolveBaseUrl(k);
    if (fromApp.isNotEmpty) return _trim(fromApp);

    return _trim(_bundled[k] ?? '');
  }

  /// Rewrites [url]'s host to the live domain for [key], keeping path and
  /// query. Used when a stored link (or a search index) still points at a
  /// domain that has since moved — HDHub4u's search API is months stale.
  static Future<String> rehost(String url, String key) async {
    try {
      // `resolveAlive`, so a rehosted link lands on a domain that answers —
      // the whole point of rehosting is that the URL we were given does not.
      final live = await resolveAlive(key);
      if (live.isEmpty) return url;
      final u = Uri.parse(url);
      final base = Uri.parse(live);
      return u.replace(scheme: base.scheme, host: base.host, port: base.port).toString();
    } catch (_) {
      return url;
    }
  }

  /// The live base URL for [key] that actually **answers**.
  ///
  /// [resolve] trusts the manifest; this verifies it. The manifest's pick is
  /// tried first and wins whenever it responds, so the normal case costs one
  /// cheap request per source per [_aliveTtl] and the behaviour is unchanged.
  /// Only when that domain is dead or serving a block page do the known
  /// [_alternates] get their turn.
  ///
  /// A Cloudflare *challenge* does not disqualify a domain outright, but it does
  /// lose to a clean one: the app can solve a challenge (see
  /// `cs_cloudflare_gate.dart`), but doing so costs the user a verification
  /// WebView, so a sibling domain that just serves the site is strictly better.
  /// When nothing is clean the challenged domain is returned and the solver
  /// deals with it.
  ///
  /// Never empty unless the key is unknown everywhere; never throws.
  static Future<String> resolveAlive(String key) async {
    final k = key.toLowerCase();

    final cached = _aliveCache[k];
    if (cached != null && DateTime.now().difference(cached.at) < _aliveTtl) {
      return cached.url;
    }
    final existing = _aliveInFlight[k];
    if (existing != null) return existing;

    final probe = _probeCandidates(k).whenComplete(() {
      _aliveInFlight.remove(k);
    });
    _aliveInFlight[k] = probe;
    return probe;
  }

  static Future<String> _probeCandidates(String k) async {
    final preferred = await resolve(k);

    // Manifest pick first, then the alternates, de-duplicated. `toSet` keeps
    // insertion order, so priority is preserved.
    final candidates = <String>{
      if (preferred.isNotEmpty) preferred,
      ...?_alternates[k]?.map(_trim),
    }.toList();
    if (candidates.isEmpty) return '';

    String? challenged;
    for (final candidate in candidates) {
      final verdict = await _probe(candidate);
      if (verdict.state == _ProbeState.ok) {
        // The URL the site *settled* on, which is not always the one we asked
        // for: `multimovies.beer` 301s to `multimovies.casa`, and a redirect
        // like that drops the query string — so searching `beer/?s=x` lands on
        // `casa/` with no query and returns the home page instead of results.
        // Following the redirect once here, at resolve time, is what makes
        // every later request hit the domain that answers it directly.
        final settled = verdict.finalUrl ?? candidate;
        _aliveCache[k] = (at: DateTime.now(), url: settled);
        return settled;
      }
      challenged ??= verdict.state == _ProbeState.challenged ? candidate : null;
    }

    // Nothing clean: prefer a solvable challenge over a dead host, and fall
    // back to the manifest's pick so a probe that failed for a local network
    // reason cannot leave the provider with no base URL at all.
    final chosen = challenged ?? candidates.first;
    _aliveCache[k] = (at: DateTime.now(), url: chosen);
    return chosen;
  }

  /// One probe of a candidate domain, reporting where it ended up.
  ///
  /// `app.get` follows redirects, which is what we want: a domain that redirects
  /// to a working sibling is working, and [_ProbeResult.finalUrl] is how the
  /// sibling's name gets back to the caller.
  static Future<_ProbeResult> _probe(String url) async {
    // Redirects are followed by hand, one hop at a time, because the point of
    // the probe is to learn WHERE the site ended up. `package:http` follows
    // them internally and then reports the response against the ORIGINAL
    // request, so a followed redirect is invisible from the outside.
    var current = url;
    for (var hop = 0; hop < 4; hop++) {
      try {
        final res = await app.get(
          current,
          allowRedirects: false,
          // Never solve Cloudflare while probing. This request exists to decide
          // whether to USE this host; solving here would pop a verification
          // WebView for a candidate we are about to reject, and a successful
          // solve would return 200 and pin the source to the blocked domain
          // instead of falling through to the sibling that serves the site
          // cleanly. (MultiMovies: the manifest names `multimovies.makeup`,
          // which is blocked, while `multimovies.casa` works.)
          solveCloudflare: false,
          timeout: const Duration(seconds: 8),
        );
        if (res.code == 403 || res.code == 503) {
          return const _ProbeResult(_ProbeState.challenged);
        }
        if (res.code >= 300 && res.code < 400) {
          final location = res.headers['location'];
          if (location == null || location.isEmpty) {
            return const _ProbeResult(_ProbeState.dead);
          }
          current = location.startsWith('http')
              ? location
              : Uri.parse(current).resolve(location).toString();
          continue;
        }
        if (!res.isOk) return const _ProbeResult(_ProbeState.dead);
        // A 200 that is really a parked/for-sale page carries no site markup,
        // and nothing cheap tells those apart reliably, so only an empty body
        // counts as dead here.
        if (res.text.trim().isEmpty) {
          return const _ProbeResult(_ProbeState.dead);
        }
        return _ProbeResult(
          _ProbeState.ok,
          finalUrl: _trim(getBaseUrl(current)),
        );
      } catch (_) {
        return const _ProbeResult(_ProbeState.dead);
      }
    }
    return const _ProbeResult(_ProbeState.dead);
  }

  /// The already-probed domain for [key], without making a request.
  ///
  /// For the synchronous callers — "open in browser", and picking the URL to
  /// open the Cloudflare solver on — which cannot await a probe but should not
  /// have to show nothing either. Null until something has resolved this key.
  static String? cachedAlive(String key) => _aliveCache[key.toLowerCase()]?.url;

  /// Forgets the probed domain for [key] (or all of them), so the next resolve
  /// re-probes. Called when the user edits a source, and by tests.
  static void invalidateAlive([String? key]) {
    if (key == null) {
      _aliveCache.clear();
      return;
    }
    _aliveCache.remove(key.toLowerCase());
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

enum _ProbeState { ok, challenged, dead }

class _ProbeResult {
  const _ProbeResult(this.state, {this.finalUrl});

  final _ProbeState state;

  /// Where the request actually landed after redirects, when that differs
  /// from what was asked for.
  final String? finalUrl;
}
