/// One push alert that could not reach the relay and is waiting for a retry.
class PendingAlert {
  const PendingAlert({
    required this.incidentId,
    required this.payload,
    required this.tokens,
    required this.createdAt,
    this.attempts = 0,
  });

  final String incidentId;
  final Map<String, String> payload;
  final List<String> tokens;
  final DateTime createdAt;
  final int attempts;

  PendingAlert copyWith({int? attempts}) => PendingAlert(
    incidentId: incidentId,
    payload: payload,
    tokens: tokens,
    createdAt: createdAt,
    attempts: attempts ?? this.attempts,
  );

  Map<String, Object?> toMap() => {
    'incidentId': incidentId,
    'payload': payload,
    'tokens': tokens,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  static PendingAlert? fromMap(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    final incidentId = raw['incidentId'];
    final createdAt = DateTime.tryParse(raw['createdAt'] as String? ?? '');
    final payload = raw['payload'];
    final tokens = raw['tokens'];
    if (incidentId is! String ||
        incidentId.isEmpty ||
        createdAt == null ||
        payload is! Map ||
        tokens is! List) {
      return null;
    }
    final payloadStrings = <String, String>{};
    for (final entry in payload.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) payloadStrings[key] = value;
    }
    final tokenList = tokens
        .whereType<String>()
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();
    if (tokenList.isEmpty) return null;
    final attempts = raw['attempts'];
    return PendingAlert(
      incidentId: incidentId,
      payload: payloadStrings,
      tokens: tokenList,
      createdAt: createdAt,
      attempts: attempts is int && attempts >= 0 ? attempts : 0,
    );
  }
}

/// Persists push alerts the relay never accepted, so they can be retried when
/// connectivity returns instead of being silently lost.
abstract interface class AlertOutbox {
  Future<List<PendingAlert>> getAll();
  Future<void> save(PendingAlert alert);
  Future<void> remove(String incidentId);
  Future<void> clear();
}

/// In-memory [AlertOutbox] for tests and as the safe default before storage
/// is wired up.
class InMemoryAlertOutbox implements AlertOutbox {
  final Map<String, PendingAlert> _alerts = {};

  @override
  Future<List<PendingAlert>> getAll() async => _alerts.values.toList();

  @override
  Future<void> save(PendingAlert alert) async => _alerts[alert.incidentId] = alert;

  @override
  Future<void> remove(String incidentId) async => _alerts.remove(incidentId);

  @override
  Future<void> clear() async => _alerts.clear();
}
