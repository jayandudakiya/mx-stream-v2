// Which `native:` sources an all-sources search actually queries.
//
// The fan-out used to drop every id starting with `native:`. That rule was
// written for the two Home *channels* — each duplicates an installed
// CloudStream extension for the same site, and listing both read as one source
// twice — but it caught every other native source too: the four ported
// CloudStream engines and anything added under Settings → Custom sources.
// Those have no channel button and no installed twin, so the blanket rule left
// them with no way into the app at all: invisible in the picker, never queried.
//
// These tests pin the narrower rule — only a Home channel is held back — at the
// level that matters, which source ids `searchStatus` is actually called with.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/aniyomi/aniyomi_filters.dart';
import 'package:orcabox/core/di/injector.dart' show sl;
import 'package:orcabox/core/mode/content_mode.dart';
import 'package:orcabox/core/mode/content_mode_cubit.dart';
import 'package:orcabox/core/models/episode.dart';
import 'package:orcabox/core/models/home_section.dart';
import 'package:orcabox/core/models/media_detail.dart';
import 'package:orcabox/core/models/media_item.dart';
import 'package:orcabox/core/models/provider_info.dart';
import 'package:orcabox/core/models/video_source.dart';
import 'package:orcabox/core/playback/search_history.dart';
import 'package:orcabox/core/playback/search_prefs.dart';
import 'package:orcabox/core/playback/search_source_prefs.dart';
import 'package:orcabox/core/playback/source_health_store.dart';
import 'package:orcabox/core/repository/source_repository.dart';
import 'package:orcabox/core/search/title_suggestion_service.dart';
import 'package:orcabox/core/state/active_source_cubit.dart';
import 'package:orcabox/features/search/bloc/search_bloc.dart';
import 'package:orcabox/features/search/bloc/search_event.dart';

// ---------------------------------------------------------------------------
// Fakes — same shapes as search_mode_scope_test.dart
// ---------------------------------------------------------------------------

class _FakeSearchPrefs extends SearchPrefs {
  @override
  String? get contentFilterName => null;
  @override
  String? get audioFilterName => null;
  @override
  String? get statusFilterName => null;
  @override
  String? get sortName => null;
  @override
  String? get genre => null;
  @override
  int? get decade => null;

  /// False so the bloc takes the all-sources fan-out branch under test.
  @override
  bool get currentSourceOnly => false;

  @override
  Future<void> setContentFilterName(String name) async {}
  @override
  Future<void> setAudioFilterName(String name) async {}
  @override
  Future<void> setStatusFilterName(String name) async {}
  @override
  Future<void> setSortName(String name) async {}
  @override
  Future<void> setGenre(String? genre) async {}
  @override
  Future<void> setDecade(int? decade) async {}
  @override
  Future<void> setCurrentSourceOnly(bool value) async {}
}

class _FakeSearchHistory extends SearchHistory {
  @override
  List<String> recent() => [];
  @override
  Future<void> add(String query) async {}
  @override
  Future<void> remove(String query) async {}
  @override
  Future<void> clear() async {}
}

class _FakeSuggestions extends TitleSuggestionService {
  _FakeSuggestions() : super(Dio());

  @override
  Future<List<String>> suggest(String query, {int limit = 8}) async => [];
}

/// Every source participates — the per-source search toggle is not what these
/// tests are about.
class _FakeSearchSourcePrefs extends SearchSourcePrefs {
  @override
  bool isIncluded(String id) => true;
}

class _FakeSourceHealthStore extends SourceHealthStore {
  @override
  SourceHealth statusOf(String id) => SourceHealth.ok;
  @override
  bool isSkippable(String id) => false;
  @override
  Future<void> record(String id, SourceOutcome outcome, {int? responseMs}) async {}
}

/// Records every sourceId `searchStatus` is called with — direct evidence of
/// what the fan-out reached, since a source dropped by filtering never gets
/// this far.
class _FakeRepo implements SourceRepository {
  @override
  List<({String id, String name})> get pickableSources => loadedSources;

  List<({String id, String name})> loadedSourcesSeed = const [];

  final Map<String, List<MediaItem>> itemsFor = {};

  final List<String> searchedSourceIds = [];

  @override
  Future<({List<MediaItem> items, SourceOutcome outcome})> searchStatus(
    String query, {
    String category = 'sub',
    String? sourceId,
    String? filtersJson,
    bool cache = false,
    int page = 1,
  }) async {
    if (sourceId != null) searchedSourceIds.add(sourceId);
    final items = itemsFor[sourceId] ?? const <MediaItem>[];
    return (
      items: items,
      outcome: items.isEmpty ? SourceOutcome.empty : SourceOutcome.ok,
    );
  }

  @override
  String displayName(String sourceId) => sourceId;

  @override
  List<({String id, String name})> get loadedSources => loadedSourcesSeed;

  @override
  String get sourceId => 'ani:1';

