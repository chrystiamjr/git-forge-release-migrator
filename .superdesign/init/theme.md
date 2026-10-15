# Token summary
Navy sidebar #0F172A; indigo primary #4F46E5; accent #818CF8; surface #FFFDF8; card #FFF6E9; heading #102A43; body #334155; secondary #64748B; muted #94A3B8. IBM Plex Sans 12/14/16/22; Inter logo 18; IBM Plex Mono 12; metric value 72. Spacing 4px grid; buttons radius 8, cards radius 20; card shadow black 6%, blur 3, y=1. No explicit responsive breakpoints.

## gfrm_app_theme
Source: `gui/lib/src/theme/gfrm_app_theme.dart`

```dart
import 'package:flutter/material.dart';

part 'gfrm_colors.dart';
part 'gfrm_shadows.dart';
part 'gfrm_theme.dart';
part 'gfrm_typography.dart';
part 'gfrm_unit.dart';

final class GfrmAppTheme {
  const GfrmAppTheme._();

  static const GfrmColors colors = GfrmColors();
  static const GfrmTypography typography = GfrmTypography();
  static const GfrmUnit unit = GfrmUnit();
  static const GfrmShadows shadows = GfrmShadows();

  static ThemeData get themeData => GfrmTheme.build();
}

```

## gfrm_colors
Source: `gui/lib/src/theme/gfrm_colors.dart`

```dart
part of 'gfrm_app_theme.dart';

final class GfrmColors {
  const GfrmColors({
    this.sidebarBackground = const Color(0xFF0F172A),
    this.sidebarActive = const Color(0xE61E293B),
    this.sidebarInactive = Colors.transparent,
    this.accent = const Color(0xFF818CF8),
    this.primary = const Color(0xFF4F46E5),
    this.primaryHover = const Color(0xFF4338CA),
    this.illustrationStroke = const Color(0xFFCBD5E1),
    this.progressTrack = const Color(0xFFE2E8F0),
    this.surface = const Color(0xFFFFFDF8),
    this.surfaceCard = const Color(0xFFFFF6E9),
    this.surfaceStrong = const Color(0xFFF6E4C9),
    this.border = const Color(0x1F102A43),
    this.textHeading = const Color(0xFF102A43),
    this.textBody = const Color(0xFF334155),
    this.textSecondary = const Color(0xFF64748B),
    this.textMuted = const Color(0xFF94A3B8),
    this.textOnDark = const Color(0xFFF8FAFC),
    this.success = const Color(0xFF43A047),
    this.successLight = const Color(0xFFE8F5E9),
    this.error = const Color(0xFFC62828),
    this.errorLight = const Color(0xFFFFEBEE),
    this.warning = const Color(0xFFE65100),
    this.warningLight = const Color(0xFFFFF3E0),
  });

  final Color sidebarBackground;
  final Color sidebarActive;
  final Color sidebarInactive;
  final Color accent;
  final Color primary;
  final Color primaryHover;
  final Color illustrationStroke;
  final Color progressTrack;
  final Color surface;
  final Color surfaceCard;
  final Color surfaceStrong;
  final Color border;
  final Color textHeading;
  final Color textBody;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnDark;
  final Color success;
  final Color successLight;
  final Color error;
  final Color errorLight;
  final Color warning;
  final Color warningLight;
}

```

## gfrm_shadows
Source: `gui/lib/src/theme/gfrm_shadows.dart`

```dart
part of 'gfrm_app_theme.dart';

final class GfrmShadows {
  const GfrmShadows({this.card = const BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1))});

  final BoxShadow card;
}

```

## gfrm_theme
Source: `gui/lib/src/theme/gfrm_theme.dart`

```dart
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

```

## gfrm_typography
Source: `gui/lib/src/theme/gfrm_typography.dart`

