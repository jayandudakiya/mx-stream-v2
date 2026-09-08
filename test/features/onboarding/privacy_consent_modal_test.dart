import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/app_mode.dart';
import 'package:orcabox/core/privacy/privacy_consent_prefs.dart';
import 'package:orcabox/features/onboarding/privacy_consent_modal.dart';
import 'package:orcabox/features/onboarding/privacy_policy_sheet.dart';

void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('privacy_modal_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(PrivacyConsentPrefs.boxName);
    final sl = GetIt.instance;
    if (!sl.isRegistered<AppMode>()) {
      sl.registerSingleton<AppMode>(AppMode(isTv: false));
    }
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      hiveDir.deleteSync(recursive: true);
    }
  });

  testWidgets('PrivacyConsentModal displays disclosures and triggers onAccepted', (tester) async {
    var accepted = false;

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivacyConsentModal(
            onAccepted: () {
              accepted = true;
            },
          ),
        ),
      ),
    );

    // Verify key titles and disclosures are rendered
    expect(find.text('Privacy & Terms'), findsOneWidget);
    expect(find.text('Your Privacy Is Respected'), findsOneWidget);
    expect(find.text('Transparent Infrastructure'), findsOneWidget);
    expect(find.text('Support Ongoing Development'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Accept & Continue'), findsOneWidget);

    // Tap Accept & Continue using runAsync for real Hive I/O
    final btn = find.byType(FilledButton);
    await tester.ensureVisible(btn);
    await tester.runAsync(() async {
      await tester.tap(btn);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(PrivacyConsentPrefs.isAccepted(), isTrue);
    expect(accepted, isTrue);
  });

  testWidgets('PrivacyPolicySheet and TermsOfServiceSheet render content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PrivacyPolicySheet(),
        ),
      ),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('1. Commitment to Privacy'), findsOneWidget);
    expect(find.text('2. Zero Personal Data Collection'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TermsOfServiceSheet(),
        ),
      ),
    );

    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('1. Acceptance of Terms'), findsOneWidget);
    expect(find.text('2. Nature of the Application'), findsOneWidget);
  });
}
