// The `/` and `@` candidate menu (dsh ui-input-trigger MenuView) over the same fixture state the React host mounts.
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_input_trigger/dsh_feature_input_trigger.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:flutter/widgets.dart';

class _Port implements TriggerEditorPort {
  @override
  bool beginCommand(CommandClaim claim, TokenSpan span) => false;
  @override
  bool consumeBareToken(String token) => false;
  @override
  bool consumeSpan(TokenSpan span) => false;
  @override
  bool insertReference(ReferenceInsert reference, TokenSpan span) => false;
  @override
  bool insertText(String text, TokenSpan span, {bool keepCompleting = false}) =>
      false;
  @override
  void notify(bool error, String text) {}
  @override
  void requestFocus() {}
}

/// Fixture candidates as the React host receives them.
InputTriggerCandidate _item(Map<String, dynamic> m) => InputTriggerCandidate(
  name: m['name'] as String,
  label: m['label'] as String?,
  description: m['description'] as String?,
  icon: m['icon'] as String?,
  section: m['section'] as String?,
  drill: m['drill'] == true,
);

final Map<String, ParityCase> inputTriggerCases = {
  'input.menu': ParityCase(
    widgets: const ['dsh_feature_input_trigger:TriggerMenuOverlay'],
    // The menu material is translucent: it sits on the page fill, which is the page's here.
    framed: false,
    build: (ctx) {
      final props = ctx.props;
      final registry = InputTriggerRegistry();
      final controller = registry.sessionOf('parity', _Port());
      final groups = [
        for (final g in (props['groups'] as List).cast<Map<String, dynamic>>())
          MenuGroup(
            source: g['source'] as String,
            showGroupTitle: g['showGroupTitle'] != false,
            ready: (g['status'] ?? 'ready') == 'ready',
            items: [
              for (final i in (g['items'] as List).cast<Map<String, dynamic>>())
                _item(i),
            ],
          ),
      ];
      final hl = props['highlight'] as Map<String, dynamic>?;
      controller.menu.set(
        MenuState(
          open: true,
          generation: 1,
          groups: groups,
          highlight: hl == null
              ? null
              : MenuHighlight(hl['source'] as String, hl['index'] as int),
        ),
      );
      final crumbs = props['crumbs'] as Map<String, dynamic>?;
      if (crumbs != null) {
        controller.headers.set({
          for (final e in crumbs.entries)
            e.key: [
              for (final c in (e.value as List).cast<Map<String, dynamic>>())
                InputTriggerCrumb(
                  label: c['label'] as String,
                  value: c['value'] as String,
                  current: c['current'] == true,
                ),
            ],
        });
      }
      return ColoredBox(
        color: ctx.theme.bgBase,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: (props['width'] as num).toDouble(),
            child: TriggerMenuOverlay(
              sessionId: 'parity',
              controller: controller,
              i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
            ),
          ),
        ),
      );
    },
  ),
};
