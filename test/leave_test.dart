import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vardiya/account/account_service.dart';
import 'package:vardiya/account/leave_model.dart';
import 'package:vardiya/account/plan_model.dart';
import 'package:vardiya/account/team_leave_page.dart';
import 'package:vardiya/account/team_plan_page.dart';
import 'package:vardiya/domain.dart';
import 'package:vardiya/theme.dart';

import 'account_test.dart' show FakeAccountGateway;
import 'invitation_test.dart' show click;

LeaveRequest request({
  String user = 'a',
  String status = 'pending',
  List<LeaveConflict> conflicts = const [],
}) => LeaveRequest(
  id: 'request',
  userId: user,
  start: DateTime.utc(2026, 10, 26),
  end: DateTime.utc(2026, 10, 27),
  description: 'Özel açıklama',
  status: status,
  conflicts: conflicts,
);

class LeaveGateway extends FakeAccountGateway {
  String role = 'employee';
  LeaveInbox inbox = LeaveInbox(1, [request()]);
  Future<LeaveInbox>? delayed;
  Object? leaveError;
  DateTime? sentStart, sentEnd;
  String? sentDescription, action, reason;
  int writes = 0;
  CloudPlan schedule = const CloudPlan(version: 1, shifts: []);
  @override
  Future<List<CloudTeam>> teams() async => [
    CloudTeam('team', 'İzin ekibi', role: role),
  ];
  @override
  Future<List<CloudMember>> members(String teamId) async => const [
    CloudMember('a', 'a@example.invalid', 'owner'),
    CloudMember('b', 'b@example.invalid', 'employee'),
  ];
  @override
  Future<LeaveInbox> readLeaves(String teamId) async =>
      delayed ?? Future.value(inbox);
  @override
  Future<CloudPlan> readPlan(String teamId, {required bool draft}) async =>
      schedule;
  @override
  Future<void> createLeave(
    String teamId,
    int version,
    DateTime start,
    DateTime end,
    String description,
  ) async {
    if (leaveError != null) throw leaveError!;
    writes++;
    sentStart = start;
    sentEnd = end;
    sentDescription = description;
    inbox = LeaveInbox(version + 1, [
      LeaveRequest(
        id: 'new',
        userId: 'a',
        start: start,
        end: end,
        description: description,
      ),
      ...inbox.requests,
    ]);
  }

  @override
  Future<void> actOnLeave(
    String teamId,
    int version,
    String requestId,
    int revision,
    String action,
    String reason,
  ) async {
    if (leaveError != null) throw leaveError!;
    writes++;
    this.action = action;
    this.reason = reason;
    final r = inbox.requests.single;
    inbox = LeaveInbox(version + 1, [
      LeaveRequest(
        id: r.id,
        userId: r.userId,
        start: r.start,
        end: r.end,
        description: r.description,
        status: switch (action) {
          'approve' => 'approved',
          'reject' => 'rejected',
          _ => 'cancelled',
        },
        revision: revision + 1,
      ),
    ]);
  }
}

Future<AccountController> setup(LeaveGateway g) async {
  g.initial = const AccountIdentity('a', 'a@example.invalid');
  final c = AccountController(g);
  await c.start();
  await Future<void>.value();
  await c.openTeam(c.teams.single);
  return c;
}

Widget app(AccountController c, {bool dark = true, bool plan = false}) =>
    MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: vardiyaTheme(dark ? Brightness.dark : Brightness.light),
      home: plan ? TeamPlanPage(controller: c) : TeamLeavePage(controller: c),
    );
