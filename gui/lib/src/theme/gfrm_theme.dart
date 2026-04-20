part of 'gfrm_app_theme.dart';

final class GfrmTheme {
  const GfrmTheme._();

  static ThemeData build() {
    const GfrmColors colors = GfrmColors();
    const GfrmTypography typography = GfrmTypography();
    final ColorScheme colorScheme = ColorScheme.light(
      primary: colors.primary,
      secondary: colors.accent,
      surface: colors.surface,
      onPrimary: Colors.white,
      onSurface: colors.textBody,
      error: Colors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: false,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: 'IBMPlexSans',
      textTheme: typography.textTheme(),
      dividerColor: colors.border,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
  }
}
