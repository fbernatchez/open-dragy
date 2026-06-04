import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/vehicle.dart';

class GarageService {
  static const String _fileName = 'garage.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<Vehicle>> loadVehicles() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final vehicleList = data['vehicles'] as List<dynamic>? ?? [];
      return vehicleList
          .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> loadActiveVehicleId() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data['activeVehicleId'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<Vehicle> vehicles, String? activeVehicleId) async {
    final file = await _getFile();
    final data = {
      'vehicles': vehicles.map((v) => v.toJson()).toList(),
      'activeVehicleId': activeVehicleId,
    };
    await file.writeAsString(jsonEncode(data));
  }
}
