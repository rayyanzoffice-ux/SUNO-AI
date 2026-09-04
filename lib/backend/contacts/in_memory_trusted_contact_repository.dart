import '../../models/trusted_contact.dart';
import 'trusted_contact_repository.dart';

/// In-memory [TrustedContactRepository] for the hackathon demo. Seeded with
/// the same demo contact the frontend's mock incident service already
/// uses, so switching a screen over to this repository doesn't change what
/// appears on screen mid-demo.
class InMemoryTrustedContactRepository implements TrustedContactRepository {
  InMemoryTrustedContactRepository({List<TrustedContact>? seed})
    : _contacts = seed ?? [_defaultDemoContact];

  static const _defaultDemoContact = TrustedContact(
    id: 'contact-1',
    name: 'Rayyan Brother',
    phone: '+92 300 0000000',
    relationship: 'Brother',
  );

  final List<TrustedContact> _contacts;

  @override
  Future<TrustedContact> add(TrustedContact contact) async {
    _contacts.add(contact);
    return contact;
  }

  @override
  Future<void> remove(String contactId) async {
    _contacts.removeWhere((contact) => contact.id == contactId);
  }

  @override
  Future<List<TrustedContact>> getAll() async => List.unmodifiable(_contacts);
}
