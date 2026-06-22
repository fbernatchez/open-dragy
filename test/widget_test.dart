import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:open_dragy/main.dart';
import 'package:open_dragy/providers/dragy_provider.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:open_dragy/models/saved_run.dart';
import 'package:open_dragy/screens/dashboard_screen.dart';
import 'package:open_dragy/screens/run_history_screen.dart';
import 'package:open_dragy/screens/run_detail_screen.dart';
import 'package:open_dragy/screens/settings_screen.dart';
import 'package:open_dragy/screens/garage_screen.dart';
import 'package:open_dragy/services/ble_service.dart';
import 'package:open_dragy/models/vehicle.dart';
import 'dart:io';
import 'package:hive/hive.dart';

class MockDragyProvider extends ChangeNotifier implements DragyProvider {
  @override
  bool isConnected = false;

  @override
  RaceMetrics metrics = RaceMetrics();

  @override
  double liveElapsedTime = 0.0;

  @override
  int satellites = 0;

  @override
  double hdop = 0.0;

  @override
  double? latitude;

  @override
  double? longitude;

  @override
  String appVersion = '1.0.0-mock';

  @override
  BluetoothDevice? connectedDevice;

  @override
  BleService get bleService => throw UnimplementedError();

  @override
  Future<bool> connect(BluetoothDevice device) async => true;

  @override
  Future<void> disconnect() async {}

  @override
  void resetRace() {}



  @override
  double altitude = 0.0;

  @override
  List<SavedRun> savedRuns = [];

  @override
  Future<void> loadSavedRuns() async {}

  @override
  Future<void> deleteRun(String id) async {}

  @override
  Future<void> updateRunNotes(String id, String notes) async {}
  @override
  bool isArmed = false;

  @override
  String runMode = 'drag';

  @override
  RaceIntervalTarget activeIntervalTarget = RaceIntervalTarget.sixtyToOneThirtyMph;

  @override
  double customIntervalStartSpeed = 100.0;

  @override
  double customIntervalEndSpeed = 200.0;

  @override
  double get intervalStartSpeed => 100.0;

  @override
  double get intervalEndSpeed => 200.0;

  @override
  double get customIntervalStartSpeedUserUnit => 100.0;

  @override
  double get customIntervalEndSpeedUserUnit => 200.0;

  @override
  String get activeDragTargetLabel => activeDragTarget.label;

  @override
  String get activeIntervalTargetLabel => activeIntervalTarget.label;

  @override
  double? get targetDistance {
    if (runMode != 'drag') return null;
    switch (activeDragTarget) {
      case RaceDragTarget.sixtyFeet: return 60.0;
      case RaceDragTarget.threeHundredThirtyFeet: return 330.0;
      case RaceDragTarget.eighthMile: return 0.125;
      case RaceDragTarget.thousandFeet: return 1000.0;
      case RaceDragTarget.quarterMile: return 0.25;
      case RaceDragTarget.halfMile: return 0.5;
    }
  }

  @override
  String? get targetDistanceUnit {
    if (runMode != 'drag') return null;
    switch (activeDragTarget) {
      case RaceDragTarget.sixtyFeet: return 'feet';
      case RaceDragTarget.threeHundredThirtyFeet: return 'feet';
      case RaceDragTarget.eighthMile: return 'mile';
      case RaceDragTarget.thousandFeet: return 'feet';
      case RaceDragTarget.quarterMile: return 'mile';
      case RaceDragTarget.halfMile: return 'mile';
    }
  }

  @override
  double? get targetStartSpeed => runMode == 'interval' ? intervalStartSpeed : null;

  @override
  double? get targetEndSpeed => runMode == 'interval' ? intervalEndSpeed : null;

