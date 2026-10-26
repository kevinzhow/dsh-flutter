import 'dart:async';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const options = [
  SelectOption(
    id: 'a/flash',
    label: 'deepseek-flash',
    group: SelectOptionGroup(name: 'a', label: 'DeepSeek Account'),
    active: true,
  ),
  SelectOption(
    id: 'a/pro',
    label: 'deepseek-pro',
    group: SelectOptionGroup(name: 'a', label: 'DeepSeek Account'),
  ),
  SelectOption(
    id: 'b/mini',
    label: 'mini-1',
    group: SelectOptionGroup(name: 'b', label: 'Local Provider'),
  ),
];

void main() {
  late PopupSelectController popup;
  late List<String> selected;
  late List<String> events;
  late Completer<List<SelectOption>> load;

  PopupSelectSpec spec({List<SelectOption>? gated}) => PopupSelectSpec(
    searchLabels: () => const PopupSearchLabels(
      placeholder: 'Search models…',
      empty: 'No models available.',
      noResults: 'No matching models.',
    ),
    options: (id, signal) => load.future,
    onSelect: (o, id) async => selected.add(o.id),
  );

  // Built inside the test body so its futures run on the test's fake clock.
  void fresh() {
    selected = [];
    events = [];
    load = Completer();
    popup = PopupSelectController(
      consume: (s) {
        events.add('consume');
        return true;
      },
      focusComposer: () => events.add('focus'),
    );
  }

  void tw(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        fresh();
        await body(t);
      });

  Widget app({
    DshLocale locale = DshLocale.en,
    Size size = const Size(800, 600),
  }) => dshTestApp(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 380,
        child: PopupSelectOverlay(
          sessionId: 's1',
          controller: popup,
          i18n: DshI18n(locale),
        ),
      ),
    ),
    size: size,
  );

  Future<void> open(WidgetTester t, {List<SelectOption> rows = options}) async {
    if (load.isCompleted) load = Completer();
    popup.open('model', spec(), 's1', EnterSegment('/model'));
    await t.pump();
    load.complete(rows);
    await t.pump();
    await t.pump();
  }

  tw('closed it draws nothing', (t) async {
    await t.pumpWidget(app());
    expect(find.byKey(const ValueKey('command-popup')), findsNothing);
  });

  tw(
    'loading, then grouped rows with the current one checked and the search focused',
    (t) async {
      await t.pumpWidget(app());
      popup.open('model', spec(), 's1', EnterSegment('/model'));
      await t.pump();
      expect(find.text('Loading options…'), findsOneWidget);
      expect(find.text('Search models…'), findsOneWidget);
      load.complete(options);
      await t.pump();
      await t.pump();
      expect(find.text('DeepSeek Account'), findsOneWidget);
      expect(find.text('Local Provider'), findsOneWidget);
      expect(find.text('deepseek-flash'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('popup-option-a/flash')),
        findsOneWidget,
      );
      expect(
        t
            .widget<EditableText>(find.byKey(const ValueKey('popup-search')))
            .focusNode
            .hasFocus,
        isTrue,
      );
    },
  );

  tw('typing filters locally; an empty result says so with the command copy', (
    t,
  ) async {
    await t.pumpWidget(app());
    await open(t);
    await t.enterText(find.byKey(const ValueKey('popup-search')), 'mini');
    await t.pump();
    expect(find.text('mini-1'), findsOneWidget);
    expect(find.text('deepseek-pro'), findsNothing);
    await t.enterText(find.byKey(const ValueKey('popup-search')), 'zzz');
    await t.pump();
    expect(find.text('No matching models.'), findsOneWidget);
  });

  tw('an empty catalog says so before any filtering', (t) async {
    await t.pumpWidget(app());
    await open(t, rows: const []);
    expect(find.text('No models available.'), findsOneWidget);
  });

  tw(
    'arrows walk the rows, Enter accepts the highlight, the popup closes and the keyboard returns',
    (t) async {
      await t.pumpWidget(app());
      await open(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump();
      expect(selected, ['a/pro']);
      expect(events, ['consume', 'focus']);
      expect(find.byKey(const ValueKey('command-popup')), findsNothing);
    },
  );

  tw('Escape returns to the composer without selecting', (t) async {
    await t.pumpWidget(app());
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(selected, isEmpty);
    expect(events, ['focus']);
    expect(find.byKey(const ValueKey('command-popup')), findsNothing);
  });

  tw('Shift+Tab leaves like Escape; Tab accepts like Enter', (t) async {
    await t.pumpWidget(app());
    await open(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(events, ['focus']);
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
    expect(selected, ['a/flash']);
  });

  tw('a tap picks a row', (t) async {
    await t.pumpWidget(app());
    await open(t);
    await t.tap(find.byKey(const ValueKey('popup-option-b/mini')));
    await t.pump();
    await t.pump();
    expect(selected, ['b/mini']);
  });

  tw('keyboard navigation reveals an offscreen grouped option', (t) async {
    final rows = [
      for (var i = 0; i < 30; i++)
        SelectOption(
          id: 'item-$i',
          label: 'Option $i',
          group: i < 15
              ? const SelectOptionGroup(name: 'a', label: 'First')
              : const SelectOptionGroup(name: 'b', label: 'Second'),
        ),
    ];
    await t.pumpWidget(app());
    await open(t, rows: rows);
    for (var i = 0; i < 24; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
    }
    await t.pump();
    final viewport = find.byKey(const ValueKey('popup-list'));
    final option = find.byKey(const ValueKey('popup-option-item-24'));
    expect(
      t.getTopLeft(option).dy,
      greaterThanOrEqualTo(t.getTopLeft(viewport).dy),
    );
    expect(
      t.getBottomLeft(option).dy,
      lessThanOrEqualTo(t.getBottomLeft(viewport).dy),
    );
    for (var i = 0; i < 8; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
    }
    await t.pump();
    final earlier = find.byKey(const ValueKey('popup-option-item-16'));
    final heading = find.text('Second');
    expect(
      t.getTopLeft(earlier).dy,
      greaterThanOrEqualTo(t.getBottomLeft(heading).dy + 2),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(selected, ['item-16']);
  });

  tw('opening a long grouped list leaves the first visible row unobscured', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    t.view.devicePixelRatio = 2.625;
    t.view.physicalSize = const Size(1080, 2400);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    final rows = [
      for (var i = 0; i < 28; i++)
        SelectOption(
          id: '$i',
          label: 'Option $i',
          group: SelectOptionGroup(
            name: '${i ~/ 14}',
            label: i < 14 ? 'First provider' : 'Second provider',
          ),
        ),
    ];
    popup.state.set(
      PopupState(
        open: true,
        command: 'model',
        status: PopupStatus.ready,
        options: rows,
      ),
    );
    final height = ValueNotifier<double>(41);
    addTearDown(height.dispose);
    await t.pumpWidget(
      dshTestApp(
        Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, value, child) =>
                SizedBox(width: 380, height: value, child: child),
            child: PopupSelectOverlay(
              sessionId: 's1',
              controller: popup,
              i18n: const DshI18n(DshLocale.en),
            ),
          ),
        ),
      ),
    );
    height.value = 320;
    await t.pumpAndSettle();
    final list = find.byKey(const ValueKey('popup-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    expect(t.state<ScrollableState>(scrollable.first).position.pixels, 0);
    final heading = find.text('First provider');
    final row = find.byKey(const ValueKey('popup-option-0'));
    expect(
      t.getTopLeft(row).dy,
      greaterThanOrEqualTo(t.getBottomLeft(heading).dy + 2),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  tw('ungrouped rows do not add the adjacent-group gap', (t) async {
    await t.pumpWidget(app());
    await open(
      t,
      rows: const [
        SelectOption(id: 'plain', label: 'Plain'),
        SelectOption(
          id: 'first',
          label: 'First row',
          group: SelectOptionGroup(name: 'a', label: 'First group'),
        ),
        SelectOption(
          id: 'second',
          label: 'Second row',
          group: SelectOptionGroup(name: 'b', label: 'Second group'),
        ),
      ],
    );
    final plain = find.byKey(const ValueKey('popup-option-plain'));
    final firstHeading = find.text('First group');
    final firstRow = find.byKey(const ValueKey('popup-option-first'));
    final secondHeading = find.text('Second group');
    expect(t.getTopLeft(firstHeading).dy - t.getBottomLeft(plain).dy, 4);
    expect(t.getTopLeft(secondHeading).dy - t.getBottomLeft(firstRow).dy, 7);
  });

  tw('a failed load shows the error with a retry that reloads', (t) async {
    await t.pumpWidget(app());
    popup.open('model', spec(), 's1', EnterSegment('/model'));
    load.completeError(StateError('catalog failed'));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('popup-error')), findsOneWidget);
    expect(find.textContaining('catalog failed'), findsOneWidget);
    load = Completer();
    await t.tap(find.byKey(const ValueKey('popup-retry')));
    await t.pump();
    load.complete(options);
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('popup-error')), findsNothing);
    expect(find.text('mini-1'), findsOneWidget);
  });

  tw('a rejected selection keeps the popup and shows why', (t) async {
    popup = PopupSelectController(consume: (_) => true, focusComposer: () {});
    await t.pumpWidget(app());
    popup.open(
      'model',
      PopupSelectSpec(
        options: (id, signal) async => options,
        onSelect: (o, id) async => throw StateError('writer held'),
      ),
      's1',
      EnterSegment('/model'),
    );
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('popup-option-a/pro')));
    await t.pump();
    await t.pump();
    expect(find.textContaining('writer held'), findsOneWidget);
    expect(find.byKey(const ValueKey('command-popup')), findsOneWidget);
  });

  tw('a gated row asks for the risk acknowledgement before it runs', (t) async {
    const gated = SelectOption(
      id: 'danger',
      label: 'Full access',
      confirmation: SelectConfirmation(
        title: 'Enable full access?',
        description: 'No approvals.',
        acknowledgeLabel: 'I understand',
        cancelLabel: 'Cancel',
        confirmLabel: 'Enable',
      ),
    );
    await t.pumpWidget(app());
    await open(t, rows: const [gated]);
    await t.tap(find.byKey(const ValueKey('popup-option-danger')));
    await t.pump();
    await t.pump();
    expect(find.text('Enable full access?'), findsOneWidget);
    expect(selected, isEmpty);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(selected, isEmpty);
    expect(find.byKey(const ValueKey('command-popup')), findsOneWidget);
  });

  tw('the zh copy', (t) async {
    await t.pumpWidget(app(locale: DshLocale.zh));
    popup.open(
      'model',
      PopupSelectSpec(
        options: (i, s) => load.future,
        onSelect: (o, i) async {},
      ),
      's1',
      EnterSegment('/model'),
    );
    await t.pump();
    expect(find.text('正在加载选项…'), findsOneWidget);
    expect(find.text('搜索…'), findsOneWidget);
  });

  tw(
    'a phone row is dsh\'s compact 27px too: the rows do not change with the width',
    (t) async {
      await t.pumpWidget(app(size: const Size(400, 800)));
      await open(t);
      expect(
        t.getRect(find.byKey(const ValueKey('popup-option-a/pro'))).height,
        closeTo(27, 1),
      );
      await t.pumpWidget(app(size: const Size(1200, 800)));
      await t.pump();
      expect(
        t.getRect(find.byKey(const ValueKey('popup-option-a/pro'))).height,
        closeTo(27, 1),
      );
    },
  );
}
