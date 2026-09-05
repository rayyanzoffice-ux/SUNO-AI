import '../../models/incident.dart';
import 'incident_repository.dart';

/// In-memory [IncidentRepository] for the hackathon demo. Data lives only
/// for the current app session and is lost on restart — this is
/// intentional for Day 1 scope and matches what the Trusted Contact screen
/// already tells the user ("stored only for this demo session"). Swap for
/// a Hive-backed implementation once persistent History is needed.
class InMemoryIncidentRepository implements IncidentRepository {
  final List<Incident> _incidents = [];

  @override
  Future<Incident> save(Incident incident) async {
    _incidents.add(incident);
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
  Future<Incident?> latest() async =>
      _incidents.isEmpty ? null : _incidents.last;

  @override
  Future<List<Incident>> getAll() async =>
      List.unmodifiable(_incidents.reversed);

  @override
  Future<void> remove(String incidentId) async {
    _incidents.removeWhere((i) => i.id == incidentId);
  }

  @override
  Future<void> clear() async {
    _incidents.clear();
  }
}
