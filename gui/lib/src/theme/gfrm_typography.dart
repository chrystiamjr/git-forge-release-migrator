import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

final class GfrmTypography {
  const GfrmTypography._();

  static TextTheme textTheme() {
    return const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 22,
        color: GfrmColors.textHeading,
        fontVariations: <FontVariation>[FontVariation('wght', 700)],
      ),
      headlineSmall: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 16,
        color: GfrmColors.textHeading,
        fontVariations: <FontVariation>[FontVariation('wght', 600)],
      ),
      bodyLarge: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 14,
        color: GfrmColors.textBody,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
      ),
      bodyMedium: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 14,
        color: GfrmColors.textBody,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
      ),
      labelLarge: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 14,
        color: GfrmColors.textOnDark,
        letterSpacing: 0.5,
        fontVariations: <FontVariation>[FontVariation('wght', 600)],
      ),
      labelMedium: TextStyle(
        fontFamily: 'IBMPlexSans',
        fontSize: 12,
        color: GfrmColors.textSecondary,
        letterSpacing: 0.96,
        fontVariations: <FontVariation>[FontVariation('wght', 500)],
      ),
    );
  }

  static const TextStyle logo = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    color: GfrmColors.accent,
    letterSpacing: 0.5,
    fontVariations: <FontVariation>[FontVariation('wght', 700)],
  );

  static const TextStyle mono = TextStyle(fontFamily: 'IBMPlexMono', fontSize: 12, color: GfrmColors.textSecondary);
}
