enum BackupBundle { sources, library, settings }

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

const _kApp = 'orcabox';
const _kVersion = 1;

/// App tokens this build still restores, beyond its own [_kApp].
///
/// The token is stamped into every backup file, so a rename would otherwise
/// make every backup a user already holds unreadable ("This isn't an OrcaBox
/// backup"). Reads accept the old names; writes only ever emit [_kApp], so the
/// set stops growing and old files convert on the next backup.
const _kLegacyApps = {'orcabox', 'OrcaBox'};

Map<String, dynamic> wrapPayload(
  Map<BackupBundle, Map<String, dynamic>> bundles, {
  required String createdAtIso,
}) => {
  'app': _kApp,
  'version': _kVersion,
  'createdAt': createdAtIso,
  'bundles': {for (final e in bundles.entries) e.key.name: e.value},
};

Map<BackupBundle, Map<String, dynamic>> unwrapPayload(
  Map<String, dynamic> raw,
) {
  final app = raw['app'];
  if (app != _kApp && !_kLegacyApps.contains(app)) {
    throw const BackupFormatException("This isn't an OrcaBox backup.");
  }
  if ((raw['version'] as num? ?? 0) > _kVersion) {
    throw const BackupFormatException('Made by a newer version of OrcaBox.');
  }
  final bundles = (raw['bundles'] as Map?) ?? const {};
  final out = <BackupBundle, Map<String, dynamic>>{};
  for (final b in BackupBundle.values) {
    final v = bundles[b.name];
    if (v is Map) out[b] = Map<String, dynamic>.from(v);
  }
  return out;
}
