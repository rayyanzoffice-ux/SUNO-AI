import 'package:flutter/material.dart';

import 'core/l10n/l10n.dart';
import 'core/l10n/locale_controller.dart';
import 'core/navigation/navigator_key.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

/// Root widget. Rebuilds when the language changes so every screen updates
/// instantly, and flips to right-to-left automatically for Arabic and Urdu.
class SunoApp extends StatelessWidget {
  /// Creates the app root.
  const SunoApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LocaleController.instance,
    builder: (context, _) => MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: navigatorKey,
      locale: LocaleController.instance.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: LocaleController.instance.hasChosenLanguage
          ? AppRoutes.home
          : AppRoutes.languageSetup,
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    ),
  );
}
