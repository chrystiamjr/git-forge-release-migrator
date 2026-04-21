import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class NewMigrationBlockingErrorBanner extends StatelessWidget {
  const NewMigrationBlockingErrorBanner({required this.blockingCount, super.key});

  final int blockingCount;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Container(
      key: const ValueKey<String>('new-migration-preflight-blocking-banner'),
      padding: EdgeInsets.all(unit.s3),
      decoration: BoxDecoration(
        color: GfrmAppTheme.colors.errorLight,
        border: Border(left: BorderSide(color: GfrmAppTheme.colors.error, width: 3)),
      ),
      child: Text(
        '$blockingCount blocking ${blockingCount == 1 ? 'error' : 'errors'} must be resolved before migration can start.',
        style: GfrmAppTheme.typography.bodyMedium.copyWith(color: GfrmAppTheme.colors.error),
      ),
    );
  }
}
