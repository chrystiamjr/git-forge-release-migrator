import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/app/gfrm_shell_page.dart';
import 'package:gfrm_gui/src/theme/gfrm_theme.dart';

class GfrmApp extends StatelessWidget {
  const GfrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gfrm',
      debugShowCheckedModeBanner: false,
      theme: GfrmTheme.build(),
      home: const GfrmShellPage(),
    );
  }
}
