import 'package:flutter/material.dart';

import '../../core/playback/pinned_sources.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/source_switcher.dart';
import '../../l10n/l10n.dart';

/// Restricts [BrowseSourcesList] to one kind-tab's buckets. Streaming = anime
/// + movies combined (they're one playback pool — see `ContentModeX.
/// matchesProvider`/`categorizedSources`); Manga and Novel map to their own
/// buckets. Null (the default) shows every bucket — the pre-tabs behaviour.
enum SourceListKind { streaming, manga, novel }

/// One source row as the buckets describe it.
typedef SourceRow = ({String id, String label, String? repo});

/// Move pinned sources into a single group at the top, in pin order.
///
/// One group across every category, the same shape the source switcher uses —
/// these two screens list the same sources and should not disagree about where
/// a pinned one lives. Pin order rather than alphabetical: the list is the
/// user's own arrangement. Pinned rows leave their category so nothing is
/// listed twice, and a category emptied by that is dropped.
///
/// Pure so the ordering can be tested without Hive or a widget tree.
List<(String, List<SourceRow>)> groupWithPinned(
  List<(String, List<SourceRow>)> groups,
  List<String> pinnedIds,
  String pinnedLabel,
) {
  final visible = [for (final g in groups) ...g.$2];
  final pinned = [
    for (final id in pinnedIds) ...visible.where((s) => s.id == id),
  ];
  final pinnedSet = {for (final s in pinned) s.id};
  return [
    if (pinned.isNotEmpty) (pinnedLabel, pinned),
    for (final (title, rows) in groups)
      (title, [for (final s in rows) if (!pinnedSet.contains(s.id)) s]),
  ].where((g) => g.$2.isNotEmpty).toList();
}

/// "Which source do you want to browse?" — the idle state of Search's Sources
/// scope, and the way into one source's own catalogue.
///
/// Reads [categorizedSources] (the same function the Home switcher uses) rather
/// than `SourceRepository.loadedSources`, which narrows by language preference:
/// right for a search fan-out, wrong for a list that claims to show what you
/// have installed.
class BrowseSourcesList extends StatelessWidget {
  const BrowseSourcesList({
    super.key,
    required this.onBrowse,
    this.query = '',
    this.kind,
  });

  final void Function(String sourceId, String name) onBrowse;

  /// Filters the rows by source name (label, and repo tag when present) —
  /// case-insensitive substring, empty = show everything. This narrows which
  /// installed sources are listed; it never touches content search.
  final String query;

  /// Which kind-tab this list is showing; null shows every bucket.
  final SourceListKind? kind;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    // Pinning is a long-press away on every row, and the switcher can change
    // it too — rebuild rather than hand back a list that lies until you leave
    // the screen.
    valueListenable: PinnedSources.notifier,
    builder: (context, pinnedIds, _) => _build(context, pinnedIds),
  );

  Widget _build(BuildContext context, List<String> pinnedIds) {
    final b = categorizedSources();
    final q = query.trim().toLowerCase();
    bool matches(SourceRow s) =>
        q.isEmpty ||
        s.label.toLowerCase().contains(q) ||
        (s.repo?.toLowerCase().contains(q) ?? false);

    final rawList = [...b.anime, ...b.movies].where(matches).toList();
    final seen = <String>{};
    final allSources = <SourceRow>[];
    for (final s in rawList) {
      if (seen.add(s.id)) allSources.add(s);
    }

    final pinnedSet = pinnedIds.toSet();
    final pinned = [
      for (final id in pinnedIds) ...allSources.where((s) => s.id == id),
    ];
    final unpinned = allSources.where((s) => !pinnedSet.contains(s.id)).toList();

    if (allSources.isEmpty) {
      final nothingInstalled = b.anime.isEmpty && b.movies.isEmpty;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          nothingInstalled
              ? context.l10n.noSourcesInstalled
              : context.l10n.noMatchesFound,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (pinned.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              context.l10n.pinned.toUpperCase(),
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (final s in pinned) _tile(s, pinnedSet.contains(s.id)),
          if (unpinned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                context.l10n.sources.toUpperCase(),
                style: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
        ],
        for (final s in unpinned) _tile(s, pinnedSet.contains(s.id)),
      ],
    );
  }

  Widget _tile(SourceRow s, bool isPinned) {
    return ListTile(
      title: Text(
        s.label,
        style: AppText.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: (s.repo == null || s.repo!.isEmpty)
          ? null
          : Text(s.repo!, style: AppText.caption),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: const Icon(
                Icons.push_pin,
                size: 15,
                color: AppColors.textTertiary,
              ),
            ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
      onTap: () => onBrowse(s.id, s.label),
      onLongPress: () => PinnedSources.toggle(s.id),
    );
  }
}
