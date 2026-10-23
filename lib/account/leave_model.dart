import '../domain.dart';
import 'plan_model.dart';

String leaveDate(DateTime day) => planTime(dayOf(day)).substring(0, 10);
String leaveStatus(String value) => switch (value) {
  'pending' => 'Bekliyor',
  'approved' => 'Onaylandı',
  'rejected' => 'Reddedildi',
  _ => 'İptal edildi',
};

class LeaveEvent {
  const LeaveEvent(this.actor, this.status, this.reason, this.at);
  final String actor, status, reason;
  final DateTime at;
  factory LeaveEvent.fromJson(Map<String, dynamic> r) => LeaveEvent(
    r['actor_id'],
    r['status'],
    r['reason'],
    DateTime.parse(r['occurred_at']),
  );
}

class LeaveConflict {
  const LeaveConflict(this.label, this.source, this.start, this.end);
  final String label, source;
  final DateTime start, end;
  factory LeaveConflict.fromJson(Map<String, dynamic> r) => LeaveConflict(
    r['label'],
    r['source'],
    parsePlanTime(r['starts_at']),
    parsePlanTime(r['ends_at']),
  );
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.userId,
    required this.start,
    required this.end,
    this.description = '',
    this.status = 'pending',
    this.revision = 0,
    this.events = const [],
    this.conflicts = const [],
  });
  final String id, userId, description, status;
  final DateTime start, end;
  final int revision;
  final List<LeaveEvent> events;
  final List<LeaveConflict> conflicts;
  factory LeaveRequest.fromJson(Map<String, dynamic> r) => LeaveRequest(
    id: r['id'],
    userId: r['user_id'],
    start: parsePlanTime(r['starts_on']),
    end: parsePlanTime(r['ends_on']),
    description: r['description'],
    status: r['status'],
    revision: (r['revision'] as num).toInt(),
    events: List.unmodifiable(
      (r['events'] as List).map(
        (e) => LeaveEvent.fromJson(Map<String, dynamic>.from(e)),
      ),
    ),
    conflicts: List.unmodifiable(
      (r['conflicts'] as List).map(
        (e) => LeaveConflict.fromJson(Map<String, dynamic>.from(e)),
      ),
    ),
  );
}

class LeaveInbox {
  const LeaveInbox(this.version, this.requests);
  final int version;
  final List<LeaveRequest> requests;
  factory LeaveInbox.fromJson(Map<String, dynamic> r) => LeaveInbox(
    (r['version'] as num).toInt(),
    List.unmodifiable(
      (r['requests'] as List).map(
        (x) => LeaveRequest.fromJson(Map<String, dynamic>.from(x)),
      ),
    ),
  );
}
