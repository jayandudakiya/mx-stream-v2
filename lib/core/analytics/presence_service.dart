import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../environment.dart';
import '../hive/safe_box.dart';
import '../privacy/privacy_consent_prefs.dart';

/// Live user counter, backed by Supabase.
///
/// A free alternative to the GA4 Realtime API: the app upserts a heartbeat row
/// every [_interval] while it is in the foreground, and the website counts rows
/// whose `last_seen` is recent. Compared with GA4 this is second-accurate
/// instead of bucketed to 30 minutes, and DAU/MAU are immediate instead of
/// lagging ~24h.
///
/// Deliberately does NOT use `supabase_flutter`: the SDK is only initialized
/// when [AppFeatures.cloudAccounts] is on, and presence must work regardless.
/// A plain PostgREST upsert over `http` needs no client and no session.
///
/// Privacy:
///  * Gated on the same privacy consent as Firebase Analytics — a user who
///    declined is never counted and never sends a request.
///  * The id is a random UUID minted on this install. It is not a device
///    identifier and cannot be correlated to a person, an account, or a
///    reinstall.
///  * No title, watch history, or location is ever sent.
abstract final class PresenceService {
  static const String _boxName = 'app_prefs';
  static const String _deviceIdKey = 'presence_device_id';

  /// How often a foregrounded app refreshes its heartbeat. The website counts a
  /// device as "active now" for 5 minutes, so this leaves room for one missed
  /// ping (flaky network, dozing radio) before a real user drops off the count.
  static const Duration _interval = Duration(minutes: 2);

  static Timer? _timer;
  static String? _deviceId;

  static bool get _configured =>
      Environment.supabaseUrl.isNotEmpty &&
      Environment.supabaseAnonKey.isNotEmpty;

  /// Begin heartbeating. Safe to call repeatedly — a second call is ignored
  /// while a timer is already running.
  static void start() {
    if (_timer != null) return;
    if (!_configured || !PrivacyConsentPrefs.isAccepted()) return;
    unawaited(_ping());
    _timer = Timer.periodic(_interval, (_) => unawaited(_ping()));
  }

  /// Stop heartbeating (app backgrounded, or consent withdrawn). The row is
  /// left behind and simply ages out of the "active now" window on its own.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Random v4 UUID, minted once per install and kept in the shared prefs box.
  ///
  /// Uses [Random.secure] so ids can't be guessed or replayed between installs.
  static Future<String> _ensureDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : await openBoxSafely(_boxName);
    var id = box.get(_deviceIdKey) as String?;
    if (id == null || id.isEmpty) {
      id = _randomUuidV4();
      await box.put(_deviceIdKey, id);
    }
    return _deviceId = id;
  }

  static String _randomUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<void> _ping() async {
    // Re-checked on every tick, not just at start(), so revoking consent stops
    // the next heartbeat without needing a restart.
    if (!_configured || !PrivacyConsentPrefs.isAccepted()) {
      stop();
      return;
    }
    try {
      final id = await _ensureDeviceId();
      // Writes go through the app_heartbeat() RPC rather than straight at the
      // table. A SECURITY DEFINER function means `anon` needs no privileges on
      // app_presence at all — it cannot read, insert or update it directly —
      // and it sidesteps the fact that an RLS-protected upsert requires a
      // SELECT policy to resolve its conflict target, which would have meant
      // opening the table up for reads. The timestamp is set server-side with
      // now(), so a client cannot forge it and clock skew is a non-issue.
      final res = await http
          .post(
            Uri.parse('${Environment.supabaseUrl}/rest/v1/rpc/app_heartbeat'),
            headers: {
              'apikey': Environment.supabaseAnonKey,
              'Authorization': 'Bearer ${Environment.supabaseAnonKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_device_id': id,
              'p_platform': defaultTargetPlatform.name,
              'p_app_version': kAppVersion,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 300 && kDebugMode) {
        debugPrint('[presence] ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      // A missed heartbeat is not worth surfacing: the device simply ages out
      // of the live count and reappears on the next successful ping.
      if (kDebugMode) debugPrint('[presence] ping failed: $e');
    }
  }
}

