/// File layout for saved drag runs under `/OpenDragy/runs/`.
///
/// One folder per run (timestamp = folder name). Sensor files use short names
/// inside the folder — same idea as `.odpkg` (`manifest.json` + `gps.csv`).
class RunFileNames {
  RunFileNames._();

  static const metricsFileName = 'run.json';
  static const gpsFileName = 'gps.csv';
  static const imuFileName = 'imu.csv';

  /// e.g. `2026-07-27_05-41-53`
  static String runDirectory(String runId) => runId;

  static String metricsJson(String runId) => '$runId/$metricsFileName';

  static String gpsCsv(String runId) => '$runId/$gpsFileName';

  static String imuCsv(String runId) => '$runId/$imuFileName';

  /// Flat layout (JSON at runs root, CSV prefixed).
  static String legacyFlatMetricsJson(String runId) => '$runId.json';

  static String legacyFlatGpsCsv(String runId) => '${runId}_gps.csv';

  static String legacyFlatImuCsv(String runId) => '${runId}_imu.csv';
}
