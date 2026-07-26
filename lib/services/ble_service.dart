import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/odgp_parser.dart';

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

  final StreamController<OdgpFix> _odgpStreamController =
      StreamController<OdgpFix>.broadcast();
  Stream<OdgpFix> get odgpStream => _odgpStreamController.stream;

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
                if (value.isEmpty) return;
                if (uuid == imuCharacteristicUuid) {
                  _processImuData(String.fromCharCodes(value));
                } else {
                  _processGpsNotify(value);
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

  final List<int> _odgpBuf = [];
  String _nmeaBuffer = "";
  String _imuBuffer = "";

  int _gpsNotifyLogBudget = 8;

  void _processGpsNotify(List<int> value) {
    if (_gpsNotifyLogBudget > 0) {
      _gpsNotifyLogBudget--;
      final head = value.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      // ignore: avoid_print
      print('[BLE] GPS notify len=${value.length} head=$head');
    }

    // Prefer ODGP binary (firmware PVT path).
    if (value.length >= 4 &&
        value[0] == 0x4F &&
        value[1] == 0x44 &&
        value[2] == 0x47 &&
        value[3] == 0x50) {
      _odgpBuf
        ..clear()
        ..addAll(value);
      final fix = OdgpParser.tryParse(_odgpBuf);
      if (fix != null) {
        _odgpStreamController.add(fix);
      }
      return;
    }

    // Reassemble ODGP if BLE fragmented a 52 B packet.
    if (_odgpBuf.isNotEmpty ||
        (value.isNotEmpty && value[0] == 0x4F) ||
        (_odgpBuf.isNotEmpty && _odgpBuf[0] == 0x4F)) {
      _odgpBuf.addAll(value);
      while (_odgpBuf.length >= OdgpParser.packetSize) {
        if (_odgpBuf[0] == 0x4F &&
            _odgpBuf[1] == 0x44 &&
            _odgpBuf[2] == 0x47 &&
            _odgpBuf[3] == 0x50) {
          final chunk = _odgpBuf.sublist(0, OdgpParser.packetSize);
          _odgpBuf.removeRange(0, OdgpParser.packetSize);
          final fix = OdgpParser.tryParse(chunk);
          if (fix != null) _odgpStreamController.add(fix);
        } else {
          _odgpBuf.removeAt(0);
        }
      }
      // If buffer looks like text, fall through.
      if (_odgpBuf.isNotEmpty && _odgpBuf[0] == 0x24) {
        // '$'
        final text = String.fromCharCodes(_odgpBuf);
        _odgpBuf.clear();
        _processNmeaText(text);
      }
      return;
    }

    // Legacy NMEA firmware fallback.
    _processNmeaText(String.fromCharCodes(value));
  }

  void _processNmeaText(String data) {
    _nmeaBuffer += data;
    int newlineIndex;
    while ((newlineIndex = _nmeaBuffer.indexOf('\n')) != -1) {
      String line = _nmeaBuffer.substring(0, newlineIndex).trim();
      _nmeaBuffer = _nmeaBuffer.substring(newlineIndex + 1);
      if (line.isNotEmpty) {
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
    _odgpBuf.clear();
    _nmeaBuffer = '';
    _imuBuffer = '';
  }

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

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
