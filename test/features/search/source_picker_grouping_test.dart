// The search source picker lists all sources in a single flat alphabetical list
// without "Built-in" / "Installed" headings, avoiding user confusion while
// keeping all sources searchable.
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
    test('the reported list displays as a single flat alphabetical list without headings or native home providers', () {
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

    test('installed engines for sites survive, while native: providers are excluded from search picker', () {
      final ids = [
        for (final r in _rows(_reported))
          if (r.source != null) r.source!.id,
      ];
      expect(ids, containsAll(['cs:VegaMovies', 'cs:Rogmovies']));
      expect(ids, isNot(contains('native:vegamovies')));
      expect(ids, isNot(contains('native:rogmovies')));
      expect(ids, hasLength(7));
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
