import '../profile/locale_repository.dart';
import 'app_storage.dart';

/// Hive-backed [LocaleRepository]. Reuses the existing `profile` box (a
/// `Box<String>`) under its own key, so no new box and no data migration.
class HiveLocaleRepository implements LocaleRepository {
  /// Creates the repository. Requires `initStorage()` to have completed.
  const HiveLocaleRepository();

  static const _languageKey = 'languageCode';

  @override
  Future<String?> getLanguageCode() async => profileBox.get(_languageKey);

  @override
  Future<void> setLanguageCode(String code) =>
      profileBox.put(_languageKey, code);
}
