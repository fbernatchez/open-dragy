import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/saved_run.dart';

class HistoryService {
  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/runs_history.json');
  }

  Future<List<SavedRun>> loadRuns() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        return [];
      }
      final contents = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(contents) as List<dynamic>;
      final runs = jsonList
          .map((json) => SavedRun.fromJson(json as Map<String, dynamic>))
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
      final runs = await loadRuns();
      runs.insert(0, run); // Insert at the beginning (newest first)
      final file = await _localFile;
      final contents = jsonEncode(runs.map((r) => r.toJson()).toList());
      await file.writeAsString(contents);
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error saving run: $e');
    }
  }

  Future<void> updateRun(SavedRun updatedRun) async {
    try {
      final runs = await loadRuns();
      final index = runs.indexWhere((r) => r.id == updatedRun.id);
      if (index != -1) {
        runs[index] = updatedRun;
        final file = await _localFile;
        final contents = jsonEncode(runs.map((r) => r.toJson()).toList());
        await file.writeAsString(contents);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error updating run: $e');
    }
  }

  Future<void> deleteRun(String id) async {
    try {
      final runs = await loadRuns();
      runs.removeWhere((r) => r.id == id);
      final file = await _localFile;
      final contents = jsonEncode(runs.map((r) => r.toJson()).toList());
      await file.writeAsString(contents);
    } catch (e) {
      // ignore: avoid_print
      print('[HistoryService] Error deleting run: $e');
    }
  }
}
