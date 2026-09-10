import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// Shows the full Privacy Policy in a sleek bottom sheet.
Future<void> showPrivacyPolicySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const PrivacyPolicySheet(),
  );
}

/// Shows the full Terms of Service in a sleek bottom sheet.
Future<void> showTermsOfServiceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const TermsOfServiceSheet(),
  );
}

/// Full scrollable Privacy Policy viewer.
class PrivacyPolicySheet extends StatelessWidget {
  const PrivacyPolicySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocumentSheet(
      title: 'Privacy Policy',
      subtitle: '$kAppName respects your personal data',
      icon: Icons.shield_outlined,
      children: const [
        _Section(
          title: '1. Commitment to Privacy',
          content:
              '$kAppName is engineered with privacy as a foundational principle. '
              'We believe user data belongs to the user alone. We do not monitor, log, '
              'profile, or sell your personal information or viewing behavior to data brokers or third parties.',
        ),
        _Section(
          title: '2. Zero Personal Data Collection',
          content:
              'The application does not collect, record, or transmit:\n'
              '• Your phone number, contacts, or address book\n'
              '• Email addresses or real-world identities\n'
              '• Device identifiers (IMEI, MAC address, serial number)\n'
              '• Physical location or GPS coordinates\n'
              '• Media files or camera / microphone inputs',
        ),
        _Section(
          title: '3. Local On-Device Storage',
          content:
              'All your personal data — including watch history, bookmarked titles, resume playback positions, '
              'and customized preferences — is saved locally on your device within private Hive storage boxes. '
              'This information remains exclusively under your control and is deleted whenever you uninstall or clear the app data.',
        ),
        _Section(
          title: '4. Transparent Ad-Supported Infrastructure',
          content:
              '$kAppName relies on advertising to support essential operations, including remote domain resolvers, '
              'cloud indexing infrastructure, scraper maintenance, and ongoing open-source engineering. '
              'Any ads served within the platform are mediated responsibly and do not collect invasive personal profiling data.',
        ),
        _Section(
          title: '5. Third-Party Media Sources',
          content:
              '$kAppName functions as an indexer and client-side media player. Content is resolved directly from publicly '
              'available internet hosts. When streaming or downloading video sources, your connection communicates directly '
              'with the third-party server hosting the file.',
        ),
        _Section(
          title: '6. Minimal Device Permissions',
          content:
              'The app requests only standard network access required to resolve metadata and video streams. '
              'No privileged system permissions (such as storage access, contacts, or SMS) are requested or required.',
        ),
      ],
    );
  }
}

/// Full scrollable Terms of Service viewer.
class TermsOfServiceSheet extends StatelessWidget {
  const TermsOfServiceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocumentSheet(
      title: 'Terms of Service',
      subtitle: 'Guidelines & Legal Disclaimer for $kAppName',
      icon: Icons.gavel_rounded,
      children: const [
        _Section(
          title: '1. Acceptance of Terms',
          content:
              'By installing, accessing, or using $kAppName, you acknowledge that you have read, '
              'understood, and agree to be bound by these Terms of Service. If you do not agree with any part '
              'of these terms, please discontinue using the application.',
        ),
        _Section(
          title: '2. Nature of the Application',
          content:
              '$kAppName is a tracking and management tool only. It does not host, provide, '
              'distribute, or maintain streaming content or extensions. All metadata and catalog information '
              'are retrieved dynamically through supported APIs and client-side integrations.',
        ),
        _Section(
          title: '3. Premier Media Hub & Legal Discovery',
          content:
              '$kAppName serves as your premier open-source hub for cinematic information, personal library tracking, '
              'and a comprehensive guide to legal streaming and media discovery. For casual viewers and cinephiles alike, '
              'our platform helps you discover, organize, and track media spanning every genre imaginable, with cast lists, '
              'plot summaries, ratings, and information on where to legally stream on services like Netflix, Amazon Prime, '
              'Hulu, Disney+, Crunchyroll, and others.',
        ),
        _Section(
          title: '4. User Responsibility & Compliance',
          content:
              'Users are solely responsible for how they use the app and any third-party services or extensions '
              'they choose to interact with, and must comply with all applicable laws, copyright, and intellectual '
              'property rights. You agree to use $kAppName exclusively for personal, non-commercial entertainment and tracking.',
        ),
        _Section(
          title: '5. Third-Party Services & Extensions',
          content:
              '$kAppName integrates only with official APIs of supported services. Third-party extensions are the '
              'responsibility of their independent creators, not the $kAppName developer. Legal concerns related to '
              'third-party services or extensions must be directed to their creators, not $kAppName.',
        ),
        _Section(
          title: '6. Privacy, Security & Community',
          content:
              'We are deeply committed to protecting your privacy. $kAppName utilizes a local-first architecture where '
              'your watch history, bookmarks, and preferences are kept securely on your device. We cultivate a respectful, '
              'passionate community centered around the appreciation of cinema and storytelling.',
        ),
        _Section(
          title: '7. Disclaimer of Warranties',
          content:
              '$kAppName is provided on an "as is" and "as available" basis without warranties of any kind, either '
              'expressed or implied. The developers and contributors do not guarantee uninterrupted streaming availability, '
              'data accuracy, or external host uptime.',
        ),
        _Section(
          title: '8. Limitation of Liability',
          content:
              'The developer of $kAppName disclaims all liability for misuse, legal issues, or violations arising from '
              'user actions. Under no circumstances shall developers or contributors be held liable for any direct, '
              'indirect, incidental, or consequential damages resulting from the use or inability to use the application '
              'or third-party services.',
        ),
      ],
    );
  }
}

class _DocumentSheet extends StatelessWidget {
  const _DocumentSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.headline),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 24, color: AppColors.surface2),
              // Scrollable clauses
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: children,
                ),
              ),
              // Bottom close button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surface2,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Close', style: AppText.button),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.body.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: AppText.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
