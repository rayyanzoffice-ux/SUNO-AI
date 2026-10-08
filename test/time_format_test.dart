import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:suno_ai/core/utils/time_format.dart';

/// Ranges of the digit blocks that `DateFormat` may substitute, as code points:
/// Arabic-Indic, Extended Arabic-Indic (Urdu/Persian), Devanagari (Hindi),
/// Bengali, plus the narrow no-break (U+202F) and no-break (U+00A0) spaces.
/// Built from code points because those two spaces are invisible in source.
final _nonAscii = RegExp(
  '[${_pair(0x0660, 0x0669)}${_pair(0x06F0, 0x06F9)}'
  '${_pair(0x0966, 0x096F)}${_pair(0x09E6, 0x09EF)}'
  '${_char(0x202F)}${_char(0x00A0)}]',
);

String _pair(int start, int end) => '${_char(start)}-${_char(end)}';

String _char(int codePoint) => String.fromCharCode(codePoint);

void main() {
  setUpAll(() async => initializeDateFormatting());

  final time = DateTime(2026, 10, 8, 14, 7);

  for (final locale in ['en', 'zh', 'hi', 'es', 'fr', 'ur', 'ar', 'bn']) {
    test('$locale clock and date use only 0-9 digits and plain spaces', () {
      for (final text in [
        formatClockLocalized(time, locale),
        formatMonthDayLocalized(time, locale),
      ]) {
        expect(_nonAscii.hasMatch(text), isFalse, reason: '$locale -> $text');
        expect(
          RegExp('[0-9]').hasMatch(text),
          isTrue,
          reason: '$locale -> $text',
        );
      }
    });
  }

  test('shared ASCII helpers keep the exact English shapes', () {
    expect(formatIsoDay(time), '2026-10-08');
    expect(formatClock24(time), '14:07');
    expect(formatIsoDayWithClock24(time), '2026-10-08 14:07');
    expect(formatClock12Hour(time), '2:07 PM');
  });

  test('asciiDigits converts every supported digit block', () {
    expect(asciiDigits('٢:٠٧'), '2:07');
    expect(asciiDigits('۱۲:۳۴'), '12:34');
    expect(asciiDigits('१४:०७'), '14:07');
    expect(asciiDigits('১৪:০৭'), '14:07');
    expect(asciiDigits('Oct 8'), 'Oct 8');
  });
}
