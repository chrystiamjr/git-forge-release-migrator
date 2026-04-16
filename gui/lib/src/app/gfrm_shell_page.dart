import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/gfrm_sidebar.dart';
import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

class GfrmShellPage extends StatelessWidget {
  const GfrmShellPage({required this.currentLocation, required this.child, super.key});

  static const Key sidebarKey = Key('gfrm-sidebar');
  static const Key contentKey = Key('gfrm-content');
  static const double _sidebarWidth = 220;

  final String currentLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
              color: GfrmColors.surface,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(padding: EdgeInsets.fromLTRB(24, isMacOS ? 56 : 24, 24, 32), child: child),
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
