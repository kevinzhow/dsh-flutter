import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SlotRegistry slots;
  late void Function() off;
  var i18n = const DshI18n(DshLocale.en);
  var closed = 0;

  final sectionSlot = DshSlots.settingsSection.typed<SettingsOwner, Widget>();
  final itemSlot = DshSlots.pluginsItem.typed<PluginItemOwner, Widget>();
  final views = <String, int>{};

  setUp(() {
    i18n = const DshI18n(DshLocale.en);
    closed = 0;
    views.clear();
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    off = registerSettingsFeature(
      slots,
      i18n: () => i18n,
      hostVersion: () => null,
    );
  });

  void Function() item(String id, int order, String title) =>
      slots.register<PluginItemOwner, Widget>(
        itemSlot,
        (owner) {
          views['$id/${owner.view.name}'] =
              (views['$id/${owner.view.name}'] ?? 0) + 1;
          return switch (owner.view) {
            PluginItemView.summary => Text('$title summary'),
            PluginItemView.page => Text('$title page'),
          };
        },
        id: id,
        order: order,
        label: () => title,
      );

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

  void surface(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  /// Let the section registration, one microtask behind the slot, land and
  /// the tree rebuild.
  Future<void> tick(WidgetTester t) async {
    await t.runAsync(pumpEventQueue);
    await t.pump();
  }

  List<(String, int, String?)> sections() => [
    for (final e in slots.entries(sectionSlot)) (e.id, e.order, e.label),
  ];

  group('registration', () {
    test('there is no Plugins section while no plugins.item is registered', () {
      expect(sections().map((s) => s.$1), ['general']);
    });

    test('the section follows the registrations, after General', () async {
      final a = item('a', 0, 'Alpha');
      await pumpEventQueue();
      expect(sections(), [
        ('general', 0, 'General'),
        ('plugins', 10, 'Plugins'),
      ]);
      final b = item('b', 1, 'Beta');
      await pumpEventQueue();
      expect(sections().map((s) => s.$1), ['general', 'plugins']);
      a();
      await pumpEventQueue();
      expect(sections().map((s) => s.$1), ['general', 'plugins']);
      b();
      await pumpEventQueue();
      expect(sections().map((s) => s.$1), ['general']);
      item('c', 0, 'Gamma');
      await pumpEventQueue();
      expect(sections().map((s) => s.$1), ['general', 'plugins']);
    });

    test('the label follows the language', () async {
      item('a', 0, 'Alpha');
      await pumpEventQueue();
      i18n = const DshI18n(DshLocale.zh);
      expect(sections().last.$3, '插件');
    });

    test('the disposer withdraws the section and stops following', () async {
      item('a', 0, 'Alpha');
      await pumpEventQueue();
      off();
      expect(sections().map((s) => s.$1), isNot(contains('plugins')));
      item('b', 1, 'Beta');
      await pumpEventQueue();
      expect(sections().map((s) => s.$1), isNot(contains('plugins')));
    });

    test('a burst of changes registers the section once', () async {
      item('a', 0, 'Alpha');
      item('b', 1, 'Beta');
      item('c', 2, 'Gamma');
      await pumpEventQueue();
      expect(sections().where((s) => s.$1 == 'plugins'), hasLength(1));
    });
  });

  group('phone', () {
    testWidgets('lists a card per plugin with its title and summary', (
      t,
    ) async {
      item('b', 20, 'Beta');
      item('a', 10, 'Alpha');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('Alpha summary'), findsOneWidget);
      expect(find.text('Beta summary'), findsOneWidget);
      // In `order`, not registration order.
      expect(
        t.getTopLeft(find.byKey(const ValueKey('plugin-item-a'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('plugin-item-b'))).dy),
      );
      // The list asks for the summary only.
      expect(views.keys.where((k) => k.endsWith('/page')), isEmpty);
    });

    testWidgets('opens the tapped card as a page and returns by the crumb', (
      t,
    ) async {
      item('a', 10, 'Alpha');
      item('b', 20, 'Beta');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      await t.tap(find.byKey(const ValueKey('plugin-item-b')));
      await t.pump();
      expect(find.byKey(const ValueKey('plugin-detail-b')), findsOneWidget);
      expect(find.text('Beta page'), findsOneWidget);
      expect(find.text('Beta summary'), findsOneWidget);
      expect(find.text('Alpha summary'), findsNothing);
      expect(find.text('Alpha page'), findsNothing);
      await t.tap(find.byKey(const ValueKey('plugin-detail-back')));
      await t.pump();
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
      expect(find.text('Beta page'), findsNothing);
    });

    testWidgets('the system back closes the page before the settings', (
      t,
    ) async {
      item('a', 10, 'Alpha');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      await t.tap(find.byKey(const ValueKey('plugin-item-a')));
      await t.pump();
      expect(find.text('Alpha page'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.text('Alpha page'), findsNothing);
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
    });

    testWidgets('a plugin that registers later joins the list', (t) async {
      item('a', 10, 'Alpha');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      expect(find.byKey(const ValueKey('plugin-item-b')), findsNothing);
      item('b', 20, 'Beta');
      await tick(t);
      expect(find.byKey(const ValueKey('plugin-item-b')), findsOneWidget);
    });

    testWidgets('a plugin that withdraws leaves the list', (t) async {
      final offA = item('a', 10, 'Alpha');
      item('b', 20, 'Beta');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      offA();
      await tick(t);
      expect(find.byKey(const ValueKey('plugin-item-a')), findsNothing);
      expect(find.byKey(const ValueKey('plugin-item-b')), findsOneWidget);
    });

    testWidgets('a page open on a withdrawn plugin returns to the list', (
      t,
    ) async {
      final offA = item('a', 10, 'Alpha');
      item('b', 20, 'Beta');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      await t.tap(find.byKey(const ValueKey('plugin-item-a')));
      await t.pump();
      expect(find.text('Alpha page'), findsOneWidget);
      offA();
      await tick(t);
      expect(find.text('Alpha page'), findsNothing);
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
    });

    testWidgets('the last plugin withdrawing returns to the section list', (
      t,
    ) async {
      final offA = item('a', 10, 'Alpha');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(section: 'plugins'));
      offA();
      await tick(t);
      expect(find.byKey(const ValueKey('plugins-list')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
    });

    testWidgets('Chinese copy: nav, group title and crumb', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      item('a', 10, 'Alpha');
      surface(t, const Size(390, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page());
      expect(find.text('插件'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('settings-nav-plugins')));
      await t.pump();
      expect(find.text('内置插件配置'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('plugin-item-a')));
      await t.pump();
      expect(find.text('插件'), findsWidgets);
      expect(find.text('Alpha page'), findsOneWidget);
    });
  });

  group('wide', () {
    testWidgets('opens a page inside the section beside the rail', (t) async {
      item('a', 10, 'Alpha');
      surface(t, const Size(1000, 800));
      await t.runAsync(pumpEventQueue);
      await t.pumpWidget(page(size: const Size(1000, 800)));
      await t.tap(find.byKey(const ValueKey('settings-nav-plugins')));
      await t.pump();
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('plugin-item-a')));
      await t.pump();
      expect(find.text('Alpha page'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('plugin-detail-back')));
      await t.pump();
      expect(find.byKey(const ValueKey('plugins-list')), findsOneWidget);
    });
  });
}
