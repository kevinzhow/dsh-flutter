import 'dart:convert';

import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

/// Shared compiled data; browser and plan tools extract this exact JSON literal.
/// The long hold is an explicit paired-PNG input, never the native default.
const toastScenarioJson = r'''
{
  "schema": "dsh-toast-scenarios/1",
  "stableHoldMs": 60000,
  "scenarios": [
    {"id": "no-icon", "icon": "none", "tone": null, "text": {"en": "Synthetic notice", "zh": "合成提示消息"}},
    {"id": "success", "icon": "none", "tone": "success", "text": {"en": "Synthetic notice", "zh": "合成提示消息"}},
    {"id": "warning", "icon": "warning", "tone": null, "text": {"en": "Synthetic notice", "zh": "合成提示消息"}},
    {"id": "long-warning", "icon": "warning", "tone": null, "text": {"en": "This is a deliberately long synthetic failure notice. It names the operation that failed and keeps natural paragraph wrapping without a fixed line count. The full text must remain readable on a narrow phone and a desktop window, using the actual content-box cap, icon seat and padding from the published source. No line break, font, colour or screenshot crop is fitted to this text.", "zh": "这是一条故意加长的合成失败提示。它说明失败的操作，并保留自然文本换行，不限制固定行数。在窄手机和桌面窗口中，完整文本都应可读，使用发布版本真实的内容宽度上限、图标位置和内边距。不会为这段文字拟合换行、字体、颜色或截图裁剪。"}},
    {"id": "long-no-icon", "icon": "none", "tone": null, "text": {"en": "This is a deliberately long synthetic notice without a glyph. It keeps natural paragraph wrapping without a fixed line count. The full text must remain readable on a narrow phone and a desktop window, using the actual content-box cap and padding from the published source. No line break, font, colour or screenshot crop is fitted to this text.", "zh": "这是一条故意加长且没有图标的合成提示。它保留自然文本换行，不限制固定行数。在窄手机和桌面窗口中，完整文本都应可读，使用发布版本真实的内容宽度上限和内边距。不会为这段文字拟合换行、字体、颜色或截图裁剪。"}},
    {"id": "whitespace", "icon": "none", "tone": null, "text": {"en": "  Synthetic   spaces\tand\nline breaks with\u00a0a non-breaking space.  ", "zh": "  合成   空格\t与\n换行以及\u00a0不换行空格。  "}, "pending": "CSS ASCII whitespace collapse is source-proven here; broader Unicode/line-breaking equivalence remains pending"},
    {"id": "unbroken-word", "icon": "warning", "tone": null, "text": {"en": "SyntheticUnbrokenToken_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "zh": "SyntheticUnbrokenToken_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}, "pending": "Sole unbreakable-run overflow is source-proven here; oversized runs inside mixed paragraphs remain pending"}
  ]
}
''';

final Map<String, Object?> toastFixtureData =
    (jsonDecode(toastScenarioJson) as Map).cast<String, Object?>();
final Map<String, Map<String, Object?>> toastScenarios = {
  for (final raw in toastFixtureData['scenarios'] as List)
    (raw as Map)['id'] as String: raw.cast<String, Object?>(),
};

Map<String, Object?> toastScenario(String id) =>
    toastScenarios[id] ??
    (throw ArgumentError.value(id, 'id', 'Unknown Toast scenario'));

String toastFixtureText(String id, String locale) =>
    (toastScenario(id)['text']
            as Map)[locale.split(RegExp('[-_]')).first == 'zh' ? 'zh' : 'en']
        as String;

/// Real canonical Toast. Omit [hold] for the actual source default lifecycle.
/// Paired captures explicitly supply stableHoldMs; native timer proofs do not.
DshToast toastFixtureWidget(
  String id,
  String locale, {
  Key? key,
  required VoidCallback onDone,
  Duration? hold,
}) {
  final scenario = toastScenario(id);
  return DshToast(
    key: key,
    text: toastFixtureText(id, locale),
    icon: scenario['icon'] == 'warning'
        ? const DshIcon(DshIcons.warning)
        : null,
    tone: scenario['tone'] == 'success' ? DshToastTone.success : null,
    hold: hold,
    onDone: onDone,
  );
}
