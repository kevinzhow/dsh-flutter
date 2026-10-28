import 'dart:async';

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/plugin_card_fixture.dart';

final Map<String, ParityCase> pluginCardCases = {
  'plugin-cards.manager': ParityCase(
    widgets: [
      'dsh_feature_plugins:PluginManagerPage loaded cards',
      'dsh_ui:DshPluginCard',
      'dsh_ui:DshPluginCardList',
    ],
    framed: false,
    geometryProbe: pluginCardGeometryProbe,
    notes: 'Actual manager with shared offline data. Published-bundle source runner required; no source-TS substitution. SVG image formats, highlight and sticky touch hover remain pending.',
    build: (ctx) => PluginCardCaptureSurface(
      scenario: (ctx.props['scenario'] as Map).cast<String, Object?>(),
      i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
    ),
  ),
};

/// Actual render boxes and public control state; this callback never pumps or
/// sends input. It observes the same tree as the captured PNG before release.
Map<String, Object?> pluginCardGeometryProbe(
  WidgetTester tester,
  ParityContext ctx,
  RenderBox captureRoot,
) {
  final package = (ctx.props['scenario'] as Map)['package'] as Map;
  final cardFinder = find.byKey(ValueKey('plugin-card-${package['name']}'));
  final cards = cardFinder.evaluate().toList();

  Map<String, Object?>? read(Element? element, {String? text}) {
    if (element == null) return null;
    final render = element.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    final offset = render.localToGlobal(Offset.zero, ancestor: captureRoot);
    final rect = offset & render.size;
    return {
      'bounds': [rect.left, rect.top, rect.width, rect.height],
      'rawFlutterRect': {
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
      },
      'widgetType': element.widget.runtimeType.toString(),
      'renderType': render.runtimeType.toString(),
      'measurement': element.widget is DshChromeText
          ? 'DshChromeText outer render/line box; not glyph ink or a stretched action'
          : 'public widget outer RenderBox',
      if (text != null) 'text': text,
    };
  }

  Element? one(Finder finder) => finder.evaluate().firstOrNull;
  Finder under(Finder finder) =>
      find.descendant(of: cardFinder, matching: finder);
  final card = cards.length == 1
      ? tester.widget<DshPluginCard>(cardFinder)
      : null;
  final action = under(find.byKey(DshPluginCard.actionKey));
  final actionElement = one(action);
  final actionWidget = actionElement?.widget as DshButton?;
  final frame = under(find.byKey(DshPluginCard.frameKey));
  final defaultArtwork = find.descendant(
    of: frame,
    matching: find.byType(DshPluginDefaultArtwork),
  );
  final artwork =
      one(defaultArtwork) ??
      one(find.descendant(of: frame, matching: find.byType(Image)));
  Element? textElement(String? value) => value == null
      ? null
      : one(
          under(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DshChromeText &&
                  (widget.data == value || widget.semanticsLabel == value),
            ),
          ),
        );
  final switchFinder = under(
    find.byKey(ValueKey('plugin-switch-${package['name']}')),
  );
  final switchElement = one(switchFinder);
  final switchWidget = switchElement?.widget as DshSwitch?;
  FocusNode? actionFocus;
  if (actionElement != null) {
    final detector = one(
      find.descendant(
        of: action,
        matching: find.byType(FocusableActionDetector),
      ),
    );
    actionFocus = (detector?.widget as FocusableActionDetector?)?.focusNode;
  }
  final ring = one(
    find.descendant(of: action, matching: find.byKey(DshButton.focusRingKey)),
  );
  final tags = under(find.byType(DshTag)).evaluate().map((element) {
    final tag = element.widget as DshTag;
    return {
      ...?read(
        element,
        text: tag.child is DshChromeText
            ? (tag.child as DshChromeText).data
            : null,
      ),
      'tone': tag.tone.name,
      'profile': tag.profile.name,
    };
  }).toList();
  return {
    'schema': 'dsh-plugin-card-geometry/1',
    'coordinateBasis': {
      'space': 'capture-root logical pixels; viewport aligned',
      'origin': [0.0, 0.0],
      'layoutViewport': [captureRoot.size.width, captureRoot.size.height],
      'devicePixelRatio': ctx.density,
      'measurement': 'RenderBox.localToGlobal(Offset.zero, ancestor: captureRoot) plus raw RenderBox.size',
      'rounding': 'none',
    },
    'status': cards.length == 1 ? 'measured' : 'expected-one-card',
    'geometrySemantics': {
      'title': 'visible DshChromeText outer line box; compare separately with the source text-sized title DOM button',
      'action': 'canonical stretched DshButton action/semantic hit box; source counterpart is the whole-card pseudo-element hit area, not the text-sized DOM button',
      'innerCard': 'canonical card outer Stack including metadata; not a viewport or heading-row inference',
      'rawRenderParagraph': 'not sampled',
      'glyphInkBounds': 'not sampled',
    },
    'cardCount': cards.length,
    'card': cards.length == 1 ? read(cards.single) : null,
    'innerCard': read(one(under(find.byType(Stack)))),
    'action': read(actionElement),
    'title': read(textElement(card?.title), text: card?.title),
    'description': read(
      textElement(card?.description),
      text: card?.description,
    ),
    'artworkFrame': read(one(frame)),
    'artwork': read(artwork),
    'artworkKind': artwork?.widget is DshPluginDefaultArtwork
        ? 'native default/fallback artwork widget'
        : artwork == null
        ? null
        : 'native Image widget; no DOM/SVG equivalence inferred',
    'imageConfigured': card?.image != null,
    'tags': tags,
    'metadataError': read(
      textElement(card?.metadataError),
      text: card?.metadataError,
    ),
    'switch': switchWidget == null
        ? null
        : {
            ...?read(switchElement),
            'checked': switchWidget.value.toString(),
            'value': switchWidget.value,
            'disabled': switchWidget.onChanged == null,
          },
    'hover': actionWidget?.sourceHovered,
    'focusedTitle': actionFocus?.hasPrimaryFocus,
    'titleFocusVisible': actionElement == null ? null : ring != null,
    'titleOutline': {
      'focusRingPresent': actionElement == null ? null : ring != null,
      'bounds': read(ring)?['bounds'],
      'measurement': 'actual canonical native focus-ring widget presence/bounds; not a CSS pseudo-element assertion',
    },
    'focusMeasurement': 'actual card action FocusableActionDetector.focusNode.hasPrimaryFocus; visible native title text is measured separately from its stretched action',
    'optionalParts': {
      'descriptionPresent':
          card?.description != null && card!.description!.isNotEmpty,
      'metadataErrorPresent': card?.metadataError != null,
      'tagCount': tags.length,
    },
  };
}

/// Full actual manager; no card layout, metric or paint is supplied by this
/// fixture. The only outer paint is the normal application theme canvas.
class PluginCardCaptureSurface extends StatefulWidget {
  const PluginCardCaptureSurface({
    super.key,
    required this.scenario,
    required this.i18n,
    this.onFixture,
  });
  final Map<String, Object?> scenario;
  final DshI18n i18n;
  final void Function(SyntheticPluginCardFixture)? onFixture;

  @override
  State<PluginCardCaptureSurface> createState() =>
      _PluginCardCaptureSurfaceState();
}

class _PluginCardCaptureSurfaceState extends State<PluginCardCaptureSurface> {
  late final fixture = SyntheticPluginCardFixture(widget.scenario);
  final slots = SlotRegistry();

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    widget.onFixture?.call(fixture);
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('plugin-cards-capture'),
    color: context.dsh.bgBase,
    child: DefaultTextStyle(
      style: context.dsh
          .textStyle('--dsw-font-s-14')
          .copyWith(color: context.dsh.labelPrimary),
      child: PluginManagerPage(
        model: fixture.manager,
        market: fixture.market,
        slots: slots,
        i18n: widget.i18n,
      ),
    ),
  );
}
