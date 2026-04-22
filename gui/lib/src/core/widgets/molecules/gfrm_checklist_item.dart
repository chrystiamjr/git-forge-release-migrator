import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_badge.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmChecklistItem extends StatelessWidget {
  const GfrmChecklistItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final GfrmBadge badge;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 20),
          SizedBox(width: unit.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(title, style: GfrmAppTheme.typography.bodyMedium),
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: unit.s1),
                  Text(subtitle!, style: GfrmAppTheme.typography.mono.copyWith(color: colors.textSecondary)),
                ],
              ],
            ),
          ),
          SizedBox(width: unit.s3),
          badge,
        ],
      ),
    );
  }
}
