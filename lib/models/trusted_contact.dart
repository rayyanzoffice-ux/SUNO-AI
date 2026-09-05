class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    this.fcmToken,
    this.verifiedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String relationship;
  final String? fcmToken;
  final DateTime? verifiedAt;

  bool get isVerified =>
      fcmToken != null && fcmToken!.trim().isNotEmpty && verifiedAt != null;

  factory TrustedContact.fromJson(Map<String, Object?> json) => TrustedContact(
    id: json['id']! as String,
    name: json['name']! as String,
    phone: json['phone']! as String,
    relationship: json['relationship']! as String,
    fcmToken: json['fcmToken'] as String?,
    verifiedAt:
        json['verifiedAt'] == null
            ? null
            : DateTime.parse(json['verifiedAt']! as String),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relationship': relationship,
    'fcmToken': fcmToken,
    'verifiedAt': verifiedAt?.toIso8601String(),
  };
}
