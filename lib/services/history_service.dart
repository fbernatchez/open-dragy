import 'package:hive/hive.dart';
import '../models/saved_run.dart';
import '../models/race_metrics.dart';
import '../models/race_test.dart';

class HistoryService {
  static const String _boxName = 'runs_box';

  Future<Box> get _box async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  Future<List<SavedRun>> loadRuns() async {
    try {
      final box = await _box;
      final List<SavedRun> runs = [];
      final Map<dynamic, dynamic> migratedEntries = {};

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final rawMap = Map<String, dynamic>.from(raw);
          final (migratedMap, wasMigrated) = migrateRawRunJson(rawMap);
          if (wasMigrated) {
            migratedEntries[key] = migratedMap;
          }
          runs.add(SavedRun.fromJson(migratedMap));
        }
      }

      // Persist any migrated or repaired records back to Hive in-place
      if (migratedEntries.isNotEmpty) {
        await box.putAll(migratedEntries);
      }

      // Sort descending by date (newest first)
      runs.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return runs;
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error loading runs: $e');
      return [];
    }
  }

  /// Migrates a raw legacy run map (e.g. from v1.1.4) and repairs missing rollout keys.
  static (Map<String, dynamic>, bool) migrateRawRunJson(
    Map<String, dynamic> rawJson,
  ) {
    bool modified = false;
    final Map<String, dynamic> json = Map<String, dynamic>.from(rawJson);

    final rawMetrics = json['metrics'];
    if (rawMetrics is! Map) {
      return (json, false);
    }

    final Map<String, dynamic> metricsMap =
        Map<String, dynamic>.from(rawMetrics);

    final bool hasLegacyTargets =
        metricsMap.containsKey('targetDistance') ||
        metricsMap.containsKey('targetStartSpeed') ||
        metricsMap.containsKey('targetEndSpeed');
    final bool hasLegacyTimeKeys = metricsMap.keys.any(
      (k) => k.startsWith('time') && k != 'time',
    );
    final bool hasLegacyTrapKeys = metricsMap.keys.any(
      (k) => k.startsWith('trap'),
    );

    if (hasLegacyTargets || hasLegacyTimeKeys || hasLegacyTrapKeys) {
      modified = true;
    }

    // 1. Build testTimes
    final Map<String, double> testTimes = {};
    if (metricsMap['testTimes'] is Map) {
      (metricsMap['testTimes'] as Map).forEach((k, v) {
        if (v != null) testTimes[k.toString()] = (v as num).toDouble();
      });
    }

    final legacyTimeKeys = {
      '60ft': 'time60ft',
      '330ft': 'time330ft',
      '0-60mph': 'time0to60mph',
      '0-100kmh': 'time0to100kmh',
      '1/8mile': 'time18Mile',
      '1000ft': 'time1000ft',
      '1/4mile': 'time14Mile',
      '1/2mile': 'time12Mile',
      '0-130mph': 'time0to130mph',
      '0-200kmh': 'time0to200kmh',
      '60-130mph': 'time60to130mph',
      '100-200kmh': 'time100to200kmh',
      '60ft_rollout': 'time60ftRollout',
      '330ft_rollout': 'time330ftRollout',
      '0-60mph_rollout': 'time0to60mphRollout',
      '0-100kmh_rollout': 'time0to100kmhRollout',
      '1/8mile_rollout': 'time18MileRollout',
      '1000ft_rollout': 'time1000ftRollout',
      '1/4mile_rollout': 'time14MileRollout',
      '1/2mile_rollout': 'time12MileRollout',
    };

    for (final entry in legacyTimeKeys.entries) {
      if (metricsMap[entry.value] != null && !testTimes.containsKey(entry.key)) {
        testTimes[entry.key] = (metricsMap[entry.value] as num).toDouble();
      }
    }

    // 2. Map target* -> test*
    final testDistance =
        metricsMap['testDistance'] ?? metricsMap['targetDistance'];
    final testDistanceUnit =
        metricsMap['testDistanceUnit'] ?? metricsMap['targetDistanceUnit'];
    final testStartSpeed =
        metricsMap['testStartSpeed'] ?? metricsMap['targetStartSpeed'];
    final testEndSpeed =
        metricsMap['testEndSpeed'] ?? metricsMap['targetEndSpeed'];
    final testSpeedUnit =
        metricsMap['testSpeedUnit'] ?? metricsMap['targetSpeedUnit'];

    // 3. Ensure interval runs have custom test key in testTimes
    if (metricsMap['runMode'] == 'interval' &&
        testStartSpeed != null &&
        testEndSpeed != null) {
      final unit = testSpeedUnit ?? 'kmh';
      final start = (testStartSpeed as num).round();
      final end = (testEndSpeed as num).round();
      final customId = 'custom_${start}_${end}_$unit';
      if (!testTimes.containsKey(customId) && metricsMap['elapsedTime'] != null) {
        testTimes[customId] = (metricsMap['elapsedTime'] as num).toDouble();
        modified = true;
      }
    }

    final rollout1ft = (metricsMap['rolloutTime1ft'] as num?)?.toDouble();

    if (!modified) {
      return (json, false);
    }

    // 4. Build clean canonical metrics map
    final cleanMetrics = <String, dynamic>{
      'speedKmh': (metricsMap['speedKmh'] as num?)?.toDouble() ?? 0.0,
      'distanceMeters':
          (metricsMap['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      'gForce': (metricsMap['gForce'] as num?)?.toDouble() ?? 0.0,
      'elapsedTime': (metricsMap['elapsedTime'] as num?)?.toDouble() ?? 0.0,
      'testTimes': testTimes,
      'rolloutTime1ft': rollout1ft,
      'startAltitude': (metricsMap['startAltitude'] as num?)?.toDouble(),
      'runMode': metricsMap['runMode'],
      'testDistance': (testDistance as num?)?.toDouble(),
      'testDistanceUnit': testDistanceUnit,
      'testStartSpeed': (testStartSpeed as num?)?.toDouble(),
      'testEndSpeed': (testEndSpeed as num?)?.toDouble(),
      'testSpeedUnit': testSpeedUnit,
      'history': metricsMap['history'] ?? [],
    };

    json['metrics'] = cleanMetrics;
    return (json, true);
  }

  Future<void> saveRun(SavedRun run) async {
    try {
      final box = await _box;
      await box.put(run.id, run.toJson());
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error saving run: $e');
    }
  }

  Future<void> updateRun(SavedRun updatedRun) async {
    try {
      final box = await _box;
      await box.put(updatedRun.id, updatedRun.toJson());
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error updating run: $e');
    }
  }

  Future<void> deleteRun(String id) async {
    try {
      final box = await _box;
      await box.delete(id);
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error deleting run: $e');
    }
  }
}
