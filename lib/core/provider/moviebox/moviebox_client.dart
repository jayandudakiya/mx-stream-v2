/// HTTP client for the MovieBox / aoneroom mobile API.
///
/// Unlike every other movie source in this app, MovieBox is a JSON API rather
/// than a site to scrape: no HTML parsing, no Cloudflare, and the stream URLs
/// come back as signed CDN links. What it does have is a guest session and a
/// signed-request scheme ([MovieBoxIdentity]), plus a pool of interchangeable
/// hosts that individually rate-limit.
///
/// Ported from `docs/MovieBox-Tui/src/providers/moviebox/client.rs`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'moviebox_signing.dart';

/// The API hosts, tried in order. They serve the same data; an individual one
/// answers 403/429 often enough that a single-host client looks broken.
const List<String> kMovieBoxHosts = [
  'https://api6.aoneroom.com',
  'https://api5.aoneroom.com',
  'https://api4.aoneroom.com',
  'https://api4sg.aoneroom.com',
  'https://api3.aoneroom.com',
  'https://api6sg.aoneroom.com',
  'https://api.inmoviebox.com',
];

/// Statuses worth retrying on the next host rather than surfacing.
const Set<int> _retryStatuses = {403, 406, 407, 429, 500, 502, 503, 504};

/// A guest session: a JWT and when it stops being valid.
class MovieBoxSession {
  MovieBoxSession({required this.token, required this.expiresAt});

  /// Reads `exp` out of the JWT payload so the client refreshes on time rather
  /// than after a failed request. A token whose expiry cannot be read is
  /// treated as short-lived instead of permanent.
  factory MovieBoxSession.fromToken(String token) {
    final fallback = DateTime.now().add(const Duration(hours: 12));
    final parts = token.split('.');
    if (parts.length < 2) {
      return MovieBoxSession(token: token, expiresAt: fallback);
    }
    try {
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      payload += '=' * ((4 - payload.length % 4) % 4);
      final claims = jsonDecode(utf8.decode(base64.decode(payload)));
      final exp = claims is Map ? claims['exp'] : null;
      if (exp is int) {
        return MovieBoxSession(
          token: token,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000),
        );
      }
    } catch (_) {
      // Fall through to the conservative expiry.
    }
    return MovieBoxSession(token: token, expiresAt: fallback);
  }

  final String token;
  final DateTime expiresAt;

  /// A minute of slack, so a token cannot expire between the check and the
  /// request it was checked for.
  bool get isValid =>
      token.isNotEmpty &&
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 1)));
}

class MovieBoxException implements Exception {
  MovieBoxException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status behind this, when there was one.
  final int? statusCode;

  /// 401 and 407 mean "these credentials are not acceptable" — a stale guest
  /// token, or (407) a signature the API would not verify. Both are worth one
  /// fresh login before giving up.
  bool get looksLikeAuthFailure => statusCode == 401 || statusCode == 407;

  @override
  String toString() => 'MovieBoxException: $message';
}

class MovieBoxClient {
  MovieBoxClient({
    http.Client? httpClient,
    MovieBoxIdentity? identity,
    List<String> hosts = kMovieBoxHosts,
  })  : _client = httpClient ?? http.Client(),
        identity = identity ?? MovieBoxIdentity.random(),
        _hosts = hosts;

  final http.Client _client;
  final MovieBoxIdentity identity;
  final List<String> _hosts;

  static const Duration _timeout = Duration(seconds: 20);

  MovieBoxSession? _session;

  /// Collapses concurrent logins onto one request — a cold search fans out
  /// several calls at once, and each would otherwise mint its own guest.
  Future<MovieBoxSession>? _loginInFlight;

  /// Index of the host that last worked, so a failover sticks instead of
  /// paying the dead host's timeout on every subsequent call.
  int _hostIndex = 0;

  /// A valid session token, logging in as a guest when needed.
  Future<String> _token() async {
    final current = _session;
    if (current != null && current.isValid) return current.token;

    final inFlight = _loginInFlight;
    if (inFlight != null) return (await inFlight).token;

    final future = _visitorLogin();
    _loginInFlight = future;
    try {
      final session = await future;
      _session = session;
      return session.token;
    } finally {
      _loginInFlight = null;
    }
  }

