import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/provider/cloudstream_kt/cs_bindings.dart';
import '../../core/provider/cloudstream_kt/cs_engines.dart';
import '../../core/provider/cloudstream_kt/cs_spec.dart';
import '../../core/provider/cloudstream_kt/custom_source_store.dart';
import '../../core/repository/source_domain_overrides.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';
import 'custom_source_editor_screen.dart';
import 'custom_source_import_screen.dart';

/// Settings → Custom sources.
///
/// Two lists, because there are two different things a user comes here to do:
///
///  * **Your sources** — add a movie site the app does not ship with, by
///    pointing one of the built-in engines at it. These become real `native:`
///    sources: they show up in search, open on the detail screen and play
///    through the same player as everything else.
///  * **Built-in sources** — override the address one of the four shipped
///    sources uses. Every one of these sites moves domain every few weeks, and
///    the remote manifests lag behind; when a manifest names a domain that has
///    died, this is how a user fixes it without waiting for an app update.
class CustomSourcesScreen extends StatefulWidget {
  const CustomSourcesScreen({super.key});

  @override
  State<CustomSourcesScreen> createState() => _CustomSourcesScreenState();
}

class _CustomSourcesScreenState extends State<CustomSourcesScreen> {
  CustomSourceStore get _store => sl<CustomSourceStore>();
  SourceDomainOverrides get _overrides => sl<SourceDomainOverrides>();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor([CustomSource? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomSourceEditorScreen(existing: existing),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _openImport() async {
    final added = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const CustomSourceImportScreen()),
    );
    if (!mounted || added == null || added == 0) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.customSourcesAddedCount(added))),
    );
  }

  Future<void> _confirmDelete(CustomSource source) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(source.name, style: AppText.headline),
        content: Text(l10n.customSourceDeleteConfirm, style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.delete,
              style: AppText.button.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.remove(source.id);
    // The provider's resolved-domain entry is keyed on its provider key, so drop
    // it too: re-adding the same site later must re-probe rather than inherit a
    // cached answer from a source that no longer exists.
    invalidateCsDomainCache(source.providerKey);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sources = _store.all;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(l10n.customSources),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(
          l10n.customSourceAdd,
          style: AppText.button.copyWith(color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(l10n.customSourcesIntro, style: AppText.caption),
          ),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.playlist_add_rounded,
                iconAccent: true,
                title: l10n.customSourceImport,
                subtitle: l10n.customSourceImportSubtitle,
                onTap: _openImport,
              ),
            ],
          ),
          SettingsSectionLabel(l10n.customSourcesYourSources),
          if (sources.isEmpty)
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: Text(
                    l10n.customSourcesNoneYet,
                    style: AppText.caption,
                  ),
                ),
              ],
            )
          else
            SettingsCard(
              children: [
                for (final source in sources)
                  SettingsTile(
                    icon: source.enabled
                        ? Icons.dns_rounded
                        : Icons.dns_outlined,
                    title: source.name,
                    subtitle:
                        '${csEngineInfo(source.engineId).label} · ${_host(source.baseUrl)}',
                    subtitleMaxLines: 2,
                    onTap: () => _openEditor(source),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch.adaptive(
                          value: source.enabled,
                          activeThumbColor: AppColors.accent,
                          onChanged: (v) =>
                              _store.setEnabled(source.id, v),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.textTertiary,
                            size: 20,
                          ),
                          onPressed: () => _confirmDelete(source),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          SettingsSectionLabel(l10n.customSourcesBuiltIn),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n.customSourcesBuiltInHint,
              style: AppText.caption,
            ),
          ),
          SettingsCard(
            children: [
              for (final spec in builtInCsSpecs)
                _BuiltInRow(
                  spec: spec,
                  overrideUrl: _overrides.get('native:${spec.key}'),
                  onChanged: () => setState(() {}),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}

/// One built-in source, with its current address and an override editor.
class _BuiltInRow extends StatelessWidget {
  const _BuiltInRow({
    required this.spec,
    required this.overrideUrl,
    required this.onChanged,
  });

  final CsSourceSpec spec;
  final String? overrideUrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsTile(
      icon: Icons.language_rounded,
      title: spec.name,
      subtitle: overrideUrl == null
          ? csEngineInfo(spec.engineId).label
          : '${l10n.customSourceOverrideSet} · ${Uri.tryParse(overrideUrl!)?.host ?? overrideUrl}',
      subtitleMaxLines: 2,
      onTap: () => _editOverride(context),
    );
  }

  Future<void> _editOverride(BuildContext context) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: overrideUrl ?? '');
    final value = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(spec.name, style: AppText.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.customSourcesBuiltInHint, style: AppText.caption),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: l10n.customSourceUrl,
                hintText: l10n.customSourceUrlHint,
              ),
            ),
          ],
        ),
        actions: [
          if (overrideUrl != null)
            TextButton(
              // Empty string is the documented "clear it" value for
              // SourceDomainOverrides.set, so this and Save share one path.
              onPressed: () => Navigator.pop(context, ''),
              child: Text(l10n.customSourceOverrideClear),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (value == null) return;

    await sl<SourceDomainOverrides>().set('native:${spec.key}', value);
    // The engine caches which domain answered for this key; a new address has to
    // take effect now, not in half an hour.
    invalidateCsDomainCache(spec.domainKey ?? spec.key);
    onChanged();
  }
}
