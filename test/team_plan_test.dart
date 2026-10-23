import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vardiya/account/account_service.dart';
import 'package:vardiya/account/plan_model.dart';
import 'package:vardiya/account/team_plan_page.dart';
import 'package:vardiya/domain.dart';
import 'package:vardiya/main.dart';

import 'support.dart';

import 'account_test.dart' show FakeAccountGateway, config;
import 'invitation_test.dart' show click;

Shift shift({String id = 'shift', String user = 'a', String name = 'Gece'}) =>
    Shift(
      id: id,
      teamId: 'team',
      employeeId: user,
      label: name,
      start: DateTime.utc(2026, 10, 25, 22),
      end: DateTime.utc(2026, 10, 26, 6),
      breakMinutes: 60,
    );

class PlanGateway extends FakeAccountGateway {
  CloudPlan draft = CloudPlan(version: 0, shifts: [shift()]);
  CloudPlan published = const CloudPlan(version: 0, shifts: []);
  Future<CloudPlan>? delayed;
  Object? planError;
  bool? requestedDraft;
  int reads = 0, saves = 0;
  String role = 'owner';
  @override
  Future<List<CloudTeam>> teams() async => [
    CloudTeam('team', 'Gerçek ekip', role: role),
  ];
  @override
  Future<List<CloudMember>> members(String teamId) async => const [
    CloudMember('a', 'uzun-calisan-adi-test@example.invalid', 'owner'),
    CloudMember('b', 'b@example.invalid', 'employee'),
  ];
  @override
  Future<CloudPlan> readPlan(String teamId, {required bool draft}) async {
    reads++;
    requestedDraft = draft;
    return delayed ?? Future.value(draft ? this.draft : published);
  }

  @override
  Future<void> saveShift(
    String teamId,
    int version,
    Shift s, {
    required bool creating,
  }) async {
    if (planError != null) throw planError!;
    if (version != draft.version) {
      throw const PostgrestException(message: 'stale', code: '40001');
    }
    saves++;
    draft = CloudPlan(
      version: version + 1,
      publishedVersion: draft.publishedVersion,
      shifts: [...draft.shifts.where((x) => x.id != s.id), s],
    );
  }

  @override
  Future<void> deleteShift(String teamId, int version, String shiftId) async {
    draft = CloudPlan(
      version: version + 1,
      publishedVersion: draft.publishedVersion,
      shifts: draft.shifts.where((s) => s.id != shiftId).toList(),
    );
  }

  @override
  Future<void> publishPlan(String teamId, int version) async {
    published = CloudPlan(
      version: version + 1,
      publishedVersion: version + 1,
      shifts: List.of(draft.shifts),
    );
    draft = CloudPlan(
      version: version + 1,
      publishedVersion: version + 1,
      shifts: draft.shifts,
    );
  }
}

Future<AccountController> setup(PlanGateway g) async {
  g.initial = const AccountIdentity('a', 'a@example.invalid');
  final c = AccountController(g);
  await c.start();
  await Future<void>.value();
  await c.openTeam(c.teams.single);
  return c;
}

