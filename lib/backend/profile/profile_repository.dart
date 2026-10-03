/// Where the user's own display name is stored.
///
/// Same swap-later pattern as the incident and contact repositories:
/// in-memory for tests, Hive in the real app.
abstract interface class ProfileRepository {
  /// Returns the saved display name, or `null` if none is set.
  Future<String?> getDisplayName();

  /// Saves [name]. Passing `null` or an empty string clears it.
  Future<void> setDisplayName(String? name);
}
