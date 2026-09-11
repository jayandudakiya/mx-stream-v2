import '../../repository/source_domain_overrides.dart';
import '../provider_manager.dart';
import 'cs_cloudflare_gate.dart';
import 'cs_domains.dart';
import 'cs_http.dart';
import 'cs_spec.dart';

/// Connects the (deliberately Flutter-free) CloudStream→Dart layer to the parts
/// of the app it cannot import: the Cloudflare solver and the user's base-URL
/// overrides.
///
/// Both are injected as hooks rather than imported directly, so the providers
/// and extractors stay runnable under plain `dart run` — which is what
/// `tool/cs_live_check.dart` relies on to exercise them against the live sites
/// without a device. With nothing installed the layer still works; it just has
/// no solver and no overrides, exactly as it behaved before.
///
/// Call once during boot, after [ProviderManager] and [SourceDomainOverrides]
/// are registered.
void installCsBindings({
  required ProviderManager providerManager,
  required SourceDomainOverrides overrides,
}) {
  app.cloudflare = AppCsCloudflareGate(providerManager);

  csBaseUrlOverride = (sourceId) => overrides.get(sourceId);
}

/// Drops the probed-domain cache for one source (or all of them) so the next
/// request re-resolves.
///
/// Called when the user changes a source's base URL: the probe result for the
/// old domain is no longer the answer to "where does this source live", and a
/// 30-minute TTL would otherwise make a correction look like it did nothing.
void invalidateCsDomainCache([String? domainKey]) =>
    CsDomains.invalidateAlive(domainKey);
