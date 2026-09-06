// Task 18 Part B: MatchLine moved from below the synopsis into the actions
// column, right under Play/Download. Harness mirrors
// reading_detail_routing_test.dart's lightweight GetIt stubs (no Hive boxes
// beyond MatchStore/ReaderPrefs, no platform channels) and pumps the PHONE
// DetailScreen directly.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mxstream/core/app_mode.dart';
import 'package:mxstream/core/di/injector.dart';
import 'package:mxstream/core/download/chapter_download_store.dart';
import 'package:mxstream/core/download/chapter_downloader.dart';
import 'package:mxstream/core/download/download_manager.dart';
import 'package:mxstream/core/download/download_record.dart';
import 'package:mxstream/core/metadata/metadata_enrichment.dart';
import 'package:mxstream/core/models/episode.dart';
import 'package:mxstream/core/models/media_extras.dart';
import 'package:mxstream/core/models/media_detail.dart';
import 'package:mxstream/core/models/media_item.dart';
import 'package:mxstream/core/models/provider_info.dart';
import 'package:mxstream/core/models/watch_status.dart';
import 'package:mxstream/core/playback/list_status_store.dart';
import 'package:mxstream/core/playback/my_list.dart';
import 'package:mxstream/core/playback/playback_prefs.dart';
import 'package:mxstream/core/playback/resume_store.dart';
import 'package:mxstream/core/playback/title_prefs.dart';
import 'package:mxstream/core/playback/watch_history.dart';
import 'package:mxstream/core/provider/cloudstream_provider.dart';
import 'package:mxstream/core/provider/base_provider.dart';
import 'package:mxstream/core/provider/provider_registry.dart';
import 'package:mxstream/core/reading/read_history.dart';
import 'package:mxstream/core/reading/read_store.dart';
import 'package:mxstream/core/reading/reader_prefs.dart';
import 'package:mxstream/core/repository/catalogue_repository.dart';
import 'package:mxstream/core/repository/source_repository.dart';
import 'package:mxstream/core/supabase/supabase_service.dart';
import 'package:mxstream/core/tracker/tracker_hub.dart';
import 'package:mxstream/core/trailer/trailer_service.dart';
import 'package:mxstream/core/zmode/match_store.dart';
import 'package:mxstream/core/zmode/zmode_source_prefs.dart';
import 'package:mxstream/core/zmode/source_matcher.dart';
import 'package:mxstream/features/detail/detail_screen.dart';
import 'package:mxstream/features/detail/wrong_title_sheet.dart';

// ── Minimal stubs — same shapes as reading_detail_routing_test.dart ────────

class _StubSourceRepository implements SourceRepository {
  _StubSourceRepository(this._detail);
  final MediaDetail _detail;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  List<({String id, String name})> get pickableSources => loadedSources;

  @override
  Future<MediaDetail> detail(
    String url, {
    String category = 'sub',
    String? sourceId,
    void Function(MediaDetail partial)? onPartial,
  }) async => _detail;

  @override
  void prefetch(String url, {String? sourceId}) {}

  @override
  String get sourceId => 'test';

  @override
  bool hasSource(String id) => false;

  @override
  String displayName(String id) => id;

  @override
  List<({String id, String name})> get loadedSources => const [];
}

class _FakeTitlePrefs extends TitlePrefsStore {
  @override
  String? category(String s, String u) => null;

  @override
  Future<void> setCategory(String s, String u, String c) async {}
}

class _FakeMyListStore implements MyListStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  bool contains(MediaItem m) => false;

  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class _FakeListStatusStore implements ListStatusStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  WatchStatus? statusOf(MediaItem m) => null;

  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class _FakeResumeStore implements ResumeStore {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  ResumeMark? get(String sourceId, String showId, String episodeId) => null;
}

class _FakeProviderRegistry implements ProviderRegistry {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  ProviderRegistryEntry? entryFor(String sourceId) => null;

  @override
  List<ProviderRegistryEntry> getAll() => const [];
}

class _FakeCloudStreamManager extends ChangeNotifier
    implements CloudStreamManager {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  BaseProvider? get(String sourceId) => null;

  @override
  String? repoNameForSourceId(String sourceId) => null;

  @override
  List<CloudStreamProvider> get enabled => const [];
}

class _FakeDownloadManager extends ChangeNotifier implements DownloadManager {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  DownloadRecord? recordFor(String sourceId, String showId, String episodeId) =>
      null;
}