  Future<MovieBoxSession> _visitorLogin() async {
    final body = await _send(
      'POST',
      '/wefeed-mobile-bff/user-api/visitor-login',
      body: '{}',
      // The login IS how a token is obtained; sending none is the point.
      authToken: null,
    );
    final token = body is Map ? body['token'] : null;
    if (token is! String || token.trim().isEmpty) {
      throw MovieBoxException('visitor-login returned no token');
    }
    return MovieBoxSession.fromToken(token);
  }

  /// Drops the session so the next call logs in again — for a 401 that the
  /// retry loop cannot resolve by moving host.
  void invalidateSession() => _session = null;

  Future<dynamic> get(String pathAndQuery) =>
      _authed('GET', pathAndQuery);

  Future<dynamic> post(String pathAndQuery, Object? body) =>
      _authed('POST', pathAndQuery, body: jsonEncode(body ?? const {}));

  /// A signed request, with one re-login if the API rejects our credentials.
  ///
  /// A guest token outlives most sessions but not all of them, and the failure
  /// is indistinguishable from a bad host: every host answers 401/407, the pool
  /// is exhausted, and the source looks dead until the app restarts. One forced
  /// re-login turns that into a hiccup.
  Future<dynamic> _authed(
    String method,
    String pathAndQuery, {
    String? body,
    bool allowRelogin = true,
  }) async {
    try {
      return await _send(
        method,
        pathAndQuery,
        body: body,
        authToken: await _token(),
      );
    } on MovieBoxException catch (e) {
      if (!allowRelogin || !e.looksLikeAuthFailure) rethrow;
      invalidateSession();
      return _authed(method, pathAndQuery, body: body, allowRelogin: false);
    }
  }

  /// Issues one request, walking the host pool on the statuses that mean "this
  /// host, right now" rather than "this request".
  ///
  /// Returns the unwrapped `data` payload: the API answers
  /// `{code, message, data}` and every caller wants the third field. A non-zero
  /// `code` is an error even though the HTTP status is 200.
  Future<dynamic> _send(
    String method,
    String pathAndQuery, {
    String? body,
    required String? authToken,
  }) async {
    Object? lastError;
    int? lastStatus;

    for (var attempt = 0; attempt < _hosts.length; attempt++) {
      final host = _hosts[(_hostIndex + attempt) % _hosts.length];
      final url = '$host$pathAndQuery';
      try {
        final headers = identity.headers(
          method: method,
          url: url,
          body: body,
          authToken: authToken,
        );
        final uri = Uri.parse(url);
        final response = method == 'GET'
            ? await _client.get(uri, headers: headers).timeout(_timeout)
            : await _client
                .post(uri, headers: headers, body: body)
                .timeout(_timeout);

        // Every response carries the server's clock. A phone whose own clock is
        // off by more than the API tolerates fails EVERY request with 407
        // "Signature invalid", because the timestamp is part of what is signed
        // — and no amount of retrying or re-logging-in fixes it. Learning the
        // offset from the first response and signing with it does.
        identity.noteServerDate(response.headers['date']);

        if (_retryStatuses.contains(response.statusCode)) {
          lastError = 'HTTP ${response.statusCode} from $host';
          lastStatus = response.statusCode;
          continue;
        }
        if (response.statusCode != 200) {
          throw MovieBoxException(
            'HTTP ${response.statusCode} for $pathAndQuery',
            statusCode: response.statusCode,
          );
        }

        // This host answered: start from it next time.
        _hostIndex = (_hostIndex + attempt) % _hosts.length;
        return _unwrap(response.body, pathAndQuery);
      } on MovieBoxException {
        rethrow;
      } catch (e) {
        lastError = e;
        continue;
      }
    }

    developer.log(
      'all hosts failed for $pathAndQuery ($lastError)',
      name: 'MovieBox',
    );
    throw MovieBoxException(
      'all hosts failed for $pathAndQuery ($lastError)',
      // Carried so a pool exhausted by 401/407 — one stale token rejected
      // everywhere — can be retried once with a fresh login, rather than
      // reading as "the whole service is down".
      statusCode: lastStatus,
    );
  }

  dynamic _unwrap(String responseBody, String pathAndQuery) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map) return decoded;
    final code = decoded['code'];
    if (code is int && code != 0) {
      throw MovieBoxException(
        'API code $code for $pathAndQuery: ${decoded['message']}',
      );
    }
    return decoded.containsKey('data') ? decoded['data'] : decoded;
  }

  void close() => _client.close();
}
