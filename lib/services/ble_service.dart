import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  final String uartServiceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String rxCharacteristicUuid =
      "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // phone → GPS UART
  final String txCharacteristicUuid =
      "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // GPS
  final String imuCharacteristicUuid =
      "6e400004-b5a3-f393-e0a9-e50e24dcca9e"; // IMU

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<List<int>>? _txSubscription;
  StreamSubscription<List<int>>? _imuSubscription;
  // ignore: unused_field
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final StreamController<String> _nmeaStreamController =
      StreamController<String>.broadcast();
  Stream<String> get nmeaStream => _nmeaStreamController.stream;

  final StreamController<String> _imuStreamController =
      StreamController<String>.broadcast();
  Stream<String> get imuStream => _imuStreamController.stream;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

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
            if (uuid == rxCharacteristicUuid &&
                (char.properties.write ||
                    char.properties.writeWithoutResponse)) {
              _rxCharacteristic = char;
              // ignore: avoid_print
              print('[BLE] RX (GPS write) ready: $uuid');
            }
            if (char.properties.notify || char.properties.indicate) {
              await char.setNotifyValue(true);
              // ignore: avoid_print
              print('[BLE] Subscribed to notifications on: $uuid');

              final subscription = char.onValueReceived.listen((value) {
                if (value.isNotEmpty) {
                  final decoded = String.fromCharCodes(value);
                  if (uuid == imuCharacteristicUuid) {
                    _processImuData(decoded);
                  } else {
                    _processReceivedData(decoded);
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

  String _buffer = "";
  String _imuBuffer = "";

  void _processReceivedData(String data) {
    _buffer += data;
    int newlineIndex;
    while ((newlineIndex = _buffer.indexOf('\n')) != -1) {
      String line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);
      if (line.isNotEmpty) {
        if (line.length >= 6 && line.startsWith('\$')) {
          final type = line.substring(3, 6);
          // Throttle: log non-GGA/RMC always; GGA/RMC occasionally.
          if (type != 'GGA' && type != 'RMC') {
            // ignore: avoid_print
            print('[BLE] NMEA $line');
          }
        } else {
          // ignore: avoid_print
          print(
            '[BLE] non-NMEA len=${line.length} '
            'head=${line.substring(0, line.length.clamp(0, 24))}',
          );
        }
        _nmeaStreamController.add(line);
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

  /// Writes raw bytes to the GPS UART (BLE RX → ESP32 → M10).
  Future<bool> writeToGps(List<int> bytes) async {
    final rx = _rxCharacteristic;
    if (rx == null || bytes.isEmpty) return false;
    try {
      await rx.write(bytes, withoutResponse: false);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] writeToGps failed: $e');
      return false;
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
    _rxCharacteristic = null;
    _connectedDevice = null;
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Continuous scan when [timeout] is null (device picker).
  /// Optional [withNames] filters advertisements (e.g. `OpenDragy`).
  void startScan({List<String> withNames = const [], Duration? timeout}) {
    FlutterBluePlus.stopScan().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        FlutterBluePlus.startScan(
          withNames: withNames,
          timeout: timeout,
        ).catchError((_) {});
      });
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<bool> get isAdapterOn async {
    try {
      return await FlutterBluePlus.adapterState.first ==
          BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }
}
