import 'dart:convert';
import 'dart:developer' as developer;

import '../native/provider_config.dart';
import 'cs_http.dart';

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

  static Map<String, String> _cache = {};
  static Future<Map<String, String>>? _inFlight;
  static DateTime? _lastFailure;
  static const Duration _failureCooldown = Duration(minutes: 5);

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
      final live = await resolve(key);
      if (live.isEmpty) return url;
      final u = Uri.parse(url);
      final base = Uri.parse(live);
      return u.replace(scheme: base.scheme, host: base.host, port: base.port).toString();
    } catch (_) {
      return url;
    }
  }

  static String _trim(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
