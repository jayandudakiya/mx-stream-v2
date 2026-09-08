import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/privacy/privacy_consent_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import 'privacy_policy_sheet.dart';
import '../../l10n/l10n.dart';

/// TV-adapted first-run onboarding with Privacy Policy, Terms & Ad Consent.
/// Focusable buttons ensure simple D-pad navigation on Android TV and Fire TV.
class OnboardingScreenTv extends StatefulWidget {
  const OnboardingScreenTv({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreenTv> createState() => _OnboardingScreenTvState();
}

class _OnboardingScreenTvState extends State<OnboardingScreenTv> {
  Future<void> _acceptAndContinue() async {
    await PrivacyConsentPrefs.markAccepted();
    if (mounted) widget.onDone();
  }

  Widget _bullet(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: AppColors.accent, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.accent,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.welcomeToApp(kAppName),
                    style: AppText.title.copyWith(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your privacy is respected. No personal phone data is collected or sold. '
                    'Ads support server infrastructure and keep $kAppName free.',
                    style: AppText.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surface2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bullet(
                          Icons.explore_outlined,
                          context.l10n.openProviders,
                        ),
                        _bullet(
                          Icons.movie_filter_outlined,
                          'Pick Movies, Series, or Anime',
                        ),
                        _bullet(
                          Icons.download_outlined,
                          context.l10n.onboardingBrowseAndInstall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TvFocusable(
                          autofocus: false,
                          onTap: () => showPrivacyPolicySheet(context),
                          child: ExcludeFocus(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: () => showPrivacyPolicySheet(context),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                  foregroundColor: AppColors.textSecondary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Privacy Policy',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TvFocusable(
                          autofocus: false,
                          onTap: () => showTermsOfServiceSheet(context),
                          child: ExcludeFocus(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: () => showTermsOfServiceSheet(context),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                  foregroundColor: AppColors.textSecondary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Terms of Service',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TvFocusable(
                    autofocus: true,
                    onTap: _acceptAndContinue,
                    child: ExcludeFocus(
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _acceptAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Accept & Continue',
                                style: AppText.button.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
