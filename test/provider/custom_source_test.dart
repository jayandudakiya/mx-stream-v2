import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_catalogue.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_engines.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_models.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_spec.dart';
import 'package:orcabox/core/provider/cloudstream_kt/custom_source_store.dart';
import 'package:orcabox/core/provider/native/native_provider_manager.dart';

void main() {
  group('CustomSourceStore.normalizeBaseUrl', () {
    test('adds a missing scheme, because that is how people type a site', () {
      expect(
        CustomSourceStore.normalizeBaseUrl('4khdhub.one'),
        'https://4khdhub.one',
      );
    });

    test('drops path, query and trailing slash — engines concatenate paths', () {
      // A pasted deep link is the common case: someone copies the address bar
      // from a movie page. Keeping the path would make every request malformed.
      expect(
        CustomSourceStore.normalizeBaseUrl('https://example.com/movies/x/?s=1'),
        'https://example.com',
      );
      expect(
        CustomSourceStore.normalizeBaseUrl('https://example.com/'),
        'https://example.com',
      );
    });

    test('keeps an explicit port and http', () {
      expect(
        CustomSourceStore.normalizeBaseUrl('http://10.0.0.5:8080/x'),
        'http://10.0.0.5:8080',
      );
    });

    test('rubbish normalises to empty rather than to a malformed base', () {
      expect(CustomSourceStore.normalizeBaseUrl('   '), '');
      expect(CustomSourceStore.normalizeBaseUrl('https://'), '');
    });
  });

  group('CustomSource', () {
    test('provider key is namespaced so it can never collide with a built-in',
        () {
      final source = CustomSource(
        id: 'abc',
        name: 'My Site',
        baseUrl: 'https://example.com',
        engineId: CsEngineId.dooplay,
        lang: 'hi',
        enabled: true,
        addedAt: DateTime(2026),
      );
      expect(source.providerKey, 'custom_abc');
      expect(source.sourceId, 'native:custom_abc');
      for (final builtIn in builtInCsSpecs) {
        expect(source.providerKey, isNot(builtIn.key));
      }
    });

    test('the spec it builds is marked custom and pins the URL', () {
      final spec = CustomSource(
        id: 'abc',
        name: 'My Site',
        baseUrl: 'https://example.com',
        engineId: CsEngineId.hdhub4u,
        lang: 'ta',
        enabled: true,
        addedAt: DateTime(2026),
      ).toSpec();

      expect(spec.isCustom, isTrue);
      expect(spec.baseUrl, 'https://example.com');
      expect(spec.lang, 'ta');
      expect(spec.engineId, CsEngineId.hdhub4u);
    });

    test('survives a storage round-trip', () {
      final original = CustomSource(
        id: 'abc',
        name: 'My Site',
        baseUrl: 'https://example.com',
        engineId: CsEngineId.uhdmovies,
        lang: 'en',
        enabled: false,
        addedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        rows: const {'movies/': 'Movies'},
      );
      final restored = CustomSource.fromMap(original.toMap());
      expect(restored, isNotNull);
      expect(restored!.name, original.name);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.engineId, original.engineId);
      expect(restored.lang, original.lang);
      expect(restored.enabled, isFalse);
      expect(restored.addedAt, original.addedAt);
      expect(restored.rows, original.rows);
    });

    test('a record naming an unknown engine is skipped, not crashed on', () {
      // What an older build sees after a newer one adds an engine.
      final map = {
        'id': 'abc',
        'name': 'My Site',
        'baseUrl': 'https://example.com',
        'engine': 'someFutureEngine',
        'lang': 'hi',
        'enabled': true,
        'addedAt': 0,
      };
      expect(CustomSource.fromMap(map), isNull);
    });
  });

  group('CustomSourceStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('custom_sources_test');
      Hive.init(dir.path);
      await CustomSourceStore.init();
    });

    tearDown(() async {
      await Hive.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('adds, lists in insertion order, and normalises the URL', () async {
      final store = CustomSourceStore();
      await store.add(
        name: 'First',
        baseUrl: 'first.example/movies/',
        engineId: CsEngineId.dooplay,
      );
      await store.add(
        name: 'Second',
        baseUrl: 'https://second.example',
        engineId: CsEngineId.fourKHdHub,
      );

      final all = store.all;
      expect(all.map((s) => s.name), ['First', 'Second']);
      expect(all.first.baseUrl, 'https://first.example');
    });

    test('finds a duplicate by address, ignoring the one being edited',
        () async {
      final store = CustomSourceStore();
      final added = await store.add(
        name: 'First',
        baseUrl: 'https://first.example',
        engineId: CsEngineId.dooplay,
      );

      expect(store.withBaseUrl('FIRST.example/')?.id, added.id);
      expect(store.withBaseUrl('https://first.example', ignoreId: added.id),
          isNull);
      expect(store.withBaseUrl('https://other.example'), isNull);
    });

    test('disabling keeps the record but drops it from enabled', () async {
      final store = CustomSourceStore();
      final added = await store.add(
        name: 'First',
        baseUrl: 'https://first.example',
        engineId: CsEngineId.dooplay,
      );

      await store.setEnabled(added.id, false);
      expect(store.all, hasLength(1));
      expect(store.enabled, isEmpty);

      await store.setEnabled(added.id, true);
      expect(store.enabled, hasLength(1));
    });

    test('an edit keeps the id, so history stays attached to the source',
        () async {
      final store = CustomSourceStore();
      final added = await store.add(
        name: 'Old name',
        baseUrl: 'https://old.example',
        engineId: CsEngineId.dooplay,
      );

      await store.update(
        added.copyWith(name: 'New name', baseUrl: 'https://new.example'),
      );

      final updated = store.byId(added.id);
      expect(updated!.name, 'New name');
      expect(updated.baseUrl, 'https://new.example');
      expect(updated.sourceId, added.sourceId);
    });
  });

  group('NativeProviderManager + custom sources', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('native_mgr_test');
      Hive.init(dir.path);
      await CustomSourceStore.init();
    });

    tearDown(() async {
      await Hive.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('registers the built-ins plus every enabled custom source', () async {
      final store = CustomSourceStore();
      await store.add(
        name: 'Mine',
        baseUrl: 'https://mine.example',
        engineId: CsEngineId.dooplay,
      );

      final manager = NativeProviderManager(customSources: store);
      final ids = manager.all.map((p) => p.sourceId).toList();

      // The originals keep their ids and their leading position.
      expect(ids.first, 'native:vegamovies');
      expect(ids, contains('native:rogmovies'));
      for (final spec in builtInCsSpecs) {
        expect(ids, contains('native:${spec.key}'));
      }
      expect(ids.where((id) => id.startsWith('native:custom_')), hasLength(1));
    });

    test('an added source appears without a restart, a removed one disappears',
        () async {
      final store = CustomSourceStore();
      final manager = NativeProviderManager(customSources: store);
      final before = manager.all.length;

      final added = await store.add(
        name: 'Mine',
        baseUrl: 'https://mine.example',
        engineId: CsEngineId.dooplay,
      );
      expect(manager.all.length, before + 1);
      expect(manager.get(added.sourceId), isNotNull);
      expect(manager.customSourceFor(added.sourceId)?.name, 'Mine');

      await store.remove(added.id);
      expect(manager.all.length, before);
      expect(manager.get(added.sourceId), isNull);
      expect(manager.customSourceFor(added.sourceId), isNull);
    });

    test('disabling unregisters the provider but keeps the stored source',
        () async {
      final store = CustomSourceStore();
      final added = await store.add(
        name: 'Mine',
        baseUrl: 'https://mine.example',
        engineId: CsEngineId.dooplay,
      );
      final manager = NativeProviderManager(customSources: store);
      expect(manager.get(added.sourceId), isNotNull);

      await store.setEnabled(added.id, false);
      expect(manager.get(added.sourceId), isNull);
      expect(store.all, hasLength(1));
    });

    test('a rebuilt provider reflects an edited name', () async {
      final store = CustomSourceStore();
      final added = await store.add(
        name: 'Old',
        baseUrl: 'https://mine.example',
        engineId: CsEngineId.dooplay,
      );
      final manager = NativeProviderManager(customSources: store);
      expect(manager.get(added.sourceId)!.displayName, 'Old');

      await store.update(added.copyWith(name: 'New'));
      expect(manager.get(added.sourceId)!.displayName, 'New');
    });
  });

  group('CsCatalogue', () {
    test('parses the url-sources.json list shape', () {
      const body = '''
      [
        {"url": "https://multimovies.makeup", "name": "MultiMovies",
         "internalName": "MultiMovies"},
        {"url": "https://4khdhub.one", "name": "4khdhub"},
        {"url": "https://4khdhub.one", "name": "4khdhub duplicate"},
        {"url": "", "name": "no url"}
      ]
      ''';
      final entries = CsCatalogue.parse(body);
      expect(entries, hasLength(2), reason: 'the duplicate URL collapses');
      expect(
        entries.firstWhere((e) => e.url.contains('multimovies')).engineId,
        CsEngineId.dooplay,
      );
      expect(
        entries.firstWhere((e) => e.url.contains('4khdhub')).engineId,
        CsEngineId.fourKHdHub,
      );
    });

    test('parses the domains.json map shape', () {
      const body = '{"HDHUB4u": "https://new5.hdhub4u.cl", '
          '"UHDMovies": "https://uhdmovies.autos"}';
      final entries = CsCatalogue.parse(body);
      expect(entries, hasLength(2));
      expect(
        entries.firstWhere((e) => e.name == 'HDHUB4u').engineId,
        CsEngineId.hdhub4u,
      );
    });

    test('an unclassified site has no engine, so the user is asked', () {
      final entries =
          CsCatalogue.parse('[{"url":"https://unknownsite.tld","name":"X"}]');
      expect(entries.single.engineId, isNull);
    });

    test('rubbish parses to an empty list rather than throwing', () {
      expect(CsCatalogue.parse('not json'), isEmpty);
      expect(CsCatalogue.parse('42'), isEmpty);
    });
  });

  group('CsSpecApi.mainUrl precedence', () {
    tearDown(() => csBaseUrlOverride = null);

    test('a user override beats the pinned URL', () async {
      csBaseUrlOverride = (id) =>
          id == 'native:custom_x' ? 'https://override.example/' : null;

      final api = buildCsApi(
        const CsSourceSpec(
          engineId: CsEngineId.dooplay,
          key: 'custom_x',
          name: 'X',
          baseUrl: 'https://pinned.example',
          isCustom: true,
        ),
      );
      expect(await api.mainUrl, 'https://override.example');
    });

    test('without an override the pinned URL is used, trailing slash dropped',
        () async {
      final api = buildCsApi(
        const CsSourceSpec(
          engineId: CsEngineId.dooplay,
          key: 'custom_x',
          name: 'X',
          baseUrl: 'https://pinned.example/',
          isCustom: true,
        ),
      );
      expect(await api.mainUrl, 'https://pinned.example');
    });
  });

  group('engine rows', () {
    test('a custom DooPlay source uses family rows, not MultiMovies genres', () {
      final builtIn = buildCsApi(
        const CsSourceSpec(
          engineId: CsEngineId.dooplay,
          key: 'multimovies',
          name: 'MultiMovies',
        ),
      );
      final custom = buildCsApi(
        const CsSourceSpec(
          engineId: CsEngineId.dooplay,
          key: 'custom_x',
          name: 'X',
          baseUrl: 'https://x.example',
          isCustom: true,
        ),
      );

      final customPaths = custom.mainPage.map((e) => e.data).toList();
      expect(customPaths, contains('movies/'));
      expect(
        customPaths.any((p) => p.startsWith('genre/')),
        isFalse,
        reason: 'another site is not guaranteed to have those genre slugs',
      );
      expect(
        builtIn.mainPage.map((e) => e.data),
        contains('genre/hindi-dubbed/'),
      );
    });

    test('explicit rows on a spec win over both defaults', () {
      final api = buildCsApi(
        CsSourceSpec(
          engineId: CsEngineId.dooplay,
          key: 'custom_x',
          name: 'X',
          baseUrl: 'https://x.example',
          isCustom: true,
          mainPageEntries: mainPageOf(const {'only/': 'Only'}),
        ),
      );
      expect(api.mainPage.map((e) => e.data), ['only/']);
    });
  });
}
