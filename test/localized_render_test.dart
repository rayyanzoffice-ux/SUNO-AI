import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/app.dart';
import 'package:suno_ai/backend/location/location_service.dart';
import 'package:suno_ai/backend/profile/locale_repository.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/l10n/l10n.dart';
import 'package:suno_ai/core/l10n/locale_controller.dart';
import 'package:suno_ai/models/detection_result.dart';
import 'package:suno_ai/models/incident.dart';
import 'package:suno_ai/screens/home/home_screen.dart';
import 'package:suno_ai/screens/safety_check/safety_check_screen.dart';
import 'package:suno_ai/services/suno_runtime_service.dart';

/// A location service that reports denial, so no test reaches for GPS.
class _UnavailableLocation extends LocationService {
  @override
  Future<LocationSnapshot?> currentLocation({
    bool requestPermission = true,
  }) async {
    status = LocationStatus.denied;
    return null;
  }
}

/// [MaterialApp] with SUNO's localizations, forced to [language] and to a
/// fixed text scale (French, Spanish and Hindi strings are far longer than
/// English, and Arabic and Urdu need room for their diacritics).
Widget _localizedApp(
  Widget child, {
  required SunoLanguage language,
  required double textScale,
}) => MaterialApp(
  locale: language.locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
  builder: (context, childBelow) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: childBelow ?? const SizedBox.shrink(),
  ),
);

Future<Incident?> _startSafetyCheck() =>
    SunoRuntimeService.instance.recordDetection(
      DetectionResult(
        eventType: 'Possible Distress Sound',
        confidence: .9,
        impactDetected: false,
        stillnessDetected: false,
        riskScore: 50,
        riskLevel: RiskLevel.medium,
        detectedAt: DateTime.now(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocaleController.instance = LocaleController(
      repository: InMemoryLocaleRepository(),
    );
    SunoRuntimeService.instance = SunoRuntimeService(
      locationService: _UnavailableLocation(),
    );
  });

  tearDown(() {
    SunoRuntimeService.instance.dispose();
  });

  testWidgets('every language lays out in the right direction', (
    tester,
  ) async {
    for (final language in SunoLanguages.all) {
      // The locale lands synchronously, before setLanguage reaches its await.
      unawaited(LocaleController.instance.setLanguage(language));
      await tester.pumpWidget(const SunoApp());
      await tester.pump();

      expect(tester.takeException(), isNull, reason: language.englishName);
      expect(
        Directionality.of(tester.element(find.byType(HomeScreen))),
        language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        reason: language.englishName,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Home and Safety Check survive all eight languages', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);

    for (final textScale in const <double>[1, 1.3]) {
      for (final language in SunoLanguages.all) {
        final label = '${language.code} at ${textScale}x text';
        // Created here, not in setUp: a Future started in setUp belongs to
        // package:test's outer zone and cannot resume inside this fake-async
        // body.
        final incident = await tester.runAsync(_startSafetyCheck);
        expect(incident, isNotNull, reason: label);

        for (final screen in <Widget>[
          const HomeScreen(),
          const SafetyCheckScreen(),
        ]) {
          final type = screen.runtimeType;
          await tester.pumpWidget(
            _localizedApp(
              screen,
              language: language,
              textScale: textScale,
            ),
          );
          await tester.pump();

          final scaler = MediaQuery.textScalerOf(
            tester.element(find.byType(type)),
          );
          expect(
            scaler.scale(100),
            closeTo(100 * textScale, .01),
            reason: '$label $type: the forced text scale never rendered',
          );
          expect(tester.takeException(), isNull, reason: '$label $type');

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
