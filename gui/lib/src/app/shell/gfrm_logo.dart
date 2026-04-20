import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmLogo extends StatelessWidget {
  const GfrmLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;

    return Row(
      children: <Widget>[
        SvgPicture.asset(
          '../website/static/img/logo.svg',
          width: 92,
          height: 42,
          colorFilter: ColorFilter.mode(colors.accent, BlendMode.srcIn),
          semanticsLabel: 'gfrm',
        ),
      ],
    );
  }
}
