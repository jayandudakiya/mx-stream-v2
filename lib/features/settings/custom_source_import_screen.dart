import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/provider/cloudstream_kt/cs_catalogue.dart';
import '../../core/provider/cloudstream_kt/cs_engines.dart';
import '../../core/provider/cloudstream_kt/cs_spec.dart';
import '../../core/provider/cloudstream_kt/custom_source_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';

/// Bulk-add sources from a catalogue: the list bundled with the app
/// (`assets/catalogue/url_sources.json`) or one fetched from a manifest URL.
///
/// Entries whose engine is known are pre-classified and can be added with one
/// tap. The rest are shown with "unknown layout" and a picker, rather than being
/// guessed at: a source added under the wrong engine returns nothing, which the
/// user then has to debug — worse than being asked one question up front.
///
/// Sites already added are marked and cannot be picked twice, so importing the
/// same list again adds only what is new.
class CustomSourceImportScreen extends StatefulWidget {
  const CustomSourceImportScreen({super.key});

  @override
  State<CustomSourceImportScreen> createState() =>
      _CustomSourceImportScreenState();
}

class _CustomSourceImportScreenState extends State<CustomSourceImportScreen> {
  final Map<String, CatalogueEntry> _entries = {};
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String _query = '';

  CustomSourceStore get _store => sl<CustomSourceStore>();

  @override
  void initState() {
    super.initState();
    _load(CsCatalogue.bundled());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(Future<List<CatalogueEntry>> source) async {
    setState(() => _loading = true);
    final list = await source;
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addEntries(list.map((e) => MapEntry(e.url, e)));
      _selected.clear();
      _loading = false;
    });
  }

  Future<void> _loadFromUrl() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.customSourceImportUrl, style: AppText.headline),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppText.body,
          decoration: const InputDecoration(hintText: 'https://…/domains.json'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _load(CsCatalogue.fromUrl(url));
  }

  /// Adds every selected entry. Only entries with an engine are selectable, so
  /// the engine is never null here.
  Future<void> _addSelected() async {
    var added = 0;
    for (final url in _selected) {
      final entry = _entries[url];
      final engine = entry?.engineId;
      if (entry == null || engine == null) continue;
      if (_store.withBaseUrl(entry.url) != null) continue;
      await _store.add(
        name: entry.name,
        baseUrl: entry.url,
        engineId: engine,
      );
      added++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  Future<void> _pickEngineFor(CatalogueEntry entry) async {
    final picked = await showModalBottomSheet<CsEngineId>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                context.l10n.customSourceImportPickEngine,
                style: AppText.headline,
              ),
            ),
            for (final engine in csEngines)
              ListTile(
                title: Text(engine.label, style: AppText.body),
                subtitle: Text(engine.description, style: AppText.caption),
                onTap: () => Navigator.pop(context, engine.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _entries[entry.url] = entry.copyWith(engineId: picked);
      _selected.add(entry.url);
    });
  }

  List<CatalogueEntry> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _entries.values.where((e) {
      if (q.isEmpty) return true;
      return e.name.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q);
    }).toList();
    // Classified first: those are the ones that can be added without a decision.
    list.sort((a, b) {
      final byEngine = (a.engineId == null ? 1 : 0) - (b.engineId == null ? 1 : 0);
      if (byEngine != 0) return byEngine;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final existing = {
      for (final s in _store.all) s.baseUrl.toLowerCase(),
    };
    final visible = _visible;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        l10n.customSourceImport,
        actions: [
          IconButton(
            tooltip: l10n.customSourceImportUrl,
            icon: const Icon(Icons.link_rounded),
            onPressed: _loadFromUrl,
          ),
        ],
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              onPressed: _addSelected,
              icon: const Icon(Icons.add),
              label: Text(
                l10n.customSourceImportAdd(_selected.length),
                style: AppText.button.copyWith(color: Colors.white),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _search,
                    style: AppText.body,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: l10n.search,
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (visible.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.customSourceImportEmpty,
                        style: AppText.caption,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final entry = visible[i];
                        final alreadyAdded =
                            existing.contains(entry.url.toLowerCase());
                        final engine = entry.engineId;

                        return CheckboxListTile(
                          value: alreadyAdded || _selected.contains(entry.url),
                          activeColor: AppColors.accent,
                          // An already-added site is shown, locked, so importing
                          // the same list twice reads as "these are done"
                          // rather than as the list having lost entries.
                          onChanged: alreadyAdded
                              ? null
                              : (v) {
                                  if (engine == null) {
                                    _pickEngineFor(entry);
                                    return;
                                  }
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(entry.url);
                                    } else {
                                      _selected.remove(entry.url);
                                    }
                                  });
                                },
                          title: Text(entry.name, style: AppText.body),
                          subtitle: Text(
                            engine == null
                                ? l10n.customSourceImportUnknownEngine
                                : '${csEngineInfo(engine).label} · '
                                    '${Uri.tryParse(entry.url)?.host ?? entry.url}',
                            style: AppText.caption.copyWith(
                              color: engine == null
                                  ? AppColors.textTertiary
                                  : null,
                            ),
                          ),
                          secondary: engine == null
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 20,
                                    color: AppColors.textTertiary,
                                  ),
                                  onPressed: () => _pickEngineFor(entry),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
