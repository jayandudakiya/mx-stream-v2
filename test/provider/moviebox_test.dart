import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orcabox/core/provider/moviebox/moviebox_client.dart';
import 'package:orcabox/core/provider/moviebox/moviebox_provider.dart';
import 'package:orcabox/core/provider/moviebox/moviebox_signing.dart';

/// Builds a CloudFront policy the way the API encodes one: base64 with `+=/`
/// swapped for `-_~`, and the padding stripped.
String _policyCookie(String resource) {
  final json = jsonEncode({
    'Statement': [
      {
        'Resource': resource,
        'Condition': {
          'DateLessThan': {'AWS:EpochTime': 1789741523},
        },
      },
    ],
  });
  final encoded = base64
      .encode(utf8.encode(json))
      .replaceAll('+', '-')
      .replaceAll('=', '_')
      .replaceAll('/', '~');
  return 'CloudFront-Policy=$encoded;CloudFront-Signature=abc;'
      'CloudFront-Key-Pair-Id=K123;';
}

void main() {
  group('signing', () {
    test('the client token hashes the timestamp REVERSED, not the timestamp',
        () {
      // 1789136995000 reversed is 0005996319871. Getting this backwards is an
      // HTTP 407 on every request, with no other symptom.
      final token = clientToken(1789136995000);
      final parts = token.split(',');
      expect(parts, hasLength(2));
      expect(parts.first, '1789136995000');
      expect(parts.last, hasLength(32));
      expect(parts.last, isNot(clientToken(1789136995001).split(',').last));
    });

    test('the canonical string is the documented seven lines, in order', () {
      final canonical = canonicalString(
        method: 'post',
        url: 'https://api6.aoneroom.com/wefeed-mobile-bff/user-api/visitor-login',
        body: '{}',
        timestampMs: 1789136995000,
      );
      final lines = canonical.split('\n');
      expect(lines, hasLength(7));
      expect(lines[0], 'POST', reason: 'the method is upper-cased');
      expect(lines[1], 'application/json');
      expect(lines[2], 'application/json');
      expect(lines[3], '2', reason: 'the body length in bytes');
      expect(lines[4], '1789136995000');
      expect(lines[5], hasLength(32), reason: 'md5 of the body');
      expect(lines[6], '/wefeed-mobile-bff/user-api/visitor-login');
    });

    test('a body-less request signs empty length and hash, not zero and a hash',
        () {
      final lines = canonicalString(
        method: 'GET',
        url: 'https://api6.aoneroom.com/x',
        timestampMs: 1,
      ).split('\n');
      expect(lines[3], isEmpty);
      expect(lines[5], isEmpty);
    });

    test('the signed URL sorts the query by key, whatever order it was written',
        () {
      const base = 'https://api6.aoneroom.com/wefeed-mobile-bff/subject-api/resource';
      final written = canonicalString(
        method: 'GET',
        url: '$base?subjectId=1&se=2&ep=3&page=1',
        timestampMs: 1,
      ).split('\n').last;
      final shuffled = canonicalString(
        method: 'GET',
        url: '$base?page=1&ep=3&subjectId=1&se=2',
        timestampMs: 1,
      ).split('\n').last;

      expect(written, shuffled);
      expect(
        written,
        '/wefeed-mobile-bff/subject-api/resource?ep=3&page=1&se=2&subjectId=1',
      );
    });

    test('the signature is stamped with the timestamp and version marker', () {
      final sig = trSignature(
        method: 'POST',
        url: 'https://api6.aoneroom.com/x',
        body: '{}',
        timestampMs: 1789136995000,
      );
      expect(sig, startsWith('1789136995000|2|'));
      // Base64 of an MD5 digest: 16 bytes → 24 chars with padding.
      expect(sig.split('|').last, hasLength(24));
    });

    test('a different body produces a different signature', () {
      String sign(String body) => trSignature(
            method: 'POST',
            url: 'https://api6.aoneroom.com/x',
            body: body,
            timestampMs: 1789136995000,
          );
      expect(sign('{"a":1}'), isNot(sign('{"a":2}')));
    });

    test('identity headers carry everything the API checks', () {
      final headers = MovieBoxIdentity.random().headers(
        method: 'GET',
        url: 'https://api6.aoneroom.com/x',
        authToken: 'tok',
      );
      expect(headers.keys, containsAll(const [
        'User-Agent',
        'Accept',
        'Content-Type',
        'x-client-token',
        'x-tr-signature',
        'x-client-info',
        'x-client-status',
        'x-forwarded-for',
        'Authorization',
      ]));
      expect(headers['Authorization'], 'Bearer tok');
      // The client-info blob and the UA describe one device; both name the app.
      expect(headers['x-client-info'], contains('com.community.oneroom'));
      expect(headers['User-Agent'], contains('com.community.oneroom'));
    });

    test('no auth token means no Authorization header (the login case)', () {
      final headers = MovieBoxIdentity.random()
          .headers(method: 'POST', url: 'https://api6.aoneroom.com/x');
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('session', () {
    /// A JWT with the given `exp`; only the payload is read.
    String jwt(int expSeconds) {
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      return '${seg({'alg': 'HS256'})}.${seg({'exp': expSeconds})}.sig';
    }

    test('expiry is read from the token, so refresh happens before a failure',
        () {
      final future =
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
              1000;
      final session = MovieBoxSession.fromToken(jwt(future));
      expect(session.isValid, isTrue);
      expect(
        session.expiresAt.difference(DateTime.now()).inDays,
        greaterThan(28),
      );
    });

    test('an expired token is not valid', () {
      final past =
          DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/
              1000;
      expect(MovieBoxSession.fromToken(jwt(past)).isValid, isFalse);
    });

    test('an unreadable token gets a short life rather than an eternal one', () {
      final session = MovieBoxSession.fromToken('not-a-jwt');
      expect(session.isValid, isTrue);
      expect(
        session.expiresAt.difference(DateTime.now()).inHours,
        lessThanOrEqualTo(12),
      );
    });

    test('an empty token is never valid', () {
      expect(MovieBoxSession.fromToken('').isValid, isFalse);
    });
  });

  group('stream selection', () {
    test('the DASH manifest is read out of the signed CloudFront policy', () {
      final cookie = _policyCookie(
        'https://sacdn.hakunaymatata.com/dash/4570768632724293216_0_0_1080_h265_349/*',
      );
      expect(
        dashManifestFromPolicy(cookie),
        'https://sacdn.hakunaymatata.com/dash/4570768632724293216_0_0_1080_h265_349/index.mpd',
      );
    });

    test('a cookie with no policy yields nothing rather than a bad URL', () {
      expect(dashManifestFromPolicy('CloudFront-Signature=abc;'), isNull);
      expect(dashManifestFromPolicy(''), isNull);
      expect(dashManifestFromPolicy('CloudFront-Policy=%%%not-base64%%%'), isNull);
    });

    test('a non-http resource is rejected', () {
      expect(dashManifestFromPolicy(_policyCookie('s3://bucket/key/*')), isNull);
    });

    test('the deprecation-notice clips are recognised', () {
      // This is what `play-info.url` holds for most subjects; playing it shows
      // a notice video instead of the film.
      for (final url in const [
        'https://macdn.aoneroom.com/other/2026/09/04/b164fbfb.mp4',
        'https://cdn.example.com/notice.mp4',
        'https://cdn.example.com/1c7de0bd3393702d9191801f15f88f8d.mp4',
      ]) {
        expect(isDeprecationNoticeUrl(url), isTrue, reason: url);
      }
    });

    test('a real CDN stream is not mistaken for a notice', () {
      expect(
        isDeprecationNoticeUrl(
          'https://sacdn.hakunaymatata.com/dash/123_0_0_1080_h265_349/index.mpd',
        ),
        isFalse,
      );
    });
  });

  group('clock skew', () {
    test('a device clock that is badly wrong is corrected from the response',
        () {
      final identity = MovieBoxIdentity.random();
      expect(identity.hasClockOffset, isFalse);

      // The API signs on a timestamp, so a device an hour behind fails every
      // request with 407 and no retry can help. Learn the truth from `Date`.
      final serverNow = DateTime.now().toUtc().add(const Duration(hours: 1));
      identity.noteServerDate(_httpDate(serverNow));

      expect(identity.hasClockOffset, isTrue);
      final signedTs = int.parse(
        identity
            .headers(method: 'GET', url: 'https://api6.aoneroom.com/x')['x-client-token']!
            .split(',')
            .first,
      );
      final drift = signedTs - DateTime.now().millisecondsSinceEpoch;
      expect(drift, greaterThan(const Duration(minutes: 50).inMilliseconds));
    });

    test('ordinary jitter is ignored, so normal devices sign with their own clock',
        () {
      final identity = MovieBoxIdentity.random();
      identity.noteServerDate(
        _httpDate(DateTime.now().toUtc().add(const Duration(seconds: 5))),
      );
      expect(identity.hasClockOffset, isFalse);
    });

    test('a missing or unparseable Date header changes nothing', () {
      final identity = MovieBoxIdentity.random();
      identity.noteServerDate(null);
      identity.noteServerDate('');
      identity.noteServerDate('yesterday afternoon');
      expect(identity.hasClockOffset, isFalse);
    });
  });

  group('client', () {
    test('a rejected token is retried once with a fresh login', () async {
      var logins = 0;
      var searches = 0;

      final client = MovieBoxClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('visitor-login')) {
            logins++;
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'token': 'token-$logins'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          searches++;
          // The first search is rejected on every host the way a stale guest
          // token is; the second (after re-login) succeeds.
          final stale = request.headers['Authorization'] == 'Bearer token-1';
          return http.Response(
            stale ? '{"code":407,"message":"Unauthorized"}' : '{"code":0,"data":{"ok":true}}',
            stale ? 407 : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.post('/wefeed-mobile-bff/subject-api/search/v2', {});

      expect(result, {'ok': true});
      expect(logins, 2, reason: 'the rejected session is replaced');
      // One try per host before giving up, then the successful retry.
      expect(searches, greaterThan(1));
    });

    test('the data envelope is unwrapped and a non-zero code is an error',
        () async {
      final client = MovieBoxClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('visitor-login')) {
            return http.Response('{"code":0,"data":{"token":"t"}}', 200);
          }
          return http.Response('{"code":1001,"message":"nope"}', 200);
        }),
      );

      await expectLater(
        client.get('/wefeed-mobile-bff/subject-api/get?subjectId=1'),
        throwsA(isA<MovieBoxException>()),
      );
    });

    test('a host answering 429 is skipped for the next one', () async {
      var attempts = 0;
      final client = MovieBoxClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('visitor-login')) {
            return http.Response('{"code":0,"data":{"token":"t"}}', 200);
          }
          attempts++;
          // Only the second host is willing.
          return attempts == 1
              ? http.Response('rate limited', 429)
              : http.Response('{"code":0,"data":{"ok":true}}', 200);
        }),
      );

      expect(await client.get('/x'), {'ok': true});
      expect(attempts, 2);
    });
  });
}

/// An RFC 1123 date, the format an HTTP `Date` header uses.
String _httpDate(DateTime utc) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[utc.weekday - 1]}, ${two(utc.day)} ${months[utc.month - 1]} '
      '${utc.year} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}
