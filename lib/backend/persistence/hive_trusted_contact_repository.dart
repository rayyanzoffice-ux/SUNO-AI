import '../../models/trusted_contact.dart';
import '../contacts/trusted_contact_repository.dart';
import 'app_storage.dart';

class HiveTrustedContactRepository implements TrustedContactRepository {
  const HiveTrustedContactRepository();

  @override
  Future<TrustedContact> add(TrustedContact contact) async {
    await contactBox.put(contact.id, {
      'id': contact.id,
      'name': contact.name,
      'phone': contact.phone,
      'relationship': contact.relationship,
    });
    return contact;
  }

  @override
  Future<void> remove(String contactId) async {
    await contactBox.delete(contactId);
  }

  @override
  Future<List<TrustedContact>> getAll() async {
    return contactBox.values
        .map((raw) => TrustedContact.fromJson(
              Map<String, Object?>.from(raw as Map),
            ))
        .toList();
  }
}
