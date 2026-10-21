import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/backend/profile/locale_repository.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/l10n/l10n.dart';
import 'package:suno_ai/core/l10n/locale_controller.dart';
import 'package:suno_ai/core/routes/app_routes.dart';
import 'package:suno_ai/screens/language/language_selection_screen.dart';

/// Mirrors production routing: the picker is a named route on top of Home, so
/// Continue's `pushReplacementNamed('/')` lands on Home rather than rendering
/// the picker again. `MaterialApp(home:)` cannot be combined with a `'/'`
/// route, which is exactly what production uses for Home.
Widget _pickerApp() => MaterialApp(
  locale: SunoLanguages.english.locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  initialRoute: '/language',
  routes: {
    AppRoutes.home: (_) => const Scaffold(body: Text('Home')),
    '/language': (_) => const LanguageSelectionScreen(isFirstRun: true),
  },
);

void main() {
  testWidgets('first-run Continue saves the language already on screen', (
    tester,
  ) async {
    final repository = InMemoryLocaleRepository();
    LocaleController.instance = LocaleController(repository: repository);
    addTearDown(() {
      LocaleController.instance = LocaleController(
        repository: InMemoryLocaleRepository(),
      );
    });

    await tester.pumpWidget(_pickerApp());

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(LocaleController.instance.hasChosenLanguage, isTrue);
    expect(await repository.getLanguageCode(), SunoLanguages.english.code);
  });

  testWidgets('a tapped language is saved before Continue', (tester) async {
    final repository = InMemoryLocaleRepository();
    LocaleController.instance = LocaleController(repository: repository);
    addTearDown(() {
      LocaleController.instance = LocaleController(
        repository: InMemoryLocaleRepository(),
      );
    });

    await tester.pumpWidget(_pickerApp());

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(await repository.getLanguageCode(), SunoLanguages.spanish.code);

    // The test app pins its locale, so the button itself stays English here.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(await repository.getLanguageCode(), SunoLanguages.spanish.code);
  });

  testWidgets('first-run Continue retries a language write that failed', (
    tester,
  ) async {
    final repository = _FlakyLocaleRepository();
    LocaleController.instance = LocaleController(repository: repository);
    addTearDown(() {
      LocaleController.instance = LocaleController(
        repository: InMemoryLocaleRepository(),
      );
    });

    await tester.pumpWidget(_pickerApp());

    // The tile updates the controller in memory but its storage write fails,
    // so without a retry the next launch would show the picker again.
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(repository.writes, 1);
    expect(await repository.getLanguageCode(), isNull);
    // Let the save-failure SnackBar expire so it cannot cover the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(repository.writes, 2);
    expect(await repository.getLanguageCode(), SunoLanguages.spanish.code);
    expect(find.text('Home'), findsOneWidget);
  });
}

class _FlakyLocaleRepository implements LocaleRepository {
  String? _code;
  int writes = 0;

  @override
  Future<String?> getLanguageCode() async => _code;

  @override
  Future<void> setLanguageCode(String code) async {
    writes++;
    if (writes == 1) throw StateError('storage unavailable');
    _code = code;
  }
}
