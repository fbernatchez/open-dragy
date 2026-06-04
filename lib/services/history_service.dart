import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/saved_run.dart';

class HistoryService {
  static const String _boxName = 'runs_box';
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
      final directory = await getApplicationDocumentsDirectory();
      final oldFile = File('${directory.path}/runs_history.json');
      if (await oldFile.exists()) {
        final contents = await oldFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(contents) as List<dynamic>;
        final runs = jsonList
            .map((json) => SavedRun.fromJson(json as Map<String, dynamic>))
            .toList();

        final box = await _box;
        for (final run in runs) {
          if (!box.containsKey(run.id)) {
            await box.put(run.id, run.toJson());
          }
        }
        await oldFile.delete();
        // ignore: avoid_print
        print('[HistoryService] Migrated ${runs.length} runs from JSON to Hive.');
      }
      _migrated = true;
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error during JSON migration: $e');
    }
  }

  Future<List<SavedRun>> loadRuns() async {
    try {
      await _migrateOldJsonIfNeeded();
      final box = await _box;
      final runs = box.values
          .map((json) => SavedRun.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
      // Sort descending by date (newest first)
      runs.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return runs;
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error loading runs: $e');
      return [];
    }
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
