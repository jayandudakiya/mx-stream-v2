import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/hive/safe_box.dart';

import 'cs_models.dart';
import 'cs_spec.dart';

/// The sources the user added themselves, under Settings → Custom sources.
///
/// A custom source is an [CsSourceSpec]: one of the built-in site engines
/// pointed at a base URL the user supplies. That is all a source is here, which
/// is why these end up indistinguishable from the built-in four — same adapter,
/// same `native:` id shape, same detail screen and player path.
///
/// Stored as plain maps in a tiny Hive box, the same way [SearchSourcePrefs] and
/// [SourceHealthStore] do. No Hive adapters and no generated code: the record is
/// four strings and two flags, and a schema this small is cheaper to read and
/// migrate as JSON than as a registered type.
///
/// A [ChangeNotifier] so the settings list and the provider registry both
/// follow edits without anyone wiring callbacks by hand.
class CustomSourceStore extends ChangeNotifier {
  static const String boxName = 'custom_sources';

  /// Opens the box. Call once during boot, before the provider registry is
  /// built — it reads this to know which sources to register.
  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await openBoxSafely(boxName);
    }
  }

  Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// Every custom source, in the order they were added. Malformed records are
  /// skipped rather than thrown on: a box written by a newer build must never
  /// stop an older one from starting.
  List<CustomSource> get all {
    final box = _box;
    if (box == null) return const [];
    final out = <CustomSource>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      final source = CustomSource.fromMap(Map<String, dynamic>.from(raw));
      if (source != null) out.add(source);
    }
    out.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return out;
  }

  /// The ones that should actually be registered as providers.
  List<CustomSource> get enabled => all.where((s) => s.enabled).toList();

  CustomSource? byId(String id) {
    final raw = _box?.get(id);
    if (raw is! Map) return null;
    return CustomSource.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Adds a source and returns it. [CustomSource.id] is generated here, and is
  /// what the app-facing source id (`native:custom_<id>`) is built from — so it
  /// is never derived from the name or URL, both of which the user can edit.
  Future<CustomSource> add({
    required String name,
    required String baseUrl,
    required CsEngineId engineId,
    String lang = 'hi',
  }) async {
    final source = CustomSource(
      id: _newId(),
      name: name.trim(),
      baseUrl: normalizeBaseUrl(baseUrl),
      engineId: engineId,
      lang: lang,
      enabled: true,
      addedAt: DateTime.now(),
    );
    await _box?.put(source.id, source.toMap());
    notifyListeners();
    return source;
  }

  /// Saves an edit. The id — and therefore the source id everything is keyed on
  /// — is deliberately immutable, so a user renaming a source or following it to
  /// a new domain keeps their history and My List entries for it.
  Future<void> update(CustomSource source) async {
    await _box?.put(source.id, source.toMap());
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final existing = byId(id);
    if (existing == null || existing.enabled == enabled) return;
    await update(existing.copyWith(enabled: enabled));
  }

  Future<void> remove(String id) async {
    await _box?.delete(id);
    notifyListeners();
  }

  /// True when [url] is already covered by a stored source, so the UI can say
  /// so instead of silently creating a duplicate that splits the user's history
  /// between two ids for one site.
  CustomSource? withBaseUrl(String url, {String? ignoreId}) {
    final normalized = normalizeBaseUrl(url).toLowerCase();
    for (final s in all) {
      if (s.id == ignoreId) continue;
      if (s.baseUrl.toLowerCase() == normalized) return s;
    }
    return null;
  }

  /// Trims a URL to the `scheme://host[:port]` form the engines expect: they all
  /// build paths by concatenation (`'$base/?s=…'`), so a trailing slash or a
  /// pasted deep link would produce a malformed request. A bare host gains
  /// `https://`, which is what someone typing `4khdhub.one` means.
  static String normalizeBaseUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    try {
      final uri = Uri.parse(text);
      if (uri.host.isEmpty) return '';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    } catch (_) {
      return '';
    }
  }

  /// Short, readable in a log line — which a UUID is not — and checked against
  /// what is already stored.
  ///
  /// A timestamp alone is not quite enough: the catalogue import adds sources in
  /// a loop, and an id collision there would silently overwrite the source added
  /// a moment earlier rather than adding a new one.
  String _newId() {
    final box = _box;
    var candidate = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var suffix = 0;
    while (box != null && box.containsKey(candidate)) {
      candidate = '${candidate}_${++suffix}';
    }
    return candidate;
  }
}

/// One user-added source, as stored.
@immutable
class CustomSource {
  const CustomSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.engineId,
    required this.lang,
    required this.enabled,
    required this.addedAt,
    this.rows,
  });

  final String id;
  final String name;
  final String baseUrl;
  final CsEngineId engineId;
  final String lang;
  final bool enabled;
  final DateTime addedAt;

  /// Optional Home rows as `path` → `label`. Null means the engine picks, which
  /// is the right default — these paths are the part a user is least likely to
  /// get right and the part that matters least, since search does not use them.
  final Map<String, String>? rows;

  /// The provider key, and so the `native:` source id. Prefixed to guarantee a
  /// custom source can never collide with a built-in one, present or future.
  String get providerKey => 'custom_$id';

  String get sourceId => 'native:$providerKey';

  /// The running-provider description this source turns into. `isCustom` is what
  /// tells an engine to use family-wide category rows and to skip site-specific
  /// shortcuts it cannot assume (HDHub4u's hosted search index, say).
  CsSourceSpec toSpec() => CsSourceSpec(
        engineId: engineId,
        key: providerKey,
        name: name,
        baseUrl: baseUrl,
        lang: lang,
        isCustom: true,
        mainPageEntries: rows == null || rows!.isEmpty
            ? null
            : mainPageOf(rows!),
      );

  CustomSource copyWith({
    String? name,
    String? baseUrl,
    CsEngineId? engineId,
    String? lang,
    bool? enabled,
    Map<String, String>? rows,
  }) =>
      CustomSource(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        engineId: engineId ?? this.engineId,
        lang: lang ?? this.lang,
        enabled: enabled ?? this.enabled,
        addedAt: addedAt,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'engine': engineId.name,
        'lang': lang,
        'enabled': enabled,
        'addedAt': addedAt.millisecondsSinceEpoch,
        if (rows != null && rows!.isNotEmpty) 'rows': rows,
      };

  /// Null for a record missing anything load-bearing, or naming an engine this
  /// build does not have — a source written by a newer version is skipped, not
  /// crashed on.
  static CustomSource? fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final name = map['name'];
    final baseUrl = map['baseUrl'];
    final engine = CsEngineId.byName(map['engine'] as String?);
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (baseUrl is! String || baseUrl.isEmpty) return null;
    if (engine == null) return null;

    final rawRows = map['rows'];
    return CustomSource(
      id: id,
      name: name,
      baseUrl: baseUrl,
      engineId: engine,
      lang: (map['lang'] as String?) ?? 'hi',
      enabled: map['enabled'] as bool? ?? true,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['addedAt'] as num?)?.toInt() ?? 0,
      ),
      rows: rawRows is Map
          ? {
              for (final e in rawRows.entries)
                e.key.toString(): e.value.toString(),
            }
          : null,
    );
  }
}
