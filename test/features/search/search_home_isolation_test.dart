// NOTES task 1 — Search must never move Home's provider.
//
// The bug: the Search source picker called `ActiveSourceCubit.setSource()`,
// and `SearchBloc._runSearch` read that same cubit to decide which source a
// scoped search should query. `ActiveSourceCubit` is a process-wide singleton
// that `HomeScreen` listens to via `BlocListener`, so scoping a search to a
// different provider silently reloaded the Home channel behind the user.
//
// The fix: the scope lives in `SearchState.searchSourceId`, seeded once from
// the active source when the bloc is built and thereafter moved only by
// `SearchScopeSourceChanged`. These tests pin both halves — the search really
// does follow its own scope, and the global cubit really is left alone.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/aniyomi/aniyomi_filters.dart';
import 'package:orcabox/core/di/injector.dart' show sl;
import 'package:orcabox/core/mode/content_mode_cubit.dart';
import 'package:orcabox/core/models/home_section.dart';
import 'package:orcabox/core/models/media_item.dart';
import 'package:orcabox/core/models/provider_info.dart';
import 'package:orcabox/core/playback/search_history.dart';
import 'package:orcabox/core/playback/search_prefs.dart';
import 'package:orcabox/core/playback/search_source_prefs.dart';
import 'package:orcabox/core/playback/source_health_store.dart';
import 'package:orcabox/core/repository/source_repository.dart';
import 'package:orcabox/core/search/title_suggestion_service.dart';
import 'package:orcabox/core/state/active_source_cubit.dart';
import 'package:orcabox/features/search/bloc/search_bloc.dart';
import 'package:orcabox/features/search/bloc/search_event.dart';
import 'package:orcabox/features/search/bloc/search_state.dart';

const _homeSource = 'cs:vegamovies';
const _otherSource = 'cs:rogmovies';

MediaItem _fakeItem(String sourceId) => MediaItem(
  id: 'id-$sourceId',
  title: 'Title from $sourceId',
  url: 'https://example.com/$sourceId',
  type: ProviderType.anime,
  sourceId: sourceId,
);

/// Scoped search ("current source only") is the mode under test, so this fake
/// pins it on — that is the branch that used to read the global cubit.
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
  @override
  bool get currentSourceOnly => true;

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
  Future<void> record(
    String id,
    SourceOutcome outcome, {
    int? responseMs,
  }) async {}
}

/// Records which sourceIds actually reached the network layer — the direct
/// evidence of what the scope resolved to.
class _FakeRepo implements SourceRepository {
  final List<String> searchedSourceIds = [];

  @override
  List<({String id, String name})> get loadedSources => const [
    (id: _homeSource, name: 'Hollywood'),
    (id: _otherSource, name: 'Bollywood'),
  ];

  @override
  List<({String id, String name})> get pickableSources => loadedSources;

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
    return (items: [_fakeItem(sourceId ?? '?')], outcome: SourceOutcome.ok);
  }

  @override
  String displayName(String sourceId) => sourceId;

  @override
  String get sourceId => _homeSource;

  @override
  void syncSearchCache() {}

  // ── Everything else — never called in these tests ─────────────────────────
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
  Future<List<AniyomiFilter>> aniFilters(String sourceId) =>
      throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late ActiveSourceCubit activeSource;
  late ContentModeCubit modeCubit;
  late _FakeRepo repo;
  late SearchBloc bloc;

  setUp(() async {
    // ContentModeCubit.create() opens a real (temp) Hive box — its constructor
    // is private, so it can't be faked from this file.
    tempDir = await Directory.systemTemp.createTemp('search_home_isolation');
    Hive.init(tempDir.path);

    activeSource = ActiveSourceCubit(fallback: _homeSource);
    modeCubit = await ContentModeCubit.create(activeSource);

    // Registered in the locator because that is how the bloc seeds its initial
    // scope — and, before the fix, how it read the scope on every search.
    sl.registerSingleton<ActiveSourceCubit>(activeSource);
    sl.registerSingleton<ContentModeCubit>(modeCubit);
    sl.registerSingleton<SearchSourcePrefs>(_FakeSearchSourcePrefs());
    sl.registerSingleton<SourceHealthStore>(_FakeSourceHealthStore());

    repo = _FakeRepo();
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

  test('the scope is seeded from the active source, so Search opens where '
      'the user was browsing', () {
    expect(bloc.state.searchSourceId, _homeSource);
    expect(bloc.state.scopedSourceId, _homeSource);
  });

  test('a scoped search queries the seeded source', () async {
    bloc.add(const SearchRunRequested('naruto'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.searchedSourceIds, [_homeSource]);
  });

  test(
    'picking another source in Search does NOT move the Home source',
    () async {
      bloc.add(const SearchScopeSourceChanged(_otherSource));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        activeSource.state,
        _homeSource,
        reason:
            'this is the bug: the picker called ActiveSourceCubit.setSource(), '
            'which HomeScreen listens to, so scoping a search reloaded the Home '
            'channel',
      );
      expect(bloc.state.searchSourceId, _otherSource);
    },
  );

  test('the search then runs against the newly scoped source', () async {
    bloc.add(const SearchRunRequested('naruto'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.searchedSourceIds.clear();

    // Scoping to a new source re-runs the current query on its own.
    bloc.add(const SearchScopeSourceChanged(_otherSource));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.searchedSourceIds, [_otherSource]);
    expect(activeSource.state, _homeSource);
  });

  test(
    'a later Home channel switch does not drag the search scope with it',
    () async {
      bloc.add(const SearchScopeSourceChanged(_otherSource));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Home switches back to Hollywood (the ModeBar's own gesture).
      activeSource.setSource(_homeSource);
      repo.searchedSourceIds.clear();

      bloc.add(const SearchRunRequested('naruto'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        repo.searchedSourceIds,
        [_otherSource],
        reason:
            'the scope is seeded once, not followed live — otherwise Search '
            'would still be a mirror of Home, just in the other direction',
      );
    },
  );

  test('scoping to the source already scoped is a no-op', () async {
    bloc.add(const SearchRunRequested('naruto'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.searchedSourceIds.clear();

    bloc.add(const SearchScopeSourceChanged(_homeSource));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.searchedSourceIds, isEmpty);
  });

  test(
    '"All sources" clears the scope; picking one turns it back on',
    () async {
      bloc.add(const SearchScopeChanged(false));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.scopedSourceId, isNull);
      // The pick itself is remembered even while unscoped, so the sheet can
      // still point at it.
      expect(bloc.state.searchSourceId, _homeSource);

      bloc.add(const SearchScopeSourceChanged(_otherSource));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.currentSourceOnly, isTrue);
      expect(bloc.state.scopedSourceId, _otherSource);
      expect(activeSource.state, _homeSource);
    },
  );
}
