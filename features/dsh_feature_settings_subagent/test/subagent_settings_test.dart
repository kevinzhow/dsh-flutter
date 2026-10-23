import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_feature_settings_subagent/dsh_feature_settings_subagent.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const depth = 'maxDepth';
const active = 'maxActiveSubagents';
const depthId = 'plugin-config-subagent-depth';
const activeId = 'plugin-config-subagent-capacity';

Map<String, Object?> section({int d = 1, int a = 8}) => {depth: d, active: a};

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

Map<String, Object?> view({
  Map<String, Object?>? value,
  Map<String, Object?> user = const {},
  int revision = 3,
}) => nsView(
  subagentNamespace,
  schema: objectSchema({
    depth: numberNode(min: 0, step: 1, defaultValue: 1),
    active: numberNode(min: 1, step: 1, defaultValue: 8),
  }),
  value: value ?? section(),
  base: section(),
  user: user,
  revision: revision,
);

Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => pumpEventQueue());
  await t.pump();
}

void surface(WidgetTester t, [Size size = const Size(390, 900)]) {
  t.view.physicalSize = size;
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
      form = FakeConfigForm(ready(user: {depth: 2}));
      scope = ConfigFormScope(form);
    });

    test('maps the snapshot field for field', () {
      final s = scope.snapshot;
      expect(s.status, SettingsScopeStatus.ready);
      expect(s.value, section());
      expect(s.base, section());
      expect(s.user, {depth: 2});
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
          SettingsFormSetOp([depth], 2),
          SettingsFormUnsetOp([active]),
        ], expectedRevision: 3),
        isTrue,
      );
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect((write.ops[0] as SetOp).value, 2);
      expect(write.ops[1], isA<UnsetOp>());
      expect(write.ops[1].path, [active]);
    });

    test('a refusal resolves false', () async {
      form.answer = false;
      expect(
        await scope.mutate(const [
          SettingsFormSetOp([depth], 2),
        ]),
        false,
      );
    });
  });

  group('limit fields', () {
    Object? verdict(SettingsFieldSpec spec, String text) {
      final write = spec.parse(text);
      return switch (write) {
        null => 'invalid',
        SettingsFieldClear() => 'clear',
        SettingsFieldSet(:final value) => value,
      };
    }

    final d = subagentLimitField(depth, 0);
    final a = subagentLimitField(active, 1);

    test('depth takes whole numbers from 0', () {
      expect(verdict(d, '0'), 0);
      expect(verdict(d, ' 3 '), 3);
      expect(verdict(d, '1e1'), 10);
      expect(verdict(d, '0x10'), 16);
      expect(verdict(d, '-1'), 'invalid');
      expect(verdict(d, '1.5'), 'invalid');
      expect(verdict(d, 'two'), 'invalid');
      expect(verdict(d, 'Infinity'), 'invalid');
    });

    test('negative zero is not a depth', () {
      expect(verdict(d, '-0'), 'invalid');
      expect(verdict(d, ' -0.0 '), 'invalid');
      expect(verdict(d, '+0'), 0);
    });

    test('capacity takes whole numbers from 1', () {
      expect(verdict(a, '1'), 1);
      expect(verdict(a, '8'), 8);
      expect(verdict(a, '0'), 'invalid');
      expect(verdict(a, '-3'), 'invalid');
      expect(verdict(a, '2.5'), 'invalid');
    });

    test('only safe integers are accepted', () {
      expect(verdict(a, '9007199254740991'), 9007199254740991);
      expect(verdict(a, '9007199254740992'), 'invalid');
      expect(verdict(a, '1e300'), 'invalid');
    });

    test('blank clears the field', () {
      expect(verdict(d, ''), 'clear');
      expect(verdict(a, '   '), 'clear');
    });

    test('stored values render as plain numbers', () {
      expect(d.format(1), '1');
      expect(d.format(null), '');
      expect(a.format('x'), '');
    });
  });

  group('card', () {
    late FakeConfigForm form;
    late SubagentLimitsCardController controller;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      form = FakeConfigForm(ready());
      controller = SubagentLimitsCardController(form);
    });
    tearDown(() => controller.dispose());

    Widget card([PluginItemView view = PluginItemView.page]) =>
        app(SubagentCard(controller: controller, i18n: i18n, view: view));

    testWidgets('the summary is the one-liner, in both languages', (t) async {
      surface(t);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(
        find.text('Set Subagent recursion depth, count, and models.'),
        findsOneWidget,
      );
      i18n = const DshI18n(DshLocale.zh);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(find.text('设置子智能体的递归层级、数量和模型。'), findsOneWidget);
    });

    testWidgets('unchanged: the Limits section, Save disabled', (t) async {
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Limits'), findsOneWidget);
      expect(find.text('Maximum recursion depth'), findsOneWidget);
      expect(find.text('Subagent parallelism limit'), findsOneWidget);
      expect(inputText(t, depthId), '1');
      expect(inputText(t, activeId), '8');
      expect(find.text('Overridden'), findsNothing);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('stacks on a phone and sits side by side when wide', (t) async {
      surface(t);
      await t.pumpWidget(card());
      expect(
        t.getTopLeft(input(depthId)).dy,
        lessThan(t.getTopLeft(input(activeId)).dy),
      );
      expect(t.getTopLeft(input(depthId)).dx, t.getTopLeft(input(activeId)).dx);
      surface(t, const Size(900, 900));
      await t.pumpWidget(card());
      expect(t.getTopLeft(input(depthId)).dy, t.getTopLeft(input(activeId)).dy);
      expect(
        t.getTopLeft(input(depthId)).dx,
        lessThan(t.getTopLeft(input(activeId)).dx),
      );
    });

    testWidgets('the help buttons disclose the rules', (t) async {
      surface(t);
      await t.pumpWidget(card());
      expect(
        find.text('Limits how many levels of Subagents an Agent can create.'),
        findsNothing,
      );
      await t.tap(find.byKey(DshSettingsValueField.helpKey(depthId)));
      await t.pump();
      expect(
        find.text('Limits how many levels of Subagents an Agent can create.'),
        findsOneWidget,
      );
      expect(find.text('Disable Subagents'), findsOneWidget);
      expect(
        find.text('Only the main Agent can create Subagents'),
        findsOneWidget,
      );
      expect(
        find.text(
          'If a tool defines its own maximum recursion depth, that setting takes precedence.',
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(DshSettingsValueField.helpKey(activeId)));
      await t.pump();
      expect(
        find.textContaining('Total live Subagents under the same main Agent'),
        findsOneWidget,
      );
    });

    testWidgets('a read-only host says so and blocks editing', (t) async {
      form.publish(ready(writable: false));
      surface(t);
      await t.pumpWidget(card());
      expect(find.byKey(DshSettingsForm.readOnlyKey), findsOneWidget);
      expect(t.widget<EditableText>(input(depthId)).readOnly, isTrue);
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
      expect(input(depthId), findsNothing);
    });

    testWidgets('dirty: a valid edit saves as one fenced write', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(depthId), '0');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      await t.tap(find.text('Save'));
      await settle(t);
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect((write.ops.single as SetOp).path, [depth]);
      expect((write.ops.single as SetOp).value, 0);
      expect(find.text('Overridden'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('an invalid depth blocks the save with its own message', (
      t,
    ) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(depthId), '-1');
      await t.pump();
      expect(find.text('Enter a whole number of 0 or more.'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      await t.tap(find.text('Save'), warnIfMissed: false);
      await settle(t);
      expect(form.writes, isEmpty);
      await t.enterText(input(depthId), '2');
      await t.pump();
      expect(find.text('Enter a whole number of 0 or more.'), findsNothing);
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('capacity 0 is invalid and says at least 1', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(activeId), '0');
      await t.pump();
      expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      await t.enterText(input(activeId), '1');
      await t.pump();
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('saving: disabled button and locked inputs', (t) async {
      final gate = Completer<void>();
      form.gate = gate.future;
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(activeId), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      expect(t.widget<EditableText>(input(activeId)).readOnly, isTrue);
      expect(t.widget<EditableText>(input(depthId)).readOnly, isTrue);
      gate.complete();
      await settle(t);
      expect(find.text('Save'), findsOneWidget);
      expect(t.widget<EditableText>(input(activeId)).readOnly, isFalse);
    });

    testWidgets('a refused save keeps the drafts and says so', (t) async {
      form.answer = false;
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(activeId), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t, activeId), '4');
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('overridden shows the badge; reset is per field', (t) async {
      form.publish(
        ready(value: section(d: 2, a: 3), user: {depth: 2, active: 3}),
      );
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Overridden'), findsNWidgets(2));
      await t.tap(find.byKey(DshSettingsValueField.resetKey(activeId)));
      await t.pump();
      expect(inputText(t, activeId), '8');
      expect(inputText(t, depthId), '2');
      expect(find.text('Overridden'), findsOneWidget);
      await t.tap(find.text('Save'));
      await settle(t);
      final write = form.writes.single;
      expect(write.ops.single, isA<UnsetOp>());
      expect(write.ops.single.path, [active]);
    });

    testWidgets('Chinese copy', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      form.publish(ready(user: {depth: 1}));
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('运行限制'), findsOneWidget);
      expect(find.text('最大递归深度'), findsOneWidget);
      expect(find.text('子智能体并行数量上限'), findsOneWidget);
      expect(find.text('已覆盖'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      await t.enterText(input(activeId), '0');
      await t.pump();
      expect(find.text('请输入不小于 1 的整数。'), findsOneWidget);
      await t.tap(find.byKey(DshSettingsValueField.helpKey(depthId)));
      await t.pump();
      expect(find.text('禁用子智能体'), findsOneWidget);
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
      host.emit('settings/document-updated', [subagentNamespace, 1]);
      await pumpEventQueue();
    }

    void Function() register() =>
        registerSubagentSettingsFeature(slots, forms: forms, i18n: () => i18n);

    test('no card while loading or while subagent is not served', () async {
      final off = register();
      expect(entries(), isEmpty);
      await pumpEventQueue();
      expect(entries(), isEmpty);
      off();
    });

    test('a host that serves only the model selection shows no card', () async {
      final off = register();
      described.add(
        nsView('subagent-model-selection-settings', schema: objectSchema({})),
      );
      await refresh();
      expect(entries(), isEmpty);
      off();
    });

    test('the card follows the namespace being served', () async {
      final off = register();
      await pumpEventQueue();
      described.add(view());
      await refresh();
      expect(entries(), [('subagent', 10, 'Subagent')]);
      described.clear();
      await refresh();
      expect(entries(), isEmpty);
      described.add(view());
      await refresh();
      expect(entries(), hasLength(1));
      off();
      expect(entries(), isEmpty);
    });

    test('the label follows the language', () async {
      described.add(view());
      final off = register();
      await refresh();
      i18n = const DshI18n(DshLocale.zh);
      expect(entries().single.$3, '子智能体');
      off();
    });

    testWidgets('a save sends the mutate op fenced with the revision', (
      t,
    ) async {
      described.add(view(revision: 7));
      host.handlers['settings/mutate'] = (args) =>
          view(value: section(a: 4), user: {active: 4}, revision: 8);
      final off = register();
      await t.runAsync(refresh);
      expect(entries(), hasLength(1));
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'subagent',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      expect(inputText(t, activeId), '8');
      await t.enterText(input(activeId), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(host.callsTo('settings/mutate').single.args, {
        'ns': 'subagent',
        'ops': [
          {
            'op': 'set',
            'path': [active],
            'value': 4,
          },
        ],
        'expectedRevision': 7,
      });
      expect(inputText(t, activeId), '4');
      expect(find.text('Overridden'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      off();
    });

    testWidgets('a reset sends an unset op', (t) async {
      described.add(view(value: section(d: 3), user: {depth: 3}, revision: 7));
      host.handlers['settings/mutate'] = (args) => view(revision: 8);
      final off = register();
      await t.runAsync(refresh);
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'subagent',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      expect(find.text('Overridden'), findsOneWidget);
      await t.tap(find.byKey(DshSettingsValueField.resetKey(depthId)));
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(host.callsTo('settings/mutate').single.args, {
        'ns': 'subagent',
        'ops': [
          {
            'op': 'unset',
            'path': [depth],
          },
        ],
        'expectedRevision': 7,
      });
      expect(find.text('Overridden'), findsNothing);
      off();
    });

    testWidgets('a host refusal keeps the drafts', (t) async {
      described.add(view(revision: 7));
      host.handlers['settings/mutate'] = (args) =>
          throw RemoteException('settings/conflict', 'stale revision');
      final off = register();
      await t.runAsync(refresh);
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'subagent',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      await t.enterText(input(activeId), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t, activeId), '4');
      off();
    });
  });
}
