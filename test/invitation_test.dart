import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vardiya/account/account_service.dart';
import 'package:vardiya/main.dart';

import 'account_test.dart' show FakeAccountGateway, config;
import 'support.dart';
import 'widget_test.dart' show fill;

Future<void> click(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

class InviteGateway extends FakeAccountGateway {
  Future<List<CloudMember>>? delayedMembers;
  Future<CreatedInvite>? delayedCode;
  Future<InvitePreview>? delayedPreview;
  bool accepted = false, cancelled = false, deny = false;
  @override
  Future<List<CloudTeam>> teams() async => accepted
      ? const [CloudTeam('team', 'Katılınan ekip')]
      : const [CloudTeam('owned', 'Yönetilen ekip', role: 'owner')];
  @override
  Future<List<CloudMember>> members(String teamId) async =>
      delayedMembers ??
      Future.value(const [CloudMember('a', 'owner@example.invalid', 'owner')]);
  @override
  Future<List<PendingInvite>> invitations(String teamId) async => cancelled
      ? []
      : [PendingInvite('invite', 'worker@example.invalid', DateTime.utc(2030))];
  @override
  Future<CreatedInvite> createInvitation(String teamId, String email) async =>
      delayedCode ??
      Future.value(CreatedInvite('invite', 'a' * 64, DateTime.utc(2030)));
  @override
  Future<void> cancelInvitation(String id) async {
    cancelled = true;
  }

  @override
  Future<InvitePreview> previewInvitation(String code) async {
    if (deny) {
      throw const PostgrestException(message: 'withheld', code: '42501');
    }
    return delayedPreview ??
        Future.value(
          InvitePreview('team', 'Katılınan ekip', DateTime.utc(2030)),
        );
  }

  @override
  Future<void> acceptInvitation(String code) async {
    accepted = true;
  }
}

Future<AccountController> controller(InviteGateway g) async {
  g.initial = const AccountIdentity('a', 'owner@example.invalid');
  final c = AccountController(g);
  await c.start();
  await Future<void>.value();
  return c;
}

void main() {
  test(
    'invitation, member, preview and raw code caches clear on logout',
    () async {
      final g = InviteGateway();
      final c = await controller(g);
      await c.openTeam(c.teams.single);
      await c.createInvitation('worker@example.invalid');
      await c.previewInvitation('a' * 64);
      expect(c.createdInvite, isNotNull);
      expect(c.teamMembers, isNotEmpty);
      expect(c.pendingInvites, isNotEmpty);
      await c.signOut();
      expect(c.teams, isEmpty);
      expect(c.selectedTeam, isNull);
      expect(c.teamMembers, isEmpty);
      expect(c.pendingInvites, isEmpty);
      expect(c.createdInvite, isNull);
      expect(c.invitePreview, isNull);
      c.dispose();
    },
  );
  test(
    'member and raw-code requests cannot populate another account',
    () async {
      final g = InviteGateway();
      final c = await controller(g);
      final members = Completer<List<CloudMember>>();
      g.delayedMembers = members.future;
      final opening = c.openTeam(c.teams.single);
      g.identity(const AccountIdentity('b', 'b@example.invalid'));
      members.complete(const [
        CloudMember('a', 'owner@example.invalid', 'owner'),
      ]);
      await opening;
      expect(c.teamMembers, isEmpty);
      expect(c.pendingInvites, isEmpty);
      g.delayedMembers = null;
      await c.loadTeams();
      await c.openTeam(c.teams.single);
      final raw = Completer<CreatedInvite>();
      g.delayedCode = raw.future;
      final creating = c.createInvitation('worker@example.invalid');
      g.identity(const AccountIdentity('c', 'c@example.invalid'));
      raw.complete(CreatedInvite('invite', 'a' * 64, DateTime.utc(2030)));
      await creating;
      expect(c.createdInvite, isNull);
      c.dispose();
    },
  );
  test(
    'edited code discards pending preview; failed preview cannot accept',
    () async {
      final g = InviteGateway();
      final c = await controller(g);
      final pending = Completer<InvitePreview>();
      g.delayedPreview = pending.future;
      final checking = c.previewInvitation('a' * 64);
      c.clearInvitationPreview();
      pending.complete(InvitePreview('team', 'Old', DateTime.utc(2030)));
      await checking;
      expect(c.invitePreview, isNull);
      g.delayedPreview = null;
      g.deny = true;
      await c.previewInvitation('a' * 64);
      await c.acceptInvitation();
      expect(c.error, contains('davet geçersiz'));
      expect(g.accepted, isFalse);
      c.dispose();
    },
  );
  testWidgets('owner creates copies and cancels invitation at narrow width', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    final g = InviteGateway();
    final c = await controller(g);
    c.focusAccount = true;
    final store = await testStore();
    await t.pumpWidget(
      VardiyaApp(store: store, initialized: true, account: c, config: config),
    );
    await t.pumpAndSettle();
    await click(t, find.text('Yönetilen ekip'));
    await click(t, find.text('Davet oluştur'));
    expect(find.text('Geçerli bir e-posta girin.'), findsOneWidget);
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    await t.pumpAndSettle();
    await fill(t, 'Çalışanın e-postası', 'worker@example.invalid');
    await click(t, find.text('Davet oluştur'));
    expect(c.createdInvite, isNotNull);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await click(t, find.text('Davet kodunu kopyala'));
    expect(copied, 'a' * 64);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    t.view.resetViewInsets();
    await t.pumpAndSettle();
    await click(t, find.text('Daveti iptal et'));
    await click(t, find.widgetWithText(FilledButton, 'İptal et'));
    expect(g.cancelled, isTrue);
    expect(c.pendingInvites, isEmpty);
    expect(c.createdInvite, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('employee previews team then accepts and sees own role', (
    t,
  ) async {
    final g = InviteGateway();
    final c = await controller(g);
    c.focusAccount = true;
    final store = await testStore();
    await t.pumpWidget(
      VardiyaApp(store: store, initialized: true, account: c, config: config),
    );
    await t.pumpAndSettle();
    await fill(t, 'Davet kodu', 'a' * 64);
    await click(t, find.text('Daveti kontrol et'));
    expect(find.text('Katılacağınız ekip: Katılınan ekip'), findsOneWidget);
    expect(g.accepted, isFalse);
    await click(t, find.text('Daveti kabul et'));
    expect(g.accepted, isTrue);
    expect(find.text('Katılınan ekip'), findsOneWidget);
    expect(find.text('Rolünüz: Çalışan · Ayrıntı için açın'), findsOneWidget);
    await click(t, find.text('Katılınan ekip'));
    expect(find.text('Çalışan davet et'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
}
