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
    if (name.text.trim().isEmpty ||
        phone.text.trim().isEmpty ||
        relationship.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete all contact fields.')),
      );
      return;
    }
    final contact = await SunoRuntimeService.instance.addTrustedContact(
      TrustedContact(
        id: DateTime.now().toString(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        relationship: relationship.text.trim(),
        fcmToken: fcmToken.text.trim().isEmpty
            ? null
            : fcmToken.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => contacts.add(contact));
    name.clear();
    phone.clear();
    relationship.clear();
    fcmToken.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trusted contact saved locally.')),
    );
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
                  contentPadding: const EdgeInsets.all(14),
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
                  subtitle: Text(
                    '${contact.relationship}\n${contact.phone}\n'
                    '${contact.fcmToken == null ? 'Push: not configured' : 'Push: configured'}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add a contact',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationship,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Relationship'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fcmToken,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Contact FCM token',
                helperText: 'Paste the token copied from the other SUNO phone.',
              ),
            ),
            const SizedBox(height: 18),
            PrimaryActionButton(
              label: 'SAVE CONTACT',
              icon: Icons.person_add_alt_1,
              onPressed: save,
            ),
          ],
        ),
      ),
    ),
  );
}
