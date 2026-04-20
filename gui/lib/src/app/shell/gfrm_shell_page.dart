import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/shell/gfrm_sidebar.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmShellPage extends StatelessWidget {
  const GfrmShellPage({required this.currentLocation, required this.child, super.key});

  static const Key sidebarKey = Key('gfrm-sidebar');
  static const Key contentKey = Key('gfrm-content');
  static const double _sidebarWidth = 220;

  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return Scaffold(
      body: Row(
        children: <Widget>[
          SizedBox(
            key: sidebarKey,
            width: _sidebarWidth,
            child: GfrmSidebar(currentLocation: currentLocation),
          ),
          Expanded(
            child: ColoredBox(
              key: contentKey,
              color: colors.surface,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(unit.s6, isMacOS ? unit.s14 : unit.s6, unit.s6, unit.s8),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
