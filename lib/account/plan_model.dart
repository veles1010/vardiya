import '../domain.dart';

// These are Istanbul civil calendar fields, not UTC instants. Never toLocal().
DateTime parsePlanTime(String value) {
  final d = DateTime.parse(value);
  return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
}

String planTime(DateTime value) =>
    value.toIso8601String().replaceFirst('Z', '');

class CloudPlan {
  const CloudPlan({
    required this.version,
    required this.shifts,
    this.publishedVersion,
    this.leaves = const [],
  });
  final int version;
  final int? publishedVersion;
  final List<Shift> shifts;
  final List<ApprovedLeave> leaves;
  factory CloudPlan.fromJson(Map<String, dynamic> data) {
    if (data['time_zone'] != 'Europe/Istanbul') {
      throw const FormatException('Unsupported team timezone');
    }
    return CloudPlan(
      version: (data['version'] as num).toInt(),
      leaves: List.unmodifiable(
        ((data['leaves'] as List?) ?? []).map(
          (r) => ApprovedLeave.fromJson(Map<String, dynamic>.from(r)),
        ),
      ),
      publishedVersion: (data['published_version'] as num?)?.toInt(),
      shifts: List.unmodifiable(
        (data['shifts'] as List).map(
          (r) => Shift(
            id: r['id'],
            teamId: r['team_id'],
            employeeId: r['user_id'],
            start: parsePlanTime(r['starts_at']),
            end: parsePlanTime(r['ends_at']),
            breakMinutes: r['break_minutes'],
            label: r['label'],
            note: r['note'],
          ),
        ),
      ),
    );
  }
}

class ApprovedLeave {
  const ApprovedLeave(this.id, this.userId, this.start, this.end);
  final String id, userId;
  final DateTime start, end; // inclusive days; not UTC instants
  factory ApprovedLeave.fromJson(Map<String, dynamic> r) => ApprovedLeave(
    r['id'],
    r['user_id'],
    parsePlanTime(r['starts_on']),
    parsePlanTime(r['ends_on']),
  );
  bool contains(DateTime day) =>
      !dayOf(day).isBefore(start) && !dayOf(day).isAfter(end);
  bool intersects(DateTime from, DateTime until) =>
      start.isBefore(until) && end.add(const Duration(days: 1)).isAfter(from);
}
