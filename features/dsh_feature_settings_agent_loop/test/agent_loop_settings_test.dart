import 'dart:async';

import 'package:dsh_client/dsh_client.dart' show RemoteException;
import 'package:dsh_feature_settings_agent_loop/dsh_feature_settings_agent_loop.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const field = 'maxParallelToolCalls';
const fieldId = 'plugin-config-agent-loop-parallel';

ConfigFormSnapshot ready({
  int value = 10,
  Map<String, Object?> user = const {},
  bool writable = true,
  int revision = 3,
}) => ConfigFormSnapshot(
  status: ConfigFormStatus.ready,
  value: {field: value},
  base: {field: 10},
  user: user,
  revision: revision,
  writable: writable,
);

Map<String, Object?> schema() =>
    objectSchema({field: numberNode(min: 1, step: 1, defaultValue: 10)});

Map<String, Object?> view({
  int value = 10,
  Map<String, Object?> user = const {},
  int revision = 3,
}) => nsView(
  agentLoopNamespace,
  schema: schema(),
  value: {field: value},
  base: {field: 10},
  user: user,
  revision: revision,
);

/// Let futures that need the real event loop finish, then rebuild.
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

Finder input() => find.byKey(DshSettingsValueField.inputKey(fieldId));

String inputText(WidgetTester t) =>
    t.widget<EditableText>(input()).controller.text;

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
      form = FakeConfigForm(ready(user: {field: 4}));
      scope = ConfigFormScope(form);
    });

    test('maps the snapshot field for field', () {
      final s = scope.snapshot;
      expect(s.status, SettingsScopeStatus.ready);
      expect(s.value, {field: 10});
      expect(s.base, {field: 10});
      expect(s.user, {field: 4});
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
      expect(scope.snapshot.writable, isFalse);
    });

    test('subscribes to the form and the disposer stops it', () {
      var calls = 0;
      final off = scope.subscribe(() => calls++);
      form.publish(ready(revision: 4));
      expect(calls, 1);
      expect(scope.snapshot.revision, 4);
      off();
      form.publish(ready(revision: 5));
      expect(calls, 1);
    });

    test('mutate maps the ops and carries the revision fence', () async {
      final landed = await scope.mutate(const [
        SettingsFormSetOp([field], 4),
        SettingsFormUnsetOp(['other']),
      ], expectedRevision: 3);
      expect(landed, isTrue);
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect(write.ops, hasLength(2));
      expect(write.ops[0], isA<SetOp>());
      expect(write.ops[0].path, [field]);
      expect((write.ops[0] as SetOp).value, 4);
      expect(write.ops[1], isA<UnsetOp>());
      expect(write.ops[1].path, ['other']);
    });

    test('a refusal resolves false', () async {
      form.answer = false;
      expect(
        await scope.mutate(const [
          SettingsFormSetOp([field], 4),
        ]),
        false,
      );
    });
  });

  group('card', () {
    late FakeConfigForm form;
    late AgentLoopCardController controller;
    var i18n = const DshI18n(DshLocale.en);

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      form = FakeConfigForm(ready());
      controller = AgentLoopCardController(form);
    });
    tearDown(() => controller.dispose());

    Widget card([PluginItemView view = PluginItemView.page]) =>
        app(AgentLoopCard(controller: controller, i18n: i18n, view: view));

    testWidgets('the summary is the one-liner, in both languages', (t) async {
      surface(t);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(
        find.text('Control how the Agent dispatches tool calls.'),
        findsOneWidget,
      );
      i18n = const DshI18n(DshLocale.zh);
      await t.pumpWidget(card(PluginItemView.summary));
      expect(find.text('控制 Agent 派发工具调用的方式。'), findsOneWidget);
    });

    testWidgets('unchanged: shows the value and Save is disabled', (t) async {
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Parallel tool calls'), findsOneWidget);
      expect(
        find.text(
          'Upper bound on parallel-safe calls running at once within one step.',
        ),
        findsOneWidget,
      );
      expect(inputText(t), '10');
      expect(find.text('Overridden'), findsNothing);
      expect(saveEnabled(t), isFalse);
      expect(find.byKey(DshSettingsForm.readOnlyKey), findsNothing);
    });

    testWidgets('a read-only host says so and blocks editing', (t) async {
      form.publish(ready(writable: false));
      surface(t);
      await t.pumpWidget(card());
      expect(
        find.text('This deployment stores settings read-only.'),
        findsOneWidget,
      );
      expect(t.widget<EditableText>(input()).readOnly, isTrue);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('a namespace the host stopped serving says so', (t) async {
      surface(t);
      await t.pumpWidget(card());
      form.publish(
        const ConfigFormSnapshot(status: ConfigFormStatus.unavailable),
      );
      await t.pump();
      expect(
        find.text(
          'This plugin is not loaded, so it cannot be configured right now.',
        ),
        findsOneWidget,
      );
      expect(input(), findsNothing);
    });

    testWidgets('dirty: an edit enables Save and a save writes it', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), '4');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      expect(form.writes, isEmpty, reason: 'staging writes nothing');
      await t.tap(find.text('Save'));
      await settle(t);
      final write = form.writes.single;
      expect(write.expectedRevision, 3);
      expect((write.ops.single as SetOp).path, [field]);
      expect((write.ops.single as SetOp).value, 4);
      // Re-seeded from what the host accepted: now overridden, nothing staged.
      expect(inputText(t), '4');
      expect(find.text('Overridden'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('typing the stored value back is not dirty', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), '5');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      await t.enterText(input(), '10');
      await t.pump();
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('an invalid number blocks the save and says why', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), 'many');
      await t.pump();
      expect(
        find.text('Enter a number, or leave blank to use the default.'),
        findsOneWidget,
      );
      expect(saveEnabled(t), isFalse);
      await t.tap(find.text('Save'), warnIfMissed: false);
      await settle(t);
      expect(form.writes, isEmpty);
      // Correcting it clears the message.
      await t.enterText(input(), '6');
      await t.pump();
      expect(
        find.text('Enter a number, or leave blank to use the default.'),
        findsNothing,
      );
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('a blank draft clears the field on save', (t) async {
      form.publish(ready(user: {field: 4}, value: 4));
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), '  ');
      await t.pump();
      expect(saveEnabled(t), isTrue);
      await t.tap(find.text('Save'));
      await settle(t);
      expect(form.writes.single.ops.single, isA<UnsetOp>());
    });

    testWidgets('saving: the button says so and is disabled', (t) async {
      final gate = Completer<void>();
      form.gate = gate.future;
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), '4');
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
      await t.enterText(input(), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(
        find.text(
          'The deployment did not accept these values; they were left for you to correct.',
        ),
        findsOneWidget,
      );
      expect(inputText(t), '4');
      expect(saveEnabled(t), isTrue);
      // The next edit clears the failure.
      await t.enterText(input(), '5');
      await t.pump();
      expect(find.byKey(DshSettingsForm.failedKey), findsNothing);
    });

    testWidgets('a transport failure is a failed save too', (t) async {
      surface(t);
      final failing = _Failing(form);
      controller.dispose();
      controller = AgentLoopCardController(failing);
      await t.pumpWidget(card());
      await t.enterText(input(), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t), '4');
    });

    testWidgets('overridden shows the badge and reset stages a clear', (
      t,
    ) async {
      form.publish(ready(user: {field: 4}, value: 4));
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('Overridden'), findsOneWidget);
      expect(inputText(t), '4');
      await t.tap(find.byKey(DshSettingsValueField.resetKey(fieldId)));
      await t.pump();
      // The draft previews the default, and the badge goes with the override.
      expect(inputText(t), '10');
      expect(find.text('Overridden'), findsNothing);
      expect(form.writes, isEmpty);
      expect(saveEnabled(t), isTrue);
      await t.tap(find.text('Save'));
      await settle(t);
      expect(form.writes.single.ops.single, isA<UnsetOp>());
    });

    testWidgets('leaving the page drops the staged edits', (t) async {
      surface(t);
      await t.pumpWidget(card());
      await t.enterText(input(), '4');
      await t.pump();
      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(card());
      expect(inputText(t), '10');
      expect(saveEnabled(t), isFalse);
    });

    testWidgets('Chinese copy', (t) async {
      i18n = const DshI18n(DshLocale.zh);
      form.publish(ready(user: {field: 4}, value: 4));
      surface(t);
      await t.pumpWidget(card());
      expect(find.text('并行工具调用数'), findsOneWidget);
      expect(find.text('同一步内最多同时运行多少个可并行的调用。'), findsOneWidget);
      expect(find.text('已覆盖'), findsOneWidget);
      expect(find.text('恢复默认'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      await t.enterText(input(), 'x');
      await t.pump();
      expect(find.text('请填数字；留空表示使用默认值。'), findsOneWidget);
    });
  });

  group('registration over a scripted host', () {
    late FakeHost host;
    late ConfigForms forms;
    late SlotRegistry slots;
    var i18n = const DshI18n(DshLocale.en);
    final itemSlot = DshSlots.pluginsItem.typed<PluginItemOwner, Widget>();
    final described = <Map<String, Object?>>[];
    var writable = true;

    List<(String, int, String?)> entries() => [
      for (final e in slots.entries(itemSlot)) (e.id, e.order, e.label),
    ];

    setUp(() {
      i18n = const DshI18n(DshLocale.en);
      writable = true;
      described.clear();
      host = FakeHost();
      host.handlers['settings/describe'] = (_) =>
          describeValue(described, writable: writable);
      slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      forms = ConfigForms(host.remotes);
    });
    // Not awaited: a widget test registers and writes from the fake-async
    // zone, whose pending continuations the teardown (a different zone) can
    // never flush, so awaiting the form queue here would wait forever.
    tearDown(() {
      unawaited(forms.dispose());
      unawaited(host.close());
    });

    Future<void> refresh() async {
      host.emit('settings/document-updated', [agentLoopNamespace, 1]);
      await pumpEventQueue();
    }

    test('no card while loading or while the host does not serve it', () async {
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      expect(entries(), isEmpty, reason: 'loading');
      await pumpEventQueue();
      expect(entries(), isEmpty, reason: 'described without agent-loop');
      off();
    });

    test('the card follows the namespace being served', () async {
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      await pumpEventQueue();
      described.add(view());
      await refresh();
      expect(entries(), [('agent-loop', 30, 'Agent loop')]);
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
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      await refresh();
      expect(entries().single.$3, 'Agent loop');
      i18n = const DshI18n(DshLocale.zh);
      expect(entries().single.$3, 'Agent 循环');
      off();
    });

    testWidgets('a save sends the mutate op fenced with the revision', (
      t,
    ) async {
      described.add(view(revision: 7));
      host.handlers['settings/mutate'] = (args) =>
          view(value: 4, user: {field: 4}, revision: 8);
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      await t.runAsync(refresh);
      expect(entries(), hasLength(1));
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'agent-loop',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      expect(inputText(t), '10');
      await t.enterText(input(), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(host.callsTo('settings/mutate').single.args, {
        'ns': 'agent-loop',
        'ops': [
          {
            'op': 'set',
            'path': [field],
            'value': 4,
          },
        ],
        'expectedRevision': 7,
      });
      expect(inputText(t), '4');
      expect(find.text('Overridden'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      off();
    });

    testWidgets('a host refusal keeps the drafts', (t) async {
      described.add(view(revision: 7));
      host.handlers['settings/mutate'] = (args) =>
          throw RemoteException('settings/conflict', 'stale revision');
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      await t.runAsync(refresh);
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'agent-loop',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      await t.enterText(input(), '4');
      await t.pump();
      await t.tap(find.text('Save'));
      await settle(t);
      expect(find.byKey(DshSettingsForm.failedKey), findsOneWidget);
      expect(inputText(t), '4');
      off();
    });

    testWidgets('a read-only document shows the notice', (t) async {
      writable = false;
      described.add(view());
      final off = registerAgentLoopSettingsFeature(
        slots,
        forms: forms,
        i18n: () => i18n,
      );
      await t.runAsync(refresh);
      surface(t);
      await t.pumpWidget(
        app(
          slots.renderOnly(
            itemSlot,
            'agent-loop',
            const PluginItemOwner(view: PluginItemView.page),
          )!,
        ),
      );
      expect(find.byKey(DshSettingsForm.readOnlyKey), findsOneWidget);
      off();
    });
  });
}

/// A form whose writes fail like a lost connection.
class _Failing implements ConfigForm {
  _Failing(this._inner);
  final ConfigForm _inner;

  @override
  ConfigFormSnapshot get snapshot => _inner.snapshot;

  @override
  void Function() subscribe(void Function() listener) =>
      _inner.subscribe(listener);

  @override
  Future<bool> mutate(List<SettingsOp> ops, {int? expectedRevision}) =>
      Future<bool>.error(StateError('connection lost'));

  @override
  Future<bool> set(String field, Object? value) => mutate([
    SetOp([field], value),
  ]);

  @override
  Future<bool> unset(String field) => mutate([
    UnsetOp([field]),
  ]);
}
