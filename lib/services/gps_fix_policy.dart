/// Minimum validity gate for samples that are allowed into timing physics.
class GpsFixPolicy {
  static bool accepts({
    required bool valid,
    required int fixType,
    required int satellites,
    required bool usedPvt,
  }) {
    return valid && usedPvt && fixType >= 3 && satellites >= 4;
  }
}
