/// Which BMI160 axis points along the car (forward/back) after mounting.
enum ImuLongAxis {
  x,
  y,
  z,
}

extension ImuLongAxisX on ImuLongAxis {
  String get shortLabel => name.toUpperCase();

  String get description {
    switch (this) {
      case ImuLongAxis.x:
        return 'X axis along car';
      case ImuLongAxis.y:
        return 'Y axis along car (default)';
      case ImuLongAxis.z:
        return 'Z axis along car';
    }
  }
}

/// Map raw accel (g) to longitudinal forward-positive G for the timed run UI.
double longitudinalG({
  required double ax,
  required double ay,
  required double az,
  required ImuLongAxis axis,
  required bool invert,
}) {
  final raw = switch (axis) {
    ImuLongAxis.x => ax,
    ImuLongAxis.y => ay,
    ImuLongAxis.z => az,
  };
  return invert ? -raw : raw;
}
