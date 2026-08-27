import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ubx_nav_pvt.dart';

class BleService {
  final String uartServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String txCharacteristicUuid =
      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // GPS
  final String imuCharacteristicUuid =
      "6e400004-b5a3-f393-e0a9-e50e24dcca9e"; // IMU
  final String versionCharacteristicUuid =
      "6e400005-b5a3-f393-e0a9-e50e24dcca9e"; // Version

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _txSubscription;
  StreamSubscription<List<int>>? _imuSubscription;
  // ignore: unused_field
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final StreamController<UbxNavPvt> _ubxStreamController =
      StreamController<UbxNavPvt>.broadcast();
  Stream<UbxNavPvt> get ubxStream => _ubxStreamController.stream;

  final StreamController<String> _imuStreamController =
      StreamController<String>.broadcast();
  Stream<String> get imuStream => _imuStreamController.stream;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  final StreamController<String> _firmwareVersionController =
      StreamController<String>.broadcast();
  Stream<String> get firmwareVersionStream => _firmwareVersionController.stream;

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));

      await device.connect(license: License.free);

      // Request a larger MTU to prevent packet fragmentation and latency build-up
      try {
        await device.requestMtu(223);
      } catch (e) {
        // ignore: avoid_print
        print('[BLE] Failed to request MTU: $e');
      }

      _connectedDevice = device;

      _connectionSubscription?.cancel();
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _connectionStateController.add(true);
        } else if (state == BluetoothConnectionState.disconnected) {
          _connectionStateController.add(false);
          _cleanupSubscriptions();
        }
      });

      List<BluetoothService> services = await device.discoverServices(
        timeout: 15,
      );

      // --- BLE DIAGNOSTICS: log all services and characteristics ---
      // ignore: avoid_print
      print('[BLE] Found ${services.length} services:');
      for (var service in services) {
        // ignore: avoid_print
        print('[BLE] SERVICE: ${service.uuid}');
        for (var char in service.characteristics) {
          final props = <String>[];
          if (char.properties.notify) props.add('NOTIFY');
          if (char.properties.indicate) props.add('INDICATE');
          if (char.properties.read) props.add('READ');
          if (char.properties.write) props.add('WRITE');
          // ignore: avoid_print
          print('[BLE]   CHAR: ${char.uuid} [${props.join(', ')}]');
        }
      }
      // --- END DIAGNOSTICS ---

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == uartServiceUuid) {
          for (var char in service.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            
            if (uuid == versionCharacteristicUuid) {
              if (char.properties.read) {
                final value = await char.read();
                final versionString = String.fromCharCodes(value);
                _firmwareVersionController.add(versionString);
              }
              continue;
            }

            if (char.properties.notify || char.properties.indicate) {
              await char.setNotifyValue(true);
              // ignore: avoid_print
              print('[BLE] Subscribed to notifications on: $uuid');

              final subscription = char.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  if (uuid == imuCharacteristicUuid) {
                    final decoded = String.fromCharCodes(value);
                    _processImuData(decoded);
                  } else {
                    _processReceivedData(value);
                  }
                }
              });

              if (uuid == imuCharacteristicUuid) {
                _imuSubscription = subscription;
              } else {
                _txSubscription = subscription;
              }
            }
          }
        }
      }

      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Connection error: $e');
      _connectionStateController.add(false);
      return false;
    }
  }

  List<int> _ubxBuffer = [];
  String _imuBuffer = "";

  void _processReceivedData(List<int> data) {
    _ubxBuffer.addAll(data);
    
    while (_ubxBuffer.length >= 8) { // Minimum size for header + len + ck
      // Find sync chars 0xB5 0x62
      if (_ubxBuffer[0] != 0xB5 || _ubxBuffer[1] != 0x62) {
        _ubxBuffer.removeAt(0);
        continue;
      }
      
      // We have sync chars. Check if it's NAV-PVT (Class 0x01, ID 0x07)
      if (_ubxBuffer[2] != 0x01 || _ubxBuffer[3] != 0x07) {
         _ubxBuffer.removeAt(0); // Not NAV-PVT, discard and continue
         continue;
      }
      
      int payloadLen = _ubxBuffer[4] | (_ubxBuffer[5] << 8);
      int packetLen = payloadLen + 8; // header(2) + cls(1) + id(1) + len(2) + payload + ck(2)
      
      // Sanity check on payload length (NAV-PVT is usually 92 or 100)
      if (payloadLen > 110) {
        _ubxBuffer.removeAt(0);
        continue;
      }
      
      if (_ubxBuffer.length >= packetLen) {
        // Extract payload
        List<int> payload = _ubxBuffer.sublist(6, 6 + payloadLen);
        
        try {
          final pvt = UbxNavPvt.fromBytes(payload);
          _ubxStreamController.add(pvt);
        } catch (e) {
          // ignore: avoid_print
          print('[BLE] Error parsing UBX: $e');
        }
        
        _ubxBuffer.removeRange(0, packetLen);
      } else {
        // Wait for more data
        break;
      }
    }
  }

  void _processImuData(String data) {
    _imuBuffer += data;
    int newlineIndex;
    while ((newlineIndex = _imuBuffer.indexOf('\n')) != -1) {
      String line = _imuBuffer.substring(0, newlineIndex).trim();
      _imuBuffer = _imuBuffer.substring(newlineIndex + 1);
      if (line.isNotEmpty) {
        _imuStreamController.add(line);
      }
    }
  }

  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _cleanupSubscriptions();
  }

  void _cleanupSubscriptions() {
    _txSubscription?.cancel();
    _txSubscription = null;
    _imuSubscription?.cancel();
    _imuSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedDevice = null;
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  Future<void> startScan() async {
    try {
      if (await FlutterBluePlus.isSupported == false) return;

      // Wait for Bluetooth to be ON
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first;

      // Stop any existing scan and start a new one
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan();
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] startScan error: $e');
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }
}