class _FakeTrailerService extends TrailerService {
  _FakeTrailerService() : super(Dio());

  @override
  Future<String?> youtubeId({
    required String title,
    String? englishTitle,
    required ProviderType type,
    String? year,
    int? tmdbId,
    bool tmdbIsTv = false,
  }) async => null;
}

/// Enrichment that takes a beat to answer, so the screen renders ONCE with the
/// extras still in flight and again after they settle. Without the delay the
/// fetch completes before the first non-skeleton build, the tab count never
/// changes, and the TabController-rebuild path is never exercised at all.
class _SlowMetadataEnrichment extends MetadataEnrichment {
  _SlowMetadataEnrichment() : super(Dio());

  @override
  Future<int?> resolveMalId(MediaDetail d) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return null;
  }

  @override
  Future<int?> resolveTmdbId(
    String title,
    String? year,
    bool isTv, {
    String? imdbId,
  }) async => null;

  @override
  Future<int?> promoteMovieToAnimeMalId(MediaDetail d) async => null;

  @override
  Future<({List<CastMember> cast, List<MediaRelation> relations})> fetch(
    MediaDetail d,
  ) async => (cast: const <CastMember>[], relations: const <MediaRelation>[]);
}

class _FakePlaybackPrefs extends PlaybackPrefs {
  @override
  bool get autoAddToMyList => false;

  @override
  String get defaultCategory => 'sub';
}

// ── Test data ────────────────────────────────────────────────────────────

// sourceId is deliberately left as the plain stub id, not ZmodeIds.sourceId
// ('zm') — the Part B gate this suite exercises is purely URL-based
// (ZmodeIds.isZ reads widget.item.url), and a real 'zm' sourceId would also
// route the Details-tab source label through MetadataRepository, which this
// lightweight harness has no need to register.
const _zmItem = MediaItem(
  id: 'zm-anime',
  title: 'Z Mode Anime',
  url: 'zm://anime/mal:5114',
  type: ProviderType.anime,
  sourceId: 'test',
);

const _zmDetail = MediaDetail(
  id: 'zm-anime',
  title: 'Z Mode Anime',
  url: 'zm://anime/mal:5114',
  type: ProviderType.anime,
  sourceId: 'test',
  // No malId — a non-null one drives _ensureFiller into a real Jikan
  // network call (FillerService.instance is a hardcoded singleton, not
  // injectable here), which never resolves inside a widget test's pump.
  description: 'A synopsis long enough to render its own section.',
  episodes: [Episode(id: 'e1', title: 'Episode 1', url: '/e1', number: 1)],
);

const _plainItem = MediaItem(
  id: 'test-anime',
  title: 'Test Anime',
  url: 'http://test/anime',
  type: ProviderType.anime,
  sourceId: 'test',
);

const _plainDetail = MediaDetail(
  id: 'test-anime',
  title: 'Test Anime',
  url: 'http://test/anime',
  type: ProviderType.anime,
  sourceId: 'test',
  description: 'A synopsis long enough to render its own section.',
  episodes: [Episode(id: 'e1', title: 'Episode 1', url: '/e1', number: 1)],
);

