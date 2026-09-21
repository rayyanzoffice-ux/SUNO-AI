import '../../models/alert_dispatch_result.dart';
import '../../models/detection_result.dart';
import '../../models/incident.dart';
import '../incidents/incident_repository.dart';
import 'app_storage.dart';

Map<String, dynamic> _incidentToMap(Incident incident) => {
  'id': incident.id,
  'status': incident.status.wireValue,
  'createdAt': incident.createdAt.toIso8601String(),
  'updatedAt': incident.updatedAt.toIso8601String(),
  'contactResponseText': incident.contactResponseText,
  'detection': incident.detectionResult.toJson(),
  'origin': incident.origin,
  'senderToken': incident.senderToken,
  'safetyCheckDeadline': incident.safetyCheckDeadline?.toIso8601String(),
  if (incident.dispatchResult case final dispatch?)
    'dispatch': {
      'success': dispatch.success,
      'attemptedCount': dispatch.attemptedCount,
      'sentCount': dispatch.sentCount,
      'failedReason': dispatch.failedReason,
    },
};

Incident _incidentFromMap(Map<dynamic, dynamic> raw) {
  final m = Map<String, dynamic>.from(raw);
  final dispatch = m['dispatch'] as Map?;
  return Incident(
    id: m['id'] as String,
    detectionResult: DetectionResult.fromJson(
      Map<String, Object?>.from(m['detection'] as Map),
    ),
    status: IncidentStatus.values.firstWhere(
      (status) => status.wireValue == m['status'],
      orElse: () => IncidentStatus.monitoring,
    ),
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
    contactResponseText: m['contactResponseText'] as String?,
    origin: m['origin'] as String? ?? 'self',
    senderToken: m['senderToken'] as String?,
    safetyCheckDeadline: DateTime.tryParse(
      m['safetyCheckDeadline'] as String? ?? '',
    ),
    dispatchResult: dispatch == null
        ? null
        : AlertDispatchResult(
            success: dispatch['success'] == true,
            attemptedCount: dispatch['attemptedCount'] as int,
            sentCount: dispatch['sentCount'] as int,
            failedReason: dispatch['failedReason'] as String?,
          ),
  );
}

class HiveIncidentRepository implements IncidentRepository {
  const HiveIncidentRepository();

  @override
  Future<Incident> save(Incident incident) async {
    if (await isDeleted(incident.id)) {
      throw StateError('This incident was deleted.');
    }
    await incidentBox.put(incident.id, _incidentToMap(incident));
    return incident;
  }

  @override
  Future<Incident> update(Incident incident) async {
    if (!incidentBox.containsKey(incident.id) || await isDeleted(incident.id)) {
      throw StateError('Cannot update an incident that is not saved.');
    }
    await incidentBox.put(incident.id, _incidentToMap(incident));
    return incident;
  }

  @override
  Future<Incident?> latest() async {
    final incidents = await getAll();
    return incidents.isEmpty ? null : incidents.first;
  }

  @override
  Future<List<Incident>> getAll() async => List.unmodifiable(
    incidentBox.values
        .where((value) => value['deleted'] != true)
        .map(_incidentFromMap)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Future<void> remove(String incidentId) =>
      incidentBox.put(incidentId, {'deleted': true});

  @override
  Future<bool> isDeleted(String incidentId) async =>
      incidentBox.get(incidentId)?['deleted'] == true;

  @override
  Future<void> clear() async {
    await incidentBox.putAll({
      for (final key in incidentBox.keys) key: {'deleted': true},
    });
  }
}
