import '../cf_solve_needed.dart';
import '../provider_manager.dart';
import 'cs_http.dart';

/// Wires the ported CloudStream providers into the app's existing Cloudflare
/// solver.
///
/// Nothing new is invented here. The JS provider engine already owns the whole
/// mechanism — the native WebView solve over `orcabox/cloudstream`, the
/// per-host `cf_clearance` + solving-User-Agent cache, its persistence across
/// restarts, the 30-minute negative cache for hosts that will not clear, and
/// the de-dupe that keeps ten concurrent requests to one host on a single
/// solve. This points the second engine at that same cache, which is the only
/// correct arrangement: a clearance is bound to a host and a User-Agent, not to
/// whichever client fetched it, so two separate caches would mean two
/// "Verifying you are human" screens for one site.
///
/// Installed once at boot by [installCsCloudflareGate]. Until then — and in the
/// live-check harness and unit tests, which have no Flutter engine to call a
/// MethodChannel on — `app.cloudflare` is null and requests go out unprotected,
/// exactly as they did before.
class AppCsCloudflareGate implements CsCloudflareGate {
  AppCsCloudflareGate(this._manager);

  final ProviderManager _manager;

  @override
  ({String cookie, String? ua})? clearance(String host) =>
      _manager.cfClearanceFor(host);

  @override
  Future<({String cookie, String? ua})?> solve(
    String url,
    String host, {
    required bool staleClearanceSent,
  }) =>
      _manager.cfClearanceForRetry(
        url,
        host,
        staleClearanceSent: staleClearanceSent,
      );

  /// Suppressed for the length of a search sweep, matching what the JS engine
  /// does around its own `search` calls: a cross-source search must never
  /// hijack the screen with a verification WebView nobody asked for.
  @override
  bool get suppressed => CsSearchScope.active;

  /// The source is not left looking merely empty: the same [CfSolveNeeded]
  /// register the JS path writes to is what the search and detail screens read
  /// to offer "this source needs verifying", so a suppressed challenge here
  /// surfaces through UI that already exists.
  @override
  void noteSuppressedChallenge(String host, String url) =>
      CfSolveNeeded.needsSolve(
        host,
        url,
        sourceId: CsSearchScope.currentSourceId,
      );
}
