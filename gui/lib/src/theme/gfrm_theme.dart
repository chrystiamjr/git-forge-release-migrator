import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_colors.dart';
import 'package:gfrm_gui/src/theme/gfrm_typography.dart';

final class GfrmTheme {
  const GfrmTheme._();

  static ThemeData build() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: GfrmColors.primary,
      secondary: GfrmColors.accent,
      surface: GfrmColors.surface,
      onPrimary: Colors.white,
      onSurface: GfrmColors.textBody,
      error: Colors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: false,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: GfrmColors.surface,
      fontFamily: 'IBMPlexSans',
      textTheme: GfrmTypography.textTheme(),
      dividerColor: GfrmColors.border,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
  }
}
