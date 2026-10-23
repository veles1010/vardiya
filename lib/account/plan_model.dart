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
  });
  final int version;
  final int? publishedVersion;
  final List<Shift> shifts;
  factory CloudPlan.fromJson(Map<String, dynamic> data) {
    if (data['time_zone'] != 'Europe/Istanbul') {
      throw const FormatException('Unsupported team timezone');
    }
    return CloudPlan(
      version: (data['version'] as num).toInt(),
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
