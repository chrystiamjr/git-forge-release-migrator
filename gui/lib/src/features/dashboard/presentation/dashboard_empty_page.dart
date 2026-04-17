import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/app_routes.dart';
import 'package:gfrm_gui/src/core/widgets/atoms/gfrm_button.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_empty_state.dart';
import 'package:gfrm_gui/src/core/widgets/molecules/gfrm_stat_card.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class DashboardEmptyPage extends StatelessWidget {
  const DashboardEmptyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Dashboard', style: Theme.of(context).textTheme.headlineLarge),
        SizedBox(height: unit.s6),
        Row(
          children: <Widget>[
            const Expanded(
              child: GfrmStatCard(label: 'Success Rate', value: '0%', showCircularProgress: true),
            ),
            SizedBox(width: unit.s6),
            const Expanded(
              child: GfrmStatCard(label: 'Total Migrations', value: '0'),
            ),
            SizedBox(width: unit.s6),
            const Expanded(
              child: GfrmStatCard(label: 'Failures', value: '0'),
            ),
          ],
        ),
        SizedBox(height: unit.s6),
        GfrmEmptyState(
          title: 'No migrations yet',
          description: 'Start your first release migration between Git forges',
          action: GfrmButton(
            label: 'New Migration',
            icon: Icons.add_circle_outline,
            onPressed: () {
              context.go(AppRoute.newMigration.path);
            },
          ),
        ),
      ],
    );
  }
}
