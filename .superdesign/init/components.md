# Desktop shared primitives
Flutter custom atomic design; Riverpod; go_router.

## gfrm_badge
Source: `gui/lib/src/core/widgets/atoms/gfrm_badge.dart`

```dart
import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmBadge extends StatelessWidget {
  const GfrmBadge({required this.label, required this.backgroundColor, required this.textColor, super.key});

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: unit.s3, vertical: unit.s1),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(unit.s2)),
      child: Text(label, style: GfrmAppTheme.typography.labelMedium.copyWith(color: textColor, letterSpacing: 0)),
    );
  }
}

```

## gfrm_button
Source: `gui/lib/src/core/widgets/atoms/gfrm_button.dart`

```dart
import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmButton extends StatelessWidget {
  const GfrmButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
    this.isSuccess = false,
    this.height = 36,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isSecondary;
  final bool isSuccess;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;

    return SizedBox(
      height: height,
      child: Material(
        color: _backgroundColor(),
        borderRadius: BorderRadius.circular(unit.s2),
        child: InkWell(
          borderRadius: BorderRadius.circular(unit.s2),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: unit.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: isSecondary ? colors.textBody : Colors.white),
                  SizedBox(width: unit.s2),
                ],
                Text(label.toUpperCase(), style: typography.buttonLabel.copyWith(color: _foregroundColor())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor() {
    final colors = GfrmAppTheme.colors;
    if (onPressed == null) {
      return colors.illustrationStroke;
    }
    if (isSecondary) {
      return colors.surface;
    }
    if (isSuccess) {
      return colors.success;
    }
    return colors.primary;
  }

  Color _foregroundColor() {
    if (isSecondary) {
      return GfrmAppTheme.colors.textBody;
    }
    return Colors.white;
  }
}

```

## gfrm_checklist_item
Source: `gui/lib/src/core/widgets/molecules/gfrm_checklist_item.dart`

```dart
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

```

## gfrm_empty_state
Source: `gui/lib/src/core/widgets/molecules/gfrm_empty_state.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmEmptyState extends StatelessWidget {
  const GfrmEmptyState({required this.title, required this.description, this.action, super.key});

  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final shadows = GfrmAppTheme.shadows;
    final typography = GfrmAppTheme.typography;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(unit.s6, unit.s10, unit.s6, unit.s14),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(unit.s5),
        border: Border.all(color: colors.border),
        boxShadow: <BoxShadow>[shadows.card],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.asset('../website/static/img/gfrm_nodes.svg', height: 130, semanticsLabel: 'empty nodes'),
          SizedBox(height: unit.s6),
          Text(title, textAlign: TextAlign.center, style: typography.emptyStateTitle),
          SizedBox(height: unit.s2),
          Text(description, textAlign: TextAlign.center, style: typography.emptyStateDescription),
          if (action != null) ...<Widget>[SizedBox(height: unit.s8), action!],
        ],
      ),
    );
  }
}

```

## gfrm_nav_item
Source: `gui/lib/src/core/widgets/molecules/gfrm_nav_item.dart`

```dart
import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/navigation/app_routes.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmNavItem extends StatelessWidget {
  const GfrmNavItem({required this.route, required this.active, required this.onPressed, super.key});

  static const double _height = 40;

  final AppRoute route;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final typography = GfrmAppTheme.typography;
    final Color textColor = active ? colors.accent : colors.textMuted;

    return Container(
      height: _height,
      margin: EdgeInsets.only(bottom: unit.s2),
      decoration: BoxDecoration(
        color: active ? colors.sidebarActive : colors.sidebarInactive,
        borderRadius: BorderRadius.circular(unit.s2),
        border: active ? Border(left: BorderSide(color: colors.accent, width: 3)) : null,
      ),
      child: Material(
        color: colors.sidebarInactive,
        child: InkWell(
          borderRadius: BorderRadius.circular(unit.s2),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.only(left: unit.s4, right: unit.s3),
            child: Row(
              children: <Widget>[
                Icon(route.icon, size: 20, color: textColor),
                SizedBox(width: unit.s3),
                Expanded(
                  child: Text(
                    route.label,
                    overflow: TextOverflow.ellipsis,
                    style: typography.sidebarItem.copyWith(color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

```

## gfrm_stat_card
Source: `gui/lib/src/core/widgets/molecules/gfrm_stat_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmStatCard extends StatelessWidget {
  const GfrmStatCard({required this.label, required this.value, this.showCircularProgress = false, super.key});

  final String label;
  final String value;
  final bool showCircularProgress;

  static const circularProgressSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final colors = GfrmAppTheme.colors;
    final unit = GfrmAppTheme.unit;
    final shadows = GfrmAppTheme.shadows;
    final typography = GfrmAppTheme.typography;

    return Container(
      height: 210,
      padding: EdgeInsets.all(unit.s6),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(unit.s5),
        border: Border.all(color: colors.border),
        boxShadow: <BoxShadow>[shadows.card],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (showCircularProgress)
            SizedBox(
              width: circularProgressSize,
              height: circularProgressSize,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: 0,
                    strokeWidth: unit.s3,
                    trackGap: 100,
                    constraints: BoxConstraints(minWidth: circularProgressSize, minHeight: circularProgressSize),
                    backgroundColor: colors.progressTrack,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.transparent),
                  ),
                  Text(value, style: typography.statValueCompact),
                ],
              ),
            )
          else
            Text(value, style: typography.statValue),
          SizedBox(height: unit.s5),
          Text(label.toUpperCase(), textAlign: TextAlign.center, style: typography.statLabel),
        ],
      ),
    );
  }
}

```