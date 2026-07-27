import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/run_id.dart';

void main() {
  test('format uses local date and time', () {
    expect(
      RunId.format(DateTime(2026, 7, 27, 5, 41, 53)),
      '2026-07-27_05-41-53',
    );
  });

  test('allocate avoids collisions within the same second', () {
    final dt = DateTime(2026, 7, 27, 5, 41, 53);
    expect(
      RunId.allocate(dt, const ['2026-07-27_05-41-53']),
      '2026-07-27_05-41-53-2',
    );
  });
}
