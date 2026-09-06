import 'package:html/dom.dart' as dom;

/// Shared parsing helpers for VegaMovies-style series pages (VegaMovies,
/// RogMovies). Mirrors the selectors and matching order of the CloudStream
/// Kotlin providers these are ported from.
///
/// Ported verbatim from MXStream's
/// `functions/fetchers/providers/core/series_page_parser.dart`.

/// CloudStream keys movie-vs-series off the page's own synopsis heading:
/// `h3:matches((?i)Series-SYNOPSIS/PLOT)`, `Series Info`, `Series synopsis/PLOT`.
final RegExp _seriesSynopsisHeading =
    RegExp(r'series[\s\-–—]*(?:synopsis|info|plot)', caseSensitive: false);

/// The movie-page counterpart — any synopsis/plot heading without the "Series"
/// prefix. Used only to tell "this page says movie" apart from "this page has
/// no heading we recognise".
final RegExp _anySynopsisHeading =
    RegExp(r'(?:synopsis|storyline|plot|movie\s*info)', caseSensitive: false);

final RegExp _qualityHeadingRegex = RegExp(r'(4K|[0-9]*0p)', caseSensitive: false);
final RegExp _zipHeadingRegex = RegExp(r'Zip', caseSensitive: false);
final RegExp _seasonRegex = RegExp(r'(?:Season |S)(\d+)');
final RegExp _unilinkRegex = RegExp(r'V-Cloud|Episode|Download', caseSensitive: false);
final RegExp _unilinkFallbackRegex = RegExp(r'G-Direct|V-Drive', caseSensitive: false);

/// Whether a details page declares itself a series, read from the page's own
/// synopsis heading the way CloudStream's `tvtype` does.
///
/// Returns null when the page carries no synopsis heading of either kind, so
/// the caller can fall back to its own heuristic rather than guessing "movie".
///
/// The release title is not a sound signal in either direction: a series page
/// whose `<h1>` never says "Season" gets read as a movie and loses every
/// episode, and a film whose name merely contains the word "Season" gets read
/// as a series and shows an empty episode list. Both fail with "No episodes
/// found for this season" while the same page plays fine in CloudStream.
bool? pageDeclaresSeries(dynamic document) {
  // h3 is what CloudStream selects; the widened pass only runs when the strict
  // form recognises nothing, matching the convention in [seriesQualityHeadings].
  for (final selector in const ['h3', 'h1, h2, h3, h4, h5, h6']) {
    final List<dom.Element> els = document.querySelectorAll(selector);
    if (els.any((el) => _seriesSynopsisHeading.hasMatch(el.text))) return true;
    if (els.any((el) => _anySynopsisHeading.hasMatch(el.text))) return false;
  }
  return null;
}

/// Quality headings on a series page, mirroring CloudStream's
/// `main > h3|h5:matches((?i)(4K|[0-9]*0p))`. A broader selector pulls in
/// unrelated headings, which fans out to wrong pages and shifts episode
/// indexes. The widened retry only runs when the strict form finds nothing.
List<dom.Element> seriesQualityHeadings(dynamic document) {
  List<dom.Element> pick(String selector) {
    final List<dom.Element> found = document.querySelectorAll(selector);
    return found
        .where((el) =>
            _qualityHeadingRegex.hasMatch(el.text) &&
            !_zipHeadingRegex.hasMatch(el.text))
        .toList();
  }

  final strict = pick('main > h3, main > h5');
  return strict.isNotEmpty ? strict : pick('h3, h5');
}

/// True when the page advertises quality headings but every one of them is a
/// complete-season archive, so [seriesQualityHeadings] legitimately yields
/// nothing.
///
/// VegaMovies publishes some titles only as `Season 1 Complete {Hindi-English}
/// 480p WEB-DL x264 [1.4GB/ZiP]`, whose download page carries a single V-Cloud
/// link to a `.zip` of the whole season. Those are excluded because episode
/// numbering here is positional — a pack link would silently become "Episode
/// 1". The exclusion is right; reporting it as "no episodes found" is not.
///
/// Purely diagnostic: it never widens what [seriesQualityHeadings] returns.
bool seriesHeadingsArePackOnly(dynamic document) {
  if (seriesQualityHeadings(document).isNotEmpty) return false;

  bool anyZipQualityHeading(String selector) {
    final List<dom.Element> found = document.querySelectorAll(selector);
    return found.any((el) =>
        _qualityHeadingRegex.hasMatch(el.text) &&
        _zipHeadingRegex.hasMatch(el.text));
  }

  return anyZipQualityHeading('main > h3, main > h5') ||
      anyZipQualityHeading('h3, h5');
}

String resolutionOfHeading(dom.Element tag) {
  final text = tag.text;
  if (text.contains('480p')) return '480p';
  if (text.contains('1080p')) return '1080p';
  if (text.contains('2160p') || text.contains('4K')) return '2160p 4K';
  return '720p';
}

/// 0 when the heading carries no season marker.
int seasonOfHeading(dom.Element tag) =>
    int.tryParse(_seasonRegex.firstMatch(tag.outerHtml)?.group(1) ?? '') ?? 0;

/// Anchors belonging to a quality heading: the following `<p>` when there is
/// one, otherwise the heading itself.
List<dom.Element> headingAnchors(dom.Element tag) {
  final pTag = tag.nextElementSibling;
  return (pTag != null && pTag.localName == 'p')
      ? pTag.querySelectorAll('a')
      : tag.querySelectorAll('a');
}

/// The single download-page link belonging to a quality heading. CloudStream
/// takes the first match only; following every match hits the same page
/// repeatedly and duplicates sources.
String? unilinkFor(dom.Element tag) {
  final aTags = headingAnchors(tag);

  dom.Element? unilink;
  for (final a in aTags) {
    if (_unilinkRegex.hasMatch(a.text)) {
      unilink = a;
      break;
    }
  }
  if (unilink == null) {
    for (final a in aTags) {
      if (_unilinkFallbackRegex.hasMatch(a.text)) {
        unilink = a;
        break;
      }
    }
  }

  final href = unilink?.attributes['href'];
  return (href == null || href.isEmpty) ? null : href;
}

/// Episode links on a download page in document order — the position *is* the
/// episode number. Mixing host types would desynchronise that numbering, so
/// hubcloud is only consulted when the page carries no vcloud links at all.
List<String> episodeLinks(dynamic downloadPage) {
  final List<dom.Element> anchors = downloadPage.querySelectorAll('p > a');

  List<String> collect(String host) {
    final hrefs = <String>[];
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      if (href.toLowerCase().contains(host) && !hrefs.contains(href)) {
        hrefs.add(href);
      }
    }
    return hrefs;
  }

  final vcloud = collect('vcloud');
  return vcloud.isNotEmpty ? vcloud : collect('hubcloud');
}
