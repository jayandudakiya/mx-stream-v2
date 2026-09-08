// The search source picker listed "VegaMovies" and "VegaMovies (Hollywood)"
// as adjacent rows (likewise "Rogmovies" / "RogMovies (Bollywood)"), which
// read as the same provider duplicated.
//
// They are not duplicates: `native:vegamovies` is the app's own Dart provider
// — the one driving the Hollywood Home channel — while "VegaMovies" is a
// separately installed extension that happens to scrape the same site. Two
// engines, both searchable on purpose.
//
// So nothing is renamed or hidden. The rows are grouped under "Built-in" and
// "Installed" headings, which is what makes the pairing read as deliberate.
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/features/home/search_screen.dart';

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
  group('isBuiltInSource', () {
    test('only the native: prefix counts as built-in', () {
      expect(isBuiltInSource('native:vegamovies'), isTrue);
      expect(isBuiltInSource('native:rogmovies'), isTrue);
      for (final id in [
        'cs:VegaMovies',
        'ani:1',
        'mihon:1',
        'lnr:royalroad',
        'allanime',
        '',
      ]) {
        expect(isBuiltInSource(id), isFalse, reason: '$id is user-installed');
      }
    });
  });

  group('sourcePickerRows', () {
    test('the reported list groups instead of looking duplicated', () {
      expect(_asDisplayed(_rows(_reported)), [
        '— Built-in —',
        'RogMovies (Bollywood)',
        'VegaMovies (Hollywood)',
        '— Installed —',
        'CineStream',
        'CineTmdb',
        'MoviesDrive',
        'Moviesmod',
        'Rogmovies',
        'TopMovies',
        'VegaMovies',
      ]);
    });

    test('both engines for one site survive — neither is hidden', () {
      final ids = [
        for (final r in _rows(_reported))
          if (r.source != null) r.source!.id,
      ];
      expect(ids, containsAll(['native:vegamovies', 'cs:VegaMovies']));
      expect(ids, containsAll(['native:rogmovies', 'cs:Rogmovies']));
      expect(ids, hasLength(_reported.length));
    });

    test('each group is alphabetical, case-insensitively', () {
      final rows = _rows(const [
        (id: 'cs:zeta', name: 'zeta'),
        (id: 'cs:Alpha', name: 'Alpha'),
        (id: 'native:b', name: 'bravo'),
        (id: 'native:A', name: 'Alfa'),
      ]);
      expect(_asDisplayed(rows), [
        '— Built-in —',
        'Alfa',
        'bravo',
        '— Installed —',
        'Alpha',
        'zeta',
      ]);
    });

    test('duplicate ids collapse, duplicate names do not', () {
      // A source registered twice is one row; two engines that merely have
      // similar names are two rows. That distinction is the whole point.
      final rows = _rows(const [
        (id: 'cs:A', name: 'Same'),
        (id: 'cs:A', name: 'Same'),
        (id: 'cs:B', name: 'Same'),
      ]);
      expect(_asDisplayed(rows), ['— Installed —', 'Same', 'Same']);
    });

    test('an empty group contributes no heading', () {
      expect(_asDisplayed(_rows(const [(id: 'native:v', name: 'Vega')])), [
        '— Built-in —',
        'Vega',
      ]);
      expect(_asDisplayed(_rows(const [(id: 'cs:v', name: 'Vega')])), [
        '— Installed —',
        'Vega',
      ]);
      expect(_rows(const []), isEmpty);
    });

    test('every row is exactly one of a heading or a source', () {
      for (final r in _rows(_reported)) {
        expect(r.header == null, r.source != null);
      }
    });
  });
}
