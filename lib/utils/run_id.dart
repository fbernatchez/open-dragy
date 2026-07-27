/// Human-readable, filesystem-safe run identifiers (local date/time).
class RunId {
  RunId._();

  /// e.g. `2026-07-27_05-41-53` (local time, sortable).
  static String format(DateTime dateTime) {
    final local = dateTime.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}_'
        '${two(local.hour)}-${two(local.minute)}-${two(local.second)}';
  }

  /// Picks [format] or appends `-2`, `-3`, … when the same second already exists.
  static String allocate(DateTime dateTime, Iterable<String> existingIds) {
    final taken = existingIds.toSet();
    final base = format(dateTime);
    if (!taken.contains(base)) return base;
    for (var i = 2; i < 100; i++) {
      final candidate = '$base-$i';
      if (!taken.contains(candidate)) return candidate;
    }
    return '${base}_${dateTime.millisecondsSinceEpoch}';
  }
}
