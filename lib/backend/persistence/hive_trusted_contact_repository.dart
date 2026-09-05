import '../../models/trusted_contact.dart';
import '../contacts/trusted_contact_repository.dart';
import 'app_storage.dart';

class HiveTrustedContactRepository implements TrustedContactRepository {
  const HiveTrustedContactRepository();

  @override
  Future<TrustedContact> add(TrustedContact contact) async {
    await contactBox.put(contact.id, _contactToMap(contact));
    return contact;
  }

  @override
  Future<TrustedContact> update(TrustedContact contact) async {
    if (!contactBox.containsKey(contact.id)) {
      throw StateError(
        'Cannot update contact ${contact.id} — it was never saved.',
      );
    }
    await contactBox.put(contact.id, _contactToMap(contact));
    return contact;
  }

  @override
  Future<void> remove(String contactId) async {
    await contactBox.delete(contactId);
  }

  Map<String, dynamic> _contactToMap(TrustedContact contact) => {
    'id': contact.id,
    'name': contact.name,
    'phone': contact.phone,
    'relationship': contact.relationship,
    'fcmToken': contact.fcmToken,
    if (contact.verifiedAt != null)
      'verifiedAt': contact.verifiedAt!.toIso8601String(),
  };

  @override
  Future<List<TrustedContact>> getAll() async {
    return contactBox.values
        .map((raw) => TrustedContact.fromJson(
              Map<String, Object?>.from(raw as Map),
            ))
        .toList();
  }
}
