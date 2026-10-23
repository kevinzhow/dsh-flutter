import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_feature_settings_shell/dsh_feature_settings_shell.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const timeout = 'timeoutMs';
const output = 'maxOutputBytes';
const timeoutId = 'plugin-config-shell-timeout';
const outputId = 'plugin-config-shell-output';

Map<String, Object?> section({int t = 60000, int o = 64000}) => {
  timeout: t,
  output: o,
};

ConfigFormSnapshot ready({
  Map<String, Object?>? value,
  Map<String, Object?> user = const {},
  bool writable = true,
  int revision = 3,
}) => ConfigFormSnapshot(
  status: ConfigFormStatus.ready,
  value: value ?? section(),
  base: section(),
  user: user,
  revision: revision,
  writable: writable,
);

Map<String, Object?> schema() => objectSchema({
  timeout: numberNode(defaultValue: 60000),
  output: numberNode(defaultValue: 64000),
});

Map<String, Object?> view(
  String ns, {
  Map<String, Object?>? value,
  Map<String, Object?> user = const {},
  int revision = 3,
}) => nsView(
  ns,
  schema: schema(),
  value: value ?? section(),
  base: section(),
  user: user,
  revision: revision,
);

Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => pumpEventQueue());
  await t.pump();
}

void surface(WidgetTester t) {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget app(Widget child) => dshTestApp(
  SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
);

Finder input(String id) => find.byKey(DshSettingsValueField.inputKey(id));

String inputText(WidgetTester t, String id) =>
    t.widget<EditableText>(input(id)).controller.text;

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
  group('adapter', () {
    late FakeConfigForm form;
    late ConfigFormScope scope;

    setUp(() {
      form = FakeConfigForm(ready(user: {timeout: 5}));
      scope = ConfigFormScope(form);
    });

    test('maps the snapshot field for field', () {
      final s = scope.snapshot;
      expect(s.status, SettingsScopeStatus.ready);
      expect(s.value, section());
      expect(s.base, section());
      expect(s.user, {timeout: 5});
      expect(s.writable, isTrue);
      expect(s.revision, 3);
    });

    test('maps each sync status', () {
      expect(
        ConfigFormScope(FakeConfigForm()).snapshot.status,
        SettingsScopeStatus.loading,
      );
      form.publish(
        const ConfigFormSnapshot(status: ConfigFormStatus.unavailable),
      );
      expect(scope.snapshot.status, SettingsScopeStatus.unavailable);
    });

    test('subscribes to the form and the disposer stops it', () {
      var calls = 0;
      final off = scope.subscribe(() => calls++);
      form.publish(ready(revision: 4));
      expect(calls, 1);
      off();
      form.publish(ready(revision: 5));
      expect(calls, 1);
    });

    test('mutate maps the ops and carries the revision fence', () async {
      expect(
        await scope.mutate(const [
          SettingsFormSetOp([timeout], 5),
          SettingsFormUnsetOp([output]),
        ], expectedRevision: 3),
        isTrue,
      );
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect((write.ops[0] as SetOp).path, [timeout]);
      expect((write.ops[0] as SetOp).value, 5);
      expect(write.ops[1], isA<UnsetOp>());
      expect(write.ops[1].path, [output]);
    });

    test('a refusal resolves false', () async {
      form.answer = false;
      expect(
        await scope.mutate(const [
          SettingsFormSetOp([timeout], 5),
        ]),
        false,
      );
    });
  });

  group('card', () {
    late FakeConfigForm form;
    late ShellCardController controller;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      form = FakeConfigForm(ready());
      controller = ShellCardController(form);
    });
    tearDown(() => controller.dispose());

    Widget card([PluginItemView view = PluginItemView.page]) =>
        app(ShellCard(controller: controller, i18n: i18n, view: view));

    testWidgets('the summary is the one-liner, in both languages', (t) async {
      surface(t);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(
        find.text(
          'Limit how long each command may run and how much it may output.',
        ),
        findsOneWidget,
      );
      i18n = const DshI18n(DshLocale.zh);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(find.text('限制每条命令最多能跑多久、最多输出多少内容。'), findsOneWidget);
    });

    testWidgets('unchanged: both fields shown, Save disabled', (t) async {
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Command timeout (ms)'), findsOneWidget);
      expect(find.text('Output cap per stream (bytes)'), findsOneWidget);
      expect(
        find.text('How long one command may run before it is terminated.'),
        findsOneWidget,
      );
      expect(inputText(t, timeoutId), '60000');
      expect(inputText(t, outputId), '64000');
      expect(find.text('Overridden'), findsNothing);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('a read-only host says so and blocks editing', (t) async {
      form.publish(ready(writable: false));
      surface(t);
      await t.pumpWidget(card());
      expect(find.byKey(DshSettingsForm.readOnlyKey), findsOneWidget);
      expect(t.widget<EditableText>(input(timeoutId)).readOnly, isTrue);
      expect(t.widget<EditableText>(input(outputId)).readOnly, isTrue);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('a namespace the host stopped serving says so', (t) async {
      surface(t);
      await t.pumpWidget(card());
      form.publish(
        const ConfigFormSnapshot(status: ConfigFormStatus.unavailable),
      );
      await t.pump();
      expect(find.byKey(DshSettingsForm.unavailableKey), findsOneWidget);
      expect(input(timeoutId), findsNothing);
    });

    testWidgets('dirty: edits to both fields save as one fenced write', (
      t,
    ) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(timeoutId), '90000');
      await t.enterText(input(outputId), '1000');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      expect(form.writes, isEmpty);
      await t.tap(find.text('Save'));
      await settle(t);
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect(
        [for (final op in write.ops) (op.path.single, (op as SetOp).value)],
        [(timeout, 90000), (output, 1000)],
      );
      expect(find.text('Overridden'), findsNWidgets(2));
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('an invalid number blocks the save and says why', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(timeoutId), '1 minute');
      await t.pump();
      expect(
        find.text('Enter a number, or leave blank to use the default.'),
        findsOneWidget,
      );
      expect(saveEnabled(t), isFalse);
      // A valid edit to the other field does not rescue the save.
      await t.enterText(input(outputId), '1000');
      await t.pump();
      expect(saveEnabled(t), isFalse);
      await t.enterText(input(timeoutId), '1e3');
      await t.pump();
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('saving: the button says so and is disabled', (t) async {
      final gate = Completer<void>();
      form.gate = gate.future;
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(timeoutId), '1');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      gate.complete();
      await settle(t);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a refused save keeps the drafts and says so', (t) async {
      form.answer = false;
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(timeoutId), '1');
      await t.enterText(input(outputId), '2');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t, timeoutId), '1');
      expect(inputText(t, outputId), '2');
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('overridden shows the badge; reset is per field', (t) async {
      form.publish(
        ready(value: section(t: 5, o: 7), user: {timeout: 5, output: 7}),
      );
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Overridden'), findsNWidgets(2));
      await t.tap(find.byKey(DshSettingsValueField.resetKey(timeoutId)));
      await t.pump();
      expect(inputText(t, timeoutId), '60000');
      expect(inputText(t, outputId), '7');
      expect(find.text('Overridden'), findsOneWidget);
      await t.tap(find.text('Save'));
      await settle(t);
      final write = form.writes.single;
      expect(write.ops.single, isA<UnsetOp>());
      expect(write.ops.single.path, [timeout]);
    });

    testWidgets('Chinese copy', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      form.publish(ready(user: {timeout: 60000}));
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('命令超时（毫秒）'), findsOneWidget);
      expect(find.text('单流输出上限（字节）'), findsOneWidget);
      expect(find.text('单条命令允许运行多久，超时即终止。'), findsOneWidget);
      expect(find.text('超出部分会转存到临时文件，而不是被丢弃。'), findsOneWidget);
      expect(find.text('已覆盖'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });
  });

  group('registration over a scripted host', () {
    late FakeHost host;
    late ConfigForms forms;
    late SlotRegistry slots;
    var i18n = const DshI18n(DshLocale.en);
    final itemSlot = DshSlots.pluginsItem.typed<PluginItemOwner, Widget>();
    final described = <Map<String, Object?>>[];

    List<(String, int, String?)> entries() => [
      for (final e in slots.entries(itemSlot)) (e.id, e.order, e.label),
    ];

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      described.clear();
      host = FakeHost();
      host.handlers['settings/describe'] = (_) => describeValue(described);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      forms = ConfigForms(host.remotes);
    });
    // Not awaited: see the agent-loop tests; a widget test writes from the
    // fake-async zone, which the teardown can never flush.
    tearDown(() {
      unawaited(forms.dispose());
      unawaited(host.close());
    });

    Future<void> refresh() async {
      host.emit('settings/document-updated', [bashNamespace, 1]);
      await pumpEventQueue();
    }

    void Function() register() =>
        registerShellSettingsFeature(slots, forms: forms, i18n: () => i18n);

    test(
      'no card while loading or while no shell executor is served',
      () async {
        final off = register();
        expect(entries(), isEmpty);
        described.add(view('agent-loop'));
        await refresh();
        expect(entries(), isEmpty);
        off();
      },
    );

    test('either executor namespace brings the card', () async {
      final off = register();
      await pumpEventQueue();
      described.add(view(bashNamespace));
      await refresh();
      expect(entries(), [('shell', 40, 'Shell')]);
      described.clear();
      await refresh();
      expect(entries(), isEmpty);
      described.add(view(pwshNamespace));
      await refresh();
      expect(entries(), [('shell', 40, 'Shell')]);
      off();
      expect(entries(), isEmpty);
    });

    test('the label follows the language', () async {
      described.add(view(bashNamespace));
      final off = register();
      await refresh();
      i18n = const DshI18n(DshLocale.zh);
      expect(entries().single.$3, '终端');
      off();
    });

    for (final ns in [bashNamespace, pwshNamespace]) {
      testWidgets('a save writes to the served executor ($ns)', (t) async {
        described.add(view(ns, revision: 7));
        host.handlers['settings/mutate'] = (args) => view(
          ns,
          value: section(t: 90000),
          user: {timeout: 90000},
          revision: 8,
        );
        final off = register();
        await t.runAsync(() async {
          host.emit('settings/document-updated', [ns, 1]);
          await pumpEventQueue();
        });
        expect(entries(), hasLength(1));
        surface(t);
        await t.pumpWidget(
          app(
            slots.renderOnly(
              itemSlot,
              'shell',
              const PluginItemOwner(view: PluginItemView.page),
            )!,
          ),
        );
        expect(inputText(t, timeoutId), '60000');
        await t.enterText(input(timeoutId), '90000');
        await t.pump();
        await t.tap(find.text('Save'));
        await settle(t);
        expect(host.callsTo('settings/mutate').single.args, {
          'ns': ns,
          'ops': [
            {
              'op': 'set',
              'path': [timeout],
              'value': 90000,
            },
          ],
          'expectedRevision': 7,
        });
        expect(inputText(t, timeoutId), '90000');
        expect(find.text('Overridden'), findsOneWidget);
        expect(saveEnabled(t), isFalse);
        off();
      });
    }

    testWidgets('a host refusal keeps the drafts', (t) async {
      described.add(view(bashNamespace, revision: 7));
      host.handlers['settings/mutate'] = (args) =>
          throw RemoteException('settings/conflict', 'stale revision');
      final off = register();
      await t.runAsync(refresh);
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'shell',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      await t.enterText(input(outputId), '5');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t, outputId), '5');
      off();
    });
  });
}