  @override
  void syncSearchCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  bool hasSource(String sourceId) => throw UnimplementedError();

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
    String? sourceId,
  }) => throw UnimplementedError();

  @override
  Future<List<HomeSection>> home({String category = 'sub', String? sourceId}) =>
      throw UnimplementedError();

  @override
  Future<List<MediaItem>> search(
    String query, {
    String category = 'sub',
    String? sourceId,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaItem>> browseMore(BrowseMore more, int page) =>
      throw UnimplementedError();

  @override
  Future<List<AniyomiFilter>> aniFilters(String sourceId) =>
      throw UnimplementedError();

  @override
  Future<MediaDetail> detail(
    String url, {
    String category = 'sub',
    String? sourceId,
    void Function(MediaDetail partial)? onPartial,
  }) => throw UnimplementedError();

  @override
  Future<List<Episode>> episodes(
    String url, {
    String category = 'sub',
    String? sourceId,
  }) => throw UnimplementedError();

  @override
  Future<List<VideoSource>> sources(
    String episodeUrl, {
    String? sourceId,
    bool fast = false,
  }) => throw UnimplementedError();

  @override
  void invalidateSources(
    String episodeUrl, {
    String? sourceId,
    bool includePrefetch = false,
  }) => throw UnimplementedError();

  @override
  void prefetch(String episodeUrl, {String? sourceId}) =>
      throw UnimplementedError();
}

MediaItem _fakeItem(String sourceId) => MediaItem(
  id: 'id-$sourceId',
  title: 'Avengers',
  url: 'https://example.com/$sourceId',
  type: ProviderType.movie,
  sourceId: sourceId,
);

void main() {
  late Directory tempDir;
  late ActiveSourceCubit activeSource;
  late ContentModeCubit modeCubit;
  late _FakeRepo repo;
  late SearchBloc bloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('search_native_test');
    Hive.init(tempDir.path);

    activeSource = ActiveSourceCubit();
    modeCubit = await ContentModeCubit.create(activeSource);
    sl.registerSingleton<ContentModeCubit>(modeCubit);
    sl.registerSingleton<SearchSourcePrefs>(_FakeSearchSourcePrefs());
    sl.registerSingleton<SourceHealthStore>(_FakeSourceHealthStore());

    repo = _FakeRepo()
      ..loadedSourcesSeed = const [
        // The two Home channels.
        (id: 'native:vegamovies', name: 'VegaMovies (Hollywood)'),
        (id: 'native:rogmovies', name: 'RogMovies (Bollywood)'),
        // A ported CloudStream engine.
        (id: 'native:multimovies', name: 'MultiMovies'),
        // A source the user added under Settings → Custom sources.
        (id: 'native:custom_k3f9a1', name: 'My Site'),
        // An installed extension, for contrast. A prefix-resolved id on
        // purpose: sourceTypeOf resolves `cs:` ids through CloudStreamManager,
        // which this harness does not register.
        (id: 'ani:1', name: 'AniSource'),
      ]
      ..itemsFor['native:multimovies'] = [_fakeItem('native:multimovies')]
      ..itemsFor['native:custom_k3f9a1'] = [_fakeItem('native:custom_k3f9a1')]
      ..itemsFor['ani:1'] = [_fakeItem('ani:1')];

    bloc = SearchBloc(
      repo: repo,
      history: _FakeSearchHistory(),
      prefs: _FakeSearchPrefs(),
      suggestions: _FakeSuggestions(),
    );
  });

  tearDown(() async {
    await bloc.close();
    await modeCubit.close();
    await activeSource.close();
    await sl.reset();
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('all-sources search reaches native sources', () {
    test('a custom source is queried alongside the other sources',
        () async {
      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        repo.searchedSourceIds,
        contains('native:custom_k3f9a1'),
        reason: 'a source added in Settings is only reachable through search',
      );
      expect(repo.searchedSourceIds, contains('ani:1'));
    });

    test('the ported CloudStream engines are queried too', () async {
      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(repo.searchedSourceIds, contains('native:multimovies'));
    });

    test('the two Home channels stay out of the fan-out', () async {
      // They duplicate installed extensions for the same sites, and they have
      // their own button on Home.
      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(repo.searchedSourceIds, isNot(contains('native:vegamovies')));
      expect(repo.searchedSourceIds, isNot(contains('native:rogmovies')));
    });

    test('their results reach the state, grouped under their own source',
        () async {
      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final sourceIds = bloc.state.groups.map((g) => g.sourceId).toSet();
      expect(sourceIds, contains('native:custom_k3f9a1'));
      expect(sourceIds, contains('native:multimovies'));
    });

    test('a custom source can also be searched on its own', () async {
      bloc.add(const SearchScopeSourceChanged('native:custom_k3f9a1'));
      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(repo.searchedSourceIds, ['native:custom_k3f9a1']);
    });

    test('movie mode still narrows: a manga source is not swept in', () async {
      await modeCubit.setMode(ContentMode.manga);
      repo.loadedSourcesSeed = const [
        (id: 'native:custom_k3f9a1', name: 'My Site'),
        (id: 'mihon:1', name: 'MangaSource'),
      ];

      bloc.add(const SearchRunRequested('avengers'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // A custom movie source is a movie source: manga mode must not query it,
      // exactly as it would not query VegaMovies.
      expect(repo.searchedSourceIds, isNot(contains('native:custom_k3f9a1')));
      expect(repo.searchedSourceIds, contains('mihon:1'));
    });
  });
}
