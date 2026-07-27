/// File layout for saved drag runs under `/OpenDragy/runs/`.
///
/// One folder per run; timestamp stays in folder name **and** in each file
/// so GPS/IMU CSVs stay identifiable when copied together for comparison.
class RunFileNames {
  RunFileNames._();

  /// e.g. `2026-07-27_05-41-53`
  static String runDirectory(String runId) => runId;

  static String metricsFileBase(String runId) => '$runId.json';

  static String gpsFileBase(String runId) => '${runId}_gps.csv';

  static String imuFileBase(String runId) => '${runId}_imu.csv';

  static String metricsJson(String runId) =>
      '${runDirectory(runId)}/${metricsFileBase(runId)}';

  static String gpsCsv(String runId) =>
      '${runDirectory(runId)}/${gpsFileBase(runId)}';

  static String imuCsv(String runId) =>
      '${runDirectory(runId)}/${imuFileBase(runId)}';

  /// File names that may exist inside `{runId}/` from older builds.
  static List<String> legacyInnerMetricsNames(String runId) => [
        metricsFileBase(runId),
        'run.json',
      ];

  static List<String> legacyInnerGpsNames(String runId) => [
        gpsFileBase(runId),
        'gps.csv',
      ];

  static List<String> legacyInnerImuNames(String runId) => [
        imuFileBase(runId),
        'imu.csv',
      ];

  /// Flat layout at `runs/` root (no per-run folder).
  static String legacyFlatMetricsJson(String runId) => '$runId.json';

  static String legacyFlatGpsCsv(String runId) => '${runId}_gps.csv';

  static String legacyFlatImuCsv(String runId) => '${runId}_imu.csv';

  /// Basename of a path/URI. Skips empty segments from trailing `/`.
  static String baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((s) => s.isNotEmpty);
    return parts.isNotEmpty ? parts.last : path;
  }
}
