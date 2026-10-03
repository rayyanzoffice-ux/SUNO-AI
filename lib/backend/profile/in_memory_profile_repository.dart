import 'profile_repository.dart';

/// Non-persistent [ProfileRepository] used by tests and as the default.
class InMemoryProfileRepository implements ProfileRepository {
  InMemoryProfileRepository({String? initialName}) : _name = initialName;

  String? _name;

  @override
  Future<String?> getDisplayName() async => _name;

  @override
  Future<void> setDisplayName(String? name) async {
    _name = (name == null || name.isEmpty) ? null : name;
  }
}
