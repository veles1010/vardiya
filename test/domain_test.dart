import 'package:flutter_test/flutter_test.dart';
import 'package:vardiya/domain.dart';

void main() {
  test('new IDs are distinct and work on web and mobile', () {
    final ids = List.generate(100, (_) => newId());
    expect(ids.toSet().length, 100);
  });
  final date = DateTime.utc(2026, 10, 31);
  Shift make({
    String id = 's',
    DateTime? day,
    int start = 1320,
    int end = 360,
    bool next = true,
    int rest = 60,
    String employee = 'e1',
  }) => timedShift(
    id: id,
    date: day ?? date,
    startMinute: start,
    endMinute: end,
    nextDay: next,
    breakMinutes: rest,
    employeeId: employee,
    teamId: 't1',
  );
  test('22:00–06:00 ends next day and deducts break', () {
    final s = make();
    expect(s.end, DateTime.utc(2026, 11, 1, 6));
    expect(s.grossMinutes, 480);
    expect(s.netMinutes, 420);
  });
  test('equal times require explicit next day', () {
    expect(
      () => make(start: 480, end: 480, next: false),
      throwsA(isA<RuleViolation>()),
    );
    expect(make(start: 480, end: 480, next: true).grossMinutes, 1440);
  });
  test('end before start requires explicit next day', () {
    expect(() => make(next: false), throwsA(isA<RuleViolation>()));
  });
  test('invalid clock components are rejected', () {
    expect(() => make(start: 1440), throwsA(isA<RuleViolation>()));
    expect(() => make(end: -1), throwsA(isA<RuleViolation>()));
  });
  test('negative and oversized break rejected; zero and full allowed', () {
    expect(() => make(rest: -1), throwsA(isA<RuleViolation>()));
    expect(() => make(rest: 481), throwsA(isA<RuleViolation>()));
    expect(make(rest: 480).netMinutes, 0);
    expect(make(rest: 0).netMinutes, 480);
  });
  test('previous night conflicts with early morning assignment', () {
    final next = make(
      id: 's2',
      day: DateTime.utc(2026, 11, 1),
      start: 300,
      end: 600,
      next: false,
    );
    expect(() => checkConflicts(next, [make()]), throwsA(isA<RuleViolation>()));
  });
  test('touching boundaries do not conflict', () {
    final next = make(
      id: 's2',
      day: DateTime.utc(2026, 11, 1),
      start: 360,
      end: 600,
      next: false,
    );
    expect(() => checkConflicts(next, [make()]), returnsNormally);
  });
  test('different employees may overlap and own record may be edited', () {
    expect(
      () => checkConflicts(make(id: 's2', employee: 'e2'), [make()]),
      returnsNormally,
    );
    expect(() => checkConflicts(make(rest: 45), [make()]), returnsNormally);
  });
  test('containment is a conflict in either direction', () {
    final inner = make(id: 'inner', start: 1380, end: 60, rest: 0);
    expect(
      () => checkConflicts(inner, [make()]),
      throwsA(isA<RuleViolation>()),
    );
    expect(
      () => checkConflicts(make(), [inner]),
      throwsA(isA<RuleViolation>()),
    );
  });
  test('month split allocates break proportionally and conserves total', () {
    final s = make();
    final october = s.netInPeriod(
      DateTime.utc(2026, 10),
      DateTime.utc(2026, 11),
    );
    final november = s.netInPeriod(
      DateTime.utc(2026, 11),
      DateTime.utc(2026, 12),
    );
    expect(october, 105);
    expect(november, 315);
    expect(october + november, s.netMinutes);
  });
  test('Sunday overnight split between Monday weeks', () {
    final s = make(day: DateTime.utc(2026, 10, 25));
    expect(
      s.netInPeriod(DateTime.utc(2026, 10, 19), DateTime.utc(2026, 10, 26)),
      105,
    );
    expect(
      s.netInPeriod(DateTime.utc(2026, 10, 26), DateTime.utc(2026, 11, 2)),
      315,
    );
    expect(weekOf(DateTime.utc(2026, 10, 25)), DateTime.utc(2026, 10, 19));
  });
  test('outside or empty periods contribute zero', () {
    final s = make();
    expect(s.netInPeriod(s.end, s.end.add(const Duration(days: 1))), 0);
    expect(s.netInPeriod(s.start, s.start), 0);
    expect(s.netInPeriod(s.end, s.start), 0);
  });
  test('leave and rest contribute no planned work', () {
    for (final kind in [EntryKind.leave, EntryKind.rest]) {
      final s = Shift(
        id: 'leave',
        start: date,
        end: date.add(const Duration(days: 1)),
        kind: kind,
      );
      expect(s.netMinutes, 0);
      expect(s.netInPeriod(date, date.add(const Duration(days: 1))), 0);
    }
  });
  test('fractional minutes remain precise until presentation', () {
    final s = make(rest: 37);
    final split = DateTime.utc(2026, 10, 31, 23, 17);
    expect(
      s.netInPeriod(s.start, split) + s.netInPeriod(split, s.end),
      closeTo(443, .000001),
    );
  });
}
