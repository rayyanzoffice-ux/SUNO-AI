import '../../models/incident.dart';
import 'incident_repository.dart';

/// In-memory [IncidentRepository] for the hackathon demo. Data lives only
/// for the current app session and is lost on restart — this is
/// intentional for Day 1 scope and matches what the Trusted Contact screen
/// already tells the user ("stored only for this demo session"). Swap for
/// a Hive-backed implementation once persistent History is needed.
class InMemoryIncidentRepository implements IncidentRepository {
  final List<Incident> _incidents = [];
  final Set<String> _deleted = {};

  @override
  Future<bool> isDeleted(String incidentId) async =>
      _deleted.contains(incidentId);

  @override
  Future<Incident> save(Incident incident) async {
    if (_deleted.contains(incident.id)) {
      throw StateError('This incident was deleted.');
    }
    final index = _incidents.indexWhere(
      (existing) => existing.id == incident.id,
    );
    if (index < 0) {
      _incidents.add(incident);
    } else {
      _incidents[index] = incident;
    }
    return incident;
  }

  @override
  Future<Incident> update(Incident incident) async {
    final index = _incidents.indexWhere(
      (existing) => existing.id == incident.id,
    );
    if (index == -1) {
      throw StateError(
        'Cannot update incident ${incident.id} — it was never saved.',
      );
    }
    _incidents[index] = incident;
    return incident;
  }

  @override
  Future<Incident?> latest() async {
    final incidents = await getAll();
    return incidents.isEmpty ? null : incidents.first;
  }

  @override
  Future<List<Incident>> getAll() async => List.unmodifiable(
    [..._incidents]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  @override
  Future<void> remove(String incidentId) async {
    _deleted.add(incidentId);
    _incidents.removeWhere((i) => i.id == incidentId);
  }

  @override
  Future<void> clear() async {
    _deleted.addAll(_incidents.map((incident) => incident.id));
    _incidents.clear();
  }
}
