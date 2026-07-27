/// File names for saved run artifacts under `/OpenDragy/runs/`.
///
/// Timestamp/run id is a **prefix** so pairs sort together and chronologically:
/// `2026-07-27_05-41-53_gps.csv` next to `2026-07-27_05-41-53_imu.csv`.
class RunFileNames {
  RunFileNames._();

  static String metricsJson(String runId) => '$runId.json';

  static String gpsCsv(String runId) => '${runId}_gps.csv';

  static String imuCsv(String runId) => '${runId}_imu.csv';

  /// Legacy layout before timestamped CSV names.
  static String legacyGpsCsv(String runId) => '$runId/gps.csv';

  static String legacyImuCsv(String runId) => '$runId/imu.csv';
}
