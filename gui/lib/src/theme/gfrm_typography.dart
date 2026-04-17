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
