import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_section_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class MatchingTagsPreviewSection extends StatelessWidget {
  const MatchingTagsPreviewSection({required this.tags, super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return NewMigrationSectionCard(
      title: 'Matching tag preview',
      child: Wrap(
        spacing: unit.s2,
        runSpacing: unit.s2,
        children: tags.map((String tag) => Chip(label: Text(tag))).toList(growable: false),
      ),
    );
  }
}
