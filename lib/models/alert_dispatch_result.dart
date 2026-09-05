/// Outcome of attempting to notify trusted contacts via the alert relay.
class AlertDispatchResult {
  const AlertDispatchResult({
    required this.success,
    required this.attemptedCount,
    this.failedReason,
  });

  final bool success;
  final int attemptedCount;
  final String? failedReason;
}
