import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/run_file_names.dart';

void main() {
  test('uses one folder per run with run id in each file name', () {
    const id = '2026-07-27_05-41-53';
    expect(RunFileNames.runDirectory(id), id);
    expect(RunFileNames.metricsJson(id), '2026-07-27_05-41-53/2026-07-27_05-41-53.json');
    expect(RunFileNames.gpsCsv(id), '2026-07-27_05-41-53/2026-07-27_05-41-53_gps.csv');
    expect(RunFileNames.imuCsv(id), '2026-07-27_05-41-53/2026-07-27_05-41-53_imu.csv');
  });
}
