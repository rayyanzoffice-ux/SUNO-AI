class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
  });

  final String id;
  final String name;
  final String phone;
  final String relationship;

  factory TrustedContact.fromJson(Map<String, Object?> json) => TrustedContact(
    id: json['id']! as String,
    name: json['name']! as String,
    phone: json['phone']! as String,
    relationship: json['relationship']! as String,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'relationship': relationship,
  };
}
