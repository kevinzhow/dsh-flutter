import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const labels = DshSettingsFormLabels(
  unavailable: 'Not loaded',
  readOnly: 'Read-only deployment',
  saveFailed: 'Not accepted',
  save: 'Save',
  saving: 'Saving...',
);

SettingsFormShell shell({
  bool available = true,
  bool writable = true,
  bool dirty = false,
  bool invalid = false,
  bool saving = false,
  bool failed = false,
}) => SettingsFormShell(
  available: available,
  writable: writable,
  dirty: dirty,
  invalid: invalid,
  saving: saving,
  failed: failed,
);

Widget app(Widget child, {double width = 390}) => dshTestApp(
  SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
  size: Size(width, 900),
);

Widget field({
  String text = '30000',
  bool overridden = false,
  bool invalid = false,
  bool disabled = false,
  String? hint = 'A hint',
  DshSettingsFieldHelp? help,
  void Function(String)? onEdit,
  VoidCallback? onReset,
}) => DshSettingsValueField(
  id: 'f',
  label: 'Timeout',
  hint: hint,
  help: help,
  text: text,
  overridden: overridden,
  invalid: invalid,
  overriddenLabel: 'Overridden',
  resetLabel: 'Reset to default',
  invalidLabel: 'Enter a number',
  disabled: disabled,
  numeric: true,
  onEdit: onEdit ?? (_) {},
  onReset: onReset ?? () {},
);

