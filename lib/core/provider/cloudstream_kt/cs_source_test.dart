import 'dart:async';

import 'cs_engines.dart';
import 'cs_http.dart';
import 'cs_models.dart';
import 'cs_spec.dart';

/// What a test run found.
enum CsTestOutcome {
  /// The site answered and the engine understood it.
  working,

  /// The site answered, but the engine read nothing out of it — almost always
  /// the wrong engine for this site, occasionally a site that has changed.
  wrongEngine,

  /// Reached, but behind a Cloudflare interstitial. Not a failure: the app can
  /// solve one when the user opens something, and search stays quiet until then.
  cloudflare,

  /// Nothing answered — dead domain, typo, or no connectivity.
  unreachable,
}

/// The result of testing one source definition.
class CsTestResult {
  const CsTestResult({
    required this.outcome,
    required this.baseUrl,
    this.browseCount = 0,
    this.searchCount = 0,
    this.sampleTitle,
    this.detail,
  });

  final CsTestOutcome outcome;

  /// The URL actually used, after normalisation and any redirect.
  final String baseUrl;
  final int browseCount;
  final int searchCount;

  /// A title that came back, so the user can see it found the right site.
  final String? sampleTitle;

  /// One line of extra context for the failure cases.
  final String? detail;

  bool get isUsable =>
      outcome == CsTestOutcome.working || outcome == CsTestOutcome.cloudflare;
}

/// Runs a real request against a source definition and reports what came back.
///
/// This exists because the failure modes here are indistinguishable from the
/// outside: a wrong engine, a dead domain and a Cloudflare block all produce an
/// empty list. Someone adding a source needs to know which of the three they
/// have — a "Test" button that says "reached the site, but this engine read
/// nothing from it" is the difference between fixing the setting in five seconds
/// and concluding the feature is broken.
///
/// Browses first (no query needed, and the cheapest page), then searches, so a
/// site whose browse rows use different category paths than its family still
/// gets credit for a working search — which is what cross-source search uses.
Future<CsTestResult> testCsSource(
  CsSourceSpec spec, {
  String query = 'the',
  Duration timeout = const Duration(seconds: 25),
}) async {
  registerCsExtractors();
  final api = buildCsApi(spec);

  String baseUrl;
  try {
    baseUrl = await api.mainUrl.timeout(const Duration(seconds: 15));
  } catch (_) {
    return CsTestResult(
      outcome: CsTestOutcome.unreachable,
      baseUrl: spec.baseUrl ?? '',
      detail: 'Could not resolve a base URL for this source.',
    );
  }
  if (baseUrl.isEmpty) {
    return const CsTestResult(
      outcome: CsTestOutcome.unreachable,
      baseUrl: '',
      detail: 'No base URL.',
    );
  }

  // Is the site there at all? Separating this from parsing is what lets the
  // result distinguish "dead domain" from "wrong engine".
  final int code;
  try {
    final res = await app.get(baseUrl, timeout: const Duration(seconds: 12));
    code = res.code;
  } catch (_) {
    return CsTestResult(
      outcome: CsTestOutcome.unreachable,
      baseUrl: baseUrl,
      detail: 'No response from $baseUrl',
    );
  }
  if (code == 403 || code == 503) {
    return CsTestResult(
      outcome: CsTestOutcome.cloudflare,
      baseUrl: baseUrl,
      detail: 'The site is behind a Cloudflare check ($code). '
          'Playback will ask you to verify once.',
    );
  }
  if (code >= 400) {
    return CsTestResult(
      outcome: CsTestOutcome.unreachable,
      baseUrl: baseUrl,
      detail: '$baseUrl answered HTTP $code.',
    );
  }

  var browse = 0;
  var search = 0;
  String? sample;

  if (api.mainPage.isNotEmpty) {
    final entry = api.mainPage.first;
    try {
      final rows = await api
          .getMainPage(1, CsMainPageRequest(name: entry.name, data: entry.data))
          .timeout(timeout);
      browse = rows.length;
      if (rows.isNotEmpty) sample = rows.first.name;
    } catch (_) {
      // Leave browse at 0 — search still decides the verdict.
    }
  }

  try {
    final hits = await api.search(query).timeout(timeout);
    search = hits.length;
    sample ??= hits.isEmpty ? null : hits.first.name;
  } catch (_) {
    // Same: an engine that throws here is reported as "read nothing".
  }

  if (browse == 0 && search == 0) {
    return CsTestResult(
      outcome: CsTestOutcome.wrongEngine,
      baseUrl: baseUrl,
      detail: 'Reached $baseUrl, but the '
          '${csEngineInfo(spec.engineId).label} engine found no titles on it. '
          'Try a different engine.',
    );
  }

  return CsTestResult(
    outcome: CsTestOutcome.working,
    baseUrl: baseUrl,
    browseCount: browse,
    searchCount: search,
    sampleTitle: sample,
  );
}
