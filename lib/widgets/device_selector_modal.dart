import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/dragy_provider.dart';

class DeviceSelectorModal extends StatefulWidget {
  const DeviceSelectorModal({super.key});

  @override
  State<DeviceSelectorModal> createState() => _DeviceSelectorModalState();
}

class _DeviceSelectorModalState extends State<DeviceSelectorModal> {
  String? _connectingDeviceId;
  late final bleService;
  // Accumulated device map — devices are added but never removed
  final Map<String, ScanResult> _devicesFound = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    bleService = Provider.of<DragyProvider>(context, listen: false).bleService;
    _checkPermissionsAndScan();
  }

  Future<void> _checkPermissionsAndScan() async {
    Map<Permission, PermissionStatus> statuses;

    if (Platform.isIOS) {
      statuses = await [
        Permission.bluetooth,
      ].request();
    } else {
      statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }

    if (!mounted) return;

    if (statuses.values.every((s) => s.isGranted)) {
      // Subscribe to scan results and accumulate them
      _scanSubscription = bleService.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          for (final r in results) {
            _devicesFound[r.device.remoteId.toString()] = r;
          }
        });
      });
      bleService.startScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions required to scan for devices.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dragyProvider = Provider.of<DragyProvider>(context);
    // Only show named devices, like native Android Bluetooth
    final results = _devicesFound.values
        .where((r) => r.device.platformName.isNotEmpty)
        .toList();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Connect to OpenDragy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: results.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final r = results[index];
                      final deviceName = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'Unknown Device';
                      final isConnectingToThis =
                          _connectingDeviceId == r.device.remoteId.toString();

                      return ListTile(
                        title: Text(deviceName),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _connectingDeviceId != null
                              ? null
                              : () async {
                                  setState(() {
                                    _connectingDeviceId =
                                        r.device.remoteId.toString();
                                  });
                                  final navigator = Navigator.of(context);
                                  final success =
                                      await dragyProvider.connect(r.device);
                                  if (!mounted) return;
                                  if (success) {
                                    navigator.pop();
                                  } else {
                                    setState(() => _connectingDeviceId = null);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to connect to device.'),
                                      ),
                                    );
                                  }
                                },
                          child: isConnectingToThis
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text('Connect'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    bleService.stopScan();
    super.dispose();
  }
}
