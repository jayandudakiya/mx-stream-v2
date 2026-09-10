import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/models/video_source.dart';
import 'package:orcabox/features/player/player_controller.dart';
import 'package:orcabox/features/player/player_screen.dart';
import 'package:orcabox/l10n/l10n.dart';

class _FakePlayerCubit extends Cubit<PlayerState> implements PlayerCubit {
  _FakePlayerCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('SourcesSheet displays sources, quality badges, and active state',
      (tester) async {
    const s1 = VideoSource(
      url: 'https://example.com/stream1.m3u8',
      label: 'HubCloud - Server 1',
      quality: '1080p',
      container: SourceContainer.hls,
      kind: AudioKind.sub,
    );
    const s2 = VideoSource(
      url: 'https://example.com/stream2.mp4',
      label: 'StreamWish - Mirror 2',
      quality: '720p',
      container: SourceContainer.mp4,
      kind: AudioKind.sub,
    );

    final cubit = _FakePlayerCubit(
      const PlayerState(
        sources: [s1, s2],
        active: s1,
      ),
    );

    VideoSource? selected;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SourcesSheet(
            controller: cubit,
            onSelect: (s) => selected = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Sources title and count
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Verify server labels
    expect(find.text('HubCloud - Server 1'), findsOneWidget);
    expect(find.text('StreamWish - Mirror 2'), findsOneWidget);

    // Verify quality badges
    expect(find.text('1080P'), findsOneWidget);
    expect(find.text('720P'), findsOneWidget);

    // Verify active badge on s1
    expect(find.text('ACTIVE'), findsOneWidget);

    // Tap second source
    await tester.tap(find.text('StreamWish - Mirror 2'));
    await tester.pumpAndSettle();

    expect(selected, equals(s2));
  });

  testWidgets(
      'SourcesSheet shows audio kind filter chips when multiple kinds exist',
      (tester) async {
    const subSource = VideoSource(
      url: 'https://example.com/sub.m3u8',
      label: 'Subbed Mirror',
      quality: '1080p',
      kind: AudioKind.sub,
    );
    const dubSource = VideoSource(
      url: 'https://example.com/dub.m3u8',
      label: 'Dubbed Mirror',
      quality: '1080p',
      kind: AudioKind.dub,
    );

    final cubit = _FakePlayerCubit(
      const PlayerState(
        sources: [subSource, dubSource],
        active: subSource,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SourcesSheet(
            controller: cubit,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Filter chips appear
    expect(find.text('All (2)'), findsOneWidget);
    expect(find.text('SUB (1)'), findsOneWidget);
    expect(find.text('DUB (1)'), findsOneWidget);

    // Filter by DUB
    await tester.tap(find.text('DUB (1)'));
    await tester.pumpAndSettle();

    // Only DUB mirror visible
    expect(find.text('Dubbed Mirror'), findsOneWidget);
    expect(find.text('Subbed Mirror'), findsNothing);
  });

  testWidgets('SourcesSheet displays empty state when sources is empty',
      (tester) async {
    final cubit = _FakePlayerCubit(const PlayerState(sources: []));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SourcesSheet(
            controller: cubit,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No alternate sources'), findsOneWidget);
  });
}
