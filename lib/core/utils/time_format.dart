import 'package:intl/intl.dart';

/// Formats a [DateTime] as 12-hour clock time with an AM/PM suffix, e.g.
/// "2:07 PM" or "11:45 AM". Shared by History and Trusted Contact View so
/// timestamps read consistently across the app.
String formatClock12Hour(DateTime time) {
  final hour24 = time.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

// ---- Shared ASCII-only building blocks (exact current English output) ----

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// `YYYY-MM-DD` (year not padded, matching the existing screens).
/// Always ASCII digits; not locale-aware by design.
String formatIsoDay(DateTime time) =>
    '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)}';

/// 24-hour `HH:MM`. Always ASCII digits; not locale-aware by design.
String formatClock24(DateTime time) =>
    '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';

/// `YYYY-MM-DD HH:MM`, used by the Contacts "last accepted test" line.
String formatIsoDayWithClock24(DateTime time) =>
    '${formatIsoDay(time)} ${formatClock24(time)}';

// ---- Locale-aware helpers, forced to 0-9 ----

/// First code point (the digit zero) of each non-ASCII digit block used by the
/// supported languages: Arabic-Indic, Extended Arabic-Indic (Urdu/Persian),
/// Devanagari (Hindi) and Bengali.
const _zeroDigits = <int>[0x0660, 0x06F0, 0x0966, 0x09E6];

/// Converts any digit from the blocks above to its 0-9 equivalent; every other
/// character is left untouched.
String asciiDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    var mapped = rune;
    for (final zero in _zeroDigits) {
      if (rune >= zero && rune <= zero + 9) {
        mapped = 0x30 + (rune - zero);
        break;
      }
    }
    buffer.writeCharCode(mapped);
  }
  return buffer.toString();
}

/// Spaces `DateFormat` can emit inside a pattern: U+202F (narrow no-break, used
/// before AM/PM markers) and U+00A0 (no-break). Named by code point because they
/// are indistinguishable from a plain space when written in source.
final _oddSpaces = [
  String.fromCharCode(0x202F),
  String.fromCharCode(0x00A0),
];

/// Makes `DateFormat` output safe to show: 0-9 digits and plain spaces.
String _normalise(String formatted) {
  var text = formatted;
  for (final space in _oddSpaces) {
    text = text.replaceAll(space, ' ');
  }
  return asciiDigits(text);
}

/// Locale-aware clock time (for example "2:07 PM" in English, "14:07" in
/// French, "2:07 م" in Arabic), always with 0-9 digits. Falls back to
/// [formatClock12Hour] if date data is unavailable, so it can never crash a
/// screen.
String formatClockLocalized(DateTime time, String localeName) {
  try {
    return _normalise(DateFormat.jm(localeName).format(time));
  } catch (_) {
    return formatClock12Hour(time);
  }
}

/// Locale-aware short date (for example "Oct 8", "8 oct."), always with 0-9
/// digits. Replaces the hard-coded English month list in History. Falls back
/// to [formatIsoDay] if date data is unavailable.
String formatMonthDayLocalized(DateTime time, String localeName) {
  try {
    return _normalise(DateFormat.MMMd(localeName).format(time));
  } catch (_) {
    return formatIsoDay(time);
  }
}
