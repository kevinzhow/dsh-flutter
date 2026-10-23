import 'package:dsh_client/generated_commands.dart';
import 'package:dsh_client/generated_permission_presets.dart';
import 'package:dsh_client/generated_settings.dart';
import 'package:dsh_client/src/remote_caller.dart';
import 'package:test/test.dart';

class FakeCaller implements RemoteCaller {
  final calls = <({String ns, String method, Map<String, Object?> args})>[];
  final replies = <Object?>[];

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add((ns: namespace, method: method, args: args));
    return replies.removeAt(0);
  }
}

Map<String, Object?> namespaceJson({int revision = 3}) => {
  'applies': 'live',
  'autoGenerate': true,
  'ns': 'ui-theme',
  'schema': {'uid': 1, 'refs': <String, Object?>{}},
  'value': {'fontSize': 14},
  'base': {'fontSize': 14},
  'user': <String, Object?>{},
  'secrets': <Object?>[],
  'revision': revision,
};

void main() {
  late FakeCaller caller;
  setUp(() => caller = FakeCaller());

  group('settings namespace', () {
    test('describe decodes the namespace views', () async {
      caller.replies.add({
        'writable': true,
        'hasDocument': false,
        'namespaces': [namespaceJson()],
      });
      final v = await SettingsRemote(caller).describe();
      expect(caller.calls.single.ns, 'settings');
      expect(caller.calls.single.method, 'describe');
      expect(v.writable, isTrue);
      expect(v.namespaces.single.ns, 'ui-theme');
      expect(v.namespaces.single.revision, 3);
      expect(v.namespaces.single.user, isA<Map<String, Object?>>());
    });

    test('mutate carries path ops and a revision only when given', () async {
      caller.replies
        ..add(namespaceJson())
        ..add(namespaceJson());
      final remote = SettingsRemote(caller);
      await remote.mutate('ui-theme', [
        const SettingsPathOpViewSet(path: ['fontSize'], value: 16),
        const SettingsPathOpViewUnset(path: ['textFontFamily']),
      ], 3);
      await remote.mutate('ui-theme', const []);
      expect(caller.calls[0].args, {
        'ns': 'ui-theme',
        'ops': [
          {
            'op': 'set',
            'path': ['fontSize'],
            'value': 16,
          },
          {
            'op': 'unset',
            'path': ['textFontFamily'],
          },
        ],
        'expectedRevision': 3,
      });
      expect(caller.calls[1].args.containsKey('expectedRevision'), isFalse);
    });

    test('a view with another apply mode is refused, not guessed', () {
      final json = namespaceJson()..['applies'] = 'restart';
      expect(() => SettingsNamespaceView.fromJson(json), throwsFormatException);
    });
  });

  group('permissionPresets namespace', () {
    test('catalog decodes options and defaults', () async {
      caller.replies.add({
        'options': [
          {
            'value': 'workspace-write',
            'name': 'workspace-write',
            'description': 'Write inside the workspace.',
          },
          {'value': 'auto', 'name': 'auto'},
        ],
        'defaultOptions': [
          {'value': 'workspace-write', 'name': 'workspace-write'},
        ],
        'defaultPreset': 'workspace-write',
      });
      final c = await PermissionPresetsRemote(caller).catalog();
      expect(caller.calls.single.ns, 'permissionPresets');
      expect([for (final o in c.options) o.value], ['workspace-write', 'auto']);
      expect(c.options.first.description, 'Write inside the workspace.');
      expect(c.options.last.description, isNull);
      expect(c.defaultPreset, 'workspace-write');
    });
  });

  group('commands namespace', () {
    test('a Typert lookup parameter travels as <key>Id', () async {
      caller.replies.add({
        'commandId': 'c-1',
        'result': {'kind': 'success', 'text': 'preset read-only'},
      });
      final done = await CommandsRemote(caller)
          .execute('sess-1', '/permission read-only', const []);
      expect(caller.calls.single.args, {
        'agentId': 'sess-1',
        'line': '/permission read-only',
        'submittedAttachments': <Object?>[],
      });
      expect(done, isNotNull);
      expect(done!.commandId, 'c-1');
      expect(done.result, isA<CommandResultSuccess>());
    });

    test('an unmatched command line answers no execution', () async {
      caller.replies.add(null);
      expect(
        await CommandsRemote(caller).execute('sess-1', '/nope', const []),
        isNull,
      );
    });

    test('an error result keeps its text', () async {
      caller.replies.add({
        'commandId': 'c-2',
        'result': {'kind': 'error', 'text': 'unknown preset "x"'},
      });
      final done = await CommandsRemote(caller)
          .execute('sess-1', '/permission x', const []);
      expect((done!.result as CommandResultError).text, 'unknown preset "x"');
    });
  });
}
