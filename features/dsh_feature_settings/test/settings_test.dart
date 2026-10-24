import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SlotRegistry slots;
  late void Function() off;
  var i18n = const DshI18n(DshLocale.en);
  String? version = '0.2.1-rc.2';
  var closed = 0;

  final sectionSlot = DshSlots.settingsSection.typed<SettingsOwner, Widget>();
  final itemSlot = DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>();

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    version = '0.2.1-rc.2';
    closed = 0;
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    off = registerSettingsFeature(
      slots,
      i18n: () => i18n,
      hostVersion: () => version,
    );
  });

  Widget page({Size size = const Size(390, 800), String? section}) =>
      dshTestApp(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: SettingsPage(
            slots: slots,
            i18n: i18n,
            onClose: () => closed++,
            initialSection: section,
          ),
        ),
        size: size,
      );

  /// A test surface of [size] logical pixels (the page lays out by its width).
  void surface(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  void row(String id, int order, String text) =>
      slots.register<SettingsOwner, Widget>(
        itemSlot,
        (_) => DshSettingsRow(
          title: text,
          description: '$text description',
          control: const SizedBox(),
        ),
        id: id,
        order: order,
      );

  group('registration', () {
    test('fills General (order 0) and the current version row (order 100)', () {
      expect(
        [for (final e in slots.entries(sectionSlot)) (e.id, e.order, e.label)],
        [('general', 0, 'General')],
      );
      expect(
        [for (final e in slots.entries(itemSlot)) (e.id, e.order)],
        [('current-version', 100)],
      );
    });

    test('the label follows the language', () {
      i18n = const DshI18n(DshLocale.zh);
      expect(slots.entries(sectionSlot).single.label, '通用设置');
    });

    test('the disposer withdraws both', () {
      off();
      expect(slots.entries(sectionSlot), isEmpty);
      expect(slots.entries(itemSlot), isEmpty);
    });
  });

  group('phone', () {
    testWidgets('lists the sections first, then opens one with a way back', (
      t,
    ) async {
      surface(t, const Size(390, 800));
      await t.pumpWidget(page());
      expect(find.byKey(const ValueKey('settings-title')), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('general-section')), findsNothing);
      await t.tap(find.byKey(const ValueKey('settings-nav-general')));
      await t.pump();
      expect(find.byKey(const ValueKey('general-section')), findsOneWidget);
      expect(
        t
            .widget<DshChromeText>(
              find.byKey(const ValueKey('settings-section-title')),
            )
            .data,
        'General',
      );
      await t.tap(find.byKey(const ValueKey('settings-section-back')));
      await t.pump();
      expect(find.byKey(const ValueKey('general-section')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
    });

    testWidgets('the back control of the list leaves the settings', (t) async {
      surface(t, const Size(390, 800));
      await t.pumpWidget(page());
      await t.tap(find.byKey(const ValueKey('settings-back')));
      expect(closed, 1);
    });

    testWidgets('can open on a given section', (t) async {
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      expect(find.byKey(const ValueKey('general-section')), findsOneWidget);
    });

    testWidgets('a section that registers later joins the list', (t) async {
      surface(t, const Size(390, 800));
      await t.pumpWidget(page());
      expect(find.byKey(const ValueKey('settings-nav-plugins')), findsNothing);
      slots.register<SettingsOwner, Widget>(
        sectionSlot,
        (_) => const Text('plugins body'),
        id: 'plugins',
        order: 50,
        label: () => 'Plugins',
      );
      await t.pump();
      expect(
        find.byKey(const ValueKey('settings-nav-plugins')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('settings-nav-plugins')));
      await t.pump();
      expect(find.text('plugins body'), findsOneWidget);
    });

    testWidgets('a section that unregisters underneath returns to the list', (
      t,
    ) async {
      final offPlugins = slots.register<SettingsOwner, Widget>(
        sectionSlot,
        (_) => const Text('plugins body'),
        id: 'plugins',
        order: 50,
        label: () => 'Plugins',
      );
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'plugins'));
      expect(find.text('plugins body'), findsOneWidget);
      offPlugins();
      await t.pump();
      expect(find.text('plugins body'), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
    });

    testWidgets('Chinese labels', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      surface(t, const Size(390, 800));
      await t.pumpWidget(page());
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('通用设置'), findsOneWidget);
    });
  });

  group('wide', () {
    testWidgets('shows the rail beside the first section and a close control', (
      t,
    ) async {
      surface(t, const Size(1000, 800));
      await t.pumpWidget(page(size: const Size(1000, 800)));
      expect(find.byKey(const ValueKey('general-section')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-section-back')), findsNothing);
      await t.tap(find.byKey(const ValueKey('settings-close')));
      expect(closed, 1);
    });

    testWidgets('selecting in the rail swaps the content', (t) async {
      slots.register<SettingsOwner, Widget>(
        sectionSlot,
        (_) => const Text('plugins body'),
        id: 'plugins',
        order: 50,
        label: () => 'Plugins',
      );
      surface(t, const Size(1000, 800));
      await t.pumpWidget(page(size: const Size(1000, 800)));
      await t.tap(find.byKey(const ValueKey('settings-nav-plugins')));
      await t.pump();
      expect(find.text('plugins body'), findsOneWidget);
      expect(find.byKey(const ValueKey('general-section')), findsNothing);
    });
  });

  group('General section', () {
    testWidgets('stacks the rows in order and ends the column on the last', (
      t,
    ) async {
      row('late', 50, 'Late row');
      row('early', -10, 'Early row');
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      final titles = [
        for (final w in t.widgetList<DshSettingsRow>(
          find.byType(DshSettingsRow),
        ))
          w.title,
      ];
      expect(titles, ['Early row', 'Late row']);
      // The current version row is last: its predecessors keep their hairline.
      final rows = find.byType(DshSettingsRow);
      bool line(int i) =>
          (t
                      .widget<DshDecoratedBox>(
                        find
                            .descendant(
                              of: rows.at(i),
                              matching: find.byType(DshDecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .border !=
          null;
      expect(line(0), isTrue);
      expect(line(1), isTrue);
      expect(find.text('Current version: 0.2.1-rc.2'), findsOneWidget);
    });

    testWidgets('the last row drops its hairline', (t) async {
      off();
      row('only', 0, 'Only row');
      slots.register<SettingsOwner, Widget>(
        sectionSlot,
        (_) => GeneralSection(slots: slots),
        id: 'general',
        order: 0,
        label: () => 'General',
      );
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      final box = t.widget<DshDecoratedBox>(
        find
            .descendant(
              of: find.byType(DshSettingsRow),
              matching: find.byType(DshDecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).border, isNull);
    });

    testWidgets('a row that registers while the section is open appears', (
      t,
    ) async {
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      expect(find.text('Late host row'), findsNothing);
      final withdraw = slots.register<SettingsOwner, Widget>(
        itemSlot,
        (_) => const DshSettingsRow(
          title: 'Late host row',
          description: 'd',
          control: SizedBox(),
        ),
        id: 'late-host',
        order: 5,
      );
      await t.pump();
      expect(find.text('Late host row'), findsOneWidget);
      withdraw();
      await t.pump();
      expect(find.text('Late host row'), findsNothing);
    });

    testWidgets('the version row shows nothing while the host has not said', (
      t,
    ) async {
      version = null;
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      expect(find.textContaining('Current version'), findsNothing);
    });

    testWidgets('Chinese version copy', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      surface(t, const Size(390, 800));
      await t.pumpWidget(page(section: 'general'));
      expect(find.text('当前版本：0.2.1-rc.2'), findsOneWidget);
    });
  });
}
