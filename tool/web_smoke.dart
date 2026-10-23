// A dart2js regression check for JavaScript's 32-bit bitwise semantics.
// Run the compiled output with tool/run_web_smoke.cjs.
import 'package:vardiya/domain.dart';

void main() {
  final ids = List.generate(1000, (_) => newId()).toSet();
  if (ids.length != 1000) {
    throw StateError('IDs must be distinct.');
  }
  final shift = timedShift(
    id: newId(),
    date: DateTime.utc(2026, 10, 31),
    startMinute: 1320,
    endMinute: 360,
    nextDay: true,
    breakMinutes: 60,
  );
  if (shift.netInPeriod(DateTime.utc(2026, 10), DateTime.utc(2026, 11)) !=
          105 ||
      shift.netInPeriod(DateTime.utc(2026, 11), DateTime.utc(2026, 12)) !=
          315) {
    throw StateError('Period split must conserve the net duration.');
  }
  final copy = Shift.fromJson(shift.toJson());
  if (copy.id != shift.id || copy.end != shift.end || copy.netMinutes != 420) {
    throw StateError('JSON round trip failed.');
  }
  // CLI regression runner: this line is its success report.
  // ignore: avoid_print
  print(
    'PASS: dart2js IDs (1000), overnight period totals and JSON round trip.',
  );
}
