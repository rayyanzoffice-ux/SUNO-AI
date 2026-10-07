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

/// Locale-aware clock time, e.g. "2:07 PM" or "14:07" depending on the locale.
/// [localeName] comes from `Localizations.localeOf(context).toLanguageTag()`.
String formatClockLocalized(DateTime time, String localeName) =>
    DateFormat.jm(localeName).format(time);

/// Locale-aware short date (e.g. "Oct 7", "7 окт."). Replaces the hard-coded
/// English month list in History.
String formatMonthDayLocalized(DateTime time, String localeName) =>
    DateFormat.MMMd(localeName).format(time);
