import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:orcabox/core/app_mode.dart';
import 'package:orcabox/core/backup/backup_service.dart';
import 'package:orcabox/core/backup/library_backup.dart';
import 'package:orcabox/core/backup/settings_backup.dart';
import 'package:orcabox/core/backup/sources_backup.dart';
import 'package:orcabox/core/di/injector.dart';
import 'package:orcabox/core/provider/provider_registry.dart';
import 'package:orcabox/core/provider/provider_repo_registry.dart';
import 'package:orcabox/core/supabase/supabase_service.dart';
import 'package:orcabox/core/tv/tv_focusable.dart';
import 'package:orcabox/features/auth/auth_cubit.dart';
import 'package:orcabox/features/backup/backup_screen.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

class _StubRegistry implements ProviderRegistry {
  @override
  List<ProviderRegistryEntry> getAll() => const [];
  @override
  ProviderRegistryEntry? entryFor(String sourceId) => null;
  @override
  Set<String> nsfwSourceIds() => const {};
  @override
  Stream<BoxEvent> watch() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StubReposRegistry implements ProviderReposRegistry {
  @override
  List<ProviderRepo> getAll() => const [];
  @override
  Stream<BoxEvent> watch() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// A REAL temp dir path_provider is mocked to. Must exist on disk: the client
// Client creates a `cookies` subdir under the app-documents dir, so a fake path
// (the old hardcoded '/tmp/test') threw PathNotFoundException.
late Directory _appDir;

void _mockPathProvider(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => _appDir.path,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    _appDir = Directory.systemTemp.createTempSync('backup_test');
    // Mock path_provider before the Supabase client is constructed: its
    // Client asynchronously requests the app documents directory, and doing
    // this here (rather than only in the test body) avoids a cross-test race
    // storage init needs a real temp dir once more than one test uses it.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => _appDir.path);
    sl
      ..registerSingleton<AppMode>(const AppMode(isTv: false))
      ..registerSingleton<BackupService>(BackupService(
        SourcesBackup(_StubReposRegistry(), _StubRegistry(), null),
        LibraryBackup(),
        SettingsBackup(),
      ));
  });

  tearDown(() {
    sl.reset();
    if (_appDir.existsSync()) _appDir.deleteSync(recursive: true);
  });

  testWidgets(
    'BackupScreen renders three bundle checkboxes and four action buttons',
    (tester) async {
      _mockPathProvider(tester);
      // Tall surface so the lazy ListView builds every tile (the screen is
      // longer than the default 800px test viewport).
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final auth = AuthCubit(SupabaseService());
      addTearDown(auth.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: auth,
            child: const BackupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Three bundle checkboxes (all checked by default).
      expect(find.text('Sources & repos'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);

      // Four action buttons (SettingsTile labels).
      expect(find.text('Back up to cloud'), findsOneWidget);
      expect(find.text('Save to a file'), findsOneWidget);
      expect(find.text('Restore from cloud'), findsOneWidget);
      expect(find.text('Restore from a file'), findsOneWidget);
    },
  );

  Future<void> pumpBackup(WidgetTester tester) async {
    _mockPathProvider(tester);
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthCubit(SupabaseService());
    addTearDown(auth.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthCubit>.value(value: auth, child: const BackupScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('TV: backup rows are wrapped in TvFocusable', (tester) async {
    sl.unregister<AppMode>();
    sl.registerSingleton<AppMode>(const AppMode(isTv: true));
    await pumpBackup(tester);
    // 4 action tiles + 3 bundle checkbox rows → at least 4 focusable rows.
    expect(
      tester.widgetList<TvFocusable>(find.byType(TvFocusable)).length,
      greaterThanOrEqualTo(4),
    );
  });

  testWidgets('phone: BackupScreen adds no TvFocusable (unchanged)', (tester) async {
    // setUp registered AppMode(isTv: false) — phone path.
    await pumpBackup(tester);
    expect(find.byType(TvFocusable), findsNothing);
  });
}
