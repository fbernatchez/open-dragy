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
