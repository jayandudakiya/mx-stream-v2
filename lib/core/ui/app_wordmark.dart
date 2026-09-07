import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// The OrcaBox logotype, drawn as text rather than loaded as artwork.
///
/// It replaces the wordmark PNG the app used to ship: the name is set in the
/// app's own type (Inter, tight and heavy), two-tone so "Orca" carries the
/// accent the rest of the UI uses. Being text, it stays sharp at any size,
/// follows a custom accent colour, and needs no per-density asset.
///
/// The two halves are separate [TextSpan]s, which is why a repo-wide search for
/// the old product name never matched this file during the rebrand — keep the
/// split in mind if the name changes again.
///
/// Sizing matches what `Image.asset(..., fit: BoxFit.contain)` did, so it drops
/// into both kinds of call site unchanged:
///  * pass [height] where the old code passed `height:` (headers, the TV rail);
///  * pass neither inside a width-driven parent (`FractionallySizedBox`) and it
///    scales to that width, as the splash and onboarding brand page do.
class AppWordmark extends StatelessWidget {
  const AppWordmark({
    super.key,
    this.height,
    this.alignment = Alignment.center,
    this.color,
  });

  /// Cap height for the logotype. Null lets the parent's width drive the size.
  final double? height;

  /// Where the mark sits when the box is bigger than the text.
  final AlignmentGeometry alignment;

  /// Overrides the "Box" half's colour (the "Orca" half always uses the
  /// accent). Defaults to the primary text colour.
  final Color? color;

  /// Drawn at a fixed size and then scaled by [FittedBox], so the glyph shapes
  /// and letter-spacing stay proportional at every call site instead of being
  /// re-hinted per size.
  static const double _intrinsicSize = 48;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppText.fontFamily,
      fontFamilyFallback: AppText.fontFamilyFallback,
      fontSize: _intrinsicSize,
      fontWeight: FontWeight.w800,
      // Negative tracking is what makes a name read as a logotype rather than
      // as a run of UI text.
      letterSpacing: -_intrinsicSize * 0.03,
      height: 1.0,
      color: color ?? AppColors.textPrimary,
    );

    final mark = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Orca', style: base.copyWith(color: AppColors.accent)),
          const TextSpan(text: 'Box'),
        ],
      ),
      style: base,
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.left,
    );

    final fitted = FittedBox(
      fit: BoxFit.contain,
      alignment: alignment,
      child: mark,
    );

    return height == null ? fitted : SizedBox(height: height, child: fitted);
  }
}
