/// Outcome of attempting to notify trusted contacts via the alert relay.
class AlertDispatchResult {
  const AlertDispatchResult({
    required this.success,
    required this.attemptedCount,
    this.sentCount = 0,
    this.smsSentCount = 0,
    this.failedReason,
  });

  /// True only when every attempted contact was reached by at least one
  /// channel (push OR SMS).
  final bool success;

  /// Number of contacts SUNO tried to notify.
  final int attemptedCount;

  /// Number of contacts the relay reports as successfully accepted by FCM.
  final int sentCount;

  /// Number of contacts reached by the offline SMS fallback instead.
  final int smsSentCount;

  final String? failedReason;

  bool get usedSmsFallback => smsSentCount > 0;

  int get totalDelivered => sentCount + smsSentCount;

  int get failedCount =>
      attemptedCount > totalDelivered ? attemptedCount - totalDelivered : 0;

  bool get partiallyDelivered =>
      totalDelivered > 0 && totalDelivered < attemptedCount;
}
