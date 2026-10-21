/// Outcome of attempting to notify trusted contacts via the alert relay.
class AlertDispatchResult {
  const AlertDispatchResult({
    required this.success,
    required this.attemptedCount,
    this.sentCount = 0,
    this.smsSentCount = 0,
    this.queued = false,
    this.failedReason,
  });

  /// True only when every attempted contact's push token was accepted by the
  /// relay. SMS is deliberately excluded: Android confirming SMS_SENT proves
  /// the phone submitted the message, not that the contact received it.
  final bool success;

  /// Number of contacts SUNO tried to notify.
  final int attemptedCount;

  /// Number of contacts whose push token the relay accepted for FCM.
  final int sentCount;

  /// Numbers Android confirmed it submitted the SMS for (SMS_SENT). This is
  /// not a delivery receipt and must never be presented as "reached".
  final int smsSentCount;

  /// True when the push alert could not reach the relay and was saved to be
  /// retried automatically once connectivity returns.
  final bool queued;

  final String? failedReason;

  bool get usedSmsFallback => smsSentCount > 0;

  /// Capped at [attemptedCount]: one contact can be credited on both channels
  /// when an SMS was submitted first and a later retry confirmed the push.
  int get totalDelivered {
    final total = sentCount + smsSentCount;
    return total > attemptedCount ? attemptedCount : total;
  }

  int get failedCount =>
      attemptedCount > totalDelivered ? attemptedCount - totalDelivered : 0;

  bool get partiallyDelivered =>
      totalDelivered > 0 && totalDelivered < attemptedCount;
}
