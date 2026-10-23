import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain.dart';

abstract interface class ScheduleRepository {
  Future<AppData?> load();
  Future<void> save(AppData data);
}

class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const storageKey = 'vardiya.data.v1';
  @override
  Future<AppData?> load() async {
    final raw = await _preferences.getString(storageKey);
    return raw == null
        ? null
        : AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(AppData data) =>
      _preferences.setString(storageKey, jsonEncode(data.toJson()));
}

class ScheduleStore extends ChangeNotifier {
  ScheduleStore(this.repository);
  final ScheduleRepository repository;
  AppData _data = AppData();
  AppData get data => _data;
  bool busy = false;
  Future<void> initialize({DateTime? now}) async {
    final saved = await repository.load();
    if (saved != null) {
      _data = saved;
    } else {
      final seed = seedDemo(now ?? DateTime.now());
      await repository.save(seed);
      _data = seed;
    }
    notifyListeners();
  }

  Future<void> _commit(AppData Function(AppData) change) async {
    if (busy) {
      throw const RuleViolation(
        'Kayıt sürüyor; lütfen tamamlanmasını bekleyin.',
      );
    }
    busy = true;
    notifyListeners();
    try {
      final next = change(_data);
      await repository.save(next);
      _data = next;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> saveTeam(Team team) => _commit((d) {
    if (team.name.trim().isEmpty) {
      throw const RuleViolation('Ekip adı gerekli.');
    }
    return d.copyWith(teams: [...d.teams.where((t) => t.id != team.id), team]);
  });
  Future<void> saveEmployee(Employee employee) => _commit((d) {
    if (employee.name.trim().isEmpty) {
      throw const RuleViolation('Çalışan adı gerekli.');
    }
    if (!d.teams.any((t) => t.id == employee.teamId)) {
      throw const RuleViolation('Ekip bulunamadı.');
    }
    return d.copyWith(
      employees: [...d.employees.where((e) => e.id != employee.id), employee],
    );
  });
  Future<void> saveTemplate(ShiftTemplate template) => _commit((d) {
    timedShift(
      id: template.id,
      date: DateTime.utc(2026),
      startMinute: template.startMinute,
      endMinute: template.endMinute,
      nextDay: template.nextDay,
      breakMinutes: template.breakMinutes,
      label: template.name,
    );
    return d.copyWith(
      templates: [...d.templates.where((t) => t.id != template.id), template],
    );
  });
  Future<void> saveShift(Shift shift, {required bool personal}) => _commit((d) {
    if (personal) {
      if (shift.employeeId != null || shift.teamId != null) {
        throw const RuleViolation('Kişisel kayıt ekip ataması olamaz.');
      }
      checkConflicts(shift, d.personal);
      return d.copyWith(
        personal: [...d.personal.where((s) => s.id != shift.id), shift],
      );
    }
    final employees = d.employees.where(
      (e) => e.id == shift.employeeId && e.teamId == shift.teamId,
    );
    if (employees.isEmpty) {
      throw const RuleViolation('Geçerli bir çalışan seçin.');
    }
    if (!employees.first.active &&
        !d.draft.any(
          (s) => s.id == shift.id && s.employeeId == shift.employeeId,
        )) {
      throw const RuleViolation('Pasif çalışana yeni vardiya atanamaz.');
    }
    if (shift.kind != EntryKind.work) {
      throw const RuleViolation('Ekip planına vardiya ekleyin.');
    }
    checkConflicts(shift, d.draft);
    return d.copyWith(
      draft: [...d.draft.where((s) => s.id != shift.id), shift],
    );
  });
  Future<void> deleteShift(String id, {required bool personal}) => _commit(
    (d) => personal
        ? d.copyWith(personal: d.personal.where((s) => s.id != id).toList())
        : d.copyWith(draft: d.draft.where((s) => s.id != id).toList()),
  );

  // Full team snapshot, all dates, including deletions. Shift values immutable.
  Future<void> publishTeam(String teamId) => _commit((d) {
    if (!d.teams.any((t) => t.id == teamId)) {
      throw const RuleViolation('Ekip bulunamadı.');
    }
    final teamDraft = d.draft.where((s) => s.teamId == teamId).toList();
    for (final shift in teamDraft) {
      checkConflicts(shift, d.draft);
    }
    return d.copyWith(
      published: [
        ...d.published.where((s) => s.teamId != teamId),
        ...teamDraft,
      ],
      publishedAt: {
        ...d.publishedAt,
        teamId: DateTime.now().toUtc().toIso8601String(),
      },
    );
  });
  bool hasUnpublishedChanges(String teamId) {
    List<String> snapshot(List<Shift> values) =>
        values
            .where((s) => s.teamId == teamId)
            .map((s) => jsonEncode(s.toJson()))
            .toList()
          ..sort();
    return !listEquals(snapshot(data.draft), snapshot(data.published));
  }
}
