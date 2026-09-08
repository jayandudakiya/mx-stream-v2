import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/privacy/privacy_consent_prefs.dart';
import 'package:orcabox/features/onboarding/onboarding_screen.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('privacy_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(PrivacyConsentPrefs.boxName);
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      hiveDir.deleteSync(recursive: true);
    }
  });

  test('PrivacyConsentPrefs defaults to not accepted and onboarding incomplete', () async {
    await PrivacyConsentPrefs.init();
    expect(PrivacyConsentPrefs.isAccepted(), isFalse);
    expect(PrivacyConsentPrefs.notifier.value, isFalse);
    expect(isOnboarded(), isFalse);
  });

  test('PrivacyConsentPrefs.markAccepted sets consent and onboarded flags in Hive', () async {
    await PrivacyConsentPrefs.init();
    expect(PrivacyConsentPrefs.isAccepted(), isFalse);

    await PrivacyConsentPrefs.markAccepted();

    expect(PrivacyConsentPrefs.isAccepted(), isTrue);
    expect(PrivacyConsentPrefs.notifier.value, isTrue);
    expect(isOnboarded(), isTrue);

    final box = Hive.box(PrivacyConsentPrefs.boxName);
    expect(box.get(PrivacyConsentPrefs.keyConsentAccepted), isTrue);
    expect(box.get(PrivacyConsentPrefs.keyOnboarded), isTrue);
  });

  test('isOnboarded returns false if onboarded is true but consent is not accepted', () async {
    final box = Hive.box(PrivacyConsentPrefs.boxName);
    await box.put('onboarded', true);
    await box.put('privacy_consent_accepted', false);

    expect(PrivacyConsentPrefs.isAccepted(), isFalse);
    expect(isOnboarded(), isFalse);

    await PrivacyConsentPrefs.markAccepted();
    expect(isOnboarded(), isTrue);
  });
}
