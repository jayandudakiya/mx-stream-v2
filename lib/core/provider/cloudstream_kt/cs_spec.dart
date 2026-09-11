/// What a ported CloudStream provider is *made of*, separated from which site
/// it is pointed at.
///
/// A Kotlin `.cs3` provider hard-codes its own domain, name and category rows,
/// because one plugin means one site. That assumption does not survive contact
/// with this app: the four ported providers are really four *site engines* —
/// DooPlay/WordPress, HDHub4u, UHDMovies and 4KHDHub — and the manifest in
/// `url-sources.json` lists dozens of sites running those same engines under
/// different domains. So each provider takes a [CsSourceSpec] saying which site
/// it is scraping, and one class serves both a built-in source and any number
/// of user-added ones.
///
/// Deliberately Flutter-free, like everything under `cloudstream_kt/` except
/// `cs_adapter.dart` and `cs_providers.dart`, so `tool/cs_live_check.dart` can
/// exercise the engines against live sites with a plain `dart run`.
library;

import 'cs_domains.dart';
import 'cs_main_api.dart';
import 'cs_models.dart';

/// A user-pinned base URL per app-facing source id (`native:hdhub4u`), or null
/// to use the resolved one.
///
/// Installed at boot from `SourceDomainOverrides` (see `cs_bindings.dart`) —
/// injected rather than imported because that store is Hive/Flutter-backed and
/// this layer stays runnable under plain `dart run`.
///
/// This is what makes an override on a built-in source real: the same store
/// exists for CloudStream's Kotlin plugins, where it can only redirect "open in
/// browser" and the Cloudflare solve, because nothing app-side can change where
/// a live plugin fetches from. These engines are ours, so an override here
/// changes the scraping too — which is the difference between a user being able
/// to rescue a source whose manifest domain has died and merely being able to
/// visit it.
String? Function(String sourceId)? csBaseUrlOverride;

/// The site engines this app can scrape with.
///
/// The name is persisted with every user-added custom source, so these are
/// permanent once shipped — rename one and every source stored under it
/// becomes unreadable.
enum CsEngineId {
  /// DooPlay — the WordPress movie theme (`div.result-item`, `#seasons`, the
  /// `doo_player_ajax` endpoint). By far the most common engine in the wild:
  /// MultiMovies, movierulzhd, hdmovie2, luxmovies, toonstream and animedekho
  /// all run it.
  dooplay,

  /// HDHub4u — a heavily customised WordPress index whose detail pages are a
  /// flat list of `<h3>`/`<h4>` link headings rather than structured markup.
  hdhub4u,

  /// UHDMovies — the "download index" family: a post of quality headings, each
  /// followed by links into a Driveleech/Driveseed locker.
  uhdmovies,

  /// 4KHDHub — a card-grid catalogue with structured `download-item` /
  /// `episode-item` blocks on the detail page.
  fourKHdHub;

  static CsEngineId? byName(String? name) {
    for (final e in CsEngineId.values) {
      if (e.name == name) return e;
    }
    return null;
  }
}

/// One provider instance: an engine pointed at a site.
///
/// [key] is the identity everything downstream hangs off — the app-facing
/// source id is `native:<key>`, and history, My List and resume positions are
/// keyed on it. It must never change for a source that has shipped, or that a
/// user has already watched something from.
class CsSourceSpec {
  const CsSourceSpec({
    required this.engineId,
    required this.key,
    required this.name,
    this.baseUrl,
    this.domainKey,
    this.lang = 'hi',
    this.mainPageEntries,
    this.isCustom = false,
  });

  final CsEngineId engineId;

  /// Stable id fragment (`multimovies`, `custom_k3f9a1`).
  final String key;

  /// Display name in the source picker and on the detail screen.
  final String name;

  /// Fixed base URL. Null for built-in sources, whose live domain comes from
  /// [CsDomains] instead so they survive the site moving — which these sites do
  /// every few weeks. A user-added source pins whatever URL they typed,
  /// because no manifest knows about it.
  final String? baseUrl;

  /// Manifest key to resolve the live domain under when it differs from [key].
  /// Only consulted while [baseUrl] is null.
  final String? domainKey;

  /// ISO code of the site's audio, mostly `hi` here.
  final String lang;

  /// Home rows for this site. Null means "the engine's own rows".
  final List<CsMainPageEntry>? mainPageEntries;

  /// True for a source the user added through Settings → Custom sources.
  final bool isCustom;

  CsSourceSpec copyWith({
    CsEngineId? engineId,
    String? key,
    String? name,
    String? baseUrl,
    String? domainKey,
    String? lang,
    List<CsMainPageEntry>? mainPageEntries,
    bool? isCustom,
  }) =>
      CsSourceSpec(
        engineId: engineId ?? this.engineId,
        key: key ?? this.key,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        domainKey: domainKey ?? this.domainKey,
        lang: lang ?? this.lang,
        mainPageEntries: mainPageEntries ?? this.mainPageEntries,
        isCustom: isCustom ?? this.isCustom,
      );
}

/// Base class for every ported provider: it answers the identity half of
/// [CsMainApi] from a [CsSourceSpec], leaving subclasses only the scraping.
abstract class CsSpecApi implements CsMainApi {
  CsSpecApi(this.spec);

  final CsSourceSpec spec;

  @override
  String get providerKey => spec.key;

  @override
  String get name => spec.name;

  @override
  String get lang => spec.lang;

  /// The app-facing id for this provider, the one overrides and history use.
  String get sourceId => 'native:${spec.key}';

  /// A user override wins, then the spec's pinned URL, then the live domain from
  /// the manifests. Never returns a trailing slash — every call site
  /// concatenates `'$base/...'`.
  @override
  Future<String> get mainUrl async {
    final override = csBaseUrlOverride?.call(sourceId)?.trim();
    if (override != null && override.isNotEmpty) return _trimSlash(override);

    final pinned = spec.baseUrl?.trim();
    if (pinned != null && pinned.isNotEmpty) return _trimSlash(pinned);
    // `resolveAlive`, not `resolve`: the manifests name a domain the site has
    // announced, which is not always one that still answers. See
    // [CsDomains.resolveAlive] — the manifest's pick still wins whenever it
    // works, so this only changes the outcome for a site whose listed domain
    // is dead or serving a block page.
    return CsDomains.resolveAlive(spec.domainKey ?? spec.key);
  }

  /// The rows verified against the site this engine was written for.
  List<CsMainPageEntry> get builtInMainPage;

  /// The rows that hold across the engine's whole family, used for a
  /// user-added site whose category paths nobody has checked. Defaults to
  /// [builtInMainPage] for an engine whose rows are generic already.
  List<CsMainPageEntry> get familyMainPage => builtInMainPage;

  @override
  List<CsMainPageEntry> get mainPage =>
      spec.mainPageEntries ??
      (spec.isCustom ? familyMainPage : builtInMainPage);
}

String _trimSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;
