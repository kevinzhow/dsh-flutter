import 'dart:async';

import 'package:dsh_feature_theme/dsh_feature_theme.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ConfigFormSnapshot ready(
  ThemeSettings s, {
  bool writable = true,
  int revision = 0,
}) => ConfigFormSnapshot(
  status: ConfigFormStatus.ready,
  value: s.toJson(),
  base: ThemeSettings().toJson(),
  user: const {},
  revision: revision,
  writable: writable,
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('theme service', () {
    late FakeConfigForm form;
    late ThemeSettingsService service;

    setUp(() {
      form = FakeConfigForm(ready(ThemeSettings()));
      service = ThemeSettingsService(host: form);
    });
    tearDown(() => service.dispose());

    test('starts from the accepted durable section', () {
      form = FakeConfigForm(
        ready(ThemeSettings(preference: ThemePreference.dark, fontSize: 18)),
      );
      service = ThemeSettingsService(host: form);
      expect(service.current.preference, ThemePreference.dark);
      expect(service.current.fontSize, 18);
    });

    test('shows the initial values until the host answers, then adopts', () {
      form = FakeConfigForm();
      service = ThemeSettingsService(
        host: form,
        initial: ThemeSettings(fontSize: 16),
      );
      expect(service.current.fontSize, 16);
      form.publish(ready(ThemeSettings(fontSize: 12)));
      expect(service.current.fontSize, 12);
    });

    test('a preference shows at once and is written', () async {
      final seen = <ThemePreference>[];
      service.settings.changes.listen((s) => seen.add(s.preference));
      service.setPreference(ThemePreference.dark);
      expect(service.current.preference, ThemePreference.dark);
      await flush();
      expect(form.written, {'preference': 'dark'});
      expect(seen, [ThemePreference.dark]);
    });

    test('an unchanged value writes nothing', () async {
      service.setPreference(ThemePreference.system);
      service.setFontSize(FontRole.text, 14);
      service.setFontFamily(FontRole.code, '');
      await flush();
      expect(form.writes, isEmpty);
    });

    test('sizes are range checked and written under their field', () async {
      service.setFontSize(FontRole.code, 13);
      service.setFontSize(FontRole.terminal, 20);
      service.setFontSize(FontRole.text, 22);
      await flush();
      expect(form.written, {
        'codeFontSize': 13,
        'terminalFontSize': 20,
        'fontSize': 22,
      });
      expect(
        () => service.setFontSize(FontRole.code, 17),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => service.setFontSize(FontRole.text, 9),
        throwsA(isA<RangeError>()),
      );
      expect(service.current.codeFontSize, 13);
    });

    test('a font list is normalized before it shows and is written', () async {
      service.setFontFamily(FontRole.text, '  Inter ,"Noto Sans", serif ');
      expect(service.current.textFontFamily, '"Inter", "Noto Sans", serif');
      await flush();
      expect(form.written, {'textFontFamily': '"Inter", "Noto Sans", serif'});
      service.setFontFamily(FontRole.text, ' ,, ');
      await flush();
      expect(service.current.textFontFamily, '');
    });

    test('an echo of an earlier write cannot revert a later change', () async {
      final gate = Completer<void>();
      form
        ..gate = gate.future
        ..foldWrites = false;
      service.setFontSize(FontRole.text, 15);
      service.setFontSize(FontRole.text, 16);
      // The host echoes the first write while both are still pending.
      form.publish(ready(ThemeSettings(fontSize: 15), revision: 1));
      expect(service.current.fontSize, 16);
      gate.complete();
      await flush();
      await flush();
      // Settled: the durable section (still the echo) is adopted.
      expect(service.current.fontSize, 15);
    });

    test('a refused latest write returns to the durable values', () async {
      form.answer = false;
      service.setPreference(ThemePreference.light);
      expect(service.current.preference, ThemePreference.light);
      await flush();
      expect(service.current.preference, ThemePreference.system);
    });

    test('a transport failure is contained and returns to durable', () async {
      form = FakeConfigForm(ready(ThemeSettings()));
      service = ThemeSettingsService(host: _Failing(form));
      service.setPreference(ThemePreference.dark);
      await flush();
      expect(service.current.preference, ThemePreference.system);
    });

    test('a section change from the host is adopted', () {
      form.publish(
        ready(
          ThemeSettings(
            preference: ThemePreference.light,
            textFontFamily: 'Georgia',
          ),
          revision: 2,
        ),
      );
      expect(service.current.preference, ThemePreference.light);
      expect(service.current.textFontFamily, '"Georgia"');
    });

    test('writable and available follow the form', () {
      expect(service.writable, isTrue);
      form.publish(ready(ThemeSettings(), writable: false));
      expect(service.writable, isFalse);
      form.publish(
        const ConfigFormSnapshot(status: ConfigFormStatus.unavailable),
      );
      expect(service.available, isFalse);
    });
  });

  group('rows', () {
    late FakeConfigForm form;
    late ThemeSettingsService service;
    late SlotRegistry slots;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      form = FakeConfigForm(ready(ThemeSettings()));
      service = ThemeSettingsService(host: form);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerThemeFeature(slots, service: service, i18n: () => i18n);
    });
    tearDown(() => service.dispose());

    Widget column() {
      final items = slots.renderList(
        DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
        const SettingsOwner(),
      );
      // The General section marks its last item as the end of the column.
      return dshTestApp(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  i == items.length - 1
                      ? DshColumnEnd(child: items[i])
                      : items[i],
              ],
            ),
          ),
        ),
        size: const Size(390, 900),
      );
    }

    testWidgets('the feature fills the General item slot in dsh order', (
      t,
    ) async {
      expect(
        [
          for (final e in slots.entries(DshSlots.settingsGeneralItem))
            (e.id, e.order),
        ],
        [('appearance', 10), ('font-size', 11)],
      );
    });

    testWidgets('Appearance marks the persisted preference and writes a pick', (
      t,
    ) async {
      await t.pumpWidget(column());
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      bool selected(String id) => t
          .getSemantics(find.byKey(ValueKey<String>('cube-$id')))
          .flagsCollection
          .isSelected
          .toBoolOrNull()!;
      expect(selected('system'), isTrue);
      expect(selected('dark'), isFalse);
      await t.tap(find.byKey(const ValueKey<String>('cube-dark')));
      await t.pump();
      expect(form.written, {'preference': 'dark'});
      expect(selected('dark'), isTrue);
      expect(selected('system'), isFalse);
    });

    testWidgets('Appearance follows a host change to the preference', (
      t,
    ) async {
      await t.pumpWidget(column());
      form.publish(
        ready(ThemeSettings(preference: ThemePreference.light), revision: 1),
      );
      await t.pump();
      expect(
        t
            .getSemantics(find.byKey(const ValueKey<String>('cube-light')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
    });

    testWidgets('the font group starts collapsed on the text size row', (
      t,
    ) async {
      await t.pumpWidget(column());
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('Only affects conversation content'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('Code font'), findsNothing);
      expect(find.text('Terminal font size'), findsNothing);
    });

    testWidgets('the expander reveals every font and size row', (t) async {
      await t.pumpWidget(column());
      await t.tap(find.byKey(const ValueKey<String>('font-expander')));
      await t.pump();
      for (final title in [
        'Text font',
        'Code font',
        'Code font size',
        'Terminal font',
        'Terminal font size',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('11'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('font-expander')));
      await t.pump();
      expect(find.text('Code font'), findsNothing);
    });

    testWidgets('a stepper arrow changes the size and writes it', (t) async {
      await t.pumpWidget(column());
      // Arrows are invisible without hover but present: a hover reveals them.
      final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(t.getCenter(find.text('14')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('font-text-up')));
      await t.pump();
      expect(form.written, {'fontSize': 15});
      expect(find.text('15'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('font-text-down')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('font-text-down')));
      await t.pump();
      expect(service.current.fontSize, 13);
    });

    testWidgets('an arrow is disabled at its limit', (t) async {
      form.publish(ready(ThemeSettings(fontSize: 22)));
      await t.pumpWidget(column());
      await t.tap(find.byKey(const ValueKey<String>('font-text-up')));
      await t.pump();
      expect(form.writes, isEmpty);
      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('a font list commits normalized when the field blurs', (
      t,
    ) async {
      await t.pumpWidget(column());
      await t.tap(find.byKey(const ValueKey<String>('font-expander')));
      await t.pump();
      final field = find.descendant(
        of: find.byKey(const ValueKey<String>('font-code-family')),
        matching: find.byType(EditableText),
      );
      await t.tap(field);
      await t.enterText(field, 'Fira Code, monospace');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(form.written, {'codeFontFamily': '"Fira Code", monospace'});
      expect(service.current.codeFontFamily, '"Fira Code", monospace');
    });

    testWidgets('controls are disabled when the host document is read-only', (
      t,
    ) async {
      form.publish(ready(ThemeSettings(), writable: false));
      await t.pumpWidget(column());
      await t.tap(find.byKey(const ValueKey<String>('cube-light')));
      await t.tap(find.byKey(const ValueKey<String>('font-text-up')));
      await t.pump();
      expect(form.writes, isEmpty);
    });

    testWidgets('Chinese copy comes from the generated dictionary', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      await t.pumpWidget(column());
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('浅色'), findsOneWidget);
      expect(find.text('深色'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('字号大小'), findsOneWidget);
      expect(find.text('px'), findsOneWidget);
    });

    testWidgets('the last row of the column carries no separator', (t) async {
      await t.pumpWidget(column());
      await t.tap(find.byKey(const ValueKey<String>('font-expander')));
      await t.pump();
      bool hasLine(Finder row) =>
          (t
                      .widget<DshDecoratedBox>(
                        find
                            .descendant(
                              of: row,
                              matching: find.byType(DshDecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .border !=
          null;
      // Appearance is not last: its hairline is drawn.
      expect(
        (t
                    .widget<DshDecoratedBox>(
                      find
                          .descendant(
                            of: find.byKey(const ValueKey('appearance-row')),
                            matching: find.byType(DshDecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .border,
        isNotNull,
      );
      // The font group ends the column: only its last row drops the hairline.
      final rows = find.byType(DshSettingsRow);
      expect(rows, findsNWidgets(6));
      for (var i = 0; i < 5; i++) {
        expect(hasLine(rows.at(i)), isTrue, reason: 'row $i');
      }
      expect(hasLine(rows.at(5)), isFalse);
    });
  });
}

/// A form whose writes fail the way a dead transport does.
class _Failing implements ConfigForm {
  _Failing(this.inner);
  final ConfigForm inner;

  @override
  ConfigFormSnapshot get snapshot => inner.snapshot;
  @override
  void Function() subscribe(void Function() l) => inner.subscribe(l);
  @override
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision}) =>
      Future.error(StateError('down'));
  @override
  Future<bool> set(String field, Object? value) =>
      Future.error(StateError('down'));
  @override
  Future<bool> unset(String field) => Future.error(StateError('down'));
}
