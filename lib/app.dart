import 'package:flutter/material.dart';

import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

class SunoApp extends StatelessWidget {
  const SunoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SUNO — AI Safety Companion',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    initialRoute: AppRoutes.home,
    routes: AppRoutes.routes,
  );
}
