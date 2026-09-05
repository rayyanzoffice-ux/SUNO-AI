/// Outcome of attempting to notify trusted contacts via the alert relay.
class AlertDispatchResult {
  const AlertDispatchResult({
    required this.success,
    required this.attemptedCount,
    this.sentCount = 0,
    this.failedReason,
  });

  /// True only when every attempted contact was accepted by the relay/FCM.
  final bool success;

  /// Number of contacts SUNO tried to notify.
  final int attemptedCount;

  /// Number of contacts the relay reports as successfully accepted by FCM.
  final int sentCount;

  final String? failedReason;

  int get failedCount =>
      attemptedCount > sentCount ? attemptedCount - sentCount : 0;

  bool get partiallyDelivered =>
      sentCount > 0 && sentCount < attemptedCount;
}
