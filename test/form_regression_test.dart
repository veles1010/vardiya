import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vardiya/editors.dart';
import 'package:vardiya/main.dart';

import 'support.dart';
import 'widget_test.dart' show click, fill;

void main() {
  testWidgets(
    'night to evening applies all fields, remains manually editable',
    (t) async {
      final store = await testStore();
      await t.pumpWidget(VardiyaApp(store: store, initialized: true));
      await t.pumpAndSettle();
      showDialog<void>(
        context: t.element(find.byType(HomeScreen)),
        builder: (_) =>
            ShiftEditor(store: store, date: DateTime.utc(2026, 10, 31)),
      );
      await t.pumpAndSettle();
      final template = find.byType(DropdownButtonFormField<String>);
      await click(t, template);
      await click(t, find.text('Gece · 22:00–06:00 (+1 gün)').last);
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(find.textContaining('1 Kasım 2026 06:00'), findsOneWidget);
      await click(t, template);
      await click(t, find.text('Akşam · 14:00–22:00').last);
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.textContaining('31 Ekim 2026 22:00'), findsOneWidget);
      await fill(t, 'Bitiş', '21:00');
      await click(t, find.text('Kaydet'));
      expect(store.data.personal.last.end, DateTime.utc(2026, 10, 31, 21));
      expect(store.data.personal.last.breakMinutes, 45);
    },
  );

  testWidgets(
    'conflict clears on date change and validates current date on save',
    (t) async {
      final store = await testStore();
      await t.pumpWidget(VardiyaApp(store: store, initialized: true));
      await t.pumpAndSettle();
      showDialog<void>(
        context: t.element(find.byType(HomeScreen)),
        builder: (_) =>
            ShiftEditor(store: store, date: DateTime.utc(2026, 10, 23)),
      );
      await t.pumpAndSettle();
      await click(t, find.byType(DropdownButtonFormField<String>));
      await click(t, find.text('Gece · 22:00–06:00 (+1 gün)').last);
      await click(t, find.text('Kaydet'));
      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(
        find.textContaining('23.10.2026 22:00 – 24.10.2026 06:00'),
        findsOneWidget,
      );
      final count = store.data.personal.length;
      await click(t, find.widgetWithText(OutlinedButton, '23 Ekim 2026'));
      await click(t, find.text('31').last);
      await click(t, find.text('Tamam'));
      expect(find.byKey(const Key('form-error')), findsNothing);
      await click(t, find.text('Kaydet'));
      expect(store.data.personal.length, count + 1);
      expect(store.data.personal.last.start, DateTime.utc(2026, 10, 31, 22));
    },
  );

  for (final type in ['personal', 'team', 'template']) {
    testWidgets(
      '$type errors clear when time or break changes, invalid values still rejected',
      (t) async {
        t.view.physicalSize = const Size(320, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetViewInsets);
        final store = await testStore();
        await t.pumpWidget(VardiyaApp(store: store, initialized: true));
        await t.pumpAndSettle();
        showDialog<void>(
          context: t.element(find.byType(HomeScreen)),
          builder: (_) => ShiftEditor(
            store: store,
            date: DateTime.utc(2026, 10, 31),
            personal: type != 'team',
            teamId: 't1',
            employeeId: 'e1',
            editTemplate: type == 'template',
          ),
        );
        await t.pumpAndSettle();
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        await fill(t, 'Ücretsiz mola (dakika)', '-1');
        await click(t, find.text('Kaydet'));
        expect(find.byKey(const Key('form-error')), findsOneWidget);
        await fill(t, 'Ücretsiz mola (dakika)', '30');
        expect(find.byKey(const Key('form-error')), findsNothing);
        await fill(t, 'Bitiş', '08:00');
        await click(t, find.text('Kaydet'));
        expect(find.byKey(const Key('form-error')), findsOneWidget);
        await fill(t, 'Bitiş', '16:00');
        expect(find.byKey(const Key('form-error')), findsNothing);
        await click(t, find.text('Kaydet'));
        expect(find.byType(ShiftEditor), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
}
