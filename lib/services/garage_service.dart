import 'package:hive/hive.dart';
import '../models/vehicle.dart';

class GarageService {
  static const String _boxName = 'garage_box';

  Future<Box> get _box async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<Vehicle>> loadVehicles() async {
    try {
      final box = await _box;
      final vehicleList = box.get('vehicles') as List<dynamic>? ?? [];
      return vehicleList
          .map((e) => Vehicle.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> loadActiveVehicleId() async {
    try {
      final box = await _box;
      return box.get('activeVehicleId') as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<Vehicle> vehicles, String? activeVehicleId) async {
    try {
      final box = await _box;
      final vehicleJsonList = vehicles.map((v) => v.toJson()).toList();
      await box.put('vehicles', vehicleJsonList);
      await box.put('activeVehicleId', activeVehicleId);
    } catch (e) {
      // ignore: avoid_print
      print('[GarageService] Error saving garage: $e');
    }
  }
}
