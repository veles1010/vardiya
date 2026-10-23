import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vardiya/domain.dart';
import 'package:vardiya/main.dart';
import 'package:vardiya/widgets.dart';

import 'support.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> fill(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('personal create, edit, delete and saved reload', (tester) async {
    tester.view.physicalSize = const Size(1440, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = MemoryPreferences();
    final store = await testStore(preferences: prefs, now: DateTime.now());
    await tester.pumpWidget(VardiyaApp(store: store, initialized: true));
    await tester.pumpAndSettle();
    await click(tester, find.byKey(const Key('add-personal')));
    await fill(tester, 'Kayıt adı', 'Deneme kişisel');
    await fill(tester, 'Başlangıç', '18:00');
    await fill(tester, 'Bitiş', '20:00');
    await fill(tester, 'Not (isteğe bağlı)', 'Kalıcı not');
    await click(tester, find.text('Kaydet'));
    expect(store.data.personal.last.label, 'Deneme kişisel');
    expect(store.data.personal.last.netMinutes, 90);
    final tile = find.widgetWithText(ShiftTile, 'Deneme kişisel');
    await click(
      tester,
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await click(tester, find.text('Düzenle'));
    await fill(tester, 'Not (isteğe bağlı)', 'Düzenlendi');
    await click(tester, find.text('Kaydet'));
    final reopened = await testStore(preferences: prefs);
    expect(reopened.data.personal.last.note, 'Düzenlendi');
    await click(
      tester,
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await click(tester, find.text('Sil'));
    await click(tester, find.widgetWithText(FilledButton, 'Sil'));
    expect(
      store.data.personal.any((s) => s.label == 'Deneme kişisel'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager creates team and employee, assigns and publishes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await testStore(now: DateTime.now());
    await tester.pumpWidget(VardiyaApp(store: store, initialized: true));
    await tester.pumpAndSettle();
    await click(tester, find.text('Ekip yönetimi'));
    expect(find.byType(Table), findsOneWidget);
    await click(tester, find.text('Yeni ekip'));
    await fill(tester, 'Ad', 'Test ekibi');
    await click(tester, find.text('Kaydet'));
    await click(tester, find.text('Çalışanlar'));
    await click(tester, find.text('Çalışan ekle'));
    await fill(tester, 'Ad', 'Ada Test');
    await fill(tester, 'Görev / unvan (isteğe bağlı)', 'Destek');
    await click(tester, find.text('Kaydet'));
    await click(tester, find.text('Haftalık plan'));
    await click(tester, find.text('Vardiya ata'));
    await click(tester, find.text('Çalışan').last);
    await click(tester, find.text('Ada Test').last);
    await fill(tester, 'Kayıt adı', 'Test görevi');
    await click(tester, find.text('Kaydet'));
    final employee = store.data.employees.firstWhere(
      (e) => e.name == 'Ada Test',
    );
    expect(store.data.forEmployee(employee.id), isEmpty);
    await click(tester, find.text('Tüm ekip taslağını yayımla'));
    await click(tester, find.widgetWithText(FilledButton, 'Yayımla'));
    expect(store.data.forEmployee(employee.id).single.label, 'Test görevi');
    await click(tester, find.text('Çalışan').first);
    await click(tester, find.byType(DropdownButtonFormField<String>));
    await click(tester, find.textContaining('Ada Test').last);
    expect(find.text('Test görevi'), findsWidgets);
    expect(find.text('Vardiya ata'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px layout, keyboard and long names do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final store = await testStore(now: DateTime.now());
    await store.saveEmployee(
      const Employee(
        id: 'e1',
        teamId: 't1',
        name: 'Çok Uzun İsimli Örnek Çalışan Deniz Yılmaz Demirkaya',
        role: 'Operasyon ve planlama sorumlusu',
      ),
    );
    await tester.pumpWidget(VardiyaApp(store: store, initialized: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await click(tester, find.byKey(const Key('add-personal')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await fill(tester, 'Başlangıç', '22:00');
    await fill(tester, 'Bitiş', '06:00');
    await click(tester, find.text('Kaydet'));
    expect(find.byKey(const Key('form-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await click(tester, find.text('Vazgeç'));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await click(tester, find.text('Ekip yönetimi'));
    expect(find.byType(Table), findsNothing);
    expect(tester.takeException(), isNull);
    await click(tester, find.text('Çalışanlar'));
    expect(tester.takeException(), isNull);
    await click(tester, find.text('Çalışan'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('leave and rest records use whole days', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await testStore(now: DateTime.now());
    await store.deleteShift('p1', personal: true);
    await tester.pumpWidget(VardiyaApp(store: store, initialized: true));
    await tester.pumpAndSettle();
    await click(tester, find.byKey(const Key('add-personal')));
    await click(tester, find.byType(DropdownButtonFormField<EntryKind>));
    await click(tester, find.text('İzin').last);
    await click(tester, find.text('Kaydet'));
    expect(store.data.personal.last.kind, EntryKind.leave);
    expect(
      store.data.personal.last.end
          .difference(store.data.personal.last.start)
          .inHours,
      24,
    );
    expect(store.data.personal.last.netMinutes, 0);
    expect(tester.takeException(), isNull);
  });
}
