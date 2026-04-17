import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gfrm_gui/src/app/app_router.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

class GfrmApp extends ConsumerWidget {
  const GfrmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter routerConfig = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'gfrm',
      debugShowCheckedModeBanner: false,
      theme: GfrmAppTheme.themeData,
      routerConfig: routerConfig,
    );
  }
}
