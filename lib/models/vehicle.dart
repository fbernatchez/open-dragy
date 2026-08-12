class Vehicle {
  final String id;
  final String make;
  final String model;
  final int year;

  Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
  });

  Vehicle copyWith({String? id, String? make, String? model, int? year}) {
    return Vehicle(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'make': make, 'model': model, 'year': year};
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      year: json['year'] as int,
    );
  }

  String get displayName => '$year $make $model';
}
