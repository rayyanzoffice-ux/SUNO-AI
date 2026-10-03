import '../profile/profile_repository.dart';
import 'app_storage.dart';

/// Hive-backed [ProfileRepository]. Uses its own box so it can never be
/// mistaken for a trusted-contact record.
class HiveProfileRepository implements ProfileRepository {
  const HiveProfileRepository();

  static const _nameKey = 'displayName';

  @override
  Future<String?> getDisplayName() async => profileBox.get(_nameKey);

  @override
  Future<void> setDisplayName(String? name) async {
    if (name == null || name.isEmpty) {
      await profileBox.delete(_nameKey);
    } else {
      await profileBox.put(_nameKey, name);
    }
  }
}
