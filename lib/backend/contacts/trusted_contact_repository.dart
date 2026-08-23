import '../../models/trusted_contact.dart';

/// Abstraction over where [TrustedContact] records are stored. Matches the
/// same swap-later pattern as [IncidentRepository] — in-memory today, Hive
/// (or SQLite) once persistence is needed, with no change required to any
/// screen that depends on this interface.
abstract interface class TrustedContactRepository {
  /// Adds a new trusted contact and returns it.
  Future<TrustedContact> add(TrustedContact contact);

  /// Removes a contact by id. No-ops silently if the id isn't found — the
  /// UI has nothing further to react to either way.
  Future<void> remove(String contactId);

  /// Returns all saved trusted contacts.
  Future<List<TrustedContact>> getAll();
}
