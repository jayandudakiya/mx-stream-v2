// Live smoke-check for the CloudStream→Dart providers.
//
// Runs each ported provider against the REAL site — domain resolve, one main
// page row, a search, the first result's detail page, then that item's links —
// and prints what each step produced. This is the only way to know a provider
// works: the parsers fail soft by design (an unmatched selector yields an empty
// list, never an exception), so a broken provider looks exactly like a quiet
// one from inside the app.
//
// Everything under `lib/core/provider/cloudstream_kt/` except `cs_adapter.dart`
// is deliberately Flutter-free so this can run without a device:
//
//   fvm dart run tool/cs_live_check.dart                    # every provider
//   fvm dart run tool/cs_live_check.dart 4khdhub            # one provider
//   fvm dart run tool/cs_live_check.dart hdhub4u --query "Jawan"
//   fvm dart run tool/cs_live_check.dart --links            # also resolve links
//   fvm dart run tool/cs_live_check.dart --probe            # and FETCH each link
//
// A custom-source definition (an engine pointed at any site), which is exactly
// what Settings → Custom sources builds:
//
//   fvm dart run tool/cs_live_check.dart --engine dooplay --url https://hdmovie2a.sbs
//
// `--links` is off by default: link resolution walks file lockers (HubCloud,
// Driveseed, GDFlix) and takes tens of seconds per item.
import 'dart:async';
import 'dart:io';

import 'package:orcabox/core/provider/cloudstream_kt/cs_main_api.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_http.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_models.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_engines.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_spec.dart';
import 'package:orcabox/core/provider/cloudstream_kt/providers/fourkhdhub_provider.dart';
import 'package:orcabox/core/provider/cloudstream_kt/providers/hdhub4u_provider.dart';
import 'package:orcabox/core/provider/cloudstream_kt/providers/multimovies_provider.dart';
import 'package:orcabox/core/provider/cloudstream_kt/providers/uhdmovies_provider.dart';
import 'package:orcabox/core/provider/moviebox/moviebox_provider.dart';

final Map<String, CsMainApi Function()> _providers = {
  'multimovies': MultiMoviesProvider.new,
  'hdhub4u': HdHub4uProvider.new,
  'uhdmovies': UhdMoviesProvider.new,
  '4khdhub': FourKHdHubProvider.new,
  // Not a CloudStream port — a signed JSON API — but it implements the same
  // CsMainApi, so the harness drives it identically.
  'moviebox': MovieBoxProvider.new,
};

const String _defaultQuery = 'Avengers';

Future<void> main(List<String> args) async {
  final withLinks = args.contains('--links') || args.contains('--probe');
  // `--probe` also FETCHES each resolved link with its own headers, which is
  // the only way to tell a link that resolved from a link that plays.
  probeLinks = args.contains('--probe');
  final query = _argValue(args, '--query') ?? _defaultQuery;
  final engineName = _argValue(args, '--engine');
  final customUrl = _argValue(args, '--url');
  // Provider keys are the bare words — minus any flag's value, which is a bare
  // word too and would otherwise be read as a provider name.
  final flagValueAt = {
    for (final flag in const ['--query', '--engine', '--url'])
      if (args.contains(flag)) args.indexOf(flag) + 1,
  };
  final keys = [
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && !flagValueAt.contains(i)) args[i],
  ];

  registerCsExtractors();

  // An ad-hoc source definition, the same thing Settings → Custom sources
  // builds: one engine pointed at one URL. This is how a site from
  // `url-sources.json` gets checked before anyone adds it as a custom source.
  if (engineName != null || customUrl != null) {
    final engine = CsEngineId.byName(engineName);
    if (engine == null || customUrl == null || customUrl.isEmpty) {
      stderr.writeln(
        'Usage: --engine <${CsEngineId.values.map((e) => e.name).join('|')}> '
        '--url <https://site>',
      );
      exitCode = 2;
      return;
    }
    final ok = await _check(
      buildCsApi(
        CsSourceSpec(
          engineId: engine,
          key: 'custom_live_check',
          name: Uri.tryParse(customUrl)?.host ?? customUrl,
          baseUrl: customUrl,
          isCustom: true,
        ),
      ),
      query: query,
      links: withLinks,
    );
    stdout.writeln('');
    stdout.writeln(ok ? 'custom source works' : 'custom source FAILED');
    exitCode = ok ? 0 : 1;
    return;
  }

  final selected = keys.isEmpty
      ? _providers.keys.toList()
      : keys.where(_providers.containsKey).toList();
  if (selected.isEmpty) {
    stderr.writeln('No such provider. Known: ${_providers.keys.join(', ')}');
    exitCode = 2;
    return;
  }

  var failures = 0;
  for (final key in selected) {
    final ok = await _check(_providers[key]!(), query: query, links: withLinks);
    if (!ok) failures++;
  }

  stdout.writeln('');
  stdout.writeln('${selected.length - failures}/${selected.length} providers passed');
  exitCode = failures == 0 ? 0 : 1;
}

