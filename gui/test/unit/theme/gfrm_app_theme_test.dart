import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

void main() {
  test('theme data exposes the GUI design tokens through Material theme', () {
    final ThemeData theme = GfrmAppTheme.themeData;

    expect(theme.colorScheme.primary, GfrmAppTheme.colors.primary);
    expect(theme.colorScheme.secondary, GfrmAppTheme.colors.accent);
    expect(theme.colorScheme.surface, GfrmAppTheme.colors.surface);
    expect(theme.scaffoldBackgroundColor, GfrmAppTheme.colors.surface);
    expect(theme.dividerColor, GfrmAppTheme.colors.border);
    expect(theme.textTheme.headlineLarge?.color, GfrmAppTheme.colors.textHeading);
    expect(theme.textTheme.bodyLarge?.color, GfrmAppTheme.colors.textBody);
  });

  test('semantic typography tokens keep component styles aligned with colors', () {
    final TextStyle emptyStateTitle = GfrmAppTheme.typography.emptyStateTitle;
    final TextStyle emptyStateDescription = GfrmAppTheme.typography.emptyStateDescription;
    final TextStyle statLabel = GfrmAppTheme.typography.statLabel;
    final TextStyle statValue = GfrmAppTheme.typography.statValue;

    expect(emptyStateTitle.color, GfrmAppTheme.colors.textSecondary);
    expect(emptyStateTitle.fontSize, 18);
    expect(emptyStateDescription.color, GfrmAppTheme.colors.textMuted);
    expect(statLabel.color, GfrmAppTheme.colors.textSecondary);
    expect(statLabel.letterSpacing, 1.6);
    expect(statValue.color, GfrmAppTheme.colors.textMuted);
    expect(statValue.fontSize, 72);
  });

  test('unit scale stays on the 4px grid used by GUI spacing and radius', () {
    expect(GfrmAppTheme.unit.s1, 4);
    expect(GfrmAppTheme.unit.s2, 8);
    expect(GfrmAppTheme.unit.s6, 24);
    expect(GfrmAppTheme.unit.s14, 56);
  });
}
