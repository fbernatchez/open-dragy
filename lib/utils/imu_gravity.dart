/// Gravity reference captured while stationary (e.g. during ARM).
class GravityVector {
  final double x;
  final double y;
  final double z;

  const GravityVector(this.x, this.y, this.z);

  static GravityVector? average(Iterable<GravityVector> samples) {
    final list = samples.toList(growable: false);
    if (list.isEmpty) return null;
    var sumX = 0.0;
    var sumY = 0.0;
    var sumZ = 0.0;
    for (final sample in list) {
      sumX += sample.x;
      sumY += sample.y;
      sumZ += sample.z;
    }
    final n = list.length;
    return GravityVector(sumX / n, sumY / n, sumZ / n);
  }
}

/// Linear acceleration after subtracting a gravity reference (sensor frame).
class LinearAcceleration {
  final double x;
  final double y;
  final double z;

  const LinearAcceleration(this.x, this.y, this.z);

  factory LinearAcceleration.fromRaw({
    required double ax,
    required double ay,
    required double az,
    GravityVector? gravity,
  }) {
    if (gravity == null) {
      return LinearAcceleration(ax, ay, az);
    }
    return LinearAcceleration(
      ax - gravity.x,
      ay - gravity.y,
      az - gravity.z,
    );
  }
}