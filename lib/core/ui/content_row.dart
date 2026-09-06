import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'reveal_item.dart';

/// An edge-bleed horizontal content row with an optional header and "See All" link.
///
/// Supports automatic horizontal scroll pagination when [onLoadMore] is provided:
/// as the user scrolls toward the right edge, the next page is fetched and appended.
class ContentRow extends StatefulWidget {
  const ContentRow({
    super.key,
    required this.title,
    this.overline,
    this.itemCount,
    this.itemBuilder,
    this.items,
    this.itemCardBuilder,
    this.onLoadMore,
    this.itemWidth = 124,
    this.itemHeight = 210,
    this.onSeeAll,
  });

  final String title;
  final String? overline;
  final int? itemCount;
  final Widget Function(BuildContext context, int index)? itemBuilder;
  final List<MediaItem>? items;
  final Widget Function(BuildContext context, MediaItem item)? itemCardBuilder;
  final Future<List<MediaItem>> Function(int page)? onLoadMore;
  final double itemWidth;
  final double itemHeight;
  final VoidCallback? onSeeAll;

  @override
  State<ContentRow> createState() => _ContentRowState();
}

class _ContentRowState extends State<ContentRow> {
  late List<MediaItem> _items = widget.items != null ? [...widget.items!] : const [];
  final Set<String> _seen = {};
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _initItems();
    if (widget.onLoadMore != null) {
      _scrollController.addListener(_onScroll);
    }
  }

  void _initItems() {
    if (widget.items != null) {
      _items = [...widget.items!];
      _seen.clear();
      for (final it in _items) {
        _seen.add(it.id.isNotEmpty ? it.id : it.url);
      }
      _page = 1;
      _hasMore = true;
    }
  }

  @override
  void didUpdateWidget(ContentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != null &&
        (widget.items!.length != oldWidget.items?.length ||
            (widget.items!.isNotEmpty &&
                oldWidget.items?.isNotEmpty == true &&
                widget.items!.first.id != oldWidget.items!.first.id))) {
      _initItems();
    }
    if (oldWidget.onLoadMore != widget.onLoadMore) {
      _scrollController.removeListener(_onScroll);
      if (widget.onLoadMore != null) {
        _scrollController.addListener(_onScroll);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || !_hasMore || !_scrollController.hasClients || widget.onLoadMore == null) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final loader = widget.onLoadMore;
    if (loader == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    List<MediaItem> next = const [];
    try {
      next = await loader(_page + 1);
    } catch (_) {
      next = const [];
    }
    if (!mounted) return;
    final fresh = <MediaItem>[];
    for (final it in next) {
      final k = it.id.isNotEmpty ? it.id : it.url;
      if (_seen.add(k)) fresh.add(it);
    }
    setState(() {
      _loading = false;
      if (fresh.isEmpty) {
        _hasMore = false;
      } else {
        _page++;
        _items.addAll(fresh);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMediaItems = widget.items != null;
    final effectiveCount = isMediaItems
        ? _items.length + (_loading ? 1 : 0)
        : (widget.itemCount ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(title: widget.title, overline: widget.overline, onSeeAll: widget.onSeeAll),
        SizedBox(
          height: widget.itemHeight,
          child: ListView.builder(
            controller: widget.onLoadMore != null ? _scrollController : null,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            cacheExtent: MediaQuery.of(context).accessibleNavigation
                ? double.infinity
                : 600,
            itemCount: effectiveCount,
            itemBuilder: (context, index) {
              if (isMediaItems && index >= _items.length) {
                return SizedBox(
                  width: 60,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                );
              }
              Widget child;
              if (isMediaItems) {
                if (widget.itemCardBuilder != null) {
                  child = widget.itemCardBuilder!(context, _items[index]);
                } else if (widget.itemBuilder != null) {
                  child = widget.itemBuilder!(context, index);
                } else {
                  child = const SizedBox.shrink();
                }
              } else {
                child = widget.itemBuilder!(context, index);
              }
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: widget.itemWidth,
                  child: RepaintBoundary(
                    child: RevealItem(
                      index: index,
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.overline, this.onSeeAll});

  final String title;
  final String? overline;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Top clears the previous row's posters so each section reads as its
      // own block; bottom is the tighter title-to-poster gap within this row.
      // The two are deliberately far apart — a header belongs to the row under
      // it, so the space above must beat the space below or the title reads as
      // a caption on the row above. Now that the poster title is a fixed two
      // lines, this gap is the same under every row instead of shifting with
      // how long the last title happened to be.
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (overline != null) ...[
            Text(overline!, style: AppText.overline),
            const SizedBox(height: 2),
          ],
          if (onSeeAll != null)
            Row(
              children: [
                Expanded(child: Text(title, style: AppText.headline)),
                GestureDetector(
                  onTap: onSeeAll,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'See All',
                      style: AppText.caption.copyWith(color: AppColors.accent),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(title, style: AppText.headline),
        ],
      ),
    );
  }
}
