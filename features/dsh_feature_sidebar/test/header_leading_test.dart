import 'dart:io';
import 'dart:ui' as ui;

import 'package:dsh_feature_sidebar/dsh_feature_sidebar.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_layout/dsh_layout.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements ShortcutStorage {
  String? raw;
  @override
  String? read() => raw;
  @override
  void write(String next) => raw = next;
}

class _Services implements SidebarServices {
  _Services({this.shortcuts});
  @override
  final ShortcutService? shortcuts;
  final store = LayoutStore(viewportWidth: 1280);
  @override
  late final layout = LayoutController(store, (_) => false);
  var started = 0;
  @override
  DshI18n get i18n => const DshI18n(DshLocale.en);
  @override
  String get brandName => 'Whalee';
  @override
  Widget browsingRegion(BuildContext context, SidebarSectionOwner owner) =>
      const SizedBox.shrink();
  @override
  void startSession() => started++;
}

Widget _controls(
  _Services services, {
  bool collapsed = true,
  ShellPlatform platform = ShellPlatform.darwin,
}) => ShellScope(
  chrome: ShellChrome(platform: platform),
  child: SidebarLeadingControls(services: services, collapsed: collapsed),
);

void main() {
  testWidgets(
    'Header consumer uses two canonical buttons with native semantics and keyboard actions',
    (t) async {
      final services = _Services();
      final semantics = t.ensureSemantics();
      await t.pumpWidget(dshTestApp(Center(child: _controls(services))));
      expect(find.byType(DshButton), findsNWidgets(2));
      expect(
        t.widgetList<DshButton>(find.byType(DshButton)).map((b) => b.profile),
        everyElement(DshButtonProfile.headerAction),
      );
      final toggle = find.byKey(const ValueKey('leading-toggle'));
      final session = find.byKey(const ValueKey('leading-new-session'));
      expect(t.getSize(toggle), const Size(28, 28));
      expect(t.getTopLeft(session).dx - t.getTopRight(toggle).dx, 8);
      expect(
        t.widgetList<DshIcon>(find.byType(DshIcon)).map((i) => i.size),
        everyElement(16),
      );
      final action = t.getSemantics(
        find.descendant(of: session, matching: find.byType(DshButton)),
      );
      expect(action.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      t.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          nodeId: action.id,
          viewId: t.view.viewId,
          type: SemanticsAction.tap,
        ),
      );
      await t.pump();
      expect(services.started, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(services.started, 3);
      final before = services.store.layoutInfo.sidebar;
      await t.tap(toggle);
      await t.pump();
      expect(services.store.layoutInfo.sidebar, isNot(before));
      semantics.dispose();
    },
  );

  testWidgets(
    'Header tooltip waits 500ms and shortcut catalog updates reach the existing consumer',
    (t) async {
      final shortcuts = ShortcutService(
        runtime: ShortcutRuntime.desktop,
        platform: ShortcutPlatform.macos,
        storage: _MemoryStorage(),
      );
      final services = _Services(shortcuts: shortcuts);
      void Function() register(String code) => shortcuts.register(
        ShortcutCommand(
          id: 'session.new',
          label: () => 'New Session',
          defaults: {
            'desktop:macos': ShortcutBinding(code, const [
              ShortcutModifier.primary,
            ]),
          },
          resolve: (_) => ShortcutHandled(services.startSession),
        ),
      );
      var off = register('KeyN');
      await shortcuts.start();
      await t.pumpWidget(dshTestApp(Center(child: _controls(services))));
      final session = find.byKey(const ValueKey('leading-new-session'));
      DshTooltip tooltip() => t.widget<DshTooltip>(
        find.descendant(of: session, matching: find.byType(DshTooltip)),
      );
      expect(tooltip().shortcutKeys, ['⌘', 'N']);
      final pointer = await t.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(t.getCenter(session));
      await t.pump(const Duration(milliseconds: 499));
      expect(find.text('New session'), findsNothing);
      await t.pump(const Duration(milliseconds: 1));
      await t.pump();
      expect(find.text('New session'), findsOneWidget);
      off();
      off = register('KeyJ');
      await t.pump();
      expect(tooltip().shortcutKeys, ['⌘', 'J']);
      await pointer.removePointer();
      await t.pumpWidget(const SizedBox.shrink());
      off();
      shortcuts.dispose();
    },
  );

  testWidgets(
    'Header migration preserves Windows expanded/collapsed tooltip placement',
    (t) async {
      final services = _Services();
      for (final collapsed in [false, true]) {
        await t.pumpWidget(
          dshTestApp(
            Center(
              child: _controls(
                services,
                collapsed: collapsed,
                platform: ShellPlatform.windows,
              ),
            ),
          ),
        );
        expect(find.byType(DshButton), findsNWidgets(collapsed ? 2 : 1));
        expect(
          t
              .widgetList<DshTooltip>(find.byType(DshTooltip))
              .map((hint) => hint.side),
          everyElement(DshTooltipSide.bottom),
        );
      }
      await t.pumpWidget(dshTestApp(Center(child: _controls(services))));
      expect(
        t
            .widgetList<DshTooltip>(find.byType(DshTooltip))
            .map((hint) => hint.side),
        everyElement(DshTooltipSide.right),
      );
    },
  );

  // Actual component raster artifacts; the companion source capture imports
  // the locked HeaderLeadingControls.tsx itself. These are not golden baselines.
  for (final brightness in Brightness.values) {
    for (final density in [1.0, 2.0]) {
      testWidgets('actual Header raster ${brightness.name} dpr$density', (
        t,
      ) async {
        final services = _Services();
        final boundary = GlobalKey();
        t.view.devicePixelRatio = density;
        t.view.physicalSize = Size(400 * density, 240 * density);
        addTearDown(t.view.reset);
        await t.pumpWidget(
          dshTestApp(
            Center(
              child: RepaintBoundary(
                key: boundary,
                child: Builder(
                  builder: (context) => SizedBox(
                    width: 96,
                    height: 64,
                    child: ColoredBox(
                      color: context.dsh.bgBase,
                      child: DshSurface(
                        color: context.dsh.bgBase,
                        child: Center(child: _controls(services)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            brightness: brightness,
          ),
        );
        await t.pump();
        Future<void> capture(String state) async {
          final output = Platform.environment['HEADER_LEADING_RASTER_OUT'];
          if (output == null) return;
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await t.runAsync(() async {
            final image = await render.toImage(pixelRatio: density);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final directory = Directory(output)..createSync(recursive: true);
            File(
              '${directory.path}/flutter-${brightness.name}-dpr${density.toInt()}-$state.png',
            ).writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('idle');
        final toggle = find.byKey(const ValueKey('leading-toggle'));
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(toggle));
        await t.pump();
        await capture('hover');
        await mouse.down(t.getCenter(toggle));
        await t.pump(const Duration(milliseconds: 100));
        await capture('pressed');
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        await t.pump(); // settle the native-equivalent pointer focus first
        final action = t.widget<FocusableActionDetector>(
          find.descendant(
            of: toggle,
            matching: find.byType(FocusableActionDetector),
          ),
        );
        expect(action.focusNode!.hasPrimaryFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.home);
        await t.pump();
        await t
            .pump(); // FocusableActionDetector publishes highlight post-frame
        expect(find.byKey(DshButton.focusRingKey), findsOneWidget);
        await capture('focus');
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
