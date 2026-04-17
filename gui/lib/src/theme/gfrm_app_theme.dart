library;

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
