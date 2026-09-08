// About: version, updates, support and community links.
part of 'settings_screen.dart';

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class AboutSettingsScreen extends StatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  State<AboutSettingsScreen> createState() => _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends State<AboutSettingsScreen> {
  // Follows SITE_BASE_URL from the build's .env, so the tile can never point
  // somewhere the rest of the app (share/pair/reset links) doesn't.
  static const String _websiteUrl = Environment.siteBaseUrl;
  // Empty until OrcaBox has its own Telegram; the old value was upstream's.
  static const String _telegramUrl = kTelegramUrl;
  static final String _discordUrl = kDiscordInviteLink;
  static const String _githubUrl = kAppRepoUrl;

  final UpdateService _updateService = UpdateService();
  bool _betaUpdates = false;

  @override
  void initState() {
    super.initState();
    _updateService.betaOptIn().then((v) {
      if (mounted) setState(() => _betaUpdates = v);
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(context.l10n.about),
      body: ListView(
        padding: const EdgeInsets.only(top: 24, bottom: 30),
        children: [
          const _ProfileCard(),
          const SizedBox(height: 24),
          SettingsSectionLabel(context.l10n.social, muted: true),
          SettingsCard(
            children: [
              SettingsTile(
                autofocus: true,
                icon: Icons.language_rounded,
                title: context.l10n.website,
                // Host only, derived — a hardcoded label would drift from the
                // URL the tile actually opens.
                subtitle: Uri.parse(_websiteUrl).host,
                onTap: () => _open(_websiteUrl),
              ),
              // Telegram and Discord hide themselves until OrcaBox has its own
              // channels — the previous values were the upstream project's.
              if (_telegramUrl.isNotEmpty)
                SettingsTile(
                  icon: Icons.send_rounded,
                  title: context.l10n.telegram,
                  subtitle: context.l10n.communityChat,
                  onTap: () => _open(_telegramUrl),
                ),
              if (kHasDiscord)
                SettingsTile(
                  icon: Icons.discord,
                  title: context.l10n.discord,
                  subtitle: context.l10n.joinTheServer,
                  onTap: () => _open(_discordUrl),
                ),
              SettingsTile(
                icon: Icons.code_rounded,
                title: context.l10n.github,
                subtitle: context.l10n.viewTheSourceCode,
                onTap: () => _open(_githubUrl),
              ),
            ],
          ),
          SettingsSectionLabel(context.l10n.appSection, muted: true),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.help_outline_rounded,
                title: context.l10n.howItWorks,
                subtitle: context.l10n.howItWorksSubtitle,
                onTap: () => _push(const HowItWorksScreen()),
              ),
              SettingsTile(
                icon: Icons.system_update_rounded,
                title: context.l10n.checkForUpdates,
                subtitle: context.l10n.checkForUpdatesSubtitle,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.checkingForUpdates)),
                  );
                  maybeShowUpdateDialog(context, manual: true);
                },
              ),
              SettingsTile(
                icon: Icons.science_outlined,
                title: context.l10n.betaUpdates,
                subtitle: context.l10n.betaUpdatesSubtitle,
                subtitleMaxLines: null,
                trailing: Switch.adaptive(
                  value: _betaUpdates,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) async {
                    // Turning it on: confirm first so it's never a silent opt-in.
                    if (v && !await confirmJoinBeta(context)) return;
                    await _updateService.setBetaOptIn(v);
                    if (!mounted) return;
                    setState(() => _betaUpdates = v);
                    // Then check right away so a waiting beta shows up.
                    if (v && context.mounted) {
                      maybeShowUpdateDialog(context, manual: true);
                    }
                  },
                ),
              ),
              // Hidden until OrcaBox has its own payout endpoints — see
              // DonateScreen. Better no Support entry than one that opens an
              // empty screen (or, worse, pays someone else).
              if (DonateScreen.isConfigured)
                SettingsTile(
                  icon: Icons.favorite_border_rounded,
                  title: context.l10n.supportTheApp,
                  subtitle: context.l10n.buyMeACoffee,
                  onTap: () => _push(const DonateScreen()),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year}  $kAppName',
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app header: the clean logo mark, name and version floating on the page
/// (no grey box).
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Image.asset('assets/icon/logo_mark.png', height: 96),
        const SizedBox(height: 16),
        Text(kAppName, style: AppText.largeTitle.copyWith(fontSize: 25)),
        const SizedBox(height: 3),
        Text(
          'v$kAppVersion',
          style: AppText.caption.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
