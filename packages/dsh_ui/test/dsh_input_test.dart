import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the input commits edited text on Enter and follows persisted updates',
    (t) async {
      final value = ValueNotifier('Initial');
      final commits = <String>[];
      addTearDown(value.dispose);
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 200,
              child: ValueListenableBuilder<String>(
                valueListenable: value,
                builder: (_, current, _) => DshInput(
                  value: current,
                  placeholder: 'Font family',
                  semanticLabel: 'Text font',
                  maxLength: 12,
                  onCommit: commits.add,
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(EditableText);
      await t.tap(field);
      await t.enterText(field, 'Example');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(commits, ['Example']);
      value.value = 'Saved';
      await t.pumpAndSettle();
      expect(t.widget<EditableText>(field).controller.text, 'Saved');
    },
  );

  testWidgets(
    'leading icon uses the published slot and leaves room for input',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 200,
              child: DshInput(
                controller: controller,
                placeholder: 'Search',
                icon: const Icon(Icons.search, key: ValueKey('input-icon')),
              ),
            ),
          ),
        ),
      );
      final input = find.byType(DshInput);
      final icon = find.byKey(const ValueKey('input-icon'));
      final field = find.byType(EditableText);
      final left = t.getTopLeft(input).dx;
      expect(t.getSize(input).height, 34);
      expect(t.getSize(icon), const Size(16, 16));
      expect(t.getTopLeft(icon).dx - left, 9); // Border plus wrapper padding.
      expect(t.getTopLeft(field).dx - left, 33);
      await t.enterText(field, 'models');
      await t.pump();
      expect(controller.text, 'models');
      expect(find.text('Search'), findsNothing);
    },
  );

  testWidgets('a disabled input neither focuses nor accepts pointer edits', (
    t,
  ) async {
    final focus = FocusNode();
    final controller = TextEditingController(text: 'Locked');
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: SizedBox(
            width: 200,
            child: DshInput(
              controller: controller,
              focusNode: focus,
              enabled: false,
            ),
          ),
        ),
      ),
    );
    await t.tapAt(t.getCenter(find.byType(DshInput)));
    await t.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(controller.text, 'Locked');
  });

  testWidgets('a supplied controller and focus node can be replaced safely', (
    t,
  ) async {
    final first = TextEditingController(text: 'First');
    final second = TextEditingController(text: 'Second');
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);
    Widget app(TextEditingController controller, FocusNode focus) => dshTestApp(
      Center(
        child: SizedBox(
          width: 200,
          child: DshInput(controller: controller, focusNode: focus),
        ),
      ),
    );
    await t.pumpWidget(app(first, firstFocus));
    await t.pumpWidget(app(second, secondFocus));
    final field = find.byType(EditableText);
    expect(t.widget<EditableText>(field).controller, same(second));
    expect(t.widget<EditableText>(field).focusNode, same(secondFocus));
    await t.enterText(field, 'New');
    expect(second.text, 'New');
    expect(first.text, 'First');
  });

  testWidgets('maximum length keeps the portion that fits, including emoji', (
    t,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: SizedBox(
            width: 200,
            child: DshInput(controller: controller, maxLength: 4),
          ),
        ),
      ),
    );
    final field = find.byType(EditableText);
    await t.enterText(field, 'ab');
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'aXYZb',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await t.pump();
    expect(controller.text, 'aXYb');
    expect(controller.selection.baseOffset, 3);
    await t.enterText(field, 'a');
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a😀😀',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await t.pump();
    expect(controller.text, 'a😀');
  });
}
