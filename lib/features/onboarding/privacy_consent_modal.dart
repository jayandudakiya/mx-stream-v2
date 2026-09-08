import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/privacy/privacy_consent_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import 'privacy_policy_sheet.dart';

/// Opens the Privacy Policy, Terms & Ad Consent Modal as a sleek, transparent sheet.
Future<bool?> showPrivacyConsentModal(
  BuildContext context, {
  VoidCallback? onAccepted,
  bool isReview = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: isReview,
    enableDrag: isReview,
    useRootNavigator: true,
    builder: (ctx) => PrivacyConsentModal(
      onAccepted: () {
        Navigator.of(ctx).pop(true);
        onAccepted?.call();
      },
      isReview: isReview,
    ),
  );
}

/// A sleek, transparent modal card presenting the Privacy Policy, Terms of Service,
/// and Advertising disclosure.
class PrivacyConsentModal extends StatelessWidget {
  const PrivacyConsentModal({
    super.key,
    required this.onAccepted,
    this.isReview = false,
  });

  /// Called when the user taps "Accept & Continue".
  final VoidCallback onAccepted;

  /// True when invoked from Settings -> Privacy to review previously accepted consent.
  final bool isReview;

  Future<void> _handleAccept() async {
    await PrivacyConsentPrefs.markAccepted();
    onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isTv ? 620 : 540,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isTv ? 24 : 28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(isTv ? 24 : 28),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    blurRadius: 36,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isTv)
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      // Header with Shield Badge & Logo
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.accent.withValues(alpha: 0.28),
                                  AppColors.accent.withValues(alpha: 0.08),
                                  Colors.transparent,
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.verified_user_rounded,
                              color: AppColors.accent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Privacy & Terms',
                                  style: AppText.title.copyWith(fontSize: 20),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Transparency & User Trust in $kAppName',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isReview)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.greenAccent.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.greenAccent,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Accepted',
                                    style: AppText.caption.copyWith(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Card 1: User Privacy First
                      _ConsentPointCard(
                        icon: Icons.shield_outlined,
                        iconColor: AppColors.accent,
                        title: 'Your Privacy Is Respected',
                        description:
                            '$kAppName does not collect, track, or sell personal phone data, contacts, location, '
                            'or viewing habits. Your history and bookmarks remain stored locally on your device.',
                      ),
                      const SizedBox(height: 12),

                      // Card 2: Ad-Supported Infrastructure
                      _ConsentPointCard(
                        icon: Icons.cloud_outlined,
                        iconColor: const Color(0xFF64B5F6),
                        title: 'Transparent Infrastructure',
                        description:
                            'Advertisements fund high-performance server infrastructure, cloud proxy resolvers, '
                            'and scraper maintenance to keep the app operational and completely free.',
                      ),
                      const SizedBox(height: 12),

                      // Card 3: Support the Project
                      _ConsentPointCard(
                        icon: Icons.favorite_outline_rounded,
                        iconColor: const Color(0xFFFF8A80),
                        title: 'Support Ongoing Development',
                        description:
                            'Please support the project by viewing ads where applicable. Your support directly enables '
                            'regular updates, fast load times, and new streaming capabilities.',
                      ),
                      const SizedBox(height: 22),

                      // Document review actions
                      Row(
                        children: [
                          Expanded(
                            child: _DocumentButton(
                              label: 'Privacy Policy',
                              icon: Icons.privacy_tip_outlined,
                              onTap: () => showPrivacyPolicySheet(context),
                              isTv: isTv,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DocumentButton(
                              label: 'Terms of Service',
                              icon: Icons.article_outlined,
                              onTap: () => showTermsOfServiceSheet(context),
                              isTv: isTv,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Primary Action: Accept & Continue (or Close in review mode)
                      if (isReview)
                        _buildButton(
                          isTv: isTv,
                          label: 'Close',
                          icon: Icons.check_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        )
                      else
                        _buildButton(
                          isTv: isTv,
                          label: 'Accept & Continue',
                          icon: Icons.arrow_forward_rounded,
                          onTap: _handleAccept,
                          isPrimary: true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required bool isTv,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final button = SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: isPrimary ? AppColors.accent : AppColors.surface2,
          foregroundColor: isPrimary ? Colors.white : AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isPrimary ? 3 : 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppText.button.copyWith(
                color: isPrimary ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 18),
          ],
        ),
      ),
    );

    if (isTv) {
      return TvFocusable(
        autofocus: isPrimary,
        onTap: onTap,
        child: ExcludeFocus(child: button),
      );
    }
    return button;
  }
}

class _ConsentPointCard extends StatelessWidget {
  const _ConsentPointCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.surface2.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentButton extends StatelessWidget {
  const _DocumentButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isTv,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface.withValues(alpha: 0.4),
          foregroundColor: AppColors.textSecondary,
          side: BorderSide(
            color: AppColors.surface2.withValues(alpha: 0.9),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (isTv) {
      return TvFocusable(
        onTap: onTap,
        child: ExcludeFocus(child: button),
      );
    }
    return button;
  }
}
