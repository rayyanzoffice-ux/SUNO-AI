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
