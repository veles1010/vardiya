import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vardiya/data.dart';
import 'package:vardiya/domain.dart';

import 'support.dart';

void main() {
  test(
    'first launch seeds once; restart preserves team, records and IDs',
    () async {
      final prefs = MemoryPreferences();
      final store = await testStore(preferences: prefs);
      await store.saveTeam(const Team(id: 'new-team', name: 'Yeni ekip'));
      await store.deleteShift('p1', personal: true);
      final writes = prefs.writes;
      final reopened = await testStore(
        preferences: prefs,
        now: DateTime.utc(2027),
      );
      expect(reopened.data.teams.last.name, 'Yeni ekip');
      expect(reopened.data.personal.any((s) => s.id == 'p1'), isFalse);
      expect(reopened.data.toJson(), store.data.toJson());
      expect(prefs.writes, writes);
    },
  );
  test('empty saved dataset is not reseeded', () async {
    final prefs = MemoryPreferences();
    prefs.values[LocalScheduleRepository.storageKey] = jsonEncode(
      AppData().toJson(),
    );
    final store = await testStore(preferences: prefs);
    expect(store.data.personal, isEmpty);
    expect(prefs.writes, 0);
  });
  test('corrupt and unknown version data never overwritten', () async {
    for (final raw in ['broken-json', '{"schemaVersion":99}']) {
      final prefs = MemoryPreferences();
      prefs.values[LocalScheduleRepository.storageKey] = raw;
      await expectLater(
        testStore(preferences: prefs),
        throwsA(isA<FormatException>()),
      );
      expect(prefs.values[LocalScheduleRepository.storageKey], raw);
      expect(prefs.writes, 0);
    }
  });
  test('failed save rolls back visible state and allows retry', () async {
    final prefs = MemoryPreferences();
    final store = await testStore(preferences: prefs);
    prefs.failWrites = true;
    await expectLater(
      store.deleteShift('p1', personal: true),
      throwsStateError,
    );
    expect(store.data.personal.any((s) => s.id == 'p1'), isTrue);
    expect(store.busy, isFalse);
    prefs.failWrites = false;
    await store.deleteShift('p1', personal: true);
    expect(store.data.personal.any((s) => s.id == 'p1'), isFalse);
  });
  test(
    'draft edit and deletion remain invisible until republish, across reload',
    () async {
      final prefs = MemoryPreferences();
      final store = await testStore(preferences: prefs);
      final old = store.data.draft.first;
      final changed = Shift(
        id: old.id,
        start: old.start,
        end: old.end,
        breakMinutes: 90,
        label: 'Güncellenen',
        note: 'Yeni not',
        employeeId: old.employeeId,
        teamId: old.teamId,
      );
      await store.saveShift(changed, personal: false);
      expect(store.data.forEmployee('e1').first.label, old.label);
      expect(store.hasUnpublishedChanges('t1'), isTrue);
      var reopened = await testStore(preferences: prefs);
      expect(reopened.data.forEmployee('e1').first.note, old.note);
      await reopened.publishTeam('t1');
      expect(reopened.data.forEmployee('e1').first.note, 'Yeni not');
      expect(reopened.hasUnpublishedChanges('t1'), isFalse);
      await reopened.deleteShift(old.id, personal: false);
      expect(
        reopened.data.forEmployee('e1').any((s) => s.id == old.id),
        isTrue,
      );
      await reopened.publishTeam('t1');
      reopened = await testStore(preferences: prefs);
      expect(
        reopened.data.forEmployee('e1').any((s) => s.id == old.id),
        isFalse,
      );
    },
  );
  test(
    'new draft only visible to selected employee after publication',
    () async {
      final store = await testStore();
      final s = timedShift(
        id: 'new',
        date: DateTime.utc(2026, 11, 5),
        startMinute: 480,
        endMinute: 960,
        nextDay: false,
        breakMinutes: 30,
        employeeId: 'e2',
        teamId: 't1',
      );
      await store.saveShift(s, personal: false);
      expect(store.data.forEmployee('e2').any((s) => s.id == 'new'), isFalse);
      await store.publishTeam('t1');
      expect(store.data.forEmployee('e2').any((s) => s.id == 'new'), isTrue);
      expect(
        store.data.forEmployee('e1').every((s) => s.employeeId == 'e1'),
        isTrue,
      );
      expect(store.data.forEmployee('missing'), isEmpty);
      expect(store.data.personal.any((s) => s.id == 'new'), isFalse);
    },
  );
  test('deactivation preserves history and rejects new assignments', () async {
    final store = await testStore();
    final before = store.data.forEmployee('e1').length;
    await store.saveEmployee(
      const Employee(id: 'e1', teamId: 't1', name: 'Yeni isim', active: false),
    );
    expect(store.data.forEmployee('e1').length, before);
    final s = timedShift(
      id: 'new',
      date: DateTime.utc(2026, 11, 5),
      startMinute: 480,
      endMinute: 960,
      nextDay: false,
      breakMinutes: 30,
      employeeId: 'e1',
      teamId: 't1',
    );
    await expectLater(
      store.saveShift(s, personal: false),
      throwsA(isA<RuleViolation>()),
    );
  });
  test(
    'personal records are separate and cannot contain employee identities',
    () async {
      final store = await testStore();
      final s = store.data.draft.first;
      await expectLater(
        store.saveShift(s, personal: true),
        throwsA(isA<RuleViolation>()),
      );
      expect(store.data.personal.every((s) => s.employeeId == null), isTrue);
    },
  );
  test('store rejects overlapping assignments before storage', () async {
    final prefs = MemoryPreferences();
    final store = await testStore(preferences: prefs);
    final old = store.data.draft.first;
    final writes = prefs.writes;
    final s = Shift(
      id: 'clash',
      start: old.start,
      end: old.end,
      employeeId: old.employeeId,
      teamId: old.teamId,
    );
    await expectLater(
      store.saveShift(s, personal: false),
      throwsA(isA<RuleViolation>()),
    );
    expect(prefs.writes, writes);
  });
  test('publishing one team preserves another team snapshot', () async {
    final store = await testStore();
    await store.saveTeam(const Team(id: 't2', name: 'İkinci'));
    await store.saveEmployee(
      const Employee(id: 'e4', teamId: 't2', name: 'Ada'),
    );
    final s = timedShift(
      id: 'other',
      date: DateTime.utc(2026, 11, 5),
      startMinute: 480,
      endMinute: 960,
      nextDay: false,
      breakMinutes: 30,
      employeeId: 'e4',
      teamId: 't2',
    );
    await store.saveShift(s, personal: false);
    await store.publishTeam('t2');
    await store.deleteShift('other', personal: false);
    await store.publishTeam('t1');
    expect(store.data.forEmployee('e4').single.id, 'other');
  });
  test('template editing does not mutate existing assignments', () async {
    final store = await testStore();
    final before = store.data.draft.first.toJson();
    await store.saveTemplate(
      const ShiftTemplate(
        id: 'morning',
        name: 'Erken',
        startMinute: 360,
        endMinute: 840,
        breakMinutes: 15,
      ),
    );
    expect(store.data.draft.first.toJson(), before);
  });
}
