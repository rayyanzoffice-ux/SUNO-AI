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
};

Incident _incidentFromMap(Map<dynamic, dynamic> raw) {
  final m = Map<String, dynamic>.from(raw);
  final det = DetectionResult.fromJson(
    Map<String, Object?>.from(m['detection'] as Map),
  );
  final statusWire = m['status'] as String;
  final status = IncidentStatus.values.firstWhere(
    (s) => s.wireValue == statusWire,
    orElse: () => IncidentStatus.monitoring,
  );
  return Incident(
    id: m['id'] as String,
    detectionResult: det,
    status: status,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
    contactResponseText: m['contactResponseText'] as String?,
  );
}

class HiveIncidentRepository implements IncidentRepository {
  const HiveIncidentRepository();

  @override
  Future<Incident> save(Incident incident) async {
    await incidentBox.put(incident.id, _incidentToMap(incident));
    return incident;
  }

  @override
  Future<Incident> update(Incident incident) async {
    if (!incidentBox.containsKey(incident.id)) {
      throw StateError(
        'Cannot update incident ${incident.id} — it was never saved.',
      );
    }
    await incidentBox.put(incident.id, _incidentToMap(incident));
    return incident;
  }

  @override
  Future<Incident?> latest() async {
    if (incidentBox.isEmpty) return null;
    return _incidentFromMap(incidentBox.values.last);
  }

  @override
  Future<List<Incident>> getAll() async {
    final all = incidentBox.values
        .map(_incidentFromMap)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(all);
  }
}
