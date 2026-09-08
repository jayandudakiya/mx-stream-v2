import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/hive/safe_box.dart';

/// Manages first-launch Privacy Policy, Terms of Service, and Ad Consent persistence.
/// Stored in the shared 'app_prefs' Hive box.
abstract final class PrivacyConsentPrefs {
  static const String boxName = 'app_prefs';
  static const String keyConsentAccepted = 'privacy_consent_accepted';
  static const String keyOnboarded = 'onboarded';

  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  /// Synchronous read of the consent state.
  static bool isAccepted() {
    if (!Hive.isBoxOpen(boxName)) return false;
    return Hive.box(boxName).get(keyConsentAccepted, defaultValue: false) as bool;
  }

  /// Initialize notifier state from Hive box.
  static Future<void> init() async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely(boxName);
    notifier.value = box.get(keyConsentAccepted, defaultValue: false) as bool;
  }

  /// Mark privacy consent accepted, and ensure onboarding flag is also set.
  static Future<void> markAccepted() async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely(boxName);
    await box.put(keyConsentAccepted, true);
    await box.put(keyOnboarded, true);
    notifier.value = true;
  }
}
