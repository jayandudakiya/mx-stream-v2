// Guards that the TMDB v3 key reaches Tmdb.apiKey through the .env pipeline.
//
// Skipped unless the suite runs with `--dart-define-from-file=.env`, so a
// plain `flutter test` still passes on a machine with no .env.
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/metadata/tmdb.dart';

void main() {
  final configured = Tmdb.apiKey.isNotEmpty;

  test('TMDB_API_KEY is a v3 key (32 hex chars)', () {
    expect(Tmdb.apiKey.length, 32,
        reason: 'TMDB v3 keys are 32 hex characters');
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(Tmdb.apiKey), isTrue,
        reason: 'expected lowercase hex; a v4 bearer token is not a v3 key');
  }, skip: !configured ? 'needs --dart-define-from-file=.env' : null);
}
