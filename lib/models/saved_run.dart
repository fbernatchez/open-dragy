import 'race_metrics.dart';

class SavedRun {
  final String id;
  final DateTime dateTime;
  final RaceMetrics metrics;
  final String? notes;
  final double? temperature; // in Celsius
  final double? humidity; // in %
  final String? vehicleId;
  final String? vehicleName; // snapshot of display name at run time

  SavedRun({
    required this.id,
    required this.dateTime,
    required this.metrics,
    this.notes,
    this.temperature,
    this.humidity,
    this.vehicleId,
    this.vehicleName,
  });

  SavedRun copyWith({
    String? id,
    DateTime? dateTime,
    RaceMetrics? metrics,
    String? notes,
    double? temperature,
    double? humidity,
    String? vehicleId,
    String? vehicleName,
  }) {
    return SavedRun(
      id: id ?? this.id,
      dateTime: dateTime ?? this.dateTime,
      metrics: metrics ?? this.metrics,
      notes: notes ?? this.notes,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateTime': dateTime.toIso8601String(),
      'metrics': metrics.toJson(),
      'notes': notes,
      'temperature': temperature,
      'humidity': humidity,
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
    };
  }

  factory SavedRun.fromJson(Map<String, dynamic> json) {
    return SavedRun(
      id: json['id'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      metrics: RaceMetrics.fromJson(
        Map<String, dynamic>.from(json['metrics'] as Map),
      ),
      notes: json['notes'] as String?,
      temperature: json['temperature'] != null
          ? (json['temperature'] as num).toDouble()
          : null,
      humidity: json['humidity'] != null
          ? (json['humidity'] as num).toDouble()
          : null,
      vehicleId: json['vehicleId'] as String?,
      vehicleName: json['vehicleName'] as String?,
    );
  }
}
