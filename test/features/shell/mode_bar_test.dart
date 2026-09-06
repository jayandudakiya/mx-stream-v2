import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxstream/core/mode/content_mode.dart';
import 'package:mxstream/core/zmode/zmode_prefs.dart';
import 'package:mxstream/features/shell/mode_bar.dart';

void main() {
  testWidgets('shows the two channels and reports the pick', (t) async {
    ModeChoice? picked;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: true,
        current: (ContentMode.anime, StreamKind.movie),
        activeSourceId: 'native:vegamovies',
        onPicked: (c) => picked = c,
      ),
    )));

    expect(find.text('Hollywood'), findsOneWidget);
    expect(find.text('Bollywood'), findsOneWidget);

    await t.tap(find.text('Hollywood'));
    expect(picked?.sourceId, 'native:vegamovies');
    expect(picked?.kind, StreamKind.movie);

    await t.tap(find.text('Bollywood'));
    expect(picked?.sourceId, 'native:rogmovies');
    expect(picked?.kind, StreamKind.movie);
  });

  testWidgets('closed bar ignores taps', (t) async {
    var picked = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: false,
        current: (ContentMode.anime, StreamKind.anime),
        activeSourceId: '',
        onPicked: (_) => picked++,
      ),
    )));
    await t.tap(find.text('Hollywood'), warnIfMissed: false);
    expect(picked, 0);
  });
}
