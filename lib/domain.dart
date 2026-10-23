import 'dart:math';

// Turkish civil times occupy UTC fields; never convert schedules with toLocal().
DateTime dayOf(DateTime v) => DateTime.utc(v.year, v.month, v.day);
DateTime weekOf(DateTime v) => dayOf(v).subtract(Duration(days: v.weekday - 1));
DateTime monthOf(DateTime v) => DateTime.utc(v.year, v.month);
String newId() =>
    // Keep the bound literal: a 32-bit shift truncates to zero on Dart web.
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

class RuleViolation implements Exception {
  const RuleViolation(this.message);
  final String message;
  @override
  String toString() => message;
}

enum EntryKind { work, leave, rest }

class Team {
  const Team({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Team.fromJson(Map<String, dynamic> j) =>
      Team(id: j['id'], name: j['name']);
}

class Employee {
  const Employee({
    required this.id,
    required this.teamId,
    required this.name,
    this.role = '',
    this.active = true,
  });
  final String id;
  final String teamId;
  final String name;
  final String role;
  final bool active;
  Map<String, dynamic> toJson() => {
    'id': id,
    'teamId': teamId,
    'name': name,
    'role': role,
    'active': active,
  };
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id: j['id'],
    teamId: j['teamId'],
    name: j['name'],
    role: j['role'],
    active: j['active'],
  );
}

class ShiftTemplate {
  const ShiftTemplate({
    required this.id,
    required this.name,
    required this.startMinute,
    required this.endMinute,
    required this.breakMinutes,
    this.nextDay = false,
  });
  final String id;
  final String name;
  final int startMinute;
  final int endMinute;
  final int breakMinutes;
  final bool nextDay;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'breakMinutes': breakMinutes,
    'nextDay': nextDay,
  };
  factory ShiftTemplate.fromJson(Map<String, dynamic> j) => ShiftTemplate(
    id: j['id'],
    name: j['name'],
    startMinute: j['startMinute'],
    endMinute: j['endMinute'],
    breakMinutes: j['breakMinutes'],
    nextDay: j['nextDay'],
  );
}

class Shift {
  const Shift({
    required this.id,
    required this.start,
    required this.end,
    this.breakMinutes = 0,
    this.kind = EntryKind.work,
    this.label = 'Vardiya',
    this.note = '',
    this.employeeId,
    this.teamId,
  });
  final String id;
  final DateTime start;
  final DateTime end;
  final int breakMinutes;
  final EntryKind kind;
  final String label;
  final String note;
  final String? employeeId;
  final String? teamId;
  double get grossMinutes =>
      end.difference(start).inMicroseconds / Duration.microsecondsPerMinute;
  double get netMinutes =>
      kind == EntryKind.work ? grossMinutes - breakMinutes : 0;
  bool overlaps(Shift other) =>
      start.isBefore(other.end) && other.start.isBefore(end);
  bool intersects(DateTime from, DateTime until) =>
      start.isBefore(until) && end.isAfter(from);

  // Allocate unpaid break uniformly. Round only the displayed aggregate.
  double netInPeriod(DateTime from, DateTime until) {
    if (kind != EntryKind.work ||
        !intersects(from, until) ||
        !until.isAfter(from)) {
      return 0;
    }
    final left = start.isAfter(from) ? start : from;
    final right = end.isBefore(until) ? end : until;
    return netMinutes *
        right.difference(left).inMicroseconds /
        end.difference(start).inMicroseconds;
  }

