// The ecosystem TAB STRIP (All · OrcaBox · CloudStream · Aniyomi) is gone —
// NOTES task 2. It filtered loaded results by which provider ecosystem a
// source came from, which is an implementation detail rather than something a
// viewer looking for a title cares about, and it split one search across
// several views. An all-sources search now aggregates every source into one
// grid; the per-source chips still narrow to a single source.
//
// What survives, and is tested here:
//   • [ecosystemOf] — still names a source ("Aniyomi") and still decides
//     whether it publishes a filter schema (browse_source_screen.dart).
//   • The group getters no longer filter by ecosystem at all, which is what
//     "one aggregated grid" means in practice.
//
// Deleted with the strip: `ecosystemTabsFor`, `SearchEcosystem.all` and
// `SearchState.ecosystem`.
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/models/media_item.dart';
import 'package:orcabox/core/models/provider_info.dart';
import 'package:orcabox/features/search/bloc/search_state.dart';

MediaItem _item(String sourceId, {String title = 'Demon Slayer'}) => MediaItem(
  id: 'id-$sourceId',
  title: title,
  url: 'https://example.com/$sourceId',
  type: ProviderType.anime,
  sourceId: sourceId,
);

SourceResultGroup _group(String sourceId, {int arrival = 0}) =>
    SourceResultGroup(
      sourceId: sourceId,
      sourceName: sourceId,
      items: [_item(sourceId)],
      arrivalIndex: arrival,
    );

void main() {
  group('ecosystemOf', () {
    test('maps the `ani:` prefix to Aniyomi', () {
      expect(ecosystemOf('ani:1'), SearchEcosystem.aniyomi);
      expect(ecosystemOf('ani:hianime'), SearchEcosystem.aniyomi);
    });

    test('maps the `cs:` prefix to CloudStream', () {
      expect(ecosystemOf('cs:AnimePahe'), SearchEcosystem.cloudstream);
      expect(ecosystemOf('cs:MovieBox@cncverse'), SearchEcosystem.cloudstream);
    });

    test('maps the manga/novel prefixes to their own ecosystems', () {
      expect(ecosystemOf('mihon:1'), SearchEcosystem.mihon);
      expect(ecosystemOf('lnr:royalroad'), SearchEcosystem.lnreader);
    });

    test('maps anything else to OrcaBox', () {
      expect(ecosystemOf('allanime'), SearchEcosystem.orcabox);
      expect(ecosystemOf('netmirror'), SearchEcosystem.orcabox);
      // No colon → not an Aniyomi/CloudStream id, so it stays OrcaBox.
      expect(ecosystemOf('anilist'), SearchEcosystem.orcabox);
      expect(ecosystemOf('csfd'), SearchEcosystem.orcabox);
      expect(ecosystemOf(''), SearchEcosystem.orcabox);
      // Native channel hubs are OrcaBox's own providers, not an extension.
      expect(ecosystemOf('native:vegamovies'), SearchEcosystem.orcabox);
      expect(ecosystemOf('native:rogmovies'), SearchEcosystem.orcabox);
    });

    test('every ecosystem still carries a display label', () {
      for (final e in SearchEcosystem.values) {
        expect(e.label, isNotEmpty);
      }
    });
  });

  group('results aggregate across every ecosystem', () {
    final groups = [
      _group('allanime', arrival: 0), // OrcaBox
      _group('cs:AnimePahe', arrival: 1), // CloudStream
      _group('ani:1', arrival: 2), // Aniyomi
    ];
    final base = SearchState().copyWith(
      status: SearchStatus.success,
      groups: groups,
    );

    test('one grid holds all three ecosystems, in arrival order', () {
      expect(base.sortedVisibleGroups.map((g) => g.sourceId), [
        'allanime',
        'cs:AnimePahe',
        'ani:1',
      ]);
      expect(base.visibleGroups.map((g) => g.sourceId), [
        'allanime',
        'cs:AnimePahe',
        'ani:1',
      ]);
      expect(base.totalCount, 3);
      expect(base.visibleResults, hasLength(3));
    });

    test('the source chips still offer every source', () {
      expect(base.sourceChipGroups.map((g) => g.sourceId), [
        'allanime',
        'cs:AnimePahe',
        'ani:1',
      ]);
    });

    test('the per-source chip is what narrows the view now', () {
      final s = base.copyWith(sourceFilter: 'cs:AnimePahe');
      expect(s.sortedVisibleGroups.map((g) => g.sourceId), ['cs:AnimePahe']);
      expect(s.visibleResults.map((i) => i.sourceId), ['cs:AnimePahe']);
      // The chip is a view filter over loaded groups, so the count of what the
      // search actually found is unchanged.
      expect(s.totalCount, 3);
    });
  });
}
