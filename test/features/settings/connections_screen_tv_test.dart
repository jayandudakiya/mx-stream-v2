import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:orcabox/core/anilist/anilist_service.dart';
import 'package:orcabox/core/tracker/mal_service.dart';
import 'package:orcabox/features/settings/connections_screen_tv.dart';

// Configurable fake trackers — mirrors the pattern in
// test/features/shell/root_shell_tv_test.dart, minus the Hive/network guts.
class _FakeAniListService extends ChangeNotifier implements AniListService {
  _FakeAniListService({this.connected = false, this.name});
  final bool connected;
  final String? name;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  bool get isConnected => connected;

  @override
  String get displayName => 'AniList';

  @override
  String? get viewerName => name;

  @override
  String? get viewerAvatar => null;

  @override
  Future<void> disconnect() async {}
}

class _FakeMalService extends ChangeNotifier implements MalService {
  _FakeMalService({this.connected = false, this.name});
  final bool connected;
  final String? name;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  bool get isConnected => connected;

  @override
  String get displayName => 'MyAnimeList';

  @override
  String? get viewerName => name;

  @override
  String? get viewerAvatar => null;

  @override
  Future<void> disconnect() async {}
}


void _register(
  GetIt sl, {
  bool aniConnected = false,
  String? aniName,
  bool malConnected = false,
  String? malName,
}) {
  sl.registerSingleton<AniListService>(
      _FakeAniListService(connected: aniConnected, name: aniName));
  sl.registerSingleton<MalService>(
      _FakeMalService(connected: malConnected, name: malName));
}

void main() {
  final sl = GetIt.instance;
  tearDown(sl.reset);

  testWidgets('lists both trackers, with no Connect action while accounts are off',
      (tester) async {
    _register(sl, aniConnected: false, malConnected: false);
    await tester.pumpWidget(const MaterialApp(home: ConnectionsScreenTv()));
    await tester.pumpAndSettle();
    // Two rows, not three: Simkl was removed with the rest of the tracker
    // (NOTES task 15), leaving AniList and MyAnimeList.
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('MyAnimeList'), findsOneWidget);
    // Connecting a tracker on TV is a phone->TV QR handoff over the Supabase
    // pair relay, so the action is hidden while AppFeatures.cloudAccounts is
    // off. Flip that flag back on and the two Connect actions return.
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('shows Connected + viewer name and a Disconnect action',
      (tester) async {
    _register(sl,
        aniConnected: true, aniName: 'ada',
        malConnected: false);
    await tester.pumpWidget(const MaterialApp(home: ConnectionsScreenTv()));
    await tester.pumpAndSettle();
    expect(find.textContaining('ada'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });
}
