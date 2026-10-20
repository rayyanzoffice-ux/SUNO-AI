import '../../models/trusted_contact.dart';
import 'sms_native_bridge.dart';

/// How one SMS actually goes out. Injected in tests so the counting and
/// number-cleaning logic can be exercised without a radio.
typedef SmsSend =
    Future<bool> Function({
      required String phoneNumber,
      required String message,
    });

/// Result of attempting the offline SMS fallback for one incident.
class SmsDispatchResult {
  const SmsDispatchResult({required this.attempted, required this.sent});

  /// Numbers SUNO tried to send to, after de-duplication.
  final int attempted;

  /// Numbers the OS accepted the send request for.
  final int sent;
}

/// Direct-to-contact SMS, used only when the push relay (FCM via Supabase)
/// could not be reached. Needs real phone numbers, not FCM tokens — this is
/// why it takes TrustedContact objects rather than the token list the push
/// alert service uses.
class SmsFallbackService {
  const SmsFallbackService({SmsSend send = SmsNativeBridge.send})
    : _send = send;

  final SmsSend _send;

  Future<SmsDispatchResult> sendAlert({
    required List<TrustedContact> contacts,
    required Map<String, String> payload,
  }) async {
    final numbers = contacts
        .map((contact) => _normalizePhone(contact.phone))
        .where((phone) => phone.isNotEmpty)
        .toSet()
        .toList();
    if (numbers.isEmpty) {
      return const SmsDispatchResult(attempted: 0, sent: 0);
    }
    final message = _buildMessage(payload);
    var sent = 0;
    for (final number in numbers) {
      if (await _send(phoneNumber: number, message: message)) sent++;
    }
    return SmsDispatchResult(attempted: numbers.length, sent: sent);
  }

  /// Keeps digits and a single leading '+'. SmsManager needs a dialable
  /// number; contact entry does not currently enforce E.164 formatting, so
  /// this is a defensive best-effort clean-up, not full validation.
  String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final plus = trimmed.startsWith('+') ? '+' : '';
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? '' : '$plus$digits';
  }

  String _buildMessage(Map<String, String> payload) {
    final sender = payload['senderName'];
    final event = payload['eventType'] ?? 'Emergency';
    final risk = payload['riskScore'];
    final lat = payload['latitude'];
    final lon = payload['longitude'];
    final isCached = payload['locationIsCached'] == 'true';
    final ageMinutes = payload['locationAgeMinutes'];
    final buffer = StringBuffer('SUNO EMERGENCY: ');
    // A bare number with no name is not actionable for whoever reads the text.
    // Every character below stays inside the plain GSM-7 alphabet, which keeps
    // the message in as few segments as possible.
    if (sender != null && sender.isNotEmpty) {
      buffer.write('$sender - $event');
    } else {
      buffer.write(event);
    }
    if (risk != null) buffer.write(' (risk $risk%)');
    if (lat != null && lon != null) {
      buffer.write('. Location: https://maps.google.com/?q=$lat,$lon');
      if (isCached && ageMinutes != null) {
        buffer.write(' (last known fix, ${ageMinutes}m old)');
      }
    } else {
      buffer.write('. Location unavailable.');
    }
    buffer.write('. Sent by SMS - SUNO could not reach the push alert.');
    return buffer.toString();
  }
}