void main() {
  test(
    'date-only leave is inclusive and never changes the planned work total',
    () {
      final p = CloudPlan.fromJson({
        'version': 1,
        'published_version': null,
        'time_zone': 'Europe/Istanbul',
        'shifts': [],
        'leaves': [
          {
            'id': 'l',
            'user_id': 'a',
            'starts_on': '2026-10-31',
            'ends_on': '2026-11-01',
          },
        ],
      });
      final l = p.leaves.single;
      expect(l.contains(DateTime.utc(2026, 11, 1, 22)), isTrue);
      expect(l.contains(DateTime.utc(2026, 11, 2)), isFalse);
      expect(
        l.intersects(DateTime.utc(2026, 11), DateTime.utc(2026, 12)),
        isTrue,
      );
      expect(leaveDate(l.start), '2026-10-31');
      expect(p.shifts, isEmpty);
    },
  );
  test('logout, account and team changes clear leave data and ignore pending replies', () async {
    final g = LeaveGateway();
    final c = await setup(g);
    await c.loadLeaves();
    expect(c.leaveInbox!.requests, isNotEmpty);
    final pending = Completer<LeaveInbox>();
    g.delayed = pending.future;
    final loading = c.loadLeaves();
    g.identity(const AccountIdentity('b', 'b@example.invalid'));
    pending.complete(g.inbox);
    await loading;
    expect(c.leaveInbox, isNull);
    expect(c.loadingLeaves, isFalse);
    g.delayed = null;
    await c.openTeam(const CloudTeam('team', 'Team'));
    await c.loadLeaves();
    await c.openTeam(const CloudTeam('other', 'Other'));
    expect(c.leaveInbox, isNull);
    await c.loadLeaves();
    await c.signOut();
    expect(c.leaveInbox, isNull);
    expect(c.teamMembers, isEmpty);
    c.dispose();
  });
  test('stale decisions and failed requests require refresh; successful leave invalidates cached plan', () async {
    final g = LeaveGateway();
    final c = await setup(g);
    await c.loadLeaves();
    await c.loadPlan(draft: false);
    g.leaveError = const PostgrestException(message: 'stale', code: '40001');
    expect(
      await c.actOnLeave(c.leaveInbox!.requests.single, 'withdraw', ''),
      isFalse,
    );
    expect(c.leavesStale, isTrue);
    expect(c.error, contains('Yenile'));
    g.leaveError = null;
    expect(
      await c.createLeave(DateTime.utc(2026), DateTime.utc(2026), ''),
      isFalse,
    );
    expect(g.writes, 0);
    await c.loadLeaves();
    expect(
      await c.actOnLeave(c.leaveInbox!.requests.single, 'withdraw', ''),
      isTrue,
    );
    expect(c.plan, isNull);
    expect(c.planStale, isTrue);
    expect(c.leaveInbox!.requests.single.status, 'cancelled');
    c.dispose();
  });
  test(
    'leave conflict errors are Turkish without revealing another employee data',
    () {
      expect(
        accountError(
          const PostgrestException(message: 'hidden', code: 'P1001'),
        ),
        contains('onaylanmış izin'),
      );
      expect(
        accountError(
          const PostgrestException(message: 'hidden', code: 'P1002'),
        ),
        contains('yeniden yayımlayın'),
      );
      expect(
        accountError(
          const PostgrestException(message: 'hidden', code: 'P1003'),
        ),
        contains('başka izin talebiniz'),
      );
    },
  );
  testWidgets(
    'employee selects inclusive dates from calendar and submits at 320px with keyboard',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final g = LeaveGateway();
      final c = await setup(g);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      expect(find.text('Bekliyor'), findsOneWidget);
      await click(t, find.text('İzin talep et'));
      await click(t, find.textContaining('Başlangıç günü ·'));
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await click(t, find.text('15').last);
      await click(t, find.text('Tamam'));
      await click(t, find.textContaining('Bitiş günü ·'));
      await click(t, find.text('20').last);
      await click(t, find.text('Tamam'));
      t.view.viewInsets = FakeViewPadding(bottom: 280);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Aile ziyareti');
      await click(t, find.text('Talebi gönder'));
      expect(g.sentStart!.day, 15);
      expect(g.sentEnd!.day, 20);
      expect(g.sentDescription, 'Aile ziyareti');
      expect(g.writes, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'employee withdraws own pending request without gaining decision controls',
    (t) async {
      final g = LeaveGateway();
      final c = await setup(g);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await click(t, find.text('Talebi geri çek'));
      await click(t, find.text('Talebi geri çek').last);
      expect(g.action, 'withdraw');
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(find.text('Talebi geri çek'), findsNothing);
      expect(find.text('Onaylı izni iptal et'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'manager sees both conflicting sources and can approve only after refresh',
    (t) async {
      final g = LeaveGateway()
        ..role = 'owner'
        ..inbox = LeaveInbox(1, [
          request(
            user: 'b',
            conflicts: [
              LeaveConflict(
                'Gece',
                'draft',
                DateTime.utc(2026, 10, 25, 22),
                DateTime.utc(2026, 10, 26, 6),
              ),
              LeaveConflict(
                'Gece',
                'published',
                DateTime.utc(2026, 10, 25, 22),
                DateTime.utc(2026, 10, 26, 6),
              ),
            ],
          ),
        ]);
      final c = await setup(g);
      await t.pumpWidget(app(c, dark: false));
      await t.pumpAndSettle();
      expect(find.textContaining('Taslak · Gece'), findsOneWidget);
      expect(find.textContaining('Yayımlanmış · Gece'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Onayla'))
            .onPressed,
        isNull,
      );
      g.inbox = LeaveInbox(2, [request(user: 'b')]);
      await click(t, find.text('Yenile'));
      await click(t, find.text('Onayla'));
      await click(t, find.text('İzni onayla').last);
      expect(g.action, 'approve');
      expect(find.text('Onaylandı'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'rejection and approved cancellation require a reason in narrow keyboard dialog',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final g = LeaveGateway()
        ..role = 'manager'
        ..inbox = LeaveInbox(1, [request(user: 'b')]);
      final c = await setup(g);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      await click(t, find.text('Reddet'));
      await click(t, find.text('Talebi reddet').last);
      expect(find.text('Gerekçe girin.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'Uygun tarih seçiniz');
      await click(t, find.text('Talebi reddet').last);
      expect(g.action, 'reject');
      expect(g.reason, 'Uygun tarih seçiniz');
      g.inbox = LeaveInbox(3, [request(user: 'b', status: 'approved')]);
      await click(t, find.text('Yenile'));
      await click(t, find.text('Onaylı izni iptal et'));
      await click(t, find.text('Onaylı izni iptal et').last);
      expect(find.text('Gerekçe girin.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'Çalışanın isteği');
      await click(t, find.text('Onaylı izni iptal et').last);
      expect(g.action, 'cancel');
      expect(find.text('İptal edildi'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'approved leave appears in employee program before first publication with zero work',
    (t) async {
      final today = istanbulToday();
      final g = LeaveGateway()
        ..schedule = CloudPlan(
          version: 1,
          shifts: [],
          leaves: [ApprovedLeave('leave', 'a', today, today)],
        );
      final c = await setup(g);
      await t.pumpWidget(app(c, plan: true));
      await t.pumpAndSettle();
      expect(find.textContaining('İzinli ·'), findsOneWidget);
      expect(find.textContaining('0 sa 00 dk'), findsOneWidget);
      expect(find.text('Vardiya ata'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'desktop grid marks every inclusive approved day without adding work',
    (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final start = weekOf(istanbulToday());
      final g = LeaveGateway()
        ..role = 'owner'
        ..schedule = CloudPlan(
          version: 1,
          shifts: [],
          leaves: [
            ApprovedLeave(
              'leave',
              'b',
              start,
              start.add(const Duration(days: 2)),
            ),
          ],
        );
      final c = await setup(g);
      await t.pumpWidget(app(c, plan: true));
      await t.pumpAndSettle();
      expect(find.text('İzinli'), findsNWidgets(3));
      expect(find.textContaining('0 sa 00 dk'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
