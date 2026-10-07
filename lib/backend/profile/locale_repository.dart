/// Where the user's chosen app language is stored.
///
/// Same swap-later pattern as the other repositories: in-memory for tests,
/// Hive in the real app. Local only: nothing here touches the network.
abstract interface class LocaleRepository {
  /// Returns the saved language code (e.g. `ur`), or `null` if none is saved.
  Future<String?> getLanguageCode();

  /// Saves [code] as the chosen language. Throws if storage fails.
  Future<void> setLanguageCode(String code);
}

/// In-memory [LocaleRepository] for tests and as the safe default before
/// storage is wired up.
class InMemoryLocaleRepository implements LocaleRepository {
  String? _code;

  @override
  Future<String?> getLanguageCode() async => _code;

  @override
  Future<void> setLanguageCode(String code) async => _code = code;
}
