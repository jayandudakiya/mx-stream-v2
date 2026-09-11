import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../privacy/privacy_consent_prefs.dart';

/// Thin wrapper over Firebase Analytics.
///
/// Two independent gates must both be open before anything is collected:
///
///  1. [available] — flipped on only after `Firebase.initializeApp()` succeeds,
///     so every call is a safe no-op on a build without `google-services.json`
///     or on a device with no Play Services.
///  2. [_consented] — the user accepted the privacy consent. The SDK itself
///     starts disabled via `firebase_analytics_collection_enabled=false` in
///     AndroidManifest.xml, so nothing (not even automatic session/screen
///     events) is gathered until [applyConsent] turns it on.
///
/// Nothing here can crash the app or block a user action.
class Analytics {
  Analytics._();

  /// Firebase initialized successfully this session.
  static bool available = false;

  /// Mirror of the persisted privacy-consent flag.
  static bool _consented = false;

  static bool get isCollecting => available && _consented;

  static NavigatorObserver? _observer;

  /// NavigatorObserver that auto-logs a `screen_view` on every route push.
  ///
  /// Building the real observer touches `FirebaseAnalytics.instance`, which
  /// THROWS `[core/no-app]` when Firebase isn't initialized — so we fall back to
  /// a plain no-op observer instead of crashing during the MaterialApp build.
  static NavigatorObserver get observer {
    if (_observer != null) return _observer!;
    try {
      _observer = FirebaseAnalyticsObserver(
        analytics: FirebaseAnalytics.instance,
      );
    } catch (_) {
      _observer = NavigatorObserver();
    }
    return _observer!;
  }

  /// Read the stored consent decision and tell the SDK to match it.
  ///
  /// Safe to call repeatedly; [PrivacyConsentPrefs.notifier] drives it whenever
  /// the user accepts, so collection starts the moment consent is given without
  /// waiting for a restart.
  static Future<void> applyConsent() async {
    if (!available) return;
    final consented = PrivacyConsentPrefs.isAccepted();
    if (consented == _consented) return;
    _consented = consented;
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
        consented,
      );
      if (consented) await _setBaseUserProperties();
    } catch (e) {
      if (kDebugMode) debugPrint('[analytics] applyConsent($consented): $e');
    }
  }

  /// Dimensions worth slicing every report by. Set once, on consent.
  static Future<void> _setBaseUserProperties() async {
    final props = <String, String>{
      'app_flavor': kReleaseMode ? 'release' : 'debug',
      if (!kIsWeb) 'os_version': _shortOsVersion(),
    };
    for (final e in props.entries) {
      try {
        await FirebaseAnalytics.instance.setUserProperty(
          name: e.key,
          value: e.value,
        );
      } catch (_) {
        // A rejected property name must never break the others.
      }
    }
  }

  static String _shortOsVersion() {
    try {
      // "Android 14 (API 34)" → keep it short; GA4 caps values at 36 chars.
      final v = Platform.operatingSystemVersion;
      return v.length > 36 ? v.substring(0, 36) : v;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Tag the device form factor so phone vs TV can be compared.
  ///
  /// Called from the boot path once [isAppleTv] / TV-layout detection has run.
  static Future<void> setDeviceClass(String value) async {
    if (!isCollecting) return;
    try {
      await FirebaseAnalytics.instance.setUserProperty(
        name: 'device_class',
        value: value,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[analytics] setDeviceClass: $e');
    }
  }

  /// Log a custom event (e.g. `Analytics.log('video_play', {'source': 'anilist'})`).
  static Future<void> log(String name, [Map<String, Object>? params]) async {
    if (!isCollecting) return;
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    } catch (e) {
      if (kDebugMode) debugPrint('[analytics] logEvent($name) failed: $e');
    }
  }
}
