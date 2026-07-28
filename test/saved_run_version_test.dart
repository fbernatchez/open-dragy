import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:open_dragy/models/saved_run.dart';

void main() {
  test('new saves use the current algorithm version', () {
    final run = SavedRun(
      id: 'new',
      dateTime: DateTime.utc(2026),
      metrics: RaceMetrics(),
    );

    expect(run.algorithmVersion, SavedRun.currentAlgorithmVersion);
    expect(run.toJson()['algorithmVersion'], SavedRun.currentAlgorithmVersion);
  });

  test('legacy JSON without a version remains identifiable as v1', () {
    final run = SavedRun.fromJson({
      'id': 'legacy',
      'dateTime': '2025-01-01T00:00:00.000Z',
      'metrics': RaceMetrics().toJson(),
    });

    expect(run.algorithmVersion, 1);
  });
}