  @override
  String? get targetSpeedUnit {
    if (runMode != 'interval') return null;
    switch (activeIntervalTarget) {
      case RaceIntervalTarget.zeroToSixtyMph:
      case RaceIntervalTarget.fiftyToSeventyFiveMph:
      case RaceIntervalTarget.sixtyToOneThirtyMph:
        return 'mph';
      case RaceIntervalTarget.zeroToOneHundredKmh:
      case RaceIntervalTarget.eightyToOneTwentyKmh:
      case RaceIntervalTarget.oneHundredToTwoHundredKmh:
        return 'kmh';
      default:
        return isMetric ? 'kmh' : 'mph';
    }
  }

  @override
  bool get isSpeedConstant => true;

  @override
  void toggleArm() {
    isArmed = !isArmed;
    notifyListeners();
  }

  @override
  void setRunMode(String mode) {
    runMode = mode;
    notifyListeners();
  }

  @override
  void setActiveIntervalTarget(RaceIntervalTarget target) {
    activeIntervalTarget = target;
    notifyListeners();
  }

  @override
  void setCustomIntervalRange(double start, double end) {
    customIntervalStartSpeed = start;
    customIntervalEndSpeed = end;
    notifyListeners();
  }

  @override
  bool isMetric = false;

  @override
  void toggleSpeedUnit() {
    isMetric = !isMetric;
    notifyListeners();
  }

  @override
  RaceDragTarget activeDragTarget = RaceDragTarget.quarterMile;

  @override
  void setActiveDragTarget(RaceDragTarget target) {
    activeDragTarget = target;
    notifyListeners();
  }


  // --- Settings ---
  @override
  bool tempInCelsius = true;

  @override
  bool useNhraRules = false;

  @override
  void setMetric(bool isMetric) {
    this.isMetric = isMetric;
    notifyListeners();
  }

  @override
  void setTempInCelsius(bool value) {
    tempInCelsius = value;
    notifyListeners();
  }

  @override
  void setUseNhraRules(bool value) {
    useNhraRules = value;
    notifyListeners();
  }

  // --- Garage ---
  @override
  List<Vehicle> vehicles = [];

  @override
  String? activeVehicleId;

