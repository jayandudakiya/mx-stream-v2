// The search source picker lists sources in a single flat alphabetical list
// without "Built-in" / "Installed" headings.
//
// Exactly one kind of source is held back: a Home *channel*. Those duplicate an
// installed CloudStream extension for the same site ("VegaMovies (Hollywood)"
// beside "VegaMovies"), which is what made the sheet read as listing one source
// twice. Every other `native:` source — the ported CloudStream engines, and
// anything the user adds under Settings → Custom sources — is an ordinary row,
// because nothing else in the app opens those.
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/ui/source_switcher.dart';
import 'package:orcabox/features/home/search_screen.dart';
import 'package:orcabox/features/shell/mode_bar.dart';

typedef _Source = ({String id, String name});

/// The list from the reported screenshot, in the arbitrary order the source
/// managers happen to concatenate them.
const _reported = <_Source>[
  (id: 'native:vegamovies', name: 'VegaMovies (Hollywood)'),
  (id: 'cs:CineStream', name: 'CineStream'),
  (id: 'cs:VegaMovies', name: 'VegaMovies'),
  (id: 'native:rogmovies', name: 'RogMovies (Bollywood)'),
  (id: 'cs:Moviesmod', name: 'Moviesmod'),
  (id: 'cs:Rogmovies', name: 'Rogmovies'),
  (id: 'cs:CineTmdb', name: 'CineTmdb'),
  (id: 'cs:MoviesDrive', name: 'MoviesDrive'),
  (id: 'cs:TopMovies', name: 'TopMovies'),
];

List<SourcePickerRow> _rows(Iterable<_Source> sources) => sourcePickerRows(
  sources,
  builtInLabel: 'Built-in',
  installedLabel: 'Installed',
);

/// Renders the sheet as the user would read it, headings included.
List<String> _asDisplayed(List<SourcePickerRow> rows) => [
  for (final r in rows)
    if (r.header != null) '— ${r.header} —' else r.source!.name,
];

void main() {
  group('isHomeChannelSource', () {
    test('only the two Home channels count as channels', () {
      expect(isHomeChannelSource('native:vegamovies'), isTrue);
      expect(isHomeChannelSource('native:rogmovies'), isTrue);
      for (final id in [
        // Ported CloudStream engines: native, but not channels.
        'native:multimovies',
        'native:hdhub4u',
        'native:uhdmovies',
        'native:4khdhub',
        // A user-added custom source.
        'native:custom_k3f9a1',
        'cs:VegaMovies',
        'ani:1',
        'mihon:1',
        'lnr:royalroad',
        'allanime',
        '',
      ]) {
        expect(isHomeChannelSource(id), isFalse, reason: '$id is not a channel');
      }
    });

    test('the channel set matches what the mode bar actually offers', () {
      // Adding a channel to `modeChoices` without listing it here would leak a
      // duplicate row back into search — the exact bug the exclusion exists for.
      final fromBar = {
        for (final c in modeChoices)
          if (c.sourceId != null) c.sourceId!,
      };
      expect(fromBar, kHomeChannelSourceIds);
    });
  });

  group('sourcePickerRows', () {
    test('the reported list displays as a single flat alphabetical list without '
        'headings or the Home channels', () {
      expect(_asDisplayed(_rows(_reported)), [
        'CineStream',
        'CineTmdb',
        'MoviesDrive',
        'Moviesmod',
        'Rogmovies',
        'TopMovies',
        'VegaMovies',
      ]);
    });

    test('installed engines survive while the Home channels are excluded', () {
      final ids = [
        for (final r in _rows(_reported))
          if (r.source != null) r.source!.id,
      ];
      expect(ids, containsAll(['cs:VegaMovies', 'cs:Rogmovies']));
      expect(ids, isNot(contains('native:vegamovies')));
      expect(ids, isNot(contains('native:rogmovies')));
      expect(ids, hasLength(7));
    });

    test('ported engines and custom sources ARE listed', () {
      // Without this they have no way into the app at all: no channel button,
      // and search was filtering every `native:` id out.
      final rows = _rows(const [
        (id: 'native:vegamovies', name: 'VegaMovies (Hollywood)'),
        (id: 'native:multimovies', name: 'MultiMovies'),
        (id: 'native:custom_k3f9a1', name: 'My Site'),
        (id: 'cs:CineStream', name: 'CineStream'),
      ]);
      expect(_asDisplayed(rows), ['CineStream', 'MultiMovies', 'My Site']);
    });

    test('the list is alphabetical, case-insensitively', () {
      final rows = _rows(const [
        (id: 'cs:zeta', name: 'zeta'),
        (id: 'cs:Alpha', name: 'Alpha'),
        (id: 'cs:b', name: 'bravo'),
        (id: 'cs:A', name: 'Alfa'),
      ]);
      expect(_asDisplayed(rows), [
        'Alfa',
        'Alpha',
        'bravo',
        'zeta',
      ]);
    });

    test('duplicate ids collapse, duplicate names do not', () {
      final rows = _rows(const [
        (id: 'cs:A', name: 'Same'),
        (id: 'cs:A', name: 'Same'),
        (id: 'cs:B', name: 'Same'),
      ]);
      expect(_asDisplayed(rows), ['Same', 'Same']);
    });

    test('an empty list contributes no rows', () {
      expect(_rows(const []), isEmpty);
    });

    test('every row has no heading and has a source', () {
      for (final r in _rows(_reported)) {
        expect(r.header, isNull);
        expect(r.source, isNotNull);
      }
    });
  });
}
