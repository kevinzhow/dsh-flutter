/// The key adapter, the reference dialog and its recording and editing, the
/// settings row.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dsh_feature_shortcuts/dsh_feature_shortcuts.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage implements ShortcutStorage {
  String? raw;
  int writes = 0;

  @override
  Future<String?> read() async => raw;

  @override
  Future<void> write(String next) async {
    raw = next;
    writes++;
  }
}

class _Services implements ShortcutsServices {
  _Services(this.shortcuts);

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);

  @override
  final ShortcutService shortcuts;
}

/// Ignore RenderFlex overflow reports: the test font (Ahem) is far wider than
/// the product font, and the editor row is checked at real widths by the
/// desktop parity captures.
void ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Press an editor control through its handler: in the test font the editor
/// row is wider than the dialog, so a pointer tap would miss the control.
Future<void> press(WidgetTester t, String key) async {
  t.widget<GestureDetector>(find.byKey(ValueKey(key))).onTap!();
  await t.pump();
}

void main() {
  late _Storage storage;
  late ShortcutService service;
  late _Services services;
  late SlotRegistry slots;
  late ShortcutsFeature feature;
  var toggled = 0;

  // Built inside the test body: the service's futures must live in the test's
  // fake-async zone to be pumped.
  void build() {
    toggled = 0;
    storage = _Storage();
    service = ShortcutService(
      runtime: ShortcutRuntime.desktop,
      platform: ShortcutPlatform.linux,
      storage: storage,
    );
    services = _Services(service);
    slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    service.register(
      ShortcutCommand(
        id: 'sidebar.left.toggle',
        label: () => 'Toggle sidebar',
        defaults: {
          for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
            p: const ShortcutBinding('KeyB', [ShortcutModifier.primary]),
          for (final p in ['web:macos', 'web:windows'])
            p: const ShortcutBinding('KeyB', [
              ShortcutModifier.primary,
              ShortcutModifier.alt,
            ]),
        },
        resolve: (_) => ShortcutHandled(() => toggled++),
      ),
    );
    feature = registerShortcutsFeature(slots, services: services).feature;
  }

  Future<void> pump(WidgetTester t, {bool host = false}) async {
    build();
    unawaited(service.start());
    await t.pump();
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final themed = dshTestApp(const SizedBox()) as MaterialApp;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigatorKey,
        theme: themed.theme,
        builder: host
            ? (context, child) =>
                  ShortcutKeyboardHost(service: service, child: child!)
            : null,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the key host dispatches a bound chord to its command', (
    t,
  ) async {
    await pump(t, host: true);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(toggled, 1);
  });

  testWidgets('a bare key does not trigger the chord', (t) async {
    await pump(t, host: true);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(toggled, 0);
  });

  testWidgets('the reference opens, lists rows by group and closes', (t) async {
    await pump(t);
    final done = feature.open();
    await t.pumpAndSettle();
    expect(feature.isOpen, isTrue);
    expect(find.byKey(const ValueKey('shortcut-reference')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shortcut-row-sidebar.left.toggle')),
      findsOneWidget,
    );
    expect(find.text('Toggle sidebar'), findsOneWidget);
    expect(service.modals.top, 'shortcuts');
    feature.close();
    await t.pumpAndSettle();
    await done;
    expect(feature.isOpen, isFalse);
    expect(service.modals.top, isNull);
  });

  testWidgets('search narrows the rows and clears', (t) async {
    await pump(t);
    unawaited(feature.open());
    await t.pumpAndSettle();
    final total = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('shortcut-row-'),
    );
    final all = total.evaluate().length;
    expect(all, greaterThan(1));
    await t.enterText(find.byKey(const ValueKey('shortcut-search')), 'sidebar');
    await t.pumpAndSettle();
    expect(total, findsOneWidget);
    await t.tap(find.byKey(const ValueKey('shortcut-search-clear')));
    await t.pumpAndSettle();
    expect(total.evaluate().length, all);
  });

  testWidgets('recording a new chord saves it to the local preference', (
    t,
  ) async {
    ignoreOverflow();
    await pump(t);
    unawaited(feature.open(command: 'sidebar.left.toggle'));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shortcut-editor-sidebar.left.toggle')),
      findsOneWidget,
    );
    await press(t, 'shortcut-recorder');
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 2));
    expect(storage.writes, 1);
    final saved = jsonDecode(storage.raw!) as Map<String, Object?>;
    expect(jsonEncode(saved), contains('KeyJ'));
    final entry = service.registry.entry('sidebar.left.toggle')!;
    expect(entry.binding?.code, 'KeyJ');
    expect(entry.modified, isTrue);
  });

  testWidgets('reset restores the default binding', (t) async {
    ignoreOverflow();
    await pump(t);
    unawaited(feature.open(command: 'sidebar.left.toggle'));
    await t.pumpAndSettle();
    await press(t, 'shortcut-clear');
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 2));
    expect(service.registry.entry('sidebar.left.toggle')!.binding, isNull);
    // The reference stays open; choosing the row opens its editor again.
    await t.tap(find.text('Toggle sidebar'));
    await t.pumpAndSettle();
    await press(t, 'shortcut-reset');
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 2));
    expect(
      service.registry.entry('sidebar.left.toggle')!.binding?.code,
      'KeyB',
    );
  });

  testWidgets('the settings row offers the reference', (t) async {
    await pump(t);
    final rows = slots.renderList(
      DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
      const SettingsOwner(),
    );
    expect(rows, hasLength(1));
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigatorKey,
        theme: (dshTestApp(const SizedBox()) as MaterialApp).theme,
        home: Scaffold(body: Column(children: rows)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('shortcuts-open-row')));
    await t.pumpAndSettle();
    expect(feature.isOpen, isTrue);
    feature.close();
    await t.pumpAndSettle();
  });

  testWidgets('the open command toggles the reference with Mod+/', (t) async {
    await pump(t, host: true);
    Future<void> chord() async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.slash);
      await t.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }

    await chord();
    expect(feature.isOpen, isTrue);
    await chord();
    expect(feature.isOpen, isFalse);
  });
}