  @override
  Vehicle? get activeVehicle {
    if (activeVehicleId == null) return null;
    try {
      return vehicles.firstWhere((v) => v.id == activeVehicleId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> addVehicle(Vehicle vehicle) async {
    vehicles = [...vehicles, vehicle];
    activeVehicleId ??= vehicle.id;
    notifyListeners();
  }

  @override
  Future<void> updateVehicle(Vehicle vehicle) async {
    final idx = vehicles.indexWhere((v) => v.id == vehicle.id);
    if (idx != -1) {
      vehicles = [...vehicles]..[idx] = vehicle;
      notifyListeners();
    }
  }

  @override
  Future<void> deleteVehicle(String id) async {
    vehicles = vehicles.where((v) => v.id != id).toList();
    if (activeVehicleId == id) {
      activeVehicleId = vehicles.isNotEmpty ? vehicles.first.id : null;
    }
    notifyListeners();
  }

  @override
  Future<void> setActiveVehicle(String id) async {
    activeVehicleId = id;
    notifyListeners();
  }

  void updateState({
    bool? isConnected,
    RaceMetrics? metrics,
    double? liveElapsedTime,
    int? satellites,
    double? hdop,
  }) {
    if (isConnected != null) this.isConnected = isConnected;
    if (metrics != null) this.metrics = metrics;
    if (liveElapsedTime != null) this.liveElapsedTime = liveElapsedTime;
    if (satellites != null) this.satellites = satellites;
    if (hdop != null) this.hdop = hdop;
    notifyListeners();
  }
}


void main() {
  testWidgets('Dashboard basic smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    
    // Initialize Hive in a temporary directory for the test context
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    
    await tester.pumpWidget(const OpenDragyApp());

    expect(find.text('OpenDragy'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_disabled), findsOneWidget);
  });

  testWidgets('Dashboard dynamic status messages test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;

    final mockProvider = MockDragyProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );

    // 1. Disconnected State
    mockProvider.updateState(isConnected: false);
    await tester.pumpAndSettle();
    expect(find.text('Disconnected'), findsOneWidget);

    // 2a. Connected & Stationary, GPS not ready (0 satellites, 0.0 hdop)
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 0.0, isRunning: false, runMode: 'drag'),
      satellites: 0,
      hdop: 0.0,
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for GPS'), findsOneWidget);

    // 2b. Connected & Stationary, GPS ready (8 satellites, 1.2 hdop)
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 0.0, isRunning: false, runMode: 'drag'),
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('Disarmed'), findsOneWidget);

    // 3. Connected & Moving (Disarmed) State
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 10.0, isRunning: false, runMode: 'drag'),
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('Disarmed'), findsOneWidget);
    expect(find.text('DRAG'), findsOneWidget);
    expect(find.text('INTERVAL'), findsOneWidget);

    // 3b. Connected, Armed, but Moving (Stop) State in drag mode
    mockProvider.isArmed = true;
    mockProvider.runMode = 'drag';
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 15.0, isRunning: false, runMode: 'drag'),
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);

    // 3c. Connected, Armed, and Stationary (Awaiting Launch) State in drag mode
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 0.0, isRunning: false, runMode: 'drag'),
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('Awaiting Launch'), findsOneWidget);
    // Reset armed state back to false for the next tests
    mockProvider.isArmed = false;

    // 4. Running State (Live Elapsed Time)
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(speedKmh: 50.0, isRunning: true, runMode: 'drag'),
      liveElapsedTime: 3.45,
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('3.45s'), findsOneWidget);
    expect(find.text('DRAG'), findsNothing);
    expect(find.text('INTERVAL'), findsNothing);

    // 5. Completed Run State (Final Time)
    mockProvider.updateState(
      isConnected: true,
      metrics: RaceMetrics(
        speedKmh: 0.0,
        isRunning: false,
        time14Mile: 12.34,
        runMode: 'drag',
      ),
      satellites: 8,
      hdop: 1.2,
    );
    await tester.pumpAndSettle();
    expect(find.text('12.34s'), findsNWidgets(2));
  });

  testWidgets('RunHistoryScreen filtering and PB test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;

    final mockProvider = MockDragyProvider();
    
    // Set up mock runs:
    // Run 1: has both 0-60 mph and 1/4 mile
    final run1 = SavedRun(
      id: 'run_1',
      dateTime: DateTime.now().subtract(const Duration(minutes: 5)),
      metrics: RaceMetrics(
        speedKmh: 0.0,
        distanceMeters: 402.336,
        elapsedTime: 11.45,
        time0to60mph: 3.42,
        time14Mile: 11.45,
        runMode: 'drag',
        targetDistance: 0.25,
        targetDistanceUnit: 'mile',
        history: [],
      ),
    );

    // Run 2: has only 0-60 mph (faster 0-60 than Run 1)
    final run2 = SavedRun(
      id: 'run_2',
      dateTime: DateTime.now().subtract(const Duration(minutes: 10)),
      metrics: RaceMetrics(
        speedKmh: 0.0,
        distanceMeters: 100.0,
        elapsedTime: 2.92,
        time0to60mph: 2.92,
        runMode: 'drag',
        targetStartSpeed: 0.0,
        targetEndSpeed: 96.56064,
        targetSpeedUnit: 'mph',
        history: [],
      ),
    );

    // Run 3: Custom interval run
    final run3 = SavedRun(
      id: 'run_3',
      dateTime: DateTime.now().subtract(const Duration(minutes: 15)),
      metrics: RaceMetrics(
        speedKmh: 0.0,
        distanceMeters: 150.0,
        elapsedTime: 2.15,
        runMode: 'interval',
        targetStartSpeed: 48.28032,
        targetEndSpeed: 80.4672,
        targetSpeedUnit: 'mph',
        history: const [
          DataPoint(elapsedTime: -0.01, speedKmh: 47.28032, gForce: 0.0, altitude: 100.0),
          DataPoint(elapsedTime: 0.0, speedKmh: 48.28032, gForce: 0.0, altitude: 100.0),
          DataPoint(elapsedTime: 2.15, speedKmh: 80.4672, gForce: 0.0, altitude: 100.0),
          DataPoint(elapsedTime: 2.16, speedKmh: 81.4672, gForce: 0.0, altitude: 100.0),
        ],
      ),
    );

    mockProvider.savedRuns = [run1, run2, run3];
    mockProvider.isMetric = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: RunHistoryScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify "All Runs" card shows "3 Runs"
    expect(find.text('3 Runs'), findsOneWidget);

    // 2. Verify PB for "0-60 mph" shows the faster time "2.92s"
    expect(find.text('2.92s'), findsNWidgets(2));

    // 3. Verify PB for "1/4 mile" shows "11.45s"
    expect(find.text('11.45s'), findsNWidgets(2));

    // 4. Verify custom rolling target run is displayed in the list
    expect(find.text('30-50 mph'), findsNWidgets(2));
    expect(find.text('2.15s'), findsNWidgets(2));

    // 5. Verify all three runs are shown initially
    expect(find.byType(RunHistoryCard), findsNWidgets(3));

    // 5. Tap on the "1/4 mile" category card to filter the list
    final quarterMileCard = find.text('1/4 mile').first;
    await tester.tap(quarterMileCard);
    await tester.pumpAndSettle();

    // 6. Verify that only 1 run is shown (since only Run 1 has 1/4 mile completed)
    expect(find.byType(RunHistoryCard), findsOneWidget);

    // 7. Verify that the run history card now shows the selected category as primary label and correct time
    expect(find.text('1/4 mile'), findsNWidgets(2));
    expect(find.text('11.45s'), findsNWidgets(2));

    // 8. Tap on the "0-60 mph" category card to filter the list
    final zeroToSixtyCard = find.text('0-60 mph').first;
    await tester.tap(zeroToSixtyCard);
    await tester.pumpAndSettle();

    // 9. Verify that 2 runs are shown (since Run 1 and Run 2 have 0-60 mph completed)
    expect(find.byType(RunHistoryCard), findsNWidgets(2));

    // 10. Verify that both card details show 0-60 mph and their respective times
    expect(find.text('2.92s'), findsNWidgets(2)); // One in category PB chip, one in Run 2 card
    expect(find.text('3.42s'), findsOneWidget);   // One in Run 1 card (not in category PB chip since PB is 2.92s)
  });

  testWidgets('SettingsScreen displays toggles and triggers actions', (WidgetTester tester) async {
    final mockProvider = MockDragyProvider();
    mockProvider.isMetric = false; // metric = false
    mockProvider.tempInCelsius = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    // Verify initial values
    expect(find.text('Unit in Metric'), findsOneWidget);
    expect(find.text('Temperature in Celsius'), findsOneWidget);

    // Find switches
    final metricSwitch = find.ancestor(
      of: find.text('Unit in Metric'),
      matching: find.byType(SwitchListTile),
    );
    final tempSwitch = find.ancestor(
      of: find.text('Temperature in Celsius'),
      matching: find.byType(SwitchListTile),
    );

    expect(metricSwitch, findsOneWidget);
    expect(tempSwitch, findsOneWidget);

    // Tapping the metric switch should change it
    await tester.tap(metricSwitch);
    await tester.pumpAndSettle();
    expect(mockProvider.isMetric, true);

    // Tapping the temperature switch should toggle it
    await tester.tap(tempSwitch);
    await tester.pumpAndSettle();
    expect(mockProvider.tempInCelsius, false);

    // Verify version info is displayed
    expect(find.text('1.0.0-mock'), findsOneWidget);
  });

  testWidgets('GarageScreen displays empty state and lists vehicles', (WidgetTester tester) async {
    final mockProvider = MockDragyProvider();

    // 1. Empty garage
    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: GarageScreen(),
        ),
      ),
    );

    expect(find.text('Your garage is empty.'), findsOneWidget);

    // 2. Add vehicle and display
    final vehicle = Vehicle(id: 'v1', make: 'Ford', model: 'Mustang', year: 2020);
    mockProvider.vehicles = [vehicle];
    mockProvider.activeVehicleId = 'v1';

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: GarageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2020 Ford Mustang'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('Dashboard rolling target dropdown filtering by unit setting test', (WidgetTester tester) async {
    final mockProvider = MockDragyProvider();
    mockProvider.isConnected = true;
    mockProvider.runMode = 'interval';

    // 1. Imperial units (isMetric = false)
    mockProvider.isMetric = false;
    mockProvider.activeIntervalTarget = RaceIntervalTarget.sixtyToOneThirtyMph;

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Dropdown button is showing '60-130 mph'
    expect(find.text('60-130 mph'), findsOneWidget);
    expect(find.text('100-200 km/h'), findsNothing);

    // Open the dropdown
    await tester.tap(find.text('60-130 mph'));
    await tester.pumpAndSettle();

    // Verify options present
    expect(find.text('0-60 mph').last, findsOneWidget);
    expect(find.text('0-100 mph').last, findsOneWidget);
    expect(find.text('0-130 mph').last, findsOneWidget);
    expect(find.text('50-75 mph').last, findsOneWidget);
    expect(find.text('60-100 mph').last, findsOneWidget);
    expect(find.text('60-130 mph').last, findsOneWidget);
    expect(find.text('Custom Range...').last, findsOneWidget);
    // Verify metric options are NOT present
    expect(find.text('0-100 km/h'), findsNothing);
    expect(find.text('0-160 km/h'), findsNothing);
    expect(find.text('80-120 km/h'), findsNothing);
    expect(find.text('100-200 km/h'), findsNothing);

    // Close the dropdown menu by selecting '0-60 mph'
    await tester.tap(find.text('0-60 mph').last);
    await tester.pumpAndSettle();

    // 2. Metric units (isMetric = true)
    mockProvider.isMetric = true;
    mockProvider.activeIntervalTarget = RaceIntervalTarget.oneHundredToTwoHundredKmh;
    mockProvider.notifyListeners();
    await tester.pumpAndSettle();

    // Verify Dropdown button is showing '100-200 km/h'
    expect(find.text('100-200 km/h'), findsOneWidget);
    expect(find.text('60-130 mph'), findsNothing);

    // Open the dropdown
    await tester.tap(find.text('100-200 km/h'));
    await tester.pumpAndSettle();

    // Verify options present
    expect(find.text('0-100 km/h').last, findsOneWidget);
    expect(find.text('0-160 km/h').last, findsOneWidget);
    expect(find.text('0-200 km/h').last, findsOneWidget);
    expect(find.text('80-120 km/h').last, findsOneWidget);
    expect(find.text('100-200 km/h').last, findsOneWidget);
    expect(find.text('Custom Range...').last, findsOneWidget);
    // Verify imperial options are NOT present
    expect(find.text('0-60 mph'), findsNothing);
    expect(find.text('0-100 mph'), findsNothing);
    expect(find.text('50-75 mph'), findsNothing);
    expect(find.text('60-130 mph'), findsNothing);
  });

  testWidgets('RunDetailScreen displays telemetry chart with data', (WidgetTester tester) async {
    final mockProvider = MockDragyProvider();
    mockProvider.isMetric = false;

    final run = SavedRun(
      id: 'run_detail_1',
      dateTime: DateTime.now(),
      metrics: RaceMetrics(
        speedKmh: 0.0,
        distanceMeters: 402.336,
        elapsedTime: 12.5,
        time14Mile: 12.5,
        history: const [
          DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0, altitude: 100.0),
          DataPoint(elapsedTime: 2.0, speedKmh: 50.0, gForce: 0.8, altitude: 101.0),
          DataPoint(elapsedTime: 2.20, speedKmh: 52.0, gForce: 0.8, altitude: 101.1),
          DataPoint(elapsedTime: 5.0, speedKmh: 100.0, gForce: 0.5, altitude: 102.0),
          DataPoint(elapsedTime: 10.0, speedKmh: 150.0, gForce: 0.3, altitude: 103.0),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: MaterialApp(
          home: RunDetailScreen(run: run),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('TELEMETRY GRAPH'), findsOneWidget);
    // Verify Legend items
    expect(find.text('Speed (mph)'), findsOneWidget);
    expect(find.text('Accel (G)'), findsOneWidget);
    expect(find.text('Height (ft)'), findsOneWidget);

    // Verify Summary stats shown
    // Max Speed in mph: 150 * 0.621371 = 93.20565 mph -> 93.2
    expect(find.text('93.2'), findsOneWidget);
    // Max Accel: 0.80G
    expect(find.text('0.80G'), findsOneWidget);
    // Min Accel: 0.00G
    expect(find.text('0.00G'), findsOneWidget);
    // Elevation change: 103.0m - 100.0m = 3.0m * 3.28084 = 9.84ft -> +9.8
    expect(find.text('+9.8'), findsOneWidget);
  });

  testWidgets('RunDetailScreen displays fallback when no telemetry data', (WidgetTester tester) async {
    final mockProvider = MockDragyProvider();

    final run = SavedRun(
      id: 'run_detail_2',
      dateTime: DateTime.now(),
      metrics: RaceMetrics(
        speedKmh: 0.0,
        distanceMeters: 0.0,
        elapsedTime: 0.0,
        runMode: 'drag',
        history: const [],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DragyProvider>.value(
        value: mockProvider,
        child: MaterialApp(
          home: RunDetailScreen(run: run),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No telemetry data recorded for this run.'), findsOneWidget);
  });

  test('SavedRun and RaceMetrics JSON deserialization handles dynamic maps from Hive', () {
    final Map<dynamic, dynamic> hiveRawData = {
      'id': 'run_123',
      'dateTime': '2026-06-04T18:00:00.000',
      'metrics': {
        'speedKmh': 100.0,
        'distanceMeters': 400.0,
        'gForce': 0.5,
        'elapsedTime': 10.0,
        'time14Mile': 10.0,
        'runMode': 'drag',
        'history': [
          {
            'elapsedTime': 0.0,
            'speedKmh': 0.0,
            'gForce': 0.0,
            'altitude': 100.0,
          },
          {
            'elapsedTime': 5.0,
            'speedKmh': 50.0,
            'gForce': 0.5,
            'altitude': 101.0,
          }
        ],
      },
      'notes': 'Test run',
      'temperature': 20.0,
      'humidity': 50.0,
      'vehicleId': 'v1',
      'vehicleName': 'My Car',
    };

    final savedRunMap = Map<String, dynamic>.from(hiveRawData);
    final savedRun = SavedRun.fromJson(savedRunMap);

    expect(savedRun.id, 'run_123');
    expect(savedRun.metrics.speedKmh, 100.0);
    expect(savedRun.metrics.history.length, 2);
    expect(savedRun.metrics.history[1].speedKmh, 50.0);
  });

  test('DragyProvider settings serialization test', () {
    double customIntervalStartSpeed = 100.0;
    double customIntervalEndSpeed = 200.0;
    
    final savedMap = {
      'isMetric': false,
      'customIntervalStartSpeed': customIntervalStartSpeed.round(),
      'customIntervalEndSpeed': customIntervalEndSpeed.round(),
    };
    
    expect(savedMap['customIntervalStartSpeed'], 100);
    expect(savedMap['customIntervalEndSpeed'], 200);
    expect(savedMap['customIntervalStartSpeed'] is int, true);
    expect(savedMap['customIntervalEndSpeed'] is int, true);
  });
}

