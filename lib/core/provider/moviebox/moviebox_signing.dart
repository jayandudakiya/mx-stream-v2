/// Request signing for the MovieBox / aoneroom mobile API.
///
/// Every request carries two computed headers, and the API rejects anything
/// without them (HTTP 407 `Signature invalid`):
///
///  * `x-client-token: <ms timestamp>,<md5 of the timestamp REVERSED>`
///  * `x-tr-signature: <ms timestamp>|2|<base64 HMAC-MD5 of a canonical string>`
///
/// Ported from the Rust client in `docs/MovieBox-Tui/src/providers/moviebox/`
/// and checked against the live API before any of it was written into the app.
/// Two details are easy to get wrong and cost every request:
///
///  * the HMAC key is the secret **base64-decoded**, not its ASCII bytes;
///  * the canonical string's URL is the path plus the query sorted by key —
///    the order a caller happened to write parameters in is not what is signed.
///
/// Flutter-free on purpose, like the `cloudstream_kt` layer, so the live-check
/// harness can exercise it with a plain `dart run`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// The app's signing secret, lifted from the Android client. Base64; the HMAC
/// key is what it decodes to.
const String _secretKeyBase64 = '76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O';

/// Bodies longer than this are truncated before hashing — the client does the
/// same, so a large POST still signs identically.
const int _signatureBodyMaxBytes = 102400;

final List<int> _secretBytes = _decodeLooseBase64(_secretKeyBase64);

/// Base64 that tolerates missing padding, which several values in this API
/// (the secret, CloudFront policies) are served without.
List<int> _decodeLooseBase64(String value) {
  var padded = value.trim();
  final padding = (4 - padded.length % 4) % 4;
  padded += '=' * padding;
  try {
    return base64.decode(padded);
  } catch (_) {
    return const [];
  }
}

String _md5Hex(List<int> data) => crypto.md5.convert(data).toString();

/// `x-client-token`. The hash is of the timestamp's digits reversed — not of
/// the timestamp itself.
String clientToken(int timestampMs) {
  final ts = timestampMs.toString();
  final reversed = ts.split('').reversed.join();
  return '$ts,${_md5Hex(utf8.encode(reversed))}';
}

/// The string the signature is computed over:
/// `METHOD\nAccept\nContent-Type\nbodyLength\ntimestamp\nbodyMd5\npath?sortedQuery`
///
/// A request with no body leaves the length and hash lines empty rather than
/// signing `0` and the hash of the empty string.
String canonicalString({
  required String method,
  required String url,
  String? body,
  String accept = 'application/json',
  String contentType = 'application/json',
  required int timestampMs,
}) {
  final canonicalUrl = _canonicalUrl(url);

  var bodyLength = '';
  var bodyHash = '';
  if (body != null) {
    final bytes = utf8.encode(body);
    bodyLength = bytes.length.toString();
    bodyHash = _md5Hex(
      bytes.length > _signatureBodyMaxBytes
          ? bytes.sublist(0, _signatureBodyMaxBytes)
          : bytes,
    );
  }

  return [
    method.toUpperCase(),
    accept,
    contentType,
    bodyLength,
    timestampMs,
    bodyHash,
    canonicalUrl,
  ].join('\n');
}

/// Path plus the query sorted by key (repeated keys keep their order), or just
/// the path when there is no query.
String _canonicalUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final params = uri.queryParametersAll;
  if (params.isEmpty) return uri.path;
  final keys = params.keys.toList()..sort();
  final parts = <String>[
    for (final key in keys)
      for (final value in params[key]!) '$key=$value',
  ];
  return '${uri.path}?${parts.join('&')}';
}

/// `x-tr-signature`.
String trSignature({
  required String method,
  required String url,
  String? body,
  String accept = 'application/json',
  String contentType = 'application/json',
  required int timestampMs,
}) {
  final canonical = canonicalString(
    method: method,
    url: url,
    body: body,
    accept: accept,
    contentType: contentType,
    timestampMs: timestampMs,
  );
  final mac = crypto.Hmac(crypto.md5, _secretBytes)
      .convert(utf8.encode(canonical));
  return '$timestampMs|2|${base64.encode(mac.bytes)}';
}

/// One device identity: the User-Agent and the `x-client-info` blob that must
/// agree with each other.
///
/// Randomised per install (not per request) the way the Rust client does it —
/// a fixed identity across every user of this app is the more obvious pattern
/// to rate-limit, and a per-request one contradicts itself between calls.
class MovieBoxIdentity {
  MovieBoxIdentity({
    required this.userAgent,
    required this.clientInfo,
    required this.forwardedFor,
  });

