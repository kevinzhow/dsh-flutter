import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Tristate;

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plugin_cards_main.dart';

const _i18n = DshI18n(DshLocale.en);
String _t(String key, [Map<String, Object?> params = const {}]) =>
    _i18n.t('pluginManager', key, params: params);

void main() {
  setUpAll(loadPinnedFontsFromEnvironment);
  for (final viewport in [
    (size: const Size(1280, 720), dpr: 1.0),
    (size: const Size(390, 844), dpr: 1.0),
    (size: const Size(390, 844), dpr: 2.625),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'actual loaded manager native contract $viewport ${brightness.name}',
        (t) async {
          t.view.physicalSize = viewport.size * viewport.dpr;
          t.view.devicePixelRatio = viewport.dpr;
          addTearDown(t.view.reset);
          await t.pumpWidget(PluginCardsNativeApp(brightness: brightness));
          await t.pumpAndSettle();
          final measured = <String, Rect>{};
          final actionLabel = _t('openDetail', {'name': 'Synthetic plugin'});
          final switchLabel = _t('enableToggle', {'name': 'Synthetic plugin'});
          Finder card() => find.byType(DshPluginCard);
          Finder action() => find.descendant(
            of: card(),
            matching: find.byKey(DshPluginCard.actionKey),
          );
          Finder toggle() =>
              find.descendant(of: card(), matching: find.byType(DshSwitch));
          Future<void> scene(LogicalKeyboardKey key, String id) async {
            await t.sendKeyEvent(key);
            await t.pumpAndSettle();
            expect(find.text('Card scenario: $id'), findsOneWidget);
            expect(find.byType(PluginManagerPage), findsOneWidget);
            expect(card(), findsOneWidget);
          }

          void requests(int attempts, int refused, bool enabled) => expect(
            find.text(
              'Requests: $attempts refused: $refused enabled: ${enabled ? 'on' : 'off'}',
            ),
            findsOneWidget,
          );
          Future<void> back() async {
            final target = find.widgetWithText(DshButton, _t('backToList'));
            measured['back'] = t.getRect(target);
            await t.tap(target);
            await t.pumpAndSettle();
            expect(card(), findsOneWidget);
          }

          void opened() => expect(find.text(_t('backToList')), findsOneWidget);
          void listed() => expect(find.text(_t('backToList')), findsNothing);
          void focusedOwner(Finder target) {
            final owner = t.getSemantics(target);
            final nodes = <SemanticsNode>[];
            void visit(SemanticsNode node) {
              if (node.flagsCollection.isFocused == Tristate.isTrue) {
                nodes.add(node);
              }
              node.visitChildren((child) {
                visit(child);
                return true;
              });
            }

            visit(owner);
            expect(nodes, hasLength(1));
            expect(nodes.single.rect, owner.rect);
            expect(
              nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
              isTrue,
            );
          }

          requests(0, 0, true);
          expect(
            t.widget<DshButton>(action()).profile,
            DshButtonProfile.pluginCard,
          );
          measured['card'] = t.getRect(card());
          measured['frame'] = t.getRect(find.byKey(DshPluginCard.frameKey));
          measured['switch'] = t.getRect(toggle());
          measured['counter'] = t.getRect(
            find.text('Requests: 0 refused: 0 enabled: on'),
          );
          measured['services'] = t.getRect(
            find.text('Services: synthetic offline'),
          );
          final nativeAction = t.getSemantics(action());
          final nativeSwitch = t.getSemantics(toggle());
          expect(nativeAction.getSemanticsData().label, actionLabel);
          expect(nativeSwitch.getSemanticsData().label, switchLabel);
          expect(nativeAction.id, isNot(nativeSwitch.id));
          expect(nativeAction.rect.size, t.getSize(card()));
          expect(nativeSwitch.rect.size, const Size(36, 20));
          expect(
            nativeAction.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          expect(
            nativeSwitch.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );

          final bounds = measured['card']!;
          await t.tapAt(bounds.topLeft + const Offset(2, 2));
          await t.pumpAndSettle();
          listed();
          requests(0, 0, true);
          await t.tapAt(Offset(bounds.left + 2, bounds.center.dy));
          await t.pumpAndSettle();
          opened();
          requests(0, 0, true);
          await back();
          await scene(LogicalKeyboardKey.f6, 'default');
          await t.tap(toggle());
          await t.pumpAndSettle();
          requests(1, 0, false);
          listed();
          expect(t.widget<DshSwitch>(toggle()).value, isFalse);

          await scene(LogicalKeyboardKey.f6, 'default');
          final detector = t.widget<FocusableActionDetector>(
            find.descendant(
              of: action(),
              matching: find.byType(FocusableActionDetector),
            ),
          );
          var tabs = 0;
          while (!detector.focusNode!.hasPrimaryFocus && tabs < 12) {
            await t.sendKeyEvent(LogicalKeyboardKey.tab);
            await t.pumpAndSettle();
            tabs++;
          }
          expect(detector.focusNode!.hasPrimaryFocus, isTrue);
          expect(tabs, 6);
          focusedOwner(action());
          expect(
            find.descendant(
              of: action(),
              matching: find.byKey(DshButton.focusRingKey),
            ),
            findsOneWidget,
          );
          measured['cardFocus'] = t.getRect(find.byKey(DshButton.focusRingKey));
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pumpAndSettle();
          opened();
          requests(0, 0, true);
          await back();
          await scene(LogicalKeyboardKey.f6, 'default');
          for (var i = 0; i < tabs; i++) {
            await t.sendKeyEvent(LogicalKeyboardKey.tab);
            await t.pumpAndSettle();
          }
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pumpAndSettle();
          expect(find.byKey(DshButton.focusRingKey), findsNothing);
          expect(
            find.byKey(const ValueKey('dsh-switch-focus-ring')),
            findsOneWidget,
          );
          focusedOwner(toggle());
          await t.sendKeyEvent(LogicalKeyboardKey.space);
          await t.pumpAndSettle();
          requests(1, 0, false);
          listed();
          final beforeNativeTap = t.getSemantics(toggle());
          beforeNativeTap.owner!.performAction(
            beforeNativeTap.id,
            SemanticsAction.tap,
          );
          await t.pumpAndSettle();
          requests(2, 0, true);
          listed();
          final openViaSemantics = t.getSemantics(action());
          openViaSemantics.owner!.performAction(
            openViaSemantics.id,
            SemanticsAction.tap,
          );
          await t.pumpAndSettle();
          opened();
          requests(2, 0, true);

          await scene(LogicalKeyboardKey.f7, 'error-disabled');
          expect(t.widget<DshSwitch>(toggle()).onChanged, isNull);
          expect(
            t
                .getSemantics(toggle())
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await t.tap(toggle());
          await t.pumpAndSettle();
          requests(0, 0, false);
          listed();
          expect(find.text(_t('statusProblem')), findsOneWidget);

          await scene(LogicalKeyboardKey.f8, 'refused-toggle');
          await t.tap(toggle());
          await t.pumpAndSettle();
          requests(1, 1, true);
          listed();
          expect(t.widget<DshSwitch>(toggle()).value, isTrue);

          await scene(LogicalKeyboardKey.f9, 'long-tags');
          final tags = find.descendant(
            of: card(),
            matching: find.byType(DshTag),
          );
          expect(tags, findsNWidgets(4));
          expect(
            t.getSize(card()).height,
            greaterThan(measured['card']!.height),
          );
          measured['wrap'] = t.getRect(card());
          for (var i = 0; i < 4; i++) {
            measured['tag-$i'] = t.getRect(tags.at(i));
          }

          await scene(LogicalKeyboardKey.f10, 'image-failed');
          expect(find.byType(DshPluginDefaultArtwork), findsOneWidget);
          expect(
            t.getSize(find.byType(DshPluginDefaultArtwork)),
            const Size(36, 36),
          );
          measured['fallback'] = t.getRect(
            find.byType(DshPluginDefaultArtwork),
          );
          await scene(LogicalKeyboardKey.f11, 'no-description');
          expect(t.getSemantics(action()).getSemanticsData().hint, isEmpty);
          measured['noDescription'] = t.getRect(card());
          await scene(LogicalKeyboardKey.f12, 'metadata-error');
          final metadata = find.text(
            _t('metadataError', {
              'error': 'Synthetic metadata diagnostic\nwith a second line',
            }),
          );
          expect(metadata, findsOneWidget);
          measured['metadata'] = t.getRect(card());
          measured['metadataLine'] = t.getRect(metadata);
          await t.tapAt(t.getCenter(metadata));
          await t.pumpAndSettle();
          opened();
          requests(0, 0, true);

          debugPrint(
            'PLUGIN_CARDS_NATIVE_GEOMETRY ${jsonEncode({
              'viewport': [viewport.size.width, viewport.size.height],
              'dpr': viewport.dpr,
              'theme': brightness.name,
              'pinnedFonts': Platform.environment['WHALEE_PIN_FONTS']?.isNotEmpty ?? false,
              'tabsToTitle': tabs,
              'actionLabel': actionLabel,
              'switchLabel': switchLabel,
              'backLabel': _t('backToList'),
              for (final row in measured.entries) row.key: [row.value.left, row.value.top, row.value.right, row.value.bottom],
            })}',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpAndSettle();
        },
      );
    }
  }
}