bool saveEnabled(WidgetTester t) =>
    t
        .widget<DshButton>(
          find.descendant(
            of: find.byKey(DshSettingsForm.saveKey),
            matching: find.byType(DshButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  group('DshSettingsForm', () {
    testWidgets('unavailable shows only the notice', (t) async {
      await t.pumpWidget(
        app(
          DshSettingsForm(
            labels: labels,
            state: shell(available: false),
            onSave: () {},
            onDiscard: () {},
            children: const [Text('controls')],
          ),
        ),
      );
      expect(find.text('Not loaded'), findsOneWidget);
      expect(find.text('controls'), findsNothing);
      expect(find.byKey(DshSettingsForm.saveKey), findsNothing);
    });

    testWidgets('read-only shows the notice over the controls', (t) async {
      await t.pumpWidget(
        app(
          DshSettingsForm(
            labels: labels,
            state: shell(writable: false),
            onSave: () {},
            onDiscard: () {},
            children: const [Text('controls')],
          ),
        ),
      );
      expect(find.text('Read-only deployment'), findsOneWidget);
      expect(find.text('controls'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('save follows dirty, invalid and saving', (t) async {
      var saves = 0;
      Widget form(SettingsFormShell s) => app(
        DshSettingsForm(
          labels: labels,
          state: s,
          onSave: () => saves++,
          onDiscard: () {},
          children: const [Text('controls')],
        ),
      );
      await t.pumpWidget(form(shell()));
      expect(saveEnabled(t), isFalse);
      await t.pumpWidget(form(shell(dirty: true)));
      expect(saveEnabled(t), isTrue);
      await t.tap(find.text('Save'));
      expect(saves, 1);
      await t.pumpWidget(form(shell(dirty: true, invalid: true)));
      expect(saveEnabled(t), isFalse);
      await t.pumpWidget(form(shell(dirty: true, saving: true)));
      expect(saveEnabled(t), isFalse);
      expect(find.text('Saving...'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      await t.tap(find.text('Saving...'), warnIfMissed: false);
      expect(saves, 1);
    });

    testWidgets('a failed save says so beside the button', (t) async {
      await t.pumpWidget(
        app(
          DshSettingsForm(
            labels: labels,
            state: shell(dirty: true, failed: true),
            onSave: () {},
            onDiscard: () {},
            children: const [],
          ),
        ),
      );
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(find.text('Not accepted'), findsOneWidget);
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('leaving the page discards, staying does not', (t) async {
      var discards = 0;
      Widget form(bool shown) => app(
        shown
            ? DshSettingsForm(
                labels: labels,
                state: shell(),
                onSave: () {},
                onDiscard: () => discards++,
                children: const [],
              )
            : const SizedBox(),
      );
      await t.pumpWidget(form(true));
      await t.pumpWidget(form(true));
      expect(discards, 0);
      await t.pumpWidget(form(false));
      expect(discards, 1);
    });

    testWidgets('the store builder follows the store', (t) async {
      final store = SettingsFormStore<int>(1);
      await t.pumpWidget(
        app(
          DshSettingsFormStoreBuilder<int>(
            store: store,
            builder: (context, n) => Text('n=$n'),
          ),
        ),
      );
      expect(find.text('n=1'), findsOneWidget);
      store.set(2);
      await t.pump();
      expect(find.text('n=2'), findsOneWidget);
    });
  });

  group('DshSettingsValueField', () {
    testWidgets('shows label, text and hint, no badge', (t) async {
      await t.pumpWidget(app(field()));
      expect(find.text('Timeout'), findsOneWidget);
      expect(find.text('A hint'), findsOneWidget);
      expect(find.text('Overridden'), findsNothing);
      expect(find.byKey(DshSettingsValueField.resetKey('f')), findsNothing);
      expect(
        t
            .widget<EditableText>(
              find.byKey(DshSettingsValueField.inputKey('f')),
            )
            .controller
            .text,
        '30000',
      );
    });

    testWidgets('typing reports each change', (t) async {
      final seen = <String>[];
      await t.pumpWidget(app(field(text: '', onEdit: seen.add)));
      await t.enterText(find.byKey(DshSettingsValueField.inputKey('f')), '12');
      await t.pump();
      expect(seen, ['12']);
    });

    testWidgets('a text pushed from outside replaces the input', (t) async {
      await t.pumpWidget(app(field(text: '1')));
      await t.pumpWidget(app(field(text: '77')));
      expect(
        t
            .widget<EditableText>(
              find.byKey(DshSettingsValueField.inputKey('f')),
            )
            .controller
            .text,
        '77',
      );
    });

    testWidgets('overridden shows the badge and a working reset', (t) async {
      var resets = 0;
      await t.pumpWidget(app(field(overridden: true, onReset: () => resets++)));
      expect(find.text('Overridden'), findsOneWidget);
      await t.tap(find.byKey(DshSettingsValueField.resetKey('f')));
      expect(resets, 1);
    });

    testWidgets('badge and reset also fit a wide column', (t) async {
      await t.pumpWidget(app(field(overridden: true), width: 900));
      expect(find.text('Overridden'), findsOneWidget);
      expect(find.text('Reset to default'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('disabled blocks the reset and the input', (t) async {
      var resets = 0;
      await t.pumpWidget(
        app(field(overridden: true, disabled: true, onReset: () => resets++)),
      );
      await t.tap(find.byKey(DshSettingsValueField.resetKey('f')));
      expect(resets, 0);
      expect(
        t
            .widget<EditableText>(
              find.byKey(DshSettingsValueField.inputKey('f')),
            )
            .readOnly,
        isTrue,
      );
    });

    testWidgets('invalid replaces the hint with the message', (t) async {
      final theme = resolveTheme(
        officialPack,
        ThemeSettings(),
        Brightness.light,
      );
      await t.pumpWidget(app(field(invalid: true)));
      expect(find.text('A hint'), findsNothing);
      expect(find.text('Enter a number'), findsOneWidget);
      final text = t.widget<Text>(
        find.descendant(
          of: find.byKey(DshSettingsValueField.messageKey('f')),
          matching: find.byType(Text),
        ),
      );
      expect(text.style!.color, theme.color('--dsw-alias-state-error-primary'));
    });

    testWidgets('a field without hint shows no message line', (t) async {
      await t.pumpWidget(app(field(hint: null)));
      expect(find.byKey(DshSettingsValueField.messageKey('f')), findsNothing);
    });

    testWidgets('the help button discloses and hides the rules', (t) async {
      await t.pumpWidget(
        app(
          field(
            help: const DshSettingsFieldHelp(
              label: 'About timeout',
              content: Text('Rules go here'),
            ),
          ),
        ),
      );
      expect(find.text('Rules go here'), findsNothing);
      await t.tap(find.byKey(DshSettingsValueField.helpKey('f')));
      await t.pump();
      expect(find.text('Rules go here'), findsOneWidget);
      await t.tap(find.byKey(DshSettingsValueField.helpKey('f')));
      await t.pump();
      expect(find.text('Rules go here'), findsNothing);
    });
  });
}
