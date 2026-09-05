import '../../models/incident.dart';

/// Abstraction over where [Incident] records are stored. The in-memory
/// implementation in this folder satisfies this for the hackathon demo; a
/// Hive-backed implementation can be swapped in later for persistent
/// History without changing any screen or controller that depends on this
/// interface — they only ever see [IncidentRepository], never the concrete
/// storage.
abstract interface class IncidentRepository {
  /// Persists a new incident and returns it unchanged, for chaining.
  Future<Incident> save(Incident incident);

  /// Updates an already-saved incident's mutable fields (status, response
  /// text, updatedAt). Throws [StateError] if no incident with that id has
  /// been saved yet — this is a programmer error, not a recoverable one.
  Future<Incident> update(Incident incident);

  /// Returns the most recently created incident, or null if none exist yet.
  /// Used by the Emergency and Trusted Contact screens to show "the current
  /// incident" without the caller needing to track an id.
  Future<Incident?> latest();

  /// Returns all incidents, most recent first — backs the History screen.
  Future<List<Incident>> getAll();

  /// Deletes a single incident by id. No-ops silently if not found.
  Future<void> remove(String incidentId);

  /// Deletes every stored incident.
  Future<void> clear();
}
