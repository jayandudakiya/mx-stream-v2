import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/ui/team_section.dart';

void main() {
  test('parseCommunity drops bots and tags everyone else Contributor', () {
    final json = [
      {'login': 'dependabot[bot]', 'html_url': 'h3', 'type': 'Bot'},
      {'login': 'renovate[bot]', 'html_url': 'h4', 'type': 'User'},
      {'login': 'newHelper', 'avatar_url': 'x', 'html_url': 'hx', 'type': 'User'},
    ];
    final out = parseCommunity(json);

    // Both bot forms are filtered — by payload `type`, and by the `[bot]`
    // login suffix for accounts GitHub still reports as Users.
    expect(out.map((m) => m.name).toList(), ['newHelper']);
    expect(out.single.role, 'Contributor');
    expect(out.single.avatarUrl, 'x');
  });

  test('parseCommunity honours kExcludedFromCommunity, case-insensitively', () {
    // Guards the filter itself rather than any particular name, so the test
    // keeps working whoever OrcaBox pins later.
    for (final login in kExcludedFromCommunity) {
      expect(
        parseCommunity([
          {'login': login.toUpperCase(), 'type': 'User'},
        ]),
        isEmpty,
        reason: '$login should not appear under Community Contributors',
      );
    }
  });

  test('OrcaBox pins no team by hand — the page is GitHub-driven', () {
    expect(kCoreTeam, isEmpty);
    expect(kFixedCommunity, isEmpty);
  });

  test('a pinned core member is never repeated under Community', () {
    for (final m in kCoreTeam) {
      final gh = m.github;
      if (gh != null) expect(kExcludedFromCommunity, contains(gh));
    }
  });

  test('TeamMember.avatar falls back to the GitHub avatar, then empty', () {
    const gh = TeamMember(name: 'x', role: 'r', link: 'l', github: 'octocat');
    expect(gh.avatar, 'https://github.com/octocat.png?size=200');
    const manual = TeamMember(name: 'y', role: 'r', link: 'l');
    expect(manual.avatar, '');
  });
}
