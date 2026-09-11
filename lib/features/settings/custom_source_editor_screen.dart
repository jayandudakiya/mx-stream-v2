import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/playback/subtitle_language.dart';
import '../../core/provider/cloudstream_kt/cs_bindings.dart';
import '../../core/provider/cloudstream_kt/cs_engines.dart';
import '../../core/provider/cloudstream_kt/cs_source_test.dart';
import '../../core/provider/cloudstream_kt/cs_spec.dart';
import '../../core/provider/cloudstream_kt/custom_source_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';

/// Add or edit one custom source.
///
/// The form is four fields, and the engine is the only one a user can get wrong
/// in a way that is hard to diagnose — a site read by the wrong engine returns
/// nothing, which looks exactly like a dead site. That is what [testCsSource]
/// and the Test button are for: they name which of the three failure modes you
/// actually have before you save.
class CustomSourceEditorScreen extends StatefulWidget {
  const CustomSourceEditorScreen({super.key, this.existing, this.initialUrl});

  /// The source being edited, or null when adding one.
  final CustomSource? existing;

  /// Pre-filled address, used when coming from the catalogue import.
  final String? initialUrl;

  @override
  State<CustomSourceEditorScreen> createState() =>
      _CustomSourceEditorScreenState();
}

class _CustomSourceEditorScreenState extends State<CustomSourceEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late CsEngineId _engine;
  late String _lang;

  bool _testing = false;
  CsTestResult? _result;
  String? _error;

  CustomSourceStore get _store => sl<CustomSourceStore>();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _url = TextEditingController(
      text: existing?.baseUrl ?? widget.initialUrl ?? '',
    );
    _engine = existing?.engineId ?? CsEngineId.dooplay;
    _lang = existing?.lang ?? 'hi';
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The definition the form currently describes, for testing and saving.
  ///
  /// Uses the real provider key when editing, so a test runs against the same
  /// id (and therefore the same override and cached domain) the live source has.
  CsSourceSpec get _spec => CsSourceSpec(
        engineId: _engine,
        key: widget.existing?.providerKey ?? 'custom_preview',
        name: _name.text.trim().isEmpty ? 'Custom source' : _name.text.trim(),
        baseUrl: CustomSourceStore.normalizeBaseUrl(_url.text),
        lang: _lang,
        isCustom: true,
      );

  /// Validation errors are shown inline AND as a snack bar: the inline text
  /// sits under the form, which on a short screen is below the fold, and a Save
  /// that appears to do nothing is worse than no validation at all.
  void _fail(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _test() async {
    final url = CustomSourceStore.normalizeBaseUrl(_url.text);
    if (url.isEmpty) {
      _fail(context.l10n.customSourceUrlRequired);
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
      _result = null;
    });
    final result = await testCsSource(_spec);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _name.text.trim();
    final url = CustomSourceStore.normalizeBaseUrl(_url.text);

    if (name.isEmpty) {
      _fail(l10n.customSourceNameRequired);
      return;
    }
    if (url.isEmpty) {
      _fail(l10n.customSourceUrlRequired);
      return;
    }
    if (_store.withBaseUrl(url, ignoreId: widget.existing?.id) != null) {
      _fail(l10n.customSourceDuplicate);
      return;
    }

    final existing = widget.existing;
    if (existing == null) {
      await _store.add(
        name: name,
        baseUrl: url,
        engineId: _engine,
        lang: _lang,
      );
    } else {
      await _store.update(
        existing.copyWith(
          name: name,
          baseUrl: url,
          engineId: _engine,
          lang: _lang,
        ),
      );
      // A changed address must take effect now: the engine remembers which
      // domain answered for this provider key for half an hour.
      invalidateCsDomainCache(existing.providerKey);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        _isEdit ? l10n.customSourceEdit : l10n.customSourceAdd,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              l10n.save,
              style: AppText.button.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 28),
        children: [
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: TextField(
                  controller: _name,
                  style: AppText.body,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.customSourceName,
                    helperText: l10n.customSourceNameHint,
                    helperStyle: AppText.caption,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: TextField(
                  controller: _url,
                  style: AppText.body,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.customSourceUrl,
                    hintText: l10n.customSourceUrlHint,
                    helperStyle: AppText.caption,
                  ),
                  onChanged: (_) {
                    // A result belongs to the URL it was produced for.
                    if (_result != null) setState(() => _result = null);
                  },
                ),
              ),
            ],
          ),
          SettingsSectionLabel(l10n.customSourceEngine),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(l10n.customSourceEngineHint, style: AppText.caption),
          ),
          SettingsCard(
            children: [
              for (final engine in csEngines)
                RadioListTile<CsEngineId>(
                  value: engine.id,
                  // ignore: deprecated_member_use
                  groupValue: _engine,
                  activeColor: AppColors.accent,
                  title: Text(engine.label, style: AppText.body),
                  subtitle: Text(
                    '${engine.description}\ne.g. ${engine.exampleSite}',
                    style: AppText.caption,
                  ),
                  isThreeLine: true,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() {
                    _engine = v ?? _engine;
                    _result = null;
                  }),
                ),
            ],
          ),
          SettingsSectionLabel(l10n.customSourceLanguage),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.translate_rounded,
                title: l10n.customSourceLanguage,
                subtitle: _languageLabel(_lang),
                onTap: _pickLanguage,
              ),
            ],
          ),
          SettingsSectionLabel(l10n.customSourceTest),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.network_check_rounded,
                iconAccent: true,
                title: _testing ? l10n.customSourceTesting : l10n.customSourceTest,
                subtitle: _testing ? null : _url.text.trim(),
                trailing: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.textTertiary,
                      ),
                onTap: _testing ? null : _test,
              ),
              if (_result != null) _TestResultRow(result: _result!),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                _error!,
                style: AppText.caption.copyWith(color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }

  static String _languageLabel(String iso) {
    for (final l in kSubtitleLanguages) {
      if (l.iso1 == iso) return l.name;
    }
    return iso;
  }

  Future<void> _pickLanguage() async {
    // The audio language of the site's releases. Only a label — it feeds the
    // source picker's language filter, not any request.
    const common = ['hi', 'en', 'ta', 'te', 'ml', 'bn', 'pa', 'ko', 'ja'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final iso in common)
              ListTile(
                title: Text(_languageLabel(iso), style: AppText.body),
                trailing: iso == _lang
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(context, iso),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _lang = picked);
  }
}

/// The verdict from a test run, in the language of what to do about it.
class _TestResultRow extends StatelessWidget {
  const _TestResultRow({required this.result});

  final CsTestResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (IconData icon, String title, Color color) = switch (result.outcome) {
      CsTestOutcome.working => (
          Icons.check_circle_rounded,
          l10n.customSourceTestWorking,
          const Color(0xFF4CAF50),
        ),
      CsTestOutcome.cloudflare => (
          Icons.shield_outlined,
          l10n.customSourceTestCloudflare,
          const Color(0xFFFFA726),
        ),
      CsTestOutcome.wrongEngine => (
          Icons.help_outline_rounded,
          l10n.customSourceTestWrongEngine,
          AppColors.accent,
        ),
      CsTestOutcome.unreachable => (
          Icons.cloud_off_rounded,
          l10n.customSourceTestUnreachable,
          AppColors.accent,
        ),
    };

    final lines = <String>[
      if (result.outcome == CsTestOutcome.working)
        l10n.customSourceTestFound(result.browseCount, result.searchCount),
      if (result.sampleTitle != null) '“${result.sampleTitle}”',
      if (result.detail != null) result.detail!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body.copyWith(color: color)),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(line, style: AppText.caption),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
