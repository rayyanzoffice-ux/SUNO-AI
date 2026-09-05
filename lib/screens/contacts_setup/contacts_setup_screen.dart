import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trusted_contact.dart';
import '../../services/suno_runtime_service.dart';
import '../../widgets/primary_action_button.dart';

class ContactsSetupScreen extends StatefulWidget {
  const ContactsSetupScreen({super.key});
  @override
  State<ContactsSetupScreen> createState() => _ContactsSetupScreenState();
}

class _ContactsSetupScreenState extends State<ContactsSetupScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final relationship = TextEditingController();
  final fcmToken = TextEditingController();
  final contacts = <TrustedContact>[];
  String? myFcmToken;
  bool loadingToken = true;

  String? _editingId;
  bool _saving = false;
  final _testingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadMyToken();
  }

  Future<void> _loadContacts() async {
    final saved = await SunoRuntimeService.instance.getTrustedContacts();
    if (mounted) setState(() => contacts.addAll(saved));
  }

  Future<void> _loadMyToken() async {
    var token = SunoRuntimeService.instance.deviceToken;
    token ??= await SunoRuntimeService.instance.refreshDeviceToken();
    if (!mounted) return;
    setState(() {
      myFcmToken = token;
      loadingToken = false;
    });
  }

  Future<void> _copyMyToken() async {
    final token = myFcmToken;
    if (token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('FCM token copied. Send it to your trusted contact.')),
    );
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || relationship.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and relationship are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final trimmedToken = fcmToken.text.trim();
      final contact = TrustedContact(
        id: _editingId ?? DateTime.now().toString(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim(),
        fcmToken: trimmedToken.isEmpty ? null : trimmedToken,
      );

      final saved = _editingId == null
          ? await SunoRuntimeService.instance.addTrustedContact(contact)
          : await SunoRuntimeService.instance.updateTrustedContact(contact);

      if (!mounted) return;
      setState(() {
        if (_editingId == null) {
          contacts.add(saved);
        } else {
          final index = contacts.indexWhere((c) => c.id == _editingId);
          if (index != -1) contacts[index] = saved;
        }
        _clearForm();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_editingId == null
                ? 'Trusted contact saved locally.'
                : 'Trusted contact updated.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEdit(TrustedContact contact) {
    setState(() {
      _editingId = contact.id;
      name.text = contact.name;
      phone.text = contact.phone;
      relationship.text = contact.relationship;
      fcmToken.text = contact.fcmToken ?? '';
    });
  }

  void _clearForm() {
    _editingId = null;
    name.clear();
    phone.clear();
    relationship.clear();
    fcmToken.clear();
  }

  Future<void> _delete(TrustedContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Remove ${contact.name} from your safety network?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SunoRuntimeService.instance.removeTrustedContact(contact.id);
    if (!mounted) return;
    setState(() => contacts.removeWhere((c) => c.id == contact.id));
  }

  Future<void> _testContact(TrustedContact contact) async {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) return;
    setState(() => _testingIds.add(contact.id));
    try {
      final ok = await SunoRuntimeService.instance.testContactNotification(
        contact,
      );
      if (!mounted) return;
      if (ok) {
        final updated = await SunoRuntimeService.instance
            .getTrustedContacts()
            .then((all) => all.firstWhere((c) => c.id == contact.id));
        setState(() {
          final index = contacts.indexWhere((c) => c.id == contact.id);
          if (index != -1) contacts[index] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.name} is reachable.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${contact.name} token rejected by FCM. Check the token.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _testingIds.remove(contact.id));
    }
  }

  String _pushStatus(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return 'Not configured';
    }
    if (contact.isVerified) return 'Verified reachable';
    return 'Token saved, unverified';
  }

  Color _pushStatusColor(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return AppColors.textMuted;
    }
    if (contact.isVerified) return AppColors.safe;
    return AppColors.warning;
  }

  IconData _pushStatusIcon(TrustedContact contact) {
    if (contact.fcmToken == null || contact.fcmToken!.trim().isEmpty) {
      return Icons.notifications_off_outlined;
    }
    if (contact.isVerified) return Icons.verified_outlined;
    return Icons.notifications_none_outlined;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    relationship.dispose();
    fcmToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Trusted contacts')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your safety network',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contacts are stored locally on this device. Exchange FCM tokens between two phones so SUNO can route emergency push alerts to the trusted contact.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MY FCM TOKEN',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (loadingToken)
                          const Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text('Getting token from Firebase...'),
                              ),
                            ],
                          )
                        else if (myFcmToken == null || myFcmToken!.isEmpty)
                          const Text(
                            'Token unavailable. Check internet, Firebase setup, and notification permission, then reopen SUNO.',
                            style: TextStyle(color: AppColors.textMuted),
                          )
                        else ...[
                          SelectableText(
                            myFcmToken!,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _copyMyToken,
                              icon: const Icon(Icons.copy),
                              label: const Text('COPY MY FCM TOKEN'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ...contacts.map(
                  (contact) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.purple,
                        child: Icon(Icons.person),
                      ),
                      title: Text(
                        contact.name,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contact.relationship),
                          if (contact.phone.isNotEmpty) Text(contact.phone),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _pushStatusIcon(contact),
                                size: 14,
                                color: _pushStatusColor(contact),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _pushStatus(contact),
                                style: TextStyle(
                                  color: _pushStatusColor(contact),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            _startEdit(contact);
                          } else if (value == 'delete') {
                            await _delete(contact);
                          } else if (value == 'test') {
                            await _testContact(contact);
                          }
                        },
                        itemBuilder: (context) => [
                          if (contact.fcmToken != null &&
                              contact.fcmToken!.trim().isNotEmpty)
                            PopupMenuItem(
                              value: 'test',
                              child: Row(
                                children: [
                                  _testingIds.contains(contact.id)
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.send_outlined,
                                          size: 18),
                                  const SizedBox(width: 10),
                                  const Text('Test reachability'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.emergency),
                                SizedBox(width: 10),
                                Text('Delete',
                                    style:
                                        TextStyle(color: AppColors.emergency)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _editingId == null ? 'Add a contact' : 'Edit contact',
                  style:
                      const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    helperText: 'Optional — useful for a future call fallback.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: relationship,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Relationship *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fcmToken,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'FCM token (optional)',
                    helperText: 'Needed only for real push alerts to this contact.',
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryActionButton(
                  label: _editingId == null ? 'SAVE CONTACT' : 'UPDATE CONTACT',
                  icon: _editingId == null
                      ? Icons.person_add_alt_1
                      : Icons.check_rounded,
                  onPressed: _saving ? null : save,
                ),
                if (_editingId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: TextButton(
                        onPressed: _clearForm,
                        child: const Text('CANCEL EDIT'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
