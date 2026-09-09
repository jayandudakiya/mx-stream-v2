// test/core/supabase/uninitialized_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/playback/category_store.dart';
import 'package:orcabox/core/playback/my_list.dart';
import 'package:orcabox/core/playback/watch_history.dart';
import 'package:orcabox/core/reading/read_history.dart';
import 'package:orcabox/core/supabase/supabase_service.dart';
import 'package:orcabox/features/auth/auth_cubit.dart';
import 'package:orcabox/features/auth/tv_pairing_service.dart';
import 'package:orcabox/features/watch_together/watch_room_service.dart';

/// `Supabase.initialize` is deliberately NOT called here — the same state the
/// app boots in while `AppFeatures.cloudAccounts` is off, and the state a
/// flag-on build lands in when the boot-time initialize times out on a dead
/// network. `Supabase.instance` ASSERTS in that state, so any constructor that
/// reaches for the client takes the whole app down to the boot-error screen:
/// these services are all built eagerly inside `initDependencies`, long before
/// any screen that uses them exists.
///
/// That is not hypothetical — `WatchRoomService`'s constructor registered a
/// `realtime.onOpen` hook and did exactly this. Constructing every one of them
/// here is the cheap standing guard against it coming back.
void main() {
  final sb = SupabaseService();

  test('currentUserId answers null instead of throwing', () {
    expect(sb.currentUserId(), isNull);
  });

  test('avatarUrl answers null instead of throwing', () {
    expect(sb.avatarUrl('someone/pic.jpg'), isNull);
  });

  test('every eagerly-constructed Supabase service builds without a client', () {
    String? noUser() => null;

    expect(() => WatchRoomService(sb), returnsNormally);
    expect(() => WatchHistory(sb, noUser), returnsNormally);
    expect(() => ReadHistory(sb, noUser), returnsNormally);
    expect(
      () => CategoryStore(remote: CategoryRemote(sb), currentUserId: noUser),
      returnsNormally,
    );
    expect(() => MyListStore(sb, noUser), returnsNormally);
    expect(() => TvPairingService(sb), returnsNormally);
    expect(() => AuthCubit(sb).close(), returnsNormally);
  });
}
