import 'native_models.dart';

/// MXStream's original movie-provider contract, ported verbatim. Named
/// [NativeBaseProvider] (rather than `BaseProvider`) to avoid colliding with
/// this app's own richer `BaseProvider`
/// (`lib/core/provider/base_provider.dart`) — see
/// `native_provider_adapter.dart` for the class that bridges the two.
abstract class NativeBaseProvider {
  String get name;
  String get lang;

  /// Get Home Page & Category Feeds
  Future<List<ProviderSearchItem>> getMainPage({
    String category = 'home',
    int page = 1,
  });

  /// Search Endpoint
  Future<List<ProviderSearchItem>> search(String query, {int page = 1});

  /// Load Details & Scrape Stream Links
  Future<ProviderMediaDetails?> loadDetails(String url, {bool skipSources = false});

  /// Extract Final Stream Links from a Video Source URL
  Future<List<StreamLink>> extractStream(String url);
}