String? _argValue(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

bool probeLinks = false;

Future<bool> _check(
  CsMainApi api, {
  required String query,
  required bool links,
}) async {
  stdout.writeln('');
  stdout.writeln('═══ ${api.name} (${api.providerKey}) ═══');

  // Through the provider itself, so the harness exercises the same resolution
  // path the app does (pinned URL, else the probed live domain).
  final base = await _step('domain', () => api.mainUrl);
  stdout.writeln('  base url      : ${base ?? 'FAILED'}');
  if (base == null || base.isEmpty) return false;

  // Main page: the first row only. A provider whose rows are all empty still
  // "works" for search, so this is reported but not fatal on its own.
  var mainCount = 0;
  if (api.mainPage.isNotEmpty) {
    final entry = api.mainPage.first;
    final rows = await _step(
      'mainPage',
      () => api.getMainPage(1, CsMainPageRequest(name: entry.name, data: entry.data)),
    );
    mainCount = rows?.length ?? 0;
    stdout.writeln('  mainPage[${entry.name}] : $mainCount items'
        '${mainCount > 0 ? '  e.g. ${rows!.first.name}' : ''}');
  }

  final results = await _step('search', () => api.search(query));
  final hits = results ?? const <CsSearchResponse>[];
  stdout.writeln('  search("$query") : ${hits.length} items');
  for (final r in hits.take(3)) {
    stdout.writeln('      • ${r.name}  [${r.type.name}]  ${r.url}');
  }

  // Fall back to a main-page item so a provider whose search is down can still
  // have its detail/link path checked.
  final target = hits.isNotEmpty ? hits.first.url : null;
  if (target == null) {
    stdout.writeln('  detail        : skipped (nothing to open)');
    return mainCount > 0;
  }

  final detail = await _step('load', () => api.load(target));
  if (detail == null) {
    stdout.writeln('  detail        : FAILED');
    return false;
  }
  stdout.writeln('  detail        : "${detail.name}" ${detail.year ?? ''} '
      '${detail.isSeries ? '${detail.episodes.length} episodes' : 'movie'}'
      '${detail.posterUrl != null ? ' +poster' : ' NO POSTER'}');
  if (detail.isSeries) {
    for (final e in detail.episodes.take(3)) {
      stdout.writeln('      • S${e.season}E${e.episode} ${e.name ?? ''}');
    }
  }

  if (!links) {
    stdout.writeln('  links         : skipped (pass --links)');
    return true;
  }

  final payload = detail.isSeries
      ? (detail.episodes.isEmpty ? null : detail.episodes.first.data)
      : (detail.dataUrl ?? detail.url);
  if (payload == null) {
    stdout.writeln('  links         : no payload');
    return false;
  }

  final result = await _step(
    'loadLinks',
    () => api.loadLinks(payload),
    timeout: const Duration(seconds: 120),
  );
  final count = result?.links.length ?? 0;
  stdout.writeln('  links         : $count');
  for (final l in (result?.links ?? const []).take(5)) {
    stdout.writeln('      • [${l.qualityLabel ?? l.quality}] ${l.name} '
        '→ ${l.url.length > 90 ? '${l.url.substring(0, 90)}…' : l.url}');
    if (probeLinks) await _probeLink(l);
  }
  return count > 0;
}

/// Fetches a resolved link exactly as the player would — same headers, same
/// Referer — and reports what the CDN says.
///
/// A link that resolves is not a link that plays: these hosts accept or refuse
/// on the Referer and on signed cookies, and the difference between the two
/// shows up in the app only as a spinner that never ends. This is the cheapest
/// place to see the actual status.
Future<void> _probeLink(CsExtractorLink link) async {
  final headers = <String, String>{
    ...link.headers,
    if (link.referer != null && link.referer!.isNotEmpty)
      'Referer': link.referer!,
    // A playlist is small enough to read; for a media file one byte is proof
    // enough that the host would serve it.
    if (!_isPlaylist(link.url)) 'Range': 'bytes=0-1',
  };
  try {
    final res = await app
        .get(link.url, headers: headers, timeout: const Duration(seconds: 15));
    final type = res.headers['content-type'] ?? '';
    final ok = res.code >= 200 && res.code < 400;
    final detail = _isPlaylist(link.url) && ok
        ? ' ${res.text.trim().split('\n').length} lines'
        : '';
    stdout.writeln(
      '         ${ok ? 'PLAYS' : 'REFUSED'} ${res.code} '
      '${type.isEmpty ? '' : '($type)'}$detail',
    );
    if (ok && _isPlaylist(link.url) && !res.text.contains('#EXT')) {
      stdout.writeln('         !! 200 but not a playlist — likely a block page');
    }
  } catch (e) {
    stdout.writeln('         REFUSED ($e)');
  }
}

bool _isPlaylist(String url) {
  final u = url.toLowerCase();
  return u.contains('.m3u8') || u.contains('.mpd');
}

/// Runs one step, printing (rather than throwing) whatever goes wrong — the
/// point of the harness is to see every step's outcome, not to stop at the
/// first bad one.
Future<T?> _step<T>(
  String label,
  Future<T> Function() body, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final started = DateTime.now();
  try {
    return await body().timeout(timeout);
  } on TimeoutException {
    stdout.writeln('  !! $label timed out after ${timeout.inSeconds}s');
    return null;
  } catch (e) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln('  !! $label threw after ${ms}ms: $e');
    return null;
  }
}
