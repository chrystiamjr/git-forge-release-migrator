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
