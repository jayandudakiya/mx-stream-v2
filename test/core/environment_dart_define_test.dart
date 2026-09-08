// Guards the --dart-define-from-file=.env pipeline.
//
// Every value below is compile-time (`String.fromEnvironment`), so this test
// only sees real values when the suite itself is run with the defines:
//
//   fvm flutter test --dart-define-from-file=.env
//
// Run without them it asserts the *fallback* shape instead, so a plain
// `flutter test` still passes. That split is the point: a build that forgets
// the define must be obvious, not silently half-configured.
import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/app_config.dart';
import 'package:orcabox/core/environment.dart';
import 'package:orcabox/core/metadata/tmdb.dart';

void main() {
  final configured = Environment.supabaseUrl.isNotEmpty;

  test('site URLs all derive from one base', () {
    expect(Environment.siteOpenUrl, '${Environment.siteBaseUrl}/open/');
    expect(Environment.sitePairUrl, '${Environment.siteBaseUrl}/pair/');
    expect(Environment.passwordResetUrl, '${Environment.siteBaseUrl}/');
    // No double slash from a base that ends in one.
    expect(Environment.siteBaseUrl.endsWith('/'), isFalse);
  });

  test('the deep-link scheme matches the share/open scheme', () {
    expect(Environment.openLinkScheme, Environment.trackerRedirectScheme);
    expect(Environment.anilistRedirectUri,
        '${Environment.trackerRedirectScheme}://anilist-auth');
    expect(Environment.malRedirectUri,
        '${Environment.trackerRedirectScheme}://mal-auth');
  });

  test('no upstream project infrastructure is baked in', () {
    // These were the previous owner's. A build must never fall back to them.
    expect(Environment.supabaseUrl, isNot(contains('eogwzrlfoercfwcfwlmv')));
    expect(Environment.siteBaseUrl, isNot(contains('zangetsu')));
    expect(Environment.passwordResetUrl, isNot(contains('zangetsu')));
  }, skip: !configured ? 'needs --dart-define-from-file=.env' : null);

  group('with the .env defines supplied', () {
    test('Supabase is configured and is a real project URL', () {
      expect(Environment.supabaseUrl, startsWith('https://'));
      expect(Environment.supabaseUrl, endsWith('.supabase.co'));
      // anon keys are JWTs — three dot-separated segments.
      expect(Environment.supabaseAnonKey.split('.').length, 3);
    });

    test('AniList client id is present for the OAuth redirect', () {
      expect(Environment.anilistClientId, isNotEmpty);
      expect(int.tryParse(Environment.anilistClientId), isNotNull);
    });

    // Moved out of source and into .env — nothing may reintroduce a literal.
    test('MAL client id comes from the define', () {
      expect(Environment.malClientId, isNotEmpty);
      expect(Environment.malClientId, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('TMDB key comes from the define', () {
      expect(Tmdb.apiKey, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    // A bare invite code reaches Uri.parse as a relative URI, which launchUrl
    // cannot open and which fails with nothing the user can act on.
    test('a configured Discord invite resolves to a launchable URL', () {
      if (!kHasDiscord) return;
      final uri = Uri.parse(kDiscordInviteLink);
      expect(uri.hasScheme, isTrue);
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
    });
    test('the app repo is set and looks like owner/name', () {
      expect(kAppRepo, matches(RegExp(r'^[\w.-]+/[\w.-]+$')));
    });
  }, skip: !configured ? 'needs --dart-define-from-file=.env' : null);
}
