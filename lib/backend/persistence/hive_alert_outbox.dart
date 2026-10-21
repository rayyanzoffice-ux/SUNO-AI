import '../alerts/alert_outbox.dart';
import 'app_storage.dart';

/// Hive-backed [AlertOutbox]. Survives process death so an alert raised with
/// no internet is still sent after the app is reopened.
class HiveAlertOutbox implements AlertOutbox {
  const HiveAlertOutbox();

  @override
  Future<List<PendingAlert>> getAll() async => alertOutboxBox.values
      .map((value) => PendingAlert.fromMap(value.cast<Object?, Object?>()))
      .whereType<PendingAlert>()
      .toList();

  @override
  Future<void> save(PendingAlert alert) =>
      alertOutboxBox.put(alert.incidentId, alert.toMap());

  @override
  Future<void> remove(String incidentId) =>
      alertOutboxBox.delete(incidentId);

  @override
  Future<void> clear() => alertOutboxBox.clear();
}