void main() {
  test('Istanbul civil serialization never converts browser timezone; boundary totals prorate break', () {
    final data = {
      'version': 3,
      'published_version': 2,
      'time_zone': 'Europe/Istanbul',
      'shifts': [
        {
          'id': 's',
          'team_id': 't',
          'user_id': 'u',
          'starts_at': '2026-10-31T22:00:00',
          'ends_at': '2026-11-01T06:00:00',
          'break_minutes': 60,
          'label': 'Gece',
          'note': '',
        },
      ],
    };
    final s = CloudPlan.fromJson(data).shifts.single;
    expect(s.start, DateTime.utc(2026, 10, 31, 22));
    expect(planTime(s.start), '2026-10-31T22:00:00.000');
    expect(s.netInPeriod(DateTime.utc(2026, 10), DateTime.utc(2026, 11)), 105);
    expect(s.netInPeriod(DateTime.utc(2026, 11), DateTime.utc(2026, 12)), 315);
    final sunday = shift();
    expect(
      sunday.netInPeriod(
        DateTime.utc(2026, 10, 19),
        DateTime.utc(2026, 10, 26),
      ),
      105,
    );
    expect(
      sunday.netInPeriod(DateTime.utc(2026, 10, 26), DateTime.utc(2026, 11, 2)),
      315,
    );
    expect(
      () => CloudPlan.fromJson({...data, 'time_zone': 'UTC'}),
      throwsFormatException,
    );
  });
  test(
    'plan snapshots survive draft deletion and update, until publication',
    () async {
      final g = PlanGateway();
      final a = await setup(g);
      await a.loadPlan(draft: true);
      expect(await a.publishPlan(), isTrue);
      expect(g.published.shifts.single.label, 'Gece');
      await a.savePlanShift(shift(name: 'Değişti'), creating: false);
      expect(g.published.shifts.single.label, 'Gece');
      await a.deletePlanShift('shift');
      expect(g.published.shifts, hasLength(1));
      await a.publishPlan();
      expect(g.published.shifts, isEmpty);
      a.dispose();
    },
  );
  test('stale version error requires refresh; account and team switch invalidate pending responses', () async {
    final g = PlanGateway();
    final a = await setup(g);
    await a.loadPlan(draft: true);
    g.planError = const PostgrestException(message: 'stale', code: '40001');
    expect(await a.savePlanShift(shift(), creating: false), isFalse);
    expect(a.planStale, isTrue);
    expect(a.error, contains('Yenile'));
    expect(await a.publishPlan(), isFalse);
    g.planError = null;
    await a.loadPlan();
    expect(a.planStale, isFalse);
    final pending = Completer<CloudPlan>();
    g.delayed = pending.future;
    final fetching = a.loadPlan();
    g.identity(const AccountIdentity('b', 'b@example.invalid'));
    pending.complete(CloudPlan(version: 90, shifts: [shift()]));
    await fetching;
    expect(a.plan, isNull);
    expect(a.teamMembers, isEmpty);
    g.delayed = null;
    await a.openTeam(const CloudTeam('team', 'Team', role: 'owner'));
    await a.loadPlan(draft: true);
    await a.signOut();
    expect(a.plan, isNull);
    expect(a.selectedTeam, isNull);
    a.dispose();
  });
  test(
    'employee always requests published and cannot call write operations',
    () async {
      final g = PlanGateway()..role = 'employee';
      final c = await setup(g);
      await c.loadPlan(draft: true);
      expect(g.requestedDraft, isFalse);
      expect(c.planDraft, isFalse);
      expect(await c.savePlanShift(shift(), creating: true), isFalse);
      expect(g.saves, 0);
      c.dispose();
    },
  );
  test(
    'failed refresh removes old rows, reports error and can retry',
    () async {
      final g = PlanGateway();
      final c = await setup(g);
      await c.loadPlan(draft: true);
      expect(c.plan!.shifts, isNotEmpty);
      g.delayed = Future<CloudPlan>.error(Exception('offline'));
      await c.loadPlan();
      expect(c.plan, isNull);
      expect(c.loadingPlan, isFalse);
      expect(c.error, contains('bağlanılamadı'));
      g.delayed = null;
      await c.loadPlan();
      expect(c.plan, isNotNull);
      expect(c.error, isNull);
      c.dispose();
    },
  );
  testWidgets(
    'published employee rows and totals are visible while draft content stays hidden',
    (t) async {
      final g = PlanGateway()
        ..role = 'employee'
        ..published = CloudPlan(
          version: 1,
          publishedVersion: 1,
          shifts: [
            Shift(
              id: 's',
              teamId: 'team',
              employeeId: 'a',
              label: 'Yayımlanan gece',
              start: weekOf(istanbulToday())
                  .add(const Duration(days: 6, hours: 22)),
              end: weekOf(istanbulToday())
                  .add(const Duration(days: 7, hours: 6)),
              breakMinutes: 60,
            ),
          ],
        )
        ..draft = CloudPlan(
          version: 2,
          publishedVersion: 1,
          shifts: [shift(name: 'Gizli taslak')],
        );
      final c = await setup(g);
      await t.pumpWidget(MaterialApp(home: TeamPlanPage(controller: c)));
      await t.pumpAndSettle();
      expect(find.text('Yayımlanan gece'), findsOneWidget);
      expect(find.text('Gizli taslak'), findsNothing);
      expect(find.textContaining('1 sa 45 dk'), findsOneWidget);
      expect(find.byTooltip('Düzenle'), findsNothing);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'narrow keyboard form validates current times, clears overlap error and saves appropriate day',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final g = PlanGateway();
      final c = await setup(g);
      await c.loadPlan(draft: true);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CloudShiftEditor(
                    controller: c,
                    day: DateTime.utc(2026, 10, 25),
                    version: 0,
                    userId: 'a',
                    teamId: 'team',
                  ),
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await click(t, find.text('Aç'));
      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await t.enterText(
        field('Başlangıç · YYYY-AA-GG SS:dd'),
        '2026-10-25 22:00',
      );
      await t.enterText(field('Bitiş · YYYY-AA-GG SS:dd'), '2026-10-26 06:00');
      await click(t, find.text('Kaydet'));
      expect(find.textContaining('çakışıyor'), findsOneWidget);
      expect(g.saves, 0);
      await t.enterText(
        field('Başlangıç · YYYY-AA-GG SS:dd'),
        '2026-10-31 22:00',
      );
      await t.pump();
      expect(find.textContaining('çakışıyor'), findsNothing);
      await t.enterText(field('Bitiş · YYYY-AA-GG SS:dd'), '2026-11-01 06:00');
      await click(t, find.text('Kaydet'));
      expect(g.saves, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'employee narrow plan fetches on entrance and refresh; no manager controls',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final g = PlanGateway()..role = 'employee';
      final c = await setup(g);
      await t.pumpWidget(MaterialApp(home: TeamPlanPage(controller: c)));
      await t.pumpAndSettle();
      expect(find.text('Vardiya ata'), findsNothing);
      expect(find.text('Yayımla · Tüm ekip taslağı'), findsNothing);
      expect(
        find.text('Bu ekip için henüz program yayımlanmadı.'),
        findsOneWidget,
      );
      final before = g.reads;
      await click(t, find.text('Yenile'));
      expect(g.reads, before + 1);
      expect(g.requestedDraft, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('real team detail opens plan without touching demo records', (
    t,
  ) async {
    final c = await setup(PlanGateway());
    final store = await testStore();
    final before = store.data.personal.length;
    await t.pumpWidget(
      VardiyaApp(store: store, initialized: true, account: c, config: config),
    );
    await t.pumpAndSettle();
    await click(t, find.text('Gerçek hesabım'));
    await click(t, find.widgetWithText(ListTile, 'Gerçek ekip'));
    await click(t, find.text('Haftalık planı aç'));
    expect(find.text('Gerçek ekip · Haftalık plan'), findsOneWidget);
    expect(store.data.personal.length, before);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'desktop team grid and explicit all dates publication confirmation',
    (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await setup(PlanGateway());
      await t.pumpWidget(MaterialApp(home: TeamPlanPage(controller: c)));
      await t.pumpAndSettle();
      expect(find.byType(Table), findsOneWidget);
      await click(t, find.text('Yayımla · Tüm ekip taslağı'));
      expect(find.textContaining('tüm tarihlerdeki'), findsOneWidget);
      await click(t, find.text('Tüm tarihleri yayımla'));
      expect(c.plan!.publishedVersion, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