```dart
part of 'gfrm_app_theme.dart';

final class GfrmTypography {
  const GfrmTypography({this.colors = const GfrmColors()});

  final GfrmColors colors;

  TextTheme textTheme() {
    return TextTheme(
      headlineLarge: headlineLarge,
      headlineSmall: headlineSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      labelLarge: labelLarge,
      labelMedium: labelMedium,
    );
  }

  TextStyle get headlineLarge {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 22,
      color: colors.textHeading,
      fontVariations: const <FontVariation>[FontVariation('wght', 700)],
    );
  }

  TextStyle get headlineSmall {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 16,
      color: colors.textHeading,
      fontVariations: const <FontVariation>[FontVariation('wght', 600)],
    );
  }

  TextStyle get bodyLarge {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 14,
      color: colors.textBody,
      fontVariations: const <FontVariation>[FontVariation('wght', 400)],
    );
  }

  TextStyle get bodyMedium {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 14,
      color: colors.textBody,
      fontVariations: const <FontVariation>[FontVariation('wght', 400)],
    );
  }

  TextStyle get labelLarge {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 14,
      color: colors.textOnDark,
      letterSpacing: 0.5,
      fontVariations: const <FontVariation>[FontVariation('wght', 600)],
    );
  }

  TextStyle get labelMedium {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 12,
      color: colors.textSecondary,
      letterSpacing: 0.96,
      fontVariations: const <FontVariation>[FontVariation('wght', 500)],
    );
  }

  TextStyle get logo {
    return TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      color: colors.accent,
      letterSpacing: 0.5,
      fontVariations: const <FontVariation>[FontVariation('wght', 700)],
    );
  }

  TextStyle get mono {
    return TextStyle(fontFamily: 'IBMPlexMono', fontSize: 12, color: colors.textSecondary);
  }

  TextStyle get buttonLabel {
    return const TextStyle(
      color: Colors.white,
      fontFamily: 'IBMPlexSans',
      fontSize: 14,
      letterSpacing: 0.5,
      fontVariations: <FontVariation>[FontVariation('wght', 600)],
    );
  }

  TextStyle get cardTitle {
    return TextStyle(fontFamily: 'IBMPlexSans', fontSize: 16, color: colors.textHeading, fontWeight: FontWeight.w600);
  }

  TextStyle get cardBody {
    return TextStyle(fontFamily: 'IBMPlexSans', fontSize: 14, color: colors.textBody);
  }

  TextStyle get emptyStateTitle {
    return TextStyle(
      color: colors.textSecondary,
      fontFamily: 'IBMPlexSans',
      fontSize: 18,
      fontVariations: const <FontVariation>[FontVariation('wght', 600)],
    );
  }

  TextStyle get emptyStateDescription {
    return TextStyle(color: colors.textMuted, fontFamily: 'IBMPlexSans', fontSize: 14);
  }

  TextStyle get sidebarItem {
    return TextStyle(
      fontFamily: 'IBMPlexSans',
      fontSize: 14,
      color: colors.textMuted,
      fontVariations: const <FontVariation>[FontVariation('wght', 500)],
    );
  }

  TextStyle get statLabel {
    return TextStyle(
      color: colors.textSecondary,
      fontFamily: 'IBMPlexSans',
      fontSize: 12,
      letterSpacing: 1.6,
      fontVariations: const <FontVariation>[FontVariation('wght', 600)],
    );
  }

  TextStyle get statValue {
    return TextStyle(
      color: colors.textMuted,
      fontFamily: 'IBMPlexSans',
      fontSize: 72,
      fontVariations: const <FontVariation>[FontVariation('wght', 700)],
    );
  }

  TextStyle get statValueCompact {
    return TextStyle(
      color: colors.textMuted,
      fontFamily: 'IBMPlexSans',
      fontSize: 32,
      fontVariations: const <FontVariation>[FontVariation('wght', 700)],
    );
  }
}

```

## gfrm_unit
Source: `gui/lib/src/theme/gfrm_unit.dart`

```dart
part of 'gfrm_app_theme.dart';

/// Unified metric scale on a 4px grid: s{n} = n * 4.
/// Use for spacing, padding, margin, and border radius.
final class GfrmUnit {
  const GfrmUnit();

  final double s1 = 4;
  final double s2 = 8;
  final double s3 = 12;
  final double s4 = 16;
  final double s5 = 20;
  final double s6 = 24;
  final double s7 = 28;
  final double s8 = 32;
  final double s9 = 36;
  final double s10 = 40;
  final double s11 = 44;
  final double s12 = 48;
  final double s13 = 52;
  final double s14 = 56;
  final double s15 = 60;
  final double s16 = 64;
  final double s17 = 68;
  final double s18 = 72;
  final double s19 = 76;
  final double s20 = 80;
  final double s21 = 84;
  final double s22 = 88;
  final double s23 = 92;
  final double s24 = 96;
  final double s25 = 100;
}

```