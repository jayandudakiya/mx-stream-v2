import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/models/video_source.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_adapter.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_main_api.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_models.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_types.dart';

/// A [CsMainApi] with canned answers, so the adapter's contract with the rest
/// of the app can be pinned without touching the network.
///
/// The point of these tests is the handover: the detail screen and the player
/// only ever see what this adapter produces, so a change here is a change to
/// playback whether or not any scraper moved.
class _FakeApi implements CsMainApi {
  _FakeApi({required this.detail, this.links = const []});

  final CsLoadResponse detail;
  final List<CsExtractorLink> links;

  /// Every payload `loadLinks` was called with, in order.
  final List<String> loadLinksCalls = [];
  int loadCalls = 0;

  @override
  Future<String> get mainUrl async => 'https://example.test';

  @override
  String get providerKey => 'faketest';

  @override
  String get name => 'FakeTest';

  @override
  String get lang => 'hi';

  @override
  Set<TvType> get supportedTypes => {TvType.movie, TvType.tvSeries};

  @override
  List<CsMainPageEntry> get mainPage => mainPageOf(const {'latest/': 'Latest'});

  @override
  Future<List<CsSearchResponse>> getMainPage(
    int page,
    CsMainPageRequest request,
  ) async =>
      [
        CsSearchResponse(
          name: 'Row item p$page ${request.data}',
          url: 'https://example.test/item',
          type: TvType.movie,
        ),
      ];

  @override
  Future<List<CsSearchResponse>> search(String query) async => [
        CsSearchResponse(
          name: 'Some.Movie.2019.1080p.WEB-DL.x264',
          url: 'https://example.test/some-movie',
          type: TvType.movie,
          quality: SearchQuality.hd,
        ),
      ];

  @override
  Future<CsLoadResponse?> load(String url) async {
    loadCalls++;
    return detail;
  }

  @override
  Future<CsLinkResult> loadLinks(String data) async {
    loadLinksCalls.add(data);
    return CsLinkResult(links: links);
  }
}

CsLoadResponse _movie() => CsLoadResponse(
      name: 'Some.Movie.2019.1080p.WEB-DL.x264',
      url: 'https://example.test/some-movie',
      type: TvType.movie,
      dataUrl: 'movie-payload',
      posterUrl: 'https://example.test/p.jpg',
      plot: 'A plot.',
      year: 2019,
    );

CsLoadResponse _series() => CsLoadResponse(
      name: 'Some Show (Season 2)',
      url: 'https://example.test/some-show',
      type: TvType.tvSeries,
      posterUrl: 'https://example.test/p.jpg',
      episodes: [
        CsEpisode(data: 'ep-2-1', name: 'The Signal', season: 2, episode: 1),
        CsEpisode(data: 'ep-2-2', name: 'The Storm', season: 2, episode: 2),
      ],
    );

