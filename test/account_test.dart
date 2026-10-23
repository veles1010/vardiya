import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vardiya/account/account_service.dart';
import 'package:vardiya/main.dart';
import 'package:vardiya/domain.dart';
import 'package:vardiya/account/plan_model.dart';

import 'support.dart';
import 'widget_test.dart' show click, fill;

class FakeAccountGateway implements AccountGateway {
  final events = StreamController<AccountIdentity?>.broadcast(sync: true);
  AccountIdentity? initial;
  Completer<AccountIdentity?>? boot;
  Future<List<CloudTeam>> Function()? fetch;
  Object? failure;
  int passwordUpdates = 0;
  @override
  Stream<AccountIdentity?> get changes => events.stream;
  @override
  Future<AccountIdentity?> initialize() async =>
      boot == null ? initial : boot!.future;
  void identity(AccountIdentity? value) {
    initial = value;
    events.add(value);
  }

  @override
  Future<void> signIn(String e, String p) async {
    if (failure != null) {
      throw failure!;
    }
    identity(const AccountIdentity('a', 'a@example.invalid'));
  }

  @override
  Future<void> signUp(String e, String p) async {
    if (failure != null) {
      throw failure!;
    }
  }

  @override
  Future<void> reset(String e) async {
    if (failure != null) {
      throw failure!;
    }
  }

  @override
  Future<void> resend(String e) async {}
  @override
  Future<void> updatePassword(String p) async {
    passwordUpdates++;
    identity(const AccountIdentity('a', 'a@example.invalid'));
  }

  @override
  Future<void> signOut() async {
    identity(null);
  }

  @override
  Future<List<CloudTeam>> teams() async => fetch == null ? const [] : fetch!();
  @override
  Future<void> createTeam(String name) async {}
  @override
  Future<void> renameTeam(String id, String name) async {}
  @override
  Future<List<CloudMember>> members(String teamId) async => const [];
  @override
  Future<List<PendingInvite>> invitations(String teamId) async => const [];
  @override
  Future<CreatedInvite> createInvitation(String teamId, String email) async =>
      CreatedInvite('invite', 'a' * 64, DateTime.utc(2030));
  @override
  Future<void> cancelInvitation(String id) async {}
  @override
  Future<InvitePreview> previewInvitation(String code) async =>
      InvitePreview('team', 'Ekip', DateTime.utc(2030));
  @override
  Future<void> acceptInvitation(String code) async {}
  @override
  Future<CloudPlan> readPlan(String teamId, {required bool draft}) async =>
      const CloudPlan(version: 0, shifts: []);
  @override
  Future<void> saveShift(
    String teamId,
    int version,
    Shift shift, {
    required bool creating,
  }) async {}
  @override
  Future<void> deleteShift(String teamId, int version, String shiftId) async {}
  @override
  Future<void> publishPlan(String teamId, int version) async {}
  @override
  void dispose() {
    unawaited(events.close());
  }
}

const config = CloudConfig(
  url: 'https://example.supabase.co',
  key: 'sb_publishable_test',
);
void main() {
  test('configuration rejects privileged keys and incomplete setup', () {
    expect(const CloudConfig().valid, isFalse);
    expect(
      const CloudConfig(
        url: 'https://example.supabase.co',
        key: 'sb_secret_bad',
      ).valid,
      isFalse,
    );
    expect(
      const CloudConfig(
        url: 'https://example.supabase.co',
        key: 'eyJhbGciOi',
      ).valid,
      isFalse,
    );
    expect(config.valid, isTrue);
  });
  test('restoration remains loading until initial session resolves', () async {
    final g = FakeAccountGateway()..boot = Completer<AccountIdentity?>();
    final c = AccountController(g);
    final start = c.start();
    expect(c.restoring, isTrue);
    g.boot!.complete(const AccountIdentity('a', 'a@example.invalid'));
    await start;
    expect(c.user!.id, 'a');
    expect(c.restoring, isFalse);
    expect(c.ready, isTrue);
    c.dispose();
  });
  test(
    'old in-flight team response cannot leak into another account',
    () async {
      final old = Completer<List<CloudTeam>>();
      final g = FakeAccountGateway()
        ..initial = const AccountIdentity('a', 'a@example.invalid')
        ..fetch = () => old.future;
      final c = AccountController(g);
      await c.start();
      g.fetch = () async => const [CloudTeam('b-team', 'B')];
      g.identity(const AccountIdentity('b', 'b@example.invalid'));
      await Future<void>.delayed(Duration.zero);
      old.complete(const [CloudTeam('a-team', 'A')]);
      await Future<void>.delayed(Duration.zero);
      expect(c.teams.single.id, 'b-team');
      await c.signOut();
      expect(c.teams, isEmpty);
      expect(c.user, isNull);
      c.dispose();
    },
  );
  test('invalid login and expired callback map to Turkish errors without credentials', () async {
    final g = FakeAccountGateway()
      ..failure = const AuthException(
        'raw secret',
        code: 'invalid_credentials',
      );
    final c = AccountController(g);
    await c.start();
    expect(await c.run(() => g.signIn('x', 'secret')), isFalse);
    expect(c.error, 'E-posta veya şifre geçersiz.');
    g.events.addError(const AuthException('raw token', code: 'otp_expired'));
    expect(c.error, contains('süresi dolmuş'));
    expect(c.error, isNot(contains('token')));
    expect(c.focusAccount, isTrue);
    c.dispose();
  });
  test('team connection failure can be retried', () async {
    final g = FakeAccountGateway()
      ..initial = const AccountIdentity('a', 'a@example.invalid')
      ..fetch = () => Future.error(StateError('offline'));
    final c = AccountController(g);
    await c.start();
    await Future<void>.delayed(Duration.zero);
    expect(c.error, contains('bağlanılamadı'));
    g.fetch = () async => const [CloudTeam('a', 'A')];
    await c.loadTeams();
    expect(c.error, isNull);
    expect(c.teams.single.name, 'A');
    c.dispose();
  });
  testWidgets(
    'recovery callback renders new password form and saves password at 320px',
    (t) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final g = FakeAccountGateway()
        ..initial = const AccountIdentity(
          'a',
          'a@example.invalid',
          recovery: true,
          fromLink: true,
        );
      final c = AccountController(g);
      await c.start();
      final store = await testStore();
      await t.pumpWidget(
        VardiyaApp(store: store, initialized: true, account: c, config: config),
      );
      await t.pumpAndSettle();
      expect(find.text('Yeni şifre belirleyin'), findsOneWidget);
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      await t.pumpAndSettle();
      await fill(t, 'Şifre', 'ExamplePass123!');
      await fill(t, 'Şifre tekrarı', 'ExamplePass123!');
      await click(t, find.text('Yeni şifreyi kaydet'));
      expect(g.passwordUpdates, 1);
      expect(find.text('Ekiplerim'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'unconfigured cloud leaves demo available without modifying local data',
    (t) async {
      final store = await testStore();
      final before = store.data.toJson();
      final c = AccountController(FakeAccountGateway());
      await t.pumpWidget(
        VardiyaApp(store: store, initialized: true, account: c),
      );
      await t.pumpAndSettle();
      await click(t, find.text('Gerçek hesabım'));
      expect(
        find.textContaining('Supabase bağlantısını yapılandırın'),
        findsOneWidget,
      );
      await click(t, find.text('Demo · Yerel'));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(store.data.toJson(), before);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
