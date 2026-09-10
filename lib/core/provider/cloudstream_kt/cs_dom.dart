/// Jsoup's idioms on top of the `html` package, so DOM lines lifted from a
/// `.cs3` provider keep reading the way they do in Kotlin.
///
/// Names that would collide with `html`'s own members (`text`, `attributes`,
/// `children`) are given distinct ones — [textTrim] rather than `text()` —
/// because a Dart extension cannot shadow an existing instance member.
library;

import 'package:html/dom.dart';

extension CsElement on Element {
  /// Jsoup `attr(name)` — "" for a missing attribute, never null.
  String attr(String name) => attributes[name] ?? '';

  /// Jsoup `selectFirst(css)`.
  Element? selectFirst(String css) => querySelector(css);

  /// Jsoup `select(css)`.
  List<Element> select(String css) => querySelectorAll(css);

  /// Jsoup `text()` — collapsed and trimmed, unlike `html`'s raw `.text`.
  String get textTrim => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Jsoup `ownText()` — this element's own text nodes, excluding children's.
  String get ownText => nodes
      .whereType<Text>()
      .map((n) => n.text)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Jsoup `absUrl(name)` — resolves a relative attribute against [base].
  String absUrl(String name, String base) {
    final raw = attr(name);
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    try {
      return Uri.parse(base).resolve(raw).toString();
    } catch (_) {
      return raw;
    }
  }

  /// The next sibling that is an element (Jsoup `nextElementSibling()`).
  Element? get nextElement {
    final siblings = parent?.children;
    if (siblings == null) return null;
    final i = siblings.indexOf(this);
    return (i >= 0 && i + 1 < siblings.length) ? siblings[i + 1] : null;
  }

  /// The previous sibling that is an element (Jsoup `previousElementSibling()`).
  Element? get previousElement {
    final siblings = parent?.children;
    if (siblings == null) return null;
    final i = siblings.indexOf(this);
    return (i > 0) ? siblings[i - 1] : null;
  }

  /// Every following element sibling up to (not including) the first whose tag
  /// is in [stopTags]. The "collect links under this heading" walk that the
  /// index-site providers all do.
  List<Element> siblingsUntil(Set<String> stopTags) {
    final out = <Element>[];
    var cur = nextElement;
    while (cur != null && !stopTags.contains(cur.localName)) {
      out.add(cur);
      cur = cur.nextElement;
    }
    return out;
  }

  /// A poster URL from whichever lazy-load attribute the theme happens to use.
  String? get imageAttr {
    for (final key in const ['data-src', 'data-lazy-src', 'src', 'data-original']) {
      final v = attr(key);
      if (v.isNotEmpty && !v.startsWith('data:image')) return v;
    }
    return null;
  }
}

extension CsDocument on Document {
  Element? selectFirst(String css) => querySelector(css);
  List<Element> select(String css) => querySelectorAll(css);
}

extension CsElementList on List<Element> {
  /// Jsoup `eachText()`.
  List<String> get eachText => map((e) => e.textTrim).where((s) => s.isNotEmpty).toList();

  /// Jsoup `eachAttr(name)`.
  List<String> eachAttr(String name) =>
      map((e) => e.attr(name)).where((s) => s.isNotEmpty).toList();
}
