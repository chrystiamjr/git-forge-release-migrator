import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/gfrm_logo.dart';
import 'package:gfrm_gui/src/theme/gfrm_colors.dart';

class GfrmSidebar extends StatelessWidget {
  const GfrmSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return ColoredBox(
      color: GfrmColors.sidebarBackground,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isMacOS ? 56 : 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const GfrmLogo(),
            const SizedBox(height: 32),
            _navItem(icon: Icons.dashboard_outlined, label: 'Dashboard', active: true),
            _navItem(icon: Icons.add_box_outlined, label: 'New Migration'),
            _navItem(icon: Icons.sync_outlined, label: 'Run Progress'),
            _navItem(icon: Icons.task_alt_outlined, label: 'Results'),
            _navItem(icon: Icons.history, label: 'History'),
            const Spacer(),
            const Divider(color: GfrmColors.border),
            _navItem(icon: Icons.settings_outlined, label: 'Settings'),
            const SizedBox(height: 12),
            Text(
              'desktop foundation',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: GfrmColors.textMuted, letterSpacing: 0),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _navItem({required IconData icon, required String label, bool active = false}) {
  final Color textColor = active ? GfrmColors.accent : GfrmColors.textMuted;

  return Container(
    height: 40,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: active ? GfrmColors.sidebarActive : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: active ? const Border(left: BorderSide(color: GfrmColors.accent, width: 3)) : null,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'IBMPlexSans',
                fontSize: 14,
                color: GfrmColors.textMuted,
              ).copyWith(color: textColor),
            ),
          ),
        ],
      ),
    ),
  );
}
