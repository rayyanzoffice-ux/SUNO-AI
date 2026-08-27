enum RiskLevel { low, medium, critical }

extension RiskLevelContract on RiskLevel {
  String get wireValue => name;

  static RiskLevel fromWireValue(String value) => RiskLevel.values.firstWhere(
    (level) => level.wireValue == value,
    orElse: () => RiskLevel.low,
  );
}

class DetectionResult {
  final String eventType;
  final double confidence;
  final bool impactDetected;
  final bool stillnessDetected;
  final int riskScore;
  final RiskLevel riskLevel;
  final double? latitude;
  final double? longitude;
  final String? locationText;
  final DateTime detectedAt;

  const DetectionResult({
    required this.eventType,
    required this.confidence,
    required this.impactDetected,
    required this.stillnessDetected,
    required this.riskScore,
    required this.riskLevel,
    this.latitude,
    this.longitude,
    this.locationText,
    required this.detectedAt,
  });

  /// Maps the shared API contract without coupling screens to JSON parsing.
  factory DetectionResult.fromJson(Map<String, Object?> json) =>
      DetectionResult(
        eventType: json['eventType']! as String,
        confidence: (json['confidence']! as num).toDouble(),
        impactDetected: json['impactDetected']! as bool,
        stillnessDetected: json['stillnessDetected']! as bool,
        riskScore: json['riskScore']! as int,
        riskLevel: RiskLevelContract.fromWireValue(
          json['riskLevel']! as String,
        ),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        locationText: json['locationText'] as String?,
        detectedAt: json['detectedAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['detectedAt']! as String),
      );

  Map<String, Object?> toJson({String? status}) => {
    'eventType': eventType,
    'confidence': confidence,
    'impactDetected': impactDetected,
    'stillnessDetected': stillnessDetected,
    'riskScore': riskScore,
    'riskLevel': riskLevel.wireValue,
    'locationText': locationText,
    'latitude': latitude,
    'longitude': longitude,
    'status': status,
    'detectedAt': detectedAt.toIso8601String(),
  };
}