  factory MovieBoxIdentity.random([Random? random]) {
    final rng = random ?? Random();

    const androidVersions = [
      ('9', 'PQ3A.190605.03081104'),
      ('10', 'QP1A.191005.007.A3'),
      ('11', 'RP1A.200720.011'),
      ('12', 'S1B.220414.015'),
      ('13', 'TQ2A.230405.003'),
    ];
    const devices = [
      ('23078RKD5C', 'Redmi'),
      ('2201117TY', 'Redmi'),
      ('2201117TG', 'Redmi'),
      ('22101316G', 'Redmi'),
      ('21121210G', 'Redmi'),
      ('M2012K11AG', 'Redmi'),
      ('M2007J20CG', 'Redmi'),
    ];
    const versionCodes = [50020117, 50020118, 50020119, 50020120, 50020121];
    const networks = ['NETWORK_WIFI', 'NETWORK_MOBILE'];
    const timezones = [
      'Asia/Kolkata',
      'Asia/Shanghai',
      'Asia/Tokyo',
      'America/New_York',
      'Europe/London',
    ];

    final android = androidVersions[rng.nextInt(androidVersions.length)];
    final device = devices[rng.nextInt(devices.length)];
    final versionCode = versionCodes[rng.nextInt(versionCodes.length)];
    final network = networks[rng.nextInt(networks.length)];
    final timezone = timezones[rng.nextInt(timezones.length)];

    final userAgent =
        'com.community.oneroom/$versionCode (Linux; U; Android ${android.$1}; '
        'en_US; ${device.$1}; Build/${android.$2}; Cronet/135.0.7012.3)';

    final clientInfo = jsonEncode({
      'package_name': 'com.community.oneroom',
      'version_name': '4.0.01.0813.03',
      'version_code': versionCode,
      'os': 'android',
      'os_version': android.$1,
      'install_ch': 'ps',
      'device_id': _randomHex(rng, 32),
      'install_store': 'ps',
      'gaid': _randomUuid(rng),
      'brand': device.$2,
      'model': device.$1,
      'system_language': 'en',
      'net': network,
      'region': 'US',
      'timezone': timezone,
      'sp_code': '40401',
      'X-Play-Mode': '2',
    });

    return MovieBoxIdentity(
      userAgent: userAgent,
      clientInfo: clientInfo,
      forwardedFor: _randomPublicIp(rng),
    );
  }

  final String userAgent;
  final String clientInfo;

  /// Sent as `x-forwarded-for`. The API geo-gates some catalogue, and the
  /// upstream client sets this too; it is a hint to the API, not a proxy.
  final String forwardedFor;

  /// Milliseconds to add to this device's clock to match the server's.
  ///
  /// The timestamp is part of what is signed, so a device whose clock is wrong
  /// by more than the API tolerates fails EVERY request with 407 "Signature
  /// invalid" — a failure that looks exactly like a broken implementation and
  /// that no retry can fix. Phones do drift, and a freshly-flashed or
  /// battery-dead device can be far out.
  int _clockOffsetMs = 0;

  /// True once a response has told us the device clock is materially wrong.
  bool get hasClockOffset => _clockOffsetMs.abs() > 0;

  /// Learns the offset from a `Date` response header. Ignored when the device
  /// is within a minute of the server, so normal jitter changes nothing.
  void noteServerDate(String? httpDate) {
    if (httpDate == null || httpDate.isEmpty) return;
    final serverTime = _parseHttpDate(httpDate);
    if (serverTime == null) return;
    final delta =
        serverTime.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
    if (delta.abs() > 60 * 1000) _clockOffsetMs = delta;
  }

  /// The timestamp to sign with: this device's clock, corrected if we have
  /// learned that it is wrong.
  int get _timestampMs =>
      DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  /// Every header a signed request needs, for [method] and [url].
  Map<String, String> headers({
    required String method,
    required String url,
    String? body,
    String? authToken,
  }) {
    final ts = _timestampMs;
    return {
      'User-Agent': userAgent,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Connection': 'keep-alive',
      'x-client-token': clientToken(ts),
      'x-tr-signature': trSignature(
        method: method,
        url: url,
        body: body,
        timestampMs: ts,
      ),
      'x-client-info': clientInfo,
      'x-client-status': '0',
      'x-forwarded-for': forwardedFor,
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'Bearer $authToken',
    };
  }
}

String _randomHex(Random rng, int length) =>
    List.generate(length, (_) => rng.nextInt(16).toRadixString(16)).join();

String _randomUuid(Random rng) {
  String block(int n) => _randomHex(rng, n);
  return '${block(8)}-${block(4)}-${block(4)}-${block(4)}-${block(12)}';
}

/// A plausible public address. Deliberately outside the private ranges — a
/// 10.x or 192.168.x value in `x-forwarded-for` reads as obviously fabricated.
String _randomPublicIp(Random rng) {
  const firstOctets = [103, 104, 105, 106, 107, 108, 109, 110];
  return '${firstOctets[rng.nextInt(firstOctets.length)]}.'
      '${rng.nextInt(256)}.${rng.nextInt(256)}.${1 + rng.nextInt(254)}';
}

/// Parses an HTTP `Date` header (RFC 1123, e.g. `Wed, 11 Sep 2026 09:15:04 GMT`).
///
/// `DateTime.parse` does not accept that format, and `HttpDate` lives in
/// `dart:io`, which this layer avoids so it stays usable everywhere the app
/// runs. Null for anything unparseable — a missing offset is harmless, a wrong
/// one is not.
DateTime? _parseHttpDate(String value) {
  const months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  final match = RegExp(
    r'^\w{3},\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final month = months[match.group(2)];
  if (month == null) return null;
  try {
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  } catch (_) {
    return null;
  }
}
