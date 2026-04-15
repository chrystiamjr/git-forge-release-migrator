import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_colors.dart';
import 'package:gfrm_gui/src/theme/gfrm_typography.dart';

class GfrmLogo extends StatelessWidget {
  const GfrmLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 28,
          height: 24,
          child: Stack(
            children: <Widget>[
              Positioned(left: 1, bottom: 2, child: _node()),
              Positioned(left: 15, top: 1, child: _node()),
              Positioned(left: 9, top: 11, child: Container(width: 2, height: 8, color: GfrmColors.accent)),
              Positioned(left: 9, top: 11, child: Container(width: 10, height: 2, color: GfrmColors.accent)),
              const Positioned(
                right: 0,
                bottom: 0,
                child: Icon(Icons.arrow_right_alt_rounded, size: 16, color: GfrmColors.accent),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const Text('gfrm', style: GfrmTypography.logo),
      ],
    );
  }
}

Widget _node() {
  return Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: GfrmColors.accent, width: 2),
    ),
  );
}