  void validate() {
    if (!end.isAfter(start)) {
      throw const RuleViolation(
        'Bitiş başlangıçtan sonra olmalı. Gece vardiyası için “Ertesi gün biter” seçeneğini açın.',
      );
    }
    if (breakMinutes < 0 || breakMinutes > grossMinutes) {
      throw const RuleViolation(
        'Mola 0 ile vardiyanın toplam süresi arasında olmalı.',
      );
    }
    if (label.trim().isEmpty) {
      throw const RuleViolation('Kayıt adı boş bırakılamaz.');
    }
    if (kind != EntryKind.work && breakMinutes != 0) {
      throw const RuleViolation('İzin ve dinlenme gününe mola eklenemez.');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'breakMinutes': breakMinutes,
    'kind': kind.name,
    'label': label,
    'note': note,
    'employeeId': employeeId,
    'teamId': teamId,
  };
  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
    id: j['id'],
    start: DateTime.parse(j['start']),
    end: DateTime.parse(j['end']),
    breakMinutes: j['breakMinutes'],
    kind: EntryKind.values.byName(j['kind']),
    label: j['label'],
    note: j['note'],
    employeeId: j['employeeId'],
    teamId: j['teamId'],
  );
}

Shift timedShift({
  required String id,
  required DateTime date,
  required int startMinute,
  required int endMinute,
  required bool nextDay,
  required int breakMinutes,
  String label = 'Vardiya',
  String note = '',
  String? employeeId,
  String? teamId,
}) {
  if (startMinute < 0 ||
      startMinute >= 1440 ||
      endMinute < 0 ||
      endMinute >= 1440) {
    throw const RuleViolation('Saat 00:00–23:59 aralığında olmalı.');
  }
  final shift = Shift(
    id: id,
    start: dayOf(date).add(Duration(minutes: startMinute)),
    end: dayOf(date).add(Duration(days: nextDay ? 1 : 0, minutes: endMinute)),
    breakMinutes: breakMinutes,
    label: label,
    note: note,
    employeeId: employeeId,
    teamId: teamId,
  );
  shift.validate();
  return shift;
}

String conflictDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void checkConflicts(Shift candidate, Iterable<Shift> existing) {
  candidate.validate();
  for (final other in existing) {
    if (other.id != candidate.id &&
        other.employeeId == candidate.employeeId &&
        other.overlaps(candidate)) {
      throw RuleViolation(
        'Bu zaman aralığı “${other.label}” kaydıyla (${conflictDateTime(other.start)} – ${conflictDateTime(other.end)}) çakışıyor. Önceki günden devam eden vardiyaları da kontrol edin.',
      );
    }
  }
}

double netTotal(Iterable<Shift> shifts, DateTime from, DateTime until) =>
    shifts.fold(0.0, (sum, shift) => sum + shift.netInPeriod(from, until));

class AppData {
  AppData({
    List<Team> teams = const [],
    List<Employee> employees = const [],
    List<ShiftTemplate> templates = const [],
    List<Shift> personal = const [],
    List<Shift> draft = const [],
    List<Shift> published = const [],
    Map<String, String> publishedAt = const {},
  }) : teams = List.unmodifiable(teams),
       employees = List.unmodifiable(employees),
       templates = List.unmodifiable(templates),
       personal = List.unmodifiable(personal),
       draft = List.unmodifiable(draft),
       published = List.unmodifiable(published),
       publishedAt = Map.unmodifiable(publishedAt);
  final List<Team> teams;
  final List<Employee> employees;
  final List<ShiftTemplate> templates;
  final List<Shift> personal;
  final List<Shift> draft;
  final List<Shift> published;
  final Map<String, String> publishedAt;
  AppData copyWith({
    List<Team>? teams,
    List<Employee>? employees,
    List<ShiftTemplate>? templates,
    List<Shift>? personal,
    List<Shift>? draft,
    List<Shift>? published,
    Map<String, String>? publishedAt,
  }) => AppData(
    teams: teams ?? this.teams,
    employees: employees ?? this.employees,
    templates: templates ?? this.templates,
    personal: personal ?? this.personal,
    draft: draft ?? this.draft,
    published: published ?? this.published,
    publishedAt: publishedAt ?? this.publishedAt,
  );
  List<Shift> forEmployee(String id) =>
      published.where((s) => s.employeeId == id).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'teams': teams.map((e) => e.toJson()).toList(),
    'employees': employees.map((e) => e.toJson()).toList(),
    'templates': templates.map((e) => e.toJson()).toList(),
    'personal': personal.map((e) => e.toJson()).toList(),
    'draft': draft.map((e) => e.toJson()).toList(),
    'published': published.map((e) => e.toJson()).toList(),
    'publishedAt': publishedAt,
  };
  factory AppData.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1) {
      throw const FormatException('Desteklenmeyen veri sürümü.');
    }
    return AppData(
      teams: (j['teams'] as List).map((e) => Team.fromJson(e)).toList(),
      employees: (j['employees'] as List)
          .map((e) => Employee.fromJson(e))
          .toList(),
      templates: (j['templates'] as List)
          .map((e) => ShiftTemplate.fromJson(e))
          .toList(),
      personal: (j['personal'] as List).map((e) => Shift.fromJson(e)).toList(),
      draft: (j['draft'] as List).map((e) => Shift.fromJson(e)).toList(),
      published: (j['published'] as List)
          .map((e) => Shift.fromJson(e))
          .toList(),
      publishedAt: Map<String, String>.from(j['publishedAt']),
    );
  }
}