void main() {
  late ZSourcePrefs prefs;
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '/tmp',
        );

    await sl.reset();
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    sl.registerSingleton<MyListStore>(_FakeMyListStore());
    sl.registerSingleton<ListStatusStore>(_FakeListStatusStore());
    sl.registerSingleton<ResumeStore>(_FakeResumeStore());
    sl.registerSingleton<ProviderRegistry>(_FakeProviderRegistry());
    sl.registerSingleton<CloudStreamManager>(_FakeCloudStreamManager());
    sl.registerSingleton<DownloadManager>(_FakeDownloadManager());
    sl.registerSingleton<TitlePrefsStore>(_FakeTitlePrefs());
    sl.registerSingleton<PlaybackPrefs>(_FakePlaybackPrefs());
    sl.registerSingleton<TrailerService>(_FakeTrailerService());
    sl.registerSingleton<TrackerHub>(TrackerHub(const []));

    tempDir = await Directory.systemTemp.createTemp('detail_zmode_test');
    Hive.init(tempDir.path);
    await ReaderPrefs.init();
    sl.registerSingleton<ReaderPrefs>(ReaderPrefs());
    await ChapterDownloadStore.init();
    sl.registerSingleton<ChapterDownloadStore>(ChapterDownloadStore());
    sl.registerLazySingleton<ChapterDownloader>(
      () => ChapterDownloader(sl<SourceRepository>(), sl<ChapterDownloadStore>()),
    );
    sl.registerSingleton<ReadStore>(_FakeReadStore());
    sl.registerSingleton<ReadHistory>(ReadHistory(SupabaseService(), () => null));
    sl.registerSingleton<WatchHistory>(
      WatchHistory(SupabaseService(), () => null),
    );

    // MatchLine's own dependencies — the source list is empty, so it settles
    // straight into the "no source" state without any async matcher work.
    final matchStore = await MatchStore.open();
    prefs = await ZSourcePrefs.open();
    sl.registerSingleton<MatchStore>(matchStore);
    sl.registerSingleton<ZSourcePrefs>(prefs);
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await sl.reset();
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpDetail(WidgetTester tester, MediaItem item, MediaDetail detail) async {
    final stub = _StubSourceRepository(detail);
    sl.registerSingleton<SourceRepository>(stub);
    sl.registerSingleton<CatalogueRepository>(sl<SourceRepository>());
    sl.registerSingleton<SourceMatcher>(SourceMatcher(
      sources: stub,
      store: sl<MatchStore>(),
      prefs: sl<ZSourcePrefs>(),
      candidates: (_) => stub.loadedSources,
    ));

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DetailScreen(item: item)));
    await tester.pump(); // let the cubit's load() resolve
    await tester.pump(); // MatchLine's own build-time resolve, if any
  }

  testWidgets('a zm:// item shows the selector under the action buttons, above the synopsis', (tester) async {
    await pumpDetail(tester, _zmItem, _zmDetail);

    expect(find.byType(MatchLine), findsOneWidget);

    final matchY = tester.getTopLeft(find.byType(MatchLine)).dy;
    final downloadY = tester
        .getTopLeft(find.byIcon(Icons.file_download_outlined).first)
        .dy;
    final synopsisY = tester
        .getTopLeft(find.textContaining('A synopsis long enough'))
        .dy;

    // Sits right after the buttons (below Download) and before the synopsis
    // section that follows it — the old placement (section 4.5) was AFTER
    // the synopsis instead.
    expect(matchY, greaterThan(downloadY));
    expect(matchY, lessThan(synopsisY));
  });

  testWidgets('a normal source item never shows the selector', (tester) async {
    await pumpDetail(tester, _plainItem, _plainDetail);

    expect(find.byType(MatchLine), findsNothing);
  });

  // Regression: the Cast tab is dropped once the extras fetch comes back
  // empty, which changes the tab count and makes _ensureTabController build a
  // second TabController. Under SingleTickerProviderStateMixin that threw
  // "multiple tickers were created" — the mixin permits ONE ticker for the
  // life of the State and never clears `_ticker`, so disposing the first
  // controller does not buy a second. Opening a title with no cast crashed the
  // page into the red error screen.
  testWidgets(
    'a title whose tab count changes rebuilds its TabController without '
    'throwing (multiple tickers)',
    (tester) async {
      // Enrichment has to still be in flight at the first non-skeleton build,
      // or the count is settled before a controller is ever made and the
      // rebuild path goes untested.
      sl.registerSingleton<MetadataEnrichment>(_SlowMetadataEnrichment());

      await pumpDetail(tester, _plainItem, _plainDetail);

      // Stage one: extras unresolved, so the Cast tab is held open.
      expect(
        find.text('Cast'),
        findsOneWidget,
        reason: 'the Cast tab must be present while extras are in flight, or '
            'the tab count never changes and this test proves nothing',
      );
      expect(tester.takeException(), isNull);

      // Stage two: extras come back empty, the tab is dropped, the count
      // changes, and a second TabController is built.
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'rebuilding the TabController must not throw',
      );
      expect(find.text('Cast'), findsNothing);
    },
  );
}

/// Empty [ReadStore] — the detail screen's resume-index lookup needs one
/// registered even though this suite only ever pumps anime (non-reading)
/// items.
class _FakeReadStore extends ReadStore {
  @override
  ({int pos, int total})? get(String sourceId, String showId, String chapterId) =>
      null;

  @override
  bool finished(String sourceId, String showId, String chapterId) => false;
}
