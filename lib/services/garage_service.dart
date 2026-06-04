import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/vehicle.dart';

class GarageService {
  static const String _boxName = 'garage_box';
  bool _migrated = false;

  Future<Box> get _box async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<void> _migrateOldJsonIfNeeded() async {
    if (_migrated) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final oldFile = File('${dir.path}/garage.json');
      if (await oldFile.exists()) {
        final content = await oldFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        final box = await _box;
        if (!box.containsKey('vehicles') && data['vehicles'] != null) {
          await box.put('vehicles', data['vehicles']);
        }
        if (!box.containsKey('activeVehicleId') && data['activeVehicleId'] != null) {
          await box.put('activeVehicleId', data['activeVehicleId']);
        }
        await oldFile.delete();
        // ignore: avoid_print
        print('[GarageService] Migrated garage data from JSON to Hive.');
      }
      _migrated = true;
    } catch (e) {
      // ignore: avoid_print
      print('[GarageService] Error during JSON migration: $e');
    }
  }

  Future<List<Vehicle>> loadVehicles() async {
    try {
      await _migrateOldJsonIfNeeded();
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
      await _migrateOldJsonIfNeeded();
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
