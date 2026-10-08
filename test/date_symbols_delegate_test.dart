import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/core/l10n/app_locales.dart';
import 'package:suno_ai/core/utils/time_format.dart';

import 'helpers/test_app.dart';

/// History and the received-alert line build their dates while the app runs,
/// so intl's per-locale date symbols have to be loaded by SUNO's own
/// localization delegates. This file never calls `initializeDateFormatting()`,
/// on purpose: if a delegate does not load them, `DateFormat` fails here
/// instead of on the demo phone.
void main() {
  final moment = DateTime(2026, 10, 8, 14, 7);

  testWidgets('the app really loads date symbols for every language', (
    tester,
  ) async {
    final english = formatMonthDayLocalized(moment, 'en');

    for (final language in SunoLanguages.all) {
      String? rendered;
      await tester.pumpWidget(
        localizedTestApp(
          Builder(
            builder: (context) {
              rendered = formatMonthDayLocalized(
                moment,
                Localizations.localeOf(context).toLanguageTag(),
              );
              return const SizedBox.shrink();
            },
          ),
          language: language,
        ),
      );

      expect(tester.takeException(), isNull, reason: language.englishName);
      // A silent fallback to English would look like a working app with a
      // wrong date, so an identical month name counts as a failure too.
      if (language.code != 'en') {
        expect(rendered, isNot(english), reason: language.englishName);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
