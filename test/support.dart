import 'package:shared_preferences/shared_preferences.dart';
import 'package:vardiya/data.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  final counters = <String, int>{'writes': 0, 'fail': 0};
  bool get failWrites => counters['fail'] == 1;
  set failWrites(bool value) => counters['fail'] = value ? 1 : 0;
  int get writes => counters['writes']!;
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) {
      throw StateError('disk full');
    }
    values[key] = value;
    counters['writes'] = writes + 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ScheduleStore> testStore({
  MemoryPreferences? preferences,
  DateTime? now,
}) async {
  final store = ScheduleStore(
    LocalScheduleRepository(preferences: preferences ?? MemoryPreferences()),
  );
  await store.initialize(now: now ?? DateTime.utc(2026, 10, 22));
  return store;
}
