import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'cs_http.dart';
import 'cs_spec.dart';

/// One site in a source catalogue — a name, a URL and (when we can tell) the
/// engine that scrapes it.
class CatalogueEntry {
  const CatalogueEntry({
    required this.name,
    required this.url,
    this.engineId,
  });

  final String name;
  final String url;

  /// The engine this site is known to run, or null when nobody has classified
  /// it. Null is offered to the user as "pick an engine", never silently
  /// guessed — a wrong engine produces an empty source, which looks like a dead
  /// site rather than a wrong setting.
  final CsEngineId? engineId;

  CatalogueEntry copyWith({CsEngineId? engineId}) => CatalogueEntry(
        name: name,
        url: url,
        engineId: engineId ?? this.engineId,
      );
}

/// Reads the source catalogues offered in Settings → Custom sources.
///
/// Two formats are accepted, because the two manifests in this space disagree:
///
///  * a **list** of `{name, url, internalName}` objects — `url-sources.json`,
///    bundled with the app as a starting point;
///  * a **map** of `name: url` — phisher's `domains.json`, which is also what
///    [CsDomains] reads for the built-in sources.
///
/// Anything else parses to an empty list rather than throwing: a user pasting
/// the wrong URL should see "no sources found", not a crash.
class CsCatalogue {
  CsCatalogue._();

  static const String bundledAsset = 'assets/catalogue/url_sources.json';

  /// Which engine each known site runs.
  ///
  /// Keyed on a substring of the host, not the manifest's `internalName`, so a
  /// site keeps its classification across the domain changes these all go
  /// through. Only entries verified by reading the live site's markup are here;
  /// everything else is deliberately absent and asks the user.
  static const Map<String, CsEngineId> _knownEngines = {
    // DooPlay / WordPress: /movies/ + /tvshows/ + doo_player_ajax.
    'multimovies': CsEngineId.dooplay,
    'movierulzhd': CsEngineId.dooplay,
    '123movies': CsEngineId.dooplay,
    'hdmovie2': CsEngineId.dooplay,
    'luxmovies': CsEngineId.dooplay,
    'toon-stream': CsEngineId.dooplay,
    'toonstream': CsEngineId.dooplay,
    'animedekho': CsEngineId.dooplay,
    'm4ufree': CsEngineId.dooplay,
    'coflix': CsEngineId.dooplay,
    'telugumv': CsEngineId.dooplay,
    'banglaplex': CsEngineId.dooplay,
    // HDHub4u-style flat download index.
    'hdhub4u': CsEngineId.hdhub4u,
    'hdhub': CsEngineId.hdhub4u,
    // UHDMovies-style locker index.
    'uhdmovies': CsEngineId.uhdmovies,
    // 4KHDHub-style card grid.
    '4khdhub': CsEngineId.fourKHdHub,
  };

  /// Patterns longest-first, so the most specific one wins.
  ///
  /// Load-bearing: `4khdhub.one` contains `hdhub`, so a plain pass over the map
  /// classified 4KHDHub as the HDHub4u engine — and an engine that reads nothing
  /// makes a live site look dead. Sorting by length removes the dependence on
  /// declaration order entirely, rather than leaving it as something the next
  /// person editing [_knownEngines] has to remember.
  static final List<String> _patternsByLength = _knownEngines.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  /// The engine [url] is known to run, or null.
  static CsEngineId? engineFor(String url) {
    final lower = url.toLowerCase();
    for (final pattern in _patternsByLength) {
      if (lower.contains(pattern)) return _knownEngines[pattern];
    }
    return null;
  }

  /// The catalogue that ships with the app.
  static Future<List<CatalogueEntry>> bundled() async {
    try {
      return parse(await rootBundle.loadString(bundledAsset));
    } catch (_) {
      return const [];
    }
  }

  /// A catalogue fetched from a URL the user supplied.
  static Future<List<CatalogueEntry>> fromUrl(String url) async {
    try {
      final res = await app.get(url, timeout: const Duration(seconds: 15));
      if (!res.isOk) return const [];
      return parse(res.text);
    } catch (_) {
      return const [];
    }
  }

  /// Parses either accepted shape. Entries without a usable URL are dropped,
  /// and duplicates (the bundled list repeats several sites) are collapsed on
  /// the URL.
  static List<CatalogueEntry> parse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }

    final out = <String, CatalogueEntry>{};

    void add(String name, String url) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('http')) return;
      final key = trimmed.toLowerCase();
      if (out.containsKey(key)) return;
      out[key] = CatalogueEntry(
        name: name.trim().isEmpty ? Uri.tryParse(trimmed)?.host ?? trimmed : name.trim(),
        url: trimmed,
        engineId: engineFor(trimmed),
      );
    }

    if (decoded is List) {
      for (final raw in decoded) {
        if (raw is! Map) continue;
        add(
          (raw['name'] ?? raw['internalName'] ?? '').toString(),
          (raw['url'] ?? '').toString(),
        );
      }
    } else if (decoded is Map) {
      for (final entry in decoded.entries) {
        add(entry.key.toString(), entry.value.toString());
      }
    }

    final list = out.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
