import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

class GfrmLogo extends StatelessWidget {
  const GfrmLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SvgPicture.asset(
          '../website/static/img/logo.svg',
          width: 92,
          height: 42,
          colorFilter: const ColorFilter.mode(GfrmColors.accent, BlendMode.srcIn),
          semanticsLabel: 'gfrm',
        ),
      ],
    );
  }
}
