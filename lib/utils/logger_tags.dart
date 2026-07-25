/// Parse comma-separated logger tags (trim, drop empties, preserve order).
List<String> parseLoggerTags(String raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(',')) {
    final tag = part.trim();
    if (tag.isEmpty) continue;
    final key = tag.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(tag);
  }
  return out;
}

String formatLoggerTags(List<String> tags) => tags.join(', ');

/// Frequency-desc unique tags; [display] keeps first-seen casing.
List<String> rankTagsByFrequency(Iterable<List<String>> tagLists) {
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final tags in tagLists) {
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => trimmed);
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return display[a]!.toLowerCase().compareTo(display[b]!.toLowerCase());
    });
  return keys.map((k) => display[k]!).toList();
}

bool sessionMatchesTagFilter(List<String> sessionTags, Set<String> selectedLower) {
  if (selectedLower.isEmpty) return true;
  for (final tag in sessionTags) {
    if (selectedLower.contains(tag.trim().toLowerCase())) return true;
  }
  return false;
}
