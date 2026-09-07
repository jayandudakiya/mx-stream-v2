import 'package:flutter_test/flutter_test.dart';
import 'package:orcabox/core/supabase/auth_user.dart';

void main() {
  test('displayName prefers name, falls back to email', () {
    expect(const AuthUser(id: '1', name: 'Ada', email: 'ada@example.com').displayName, 'Ada');
    expect(const AuthUser(id: '1', name: '', email: 'k@x.com').displayName, 'k@x.com');
  });
}