AppData seedDemo(DateTime now) {
  final monday = weekOf(now);
  const templates = [
    ShiftTemplate(
      id: 'morning',
      name: 'Sabah',
      startMinute: 480,
      endMinute: 960,
      breakMinutes: 30,
    ),
    ShiftTemplate(
      id: 'evening',
      name: 'Akşam',
      startMinute: 840,
      endMinute: 1320,
      breakMinutes: 45,
    ),
    ShiftTemplate(
      id: 'night',
      name: 'Gece',
      startMinute: 1320,
      endMinute: 360,
      breakMinutes: 60,
      nextDay: true,
    ),
  ];
  const people = [
    Employee(
      id: 'e1',
      teamId: 't1',
      name: 'Deniz Yılmaz',
      role: 'Ekip sorumlusu',
    ),
    Employee(id: 'e2', teamId: 't1', name: 'Ece Demir', role: 'Operasyon'),
    Employee(id: 'e3', teamId: 't1', name: 'Mert Kaya', role: 'Operasyon'),
  ];
  final draft = <Shift>[];
  for (var person = 0; person < people.length; person++) {
    for (var day = 0; day < 5; day++) {
      final t = templates[person];
      draft.add(
        timedShift(
          id: 'demo-$person-$day',
          date: monday.add(Duration(days: day)),
          startMinute: t.startMinute,
          endMinute: t.endMinute,
          nextDay: t.nextDay,
          breakMinutes: t.breakMinutes,
          employeeId: people[person].id,
          teamId: 't1',
          label: t.name,
          note: day == 0 ? 'Haftalık ekip buluşması' : '',
        ),
      );
    }
  }
  final today = dayOf(now);
  return AppData(
    teams: const [Team(id: 't1', name: 'Merkez Operasyon')],
    employees: people,
    templates: templates,
    draft: draft,
    published: draft,
    publishedAt: {'t1': now.toUtc().toIso8601String()},
    personal: [
      timedShift(
        id: 'p1',
        date: today,
        startMinute: 540,
        endMinute: 1020,
        nextDay: false,
        breakMinutes: 30,
        label: 'Gündüz',
        note: 'Kişisel planım',
      ),
      timedShift(
        id: 'p2',
        date: today.add(const Duration(days: 1)),
        startMinute: 1320,
        endMinute: 360,
        nextDay: true,
        breakMinutes: 60,
        label: 'Gece',
      ),
      Shift(
        id: 'p3',
        start: today.add(const Duration(days: 3)),
        end: today.add(const Duration(days: 4)),
        kind: EntryKind.rest,
        label: 'Dinlenme',
      ),
      Shift(
        id: 'p4',
        start: today.add(const Duration(days: 5)),
        end: today.add(const Duration(days: 6)),
        kind: EntryKind.leave,
        label: 'İzin',
      ),
    ],
  );
}
