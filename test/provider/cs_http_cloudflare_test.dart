// The Cloudflare gate on the ported-provider HTTP client, and the one caller
// that must opt out of it.
//
// `CsDomains` probes candidate domains to decide which one a source should use.
// That probe goes through the same client as everything else, so with the app's
// solver installed a 403 from a candidate would pop a verification WebView for
// a domain about to be rejected — and a successful solve would turn the 403
// into a 200, reading as "this domain works" and pinning the source to the one
// host that needed solving. MultiMovies is the live case: the manifest names
// `multimovies.makeup`, which is blocked, while `multimovies.casa` serves the
// site cleanly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/provider/cloudstream_kt/cs_http.dart';

/// Records what the transport asked of the solver.
class _RecordingGate implements CsCloudflareGate {
  final List<String> solveCalls = [];
  final List<String> suppressedNotices = [];

  /// What [solve] hands back — null means "could not clear this host".
  ({String cookie, String? ua})? solveResult;

  @override
  bool suppressed = false;

  @override
  ({String cookie, String? ua})? clearance(String host) => null;

  @override
  Future<({String cookie, String? ua})?> solve(
    String url,
    String host, {
    required bool staleClearanceSent,
  }) async {
    solveCalls.add(host);
    return solveResult;
  }

  @override
  void noteSuppressedChallenge(String host, String url) =>
      suppressedNotices.add(host);
}

void main() {
  late HttpServer server;
  late String base;

  /// How many times the server was hit, so a retry is visible.
  var hits = 0;

  /// Status for the next response; 403 with a Cloudflare-ish body by default.
  var status = 403;

  setUp(() async {
    hits = 0;
    status = 403;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      hits++;
      request.response.statusCode = status;
      request.response.headers.set('server', 'cloudflare');
      request.response.write(
        status == 403
            ? '<html><title>Just a moment...</title></html>'
            : '<html>the real site</html>',
      );
      await request.response.close();
    });
  });

  tearDown(() async {
    app.cloudflare = null;
    await server.close(force: true);
  });

  test('a challenged response is solved and replayed by default', () async {
    final gate = _RecordingGate()
      ..solveResult = (cookie: 'cf_clearance=abc', ua: 'SolvingUA/1.0');
    app.cloudflare = gate;

    final res = await app.get(base);

    expect(gate.solveCalls, hasLength(1));
    expect(hits, 2, reason: 'the request is replayed once cleared');
    // The replay still 403s here (the fake server always does), but the point
    // is that the solve-and-retry path ran.
    expect(res.code, 403);
  });

  test('a probe never solves, however challenged the response is', () async {
    final gate = _RecordingGate()
      ..solveResult = (cookie: 'cf_clearance=abc', ua: 'SolvingUA/1.0');
    app.cloudflare = gate;

    final res = await app.get(base, solveCloudflare: false);

    expect(gate.solveCalls, isEmpty, reason: 'no verification WebView');
    expect(hits, 1, reason: 'no replay');
    expect(
      res.code,
      403,
      reason: 'the caller sees the challenge and can reject this candidate',
    );
  });

  test('a suppressed sweep records the host instead of solving it', () async {
    final gate = _RecordingGate()..suppressed = true;
    app.cloudflare = gate;

    await app.get(base);

    expect(gate.solveCalls, isEmpty);
    expect(gate.suppressedNotices, ['127.0.0.1']);
  });

  test('a solver that cannot clear the host returns the challenge unchanged',
      () async {
    final gate = _RecordingGate()..solveResult = null;
    app.cloudflare = gate;

    final res = await app.get(base);

    expect(gate.solveCalls, hasLength(1));
    expect(hits, 1, reason: 'nothing to replay with');
    expect(res.code, 403);
  });

  test('an ordinary response never reaches the solver', () async {
    status = 200;
    final gate = _RecordingGate();
    app.cloudflare = gate;

    final res = await app.get(base);

    expect(res.code, 200);
    expect(gate.solveCalls, isEmpty);
    expect(hits, 1);
  });

  test('with no gate installed, a challenge is simply returned', () async {
    final res = await app.get(base);
    expect(res.code, 403);
    expect(hits, 1);
  });
}
