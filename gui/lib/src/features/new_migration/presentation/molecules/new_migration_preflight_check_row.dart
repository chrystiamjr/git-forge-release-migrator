import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';
import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_badge.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_checklist_item.dart';

final class NewMigrationPreflightCheckRow extends StatelessWidget {
  const NewMigrationPreflightCheckRow({required this.item, required this.hasBlockingErrors, super.key});

  final DesktopPreflightCheckItem item;
  final bool hasBlockingErrors;

  @override
  Widget build(BuildContext context) {
    return GfrmChecklistItem(
      icon: _icon(),
      iconColor: _iconColor(),
      title: item.message,
      subtitle: item.hint,
      badge: GfrmBadge(label: _badgeLabel(), backgroundColor: _badgeBackgroundColor(), textColor: _badgeTextColor()),
    );
  }

  String _badgeLabel() {
    if (item.isBlocking && hasBlockingErrors) {
      return 'Blocked';
    }
    if (item.isBlocking) {
      return 'Error';
    }
    if (item.isWarning) {
      return 'Warning';
    }
    return 'OK';
  }

  IconData _icon() {
    if (item.isBlocking) {
      return Icons.close;
    }
    if (item.isWarning) {
      return Icons.warning_amber_rounded;
    }
    return Icons.check;
  }

  Color _iconColor() {
    if (item.isBlocking) {
      return const Color(0xFFC62828);
    }
    if (item.isWarning) {
      return const Color(0xFFE65100);
    }
    return const Color(0xFF2E7D32);
  }

  Color _badgeBackgroundColor() {
    if (item.isBlocking) {
      return const Color(0xFFFFEBEE);
    }
    if (item.isWarning) {
      return const Color(0xFFFFF3E0);
    }
    return const Color(0xFFE8F5E9);
  }

  Color _badgeTextColor() {
    if (item.isBlocking) {
      return const Color(0xFFC62828);
    }
    if (item.isWarning) {
      return const Color(0xFFE65100);
    }
    return const Color(0xFF2E7D32);
  }
}
