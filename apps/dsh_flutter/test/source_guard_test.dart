import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards for the rules every screen follows: colours and type come from
/// the theme contract, and every word a person reads comes from the catalog.
void main() {
  final roots = [
    'lib',
    '../../features/dsh_feature_approval/lib',
    '../../features/dsh_feature_attachment/lib',
    '../../features/dsh_feature_commands/lib',
    '../../features/dsh_feature_chat/lib',
    '../../features/dsh_feature_conversation/lib',
    '../../features/dsh_feature_documentpreview/lib',
    '../../features/dsh_feature_files/lib',
    '../../features/dsh_feature_input_trigger/lib',
    '../../features/dsh_feature_directory_picker_native/lib',
    '../../features/dsh_feature_layout/lib',
    '../../features/dsh_feature_open_in_app/lib',
    '../../features/dsh_feature_plan/lib',
    '../../features/dsh_feature_reference/lib',
    '../../features/dsh_feature_deliverables/lib',
    '../../features/dsh_feature_secret_mask/lib',
    '../../features/dsh_feature_subagent/lib',
    '../../features/dsh_feature_session/lib',
    '../../features/dsh_feature_settings/lib',
    '../../features/dsh_feature_model_settings/lib',
    '../../features/dsh_feature_agent_management/lib',
    '../../features/dsh_feature_plugins/lib',
    '../../features/dsh_feature_shortcuts/lib',
    '../../features/dsh_feature_sidebar/lib',
    '../../features/dsh_feature_sidebar_right/lib',
    '../../features/dsh_feature_sidebar_terminal/lib',
    '../../features/dsh_feature_tool/lib',
    '../../features/dsh_feature_user_questions/lib',
    '../../features/dsh_feature_workflow_run/lib',
    '../../packages/dsh_dockkit/lib',
    '../../packages/dsh_ui/lib',
  ];
  final files = [
    for (final r in roots)
      ...Directory(r)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];

  String strip(String source) => source
      .replaceAll(RegExp(r'//.*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  test('the guard sees the feature sources', () {
    expect(files.length, greaterThan(30));
  });

  test('icons come from dsh or Charcoal, never Material or Cupertino', () {
    // dsh's own glyphs are DshIcons / DshShellIcons; a control only Whalee has
    // uses CharcoalIcons (docs/parity.md, "Icons").
    final bad = RegExp(r'\bIcons\.|CupertinoIcons|\bIconData\b|\bIcon\(');
    // Every package of the workspace, not only the roots listed above.
    final everything = [
      'lib',
      for (final group in ['features', 'packages'])
        for (final d in Directory(
          '../../$group',
        ).listSync().whereType<Directory>())
          '${d.path}/lib',
    ].where((p) => Directory(p).existsSync());
    final all = [
      for (final r in everything)
        ...Directory(r)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];
    expect(all.length, greaterThan(files.length));
    for (final f in all) {
      expect(
        bad.hasMatch(strip(f.readAsStringSync())),
        isFalse,
        reason: '${f.path} draws a Material or Cupertino icon',
      );
    }
  });

  test('no hard-coded colours: every colour is a theme token', () {
    final bad = RegExp(
      r'Color\(\s*0x|Colors\.|Color\.fromRGBO|Color\.fromARGB',
    );
    for (final f in files) {
      // Fixed-colour artwork (dsh draws these glyphs with literal fills) and the
      // emulator's sixteen ANSI colours, which dsh leaves at xterm.js's own.
      if (f.path.endsWith('dsh_guide.dart') ||
          f.path.endsWith('terminal_theme.dart')) {
        continue;
      }
      expect(
        bad.hasMatch(strip(f.readAsStringSync())),
        isFalse,
        reason: '${f.path} hard-codes a colour',
      );
    }
  });

  test('no hard-coded font sizes or families: text styles come from the ladder', () {
    final bad = RegExp(
      r'fontSize\s*:|fontFamily\s*:|TextStyle\(\s*\n?\s*(fontSize|fontFamily)',
    );
    for (final f in files) {
      // dsh_text_baseline.dart measures a style's own face (it copies the
      // style's size and family; it names none).
      if (f.path.endsWith('dsh_text_baseline.dart')) continue;
      // The emulator takes the user's terminal font list from the theme and
      // names the built-in monospace stack beside it.
      if (f.path.endsWith('terminal_theme.dart')) continue;
      // Copying a resolved style's size/family preserves its theme tokens.
      // Keep rejecting literal values, including those in the same file.
      var source = strip(f.readAsStringSync()).replaceAll(
        RegExp(r'\b(fontSize|fontFamily)\s*:\s*[a-zA-Z_]\w*\.\1\s*,'),
        '',
      );
      // QueueDock.module.css explicitly uses 10px for compact file byte sizes;
      // the shared typography ladder has no corresponding token. Keep this
      // exception limited to that one literal, not the rest of the feature.
      if (f.path.endsWith('/queue_dock.dart')) {
        source = source.replaceAll(RegExp(r'fontSize\s*:\s*10\s*,'), '');
      }
      expect(
        bad.hasMatch(source),
        isFalse,
        reason: '${f.path} hard-codes a font size or family',
      );
    }
  });

  test(
    'no literal user-facing strings: Text, hints and labels read the catalog',
    () {
      final literalText = RegExp(r'''Text\(\s*['"][^'"$]*[A-Za-z]''');
      final literalLabel = RegExp(
        r'''(hintText|semanticLabel|label|tooltip|title)\s*:\s*['"][^'"$]*[A-Za-z]''',
      );
      for (final f in files) {
        final text = strip(f.readAsStringSync());
        expect(
          literalText.hasMatch(text),
          isFalse,
          reason: '${f.path} passes a string literal to Text',
        );
        expect(
          literalLabel.hasMatch(text),
          isFalse,
          reason: '${f.path} has a literal label or hint',
        );
      }
    },
  );
}
