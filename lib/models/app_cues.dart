/// Milestone audio style when cues are enabled.
enum AudioCueMode {
  beep,
  voice,
}

/// On-screen cue when the selected drag/interval target finishes.
/// Shown only while the app is in the foreground (display on).
enum FinishCelebrationMode {
  off,
  flash,
  checkered,
}

/// Optional intermediate audio cues (selected drag/interval finish is always on).
enum OptionalAudioMilestone {
  sixtyFeet('60ft', '60 ft'),
  threeThirty('330ft', '330 ft'),
  zeroFifty('0-50kmh', '0–50 km/h'),
  /// Covers 0–100 km/h or 0–60 mph depending on units.
  speedMark('speed', '0–100 km/h / 0–60 mph'),
  eighth('18mile', '1/8 mile'),
  thousand('1000ft', '1000 ft'),
  quarter('14mile', '1/4 mile'),
  half('12mile', '1/2 mile');

  final String id;
  final String label;
  const OptionalAudioMilestone(this.id, this.label);
}

/// Result rows on dashboard / detail / AA. Engine still computes everything.
enum VisibleResultField {
  sixtyFeet('60ft', '60 ft'),
  threeThirty('330ft', '330 ft'),
  zeroFifty('0-50kmh', '0–50 km/h'),
  zeroSixtyMph('0-60mph', '0–60 mph'),
  zeroOneHundred('0-100kmh', '0–100 km/h'),
  eighth('1/8mile', '1/8 mile'),
  thousand('1000ft', '1000 ft'),
  quarter('1/4mile', '1/4 mile'),
  half('1/2mile', '1/2 mile'),
  zeroTwoHundred('0-200kmh', '0–200 km/h'),
  hundredToTwoHundred('100-200kmh', '100–200 km/h'),
  sixtyToOneThirty('60-130mph', '60–130 mph');

  final String id;
  final String label;
  const VisibleResultField(this.id, this.label);

  bool get isMetricOnly =>
      this == zeroFifty ||
      this == zeroOneHundred ||
      this == zeroTwoHundred ||
      this == hundredToTwoHundred;

  bool get isImperialOnly =>
      this == zeroSixtyMph || this == sixtyToOneThirty;

  /// Defaults: launch + EU speed marks + 1/8 + 1/4; 330/1000/½ off.
  static Set<VisibleResultField> get defaults => {
        sixtyFeet,
        zeroFifty,
        zeroSixtyMph,
        zeroOneHundred,
        eighth,
        quarter,
      };
}
