import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_features.dart';

class SupabaseService {
  SupabaseClient get client => Supabase.instance.client;

  /// The signed-in user's id, or null when signed out OR when Supabase isn't
  /// initialized yet (e.g. its boot init timed out on a dead network). Either
  /// way the stores treat it as local-only — never crashes on an uninitialized
  /// client (`Supabase.instance` asserts when init never ran).
  ///
  /// Also null — unconditionally — while [AppFeatures.cloudAccounts] is off.
  /// That single answer is what makes the whole library local-only: every store
  /// (My List, watch/read history, categories) already treats a null id as
  /// "signed out, keep it local", so no cloud row is ever read or written.
  String? currentUserId() {
    if (!AppFeatures.cloudAccounts) return null;
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Public URL for an avatar Storage object path (bucket public-read).
  /// Null while accounts are off (there is no client to ask).
  String? avatarUrl(String path) {
    if (!AppFeatures.cloudAccounts) return null;
    try {
      return client.storage.from('avatars').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }
}
