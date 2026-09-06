import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralized configuration for the native movie-provider engine —
/// endpoints, fallback domains, and the live domain resolver.
///
/// Ported verbatim from MXStream's
/// `functions/fetchers/providers/provider_config.dart`.
class ProviderConfig {
  // ---------------------------------------------------------------------------
  // 1. Remote Endpoints & Repositories (Active Dynamic Source)
  // ---------------------------------------------------------------------------

  /// Dynamic live domain resolver endpoint from GitHub
  static const String urlsEndpoint =
      'https://raw.githubusercontent.com/SaurabhKaperwan/Utils/refs/heads/main/urls.json';

  /// CloudStream / CSX extensions & plugins catalogue
  static const String pluginsEndpoint =
      'https://raw.githubusercontent.com/SaurabhKaperwan/CSX/builds/plugins.json';

  /// Default Megix Repository definition (CS.json)
  static const String defaultRepoUrl =
      'https://raw.githubusercontent.com/SaurabhKaperwan/CSX/builds/CS.json';

  /// Cinemeta API for IMDb metadata enrichment (synopsis, cast, genres)
  static const String cinemetaUrl = 'https://v3-cinemeta.strem.io/meta';

  /// Standard Desktop User-Agent for requests
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // ---------------------------------------------------------------------------
  // 2. Default Active Provider Selection
  // ---------------------------------------------------------------------------
  static const String defaultActiveProvider = 'VegaMovies';

  // ---------------------------------------------------------------------------
  // 3. Fallback Provider URLs
  // ---------------------------------------------------------------------------
  /// Last-resort domains used when urls.json is unreachable (some ISPs block
  /// raw.githubusercontent.com on broadband but not on mobile data). Without
  /// these, resolveBaseUrl returns '' and every provider request is malformed.
  static const Map<String, String> defaultProviderUrls = {
    'vegamovies': 'https://new2.vegamovies.futbol',
    'rogmovies': 'https://new2.rogmovies.click',
    'vcloud': 'https://vcloud.fit',
    'hubcloud': 'https://hubcloud.cx',
    'gdflix': 'https://new3.gdflix.io',
    'moviesdrive': 'https://new3.moviesdrive.christmas',
    'moviesmod': 'https://moviesmod.zone',
    'topmovies': 'https://moviesleech.art',
    'bollyflix': 'https://bollyflix.af',
    'uhdmovies': 'https://uhdmovies.autos',
    'multimovies': 'https://multimovies.makeup',
    '4khdhub': 'https://4khdhub.one',
  };

  // ---------------------------------------------------------------------------
  // 4. Dynamic URL Cache & Resolver (Active Live Mechanism)
  // ---------------------------------------------------------------------------
  static final Map<String, String> _resolvedBaseUrlCache = {};

  /// Guards against re-hitting urls.json on every lookup when it is blocked.
  /// Without this, a blocked network costs a full timeout per provider call.
  static Future<Map<String, String>>? _inFlightFetch;
  static DateTime? _lastFailedFetch;
  static const Duration _failureCooldown = Duration(minutes: 5);

  /// Get reference static provider URL
  static String? getStaticProviderUrl(String providerName) {
    final key = providerName.toLowerCase();
    return defaultProviderUrls[key];
  }

  /// Fetch the entire live dynamic URLs dictionary from urls.json with in-memory caching
  static Future<Map<String, String>> fetchDynamicUrls() async {
    if (_resolvedBaseUrlCache.isNotEmpty) {
      return _resolvedBaseUrlCache;
    }

    // Back off after a failure instead of paying a full timeout on every call.
    final lastFailure = _lastFailedFetch;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < _failureCooldown) {
      return _resolvedBaseUrlCache;
    }

    // Collapse concurrent callers onto a single request.
    final existing = _inFlightFetch;
    if (existing != null) return existing;

    final fetch = _doFetchDynamicUrls();
    _inFlightFetch = fetch;
    try {
      return await fetch;
    } finally {
      _inFlightFetch = null;
    }
  }

  static Future<Map<String, String>> _doFetchDynamicUrls() async {
    try {
      final response = await http
          .get(Uri.parse(urlsEndpoint))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        data.forEach((key, value) {
          _resolvedBaseUrlCache[key.toLowerCase()] = value.toString();
        });
        _lastFailedFetch = null;
        return _resolvedBaseUrlCache;
      }
      _lastFailedFetch = DateTime.now();
    } catch (e) {
      _lastFailedFetch = DateTime.now();
      debugPrint('Error fetching dynamic urls: $e');
    }
    return _resolvedBaseUrlCache;
  }

  /// Dynamically resolve live base URL for a provider from urls.json, falling
  /// back to the bundled domain so a blocked resolver never yields an empty
  /// base URL (which would make every downstream request malformed).
  static Future<String> resolveBaseUrl(String providerKey) async {
    final key = providerKey.toLowerCase();
    if (_resolvedBaseUrlCache.containsKey(key)) {
      return _resolvedBaseUrlCache[key]!;
    }

    final urls = await fetchDynamicUrls();
    final url = urls[key];
    if (url != null && url.isNotEmpty) {
      _resolvedBaseUrlCache[key] = url;
      return url;
    }

    return getStaticProviderUrl(key) ?? '';
  }

  /// 100% deterministic integer ID from string, persistent across app restarts
  static int getStableMediaId(String input) {
    if (input.isEmpty) return 0;
    int hash = 0x811c9dc5;
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }
}