void main() {
  group('CsProviderAdapter — identity', () {
    test('source id is native:<providerKey>, so a custom source is a native one',
        () {
      final adapter = CsProviderAdapter(_FakeApi(detail: _movie()));
      expect(adapter.sourceId, 'native:faketest');
      expect(adapter.displayName, 'FakeTest');
    });

    test('a main-page row survives encode/decode with spaces in both halves',
        () {
      const entry = CsMainPageEntry('genre/hindi-dubbed/', 'Hindi Dubbed');
      final packed = CsProviderAdapter.encodeCategory(entry);
      final decoded = CsProviderAdapter.decodeCategory(packed);
      expect(decoded.name, 'Hindi Dubbed');
      expect(decoded.data, 'genre/hindi-dubbed/');
    });
  });

  group('CsProviderAdapter — detail screen', () {
    test('a movie yields exactly one episode keyed on the detail url', () async {
      final adapter = CsProviderAdapter(_FakeApi(detail: _movie()));
      final detail = await adapter.getDetail('https://example.test/some-movie');

      expect(detail.episodes, hasLength(1));
      expect(detail.episodes.single.url, 'https://example.test/some-movie');
      expect(detail.tmdbIsTv, isFalse);
      expect(detail.format, 'Movie');
      // The release string is cleaned for display but kept for the picker.
      expect(detail.title, 'Some Movie');
      expect(detail.englishTitle, 'Some.Movie.2019.1080p.WEB-DL.x264');
    });

    test('a series yields stable synthetic episode ids, not link payloads',
        () async {
      final adapter = CsProviderAdapter(_FakeApi(detail: _series()));
      final detail = await adapter.getDetail('https://example.test/some-show');

      expect(detail.format, 'TV');
      expect(detail.tmdbIsTv, isTrue);
      expect(detail.episodes.map((e) => e.url), [
        'https://example.test/some-show::s2e1',
        'https://example.test/some-show::s2e2',
      ]);
      // History/resume are keyed on these, so a site re-ordering its mirrors
      // must not change them.
      expect(detail.episodes.first.season, 2);
      expect(detail.episodes.first.number, 1);
      expect(detail.episodes.first.title, 'The Signal');
    });

    test('an unreadable page degrades to an empty detail, not an exception',
        () async {
      final adapter = CsProviderAdapter(_NullLoadApi());
      final detail = await adapter.getDetail('https://example.test/gone');
      expect(detail.title, isEmpty);
      expect(detail.sourceId, 'native:nulltest');
    });
  });

  group('CsProviderAdapter — player handover', () {
    test('links become VideoSources with referer headers and best quality first',
        () async {
      final api = _FakeApi(
        detail: _movie(),
        links: [
          CsExtractorLink(
            source: 'HubCloud',
            name: 'HubCloud · FSL 720p',
            url: 'https://cdn.test/720.mkv',
            quality: Qualities.p720,
            referer: 'https://example.test/',
          ),
          CsExtractorLink(
            source: 'HubCloud',
            name: 'HubCloud · FSL 1080p',
            url: 'https://cdn.test/1080.mkv',
            quality: Qualities.p1080,
            referer: 'https://example.test/',
            headers: {'X-Token': 'abc'},
          ),
        ],
      );
      final adapter = CsProviderAdapter(api);

      final sources =
          await adapter.getVideoSources('https://example.test/some-movie');

      expect(sources, hasLength(2));
      // Sorted so the player's default pick is the best mirror.
      expect(sources.first.quality, '1080p');
      expect(sources.last.quality, '720p');
      // The player forwards these to media_kit verbatim; a missing Referer is
      // a 403 on most of these CDNs.
      expect(sources.first.headers, containsPair('Referer', 'https://example.test/'));
      expect(sources.first.headers, containsPair('X-Token', 'abc'));
      expect(sources.first.container, SourceContainer.mp4);
      expect(api.loadLinksCalls, ['movie-payload']);
    });

    test('an m3u8 link is reported as HLS so the player picks the right demuxer',
        () async {
      final adapter = CsProviderAdapter(
        _FakeApi(
          detail: _movie(),
          links: [
            CsExtractorLink(
              source: 'Stream',
              name: 'Stream',
              url: 'https://cdn.test/hls2/master.m3u8',
              quality: Qualities.p1080,
            ),
          ],
        ),
      );
      final sources =
          await adapter.getVideoSources('https://example.test/some-movie');
      expect(sources.single.container, SourceContainer.hls);
      // No referer was set, so no headers map is invented.
      expect(sources.single.headers, isNull);
    });

    test('an episode id resolves back to its payload on a cold cache', () async {
      final api = _FakeApi(
        detail: _series(),
        links: [
          CsExtractorLink(
            source: 'Stream',
            name: 'Stream',
            url: 'https://cdn.test/e2.mkv',
            quality: Qualities.p720,
          ),
        ],
      );
      final adapter = CsProviderAdapter(api);

      // Straight to playback without opening the detail screen first — the
      // "resume an episode after a fresh launch" path.
      final sources = await adapter
          .getVideoSources('https://example.test/some-show::s2e2');

      expect(sources, hasLength(1));
      expect(api.loadLinksCalls, ['ep-2-2']);
      expect(api.loadCalls, 1, reason: 'the detail page is re-read once');
    });

    test('no links means no sources, not a thrown error', () async {
      final adapter = CsProviderAdapter(_FakeApi(detail: _movie()));
      final sources =
          await adapter.getVideoSources('https://example.test/some-movie');
      expect(sources, isEmpty);
    });
  });

  group('CsProviderAdapter — browse', () {
    test('search is page-1 only, so infinite scroll cannot loop', () async {
      final adapter = CsProviderAdapter(_FakeApi(detail: _movie()));
      expect(await adapter.search('x', 2), isEmpty);
      expect(await adapter.search('x', 1), hasLength(1));
    });

    test('browseMainPage forwards the decoded row and page', () async {
      final adapter = CsProviderAdapter(_FakeApi(detail: _movie()));
      final packed =
          CsProviderAdapter.encodeCategory(const CsMainPageEntry('latest/', 'Latest'));
      final items = await adapter.browseMainPage(packed, 3);
      expect(items.single.title, contains('p3'));
      expect(items.single.title, contains('latest/'));
    });
  });
}

/// A provider whose detail page cannot be read.
class _NullLoadApi extends _FakeApi {
  _NullLoadApi() : super(detail: _movie());

  @override
  String get providerKey => 'nulltest';

  @override
  Future<CsLoadResponse?> load(String url) async => null;
}
