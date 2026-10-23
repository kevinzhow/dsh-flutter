import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_settings.dart' as wire;
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

final themeSchema = objectSchema({
  'fontSize': numberNode(min: 10, max: 22, step: 1, defaultValue: 14),
  'textFontFamily': {
    'type': 'string',
    'meta': {'default': ''},
  },
});

Map<String, Object?> themeView({
  int fontSize = 14,
  int revision = 0,
  Map<String, Object?>? user,
}) => nsView(
  'ui-theme',
  schema: themeSchema,
  value: {'fontSize': fontSize, 'textFontFamily': ''},
  base: {'fontSize': 14, 'textFontFamily': ''},
  user: user ?? {},
  revision: revision,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeHost host;
  late ConfigForms forms;

  setUp(() {
    host = FakeHost();
  });

  tearDown(() async {
    await forms.dispose();
    await host.close();
  });

  ConfigForms build({List<Map<String, Object?>>? namespaces}) {
    host.handlers['settings/describe'] = (_) =>
        describeValue(namespaces ?? [themeView()]);
    return forms = ConfigForms(host.remotes);
  }

  group('describe mirror', () {
    test('reads once at startup and serves the view', () async {
      build();
      await forms.mirror.ensure();
      expect(forms.mirror.snapshot.status, MirrorStatus.ready);
      expect(forms.mirror.namespace('ui-theme')?.revision, 0);
      expect(host.callsTo('settings/describe'), hasLength(1));
    });

    test('a failed first read falls back to idle and ensure retries', () async {
      var fail = true;
      host.handlers['settings/describe'] = (_) {
        if (fail) throw RemoteException('gateway/internal', 'boom');
        return describeValue([themeView()]);
      };
      forms = ConfigForms(host.remotes);
      await forms.mirror.ensure();
      expect(forms.mirror.snapshot.status, MirrorStatus.idle);
      expect(forms.mirror.snapshot.error, contains('boom'));
      fail = false;
      await forms.mirror.ensure();
      expect(forms.mirror.snapshot.status, MirrorStatus.ready);
      expect(forms.mirror.snapshot.error, isNull);
    });

    test('a later failure keeps serving the held view', () async {
      build();
      await forms.mirror.ensure();
      host.handlers['settings/describe'] = (_) =>
          throw RemoteException('gateway/internal', 'down');
      await forms.mirror.load();
      expect(forms.mirror.snapshot.status, MirrorStatus.ready);
      expect(forms.mirror.snapshot.view, isNotNull);
      expect(forms.mirror.snapshot.error, contains('down'));
    });

    test('loads during a read fold into one rerun', () async {
      final gate = Completer<void>();
      var reads = 0;
      host.handlers['settings/describe'] = (_) async {
        reads += 1;
        if (reads == 1) await gate.future;
        return describeValue([themeView(revision: reads)]);
      };
      forms = ConfigForms(host.remotes);
      await settle();
      final a = forms.mirror.load();
      final b = forms.mirror.load();
      gate.complete();
      await Future.wait([a, b]);
      expect(reads, 2);
      expect(forms.mirror.namespace('ui-theme')?.revision, 2);
    });

    test('settings/document-updated and a new generation refresh', () async {
      build();
      await forms.mirror.ensure();
      host.emit('settings/document-updated', ['ui-theme', 3]);
      await settle();
      await settle();
      expect(host.callsTo('settings/describe'), hasLength(2));
      host.gens.add(null);
      await settle();
      expect(host.callsTo('settings/describe'), hasLength(2));
      host.gens.add(FakeGeneration());
      await settle();
      await settle();
      expect(host.callsTo('settings/describe'), hasLength(3));
    });

    test(
      'a write answer invalidates a read that started before the write',
      () async {
        final gate = Completer<void>();
        var reads = 0;
        host.handlers['settings/describe'] = (_) async {
          reads += 1;
          if (reads == 2) await gate.future;
          return describeValue([themeView(fontSize: reads == 2 ? 14 : 18)]);
        };
        forms = ConfigForms(host.remotes);
        await forms.mirror.ensure();
        final slow = forms.mirror.load();
        await settle();
        forms.mirror.acceptView(
          wire.SettingsNamespaceView.fromJson(
            themeView(fontSize: 16, revision: 1),
          ),
        );
        gate.complete();
        await slow;
        // The stale read (14) never published; the rerun read (18) did.
        expect(reads, 3);
        expect(
          (forms.mirror.namespace('ui-theme')!.value
              as Map<String, Object?>)['fontSize'],
          18,
        );
      },
    );
  });

  group('config form', () {
    test('derives ready values from a schema-valid section', () async {
      build();
      final form = forms.get('ui-theme');
      expect(form.snapshot.status, ConfigFormStatus.loading);
      await forms.mirror.ensure();
      expect(form.snapshot.status, ConfigFormStatus.ready);
      expect(form.snapshot.value?['fontSize'], 14);
      expect(form.snapshot.revision, 0);
      expect(form.snapshot.writable, isTrue);
      expect(forms.get('ui-theme'), same(form));
    });

    test('a namespace the host does not serve is unavailable', () async {
      build();
      final form = forms.get('nope');
      await forms.mirror.ensure();
      expect(form.snapshot.status, ConfigFormStatus.unavailable);
      expect(form.snapshot.writable, isTrue);
    });

    test('a section the schema refuses is never accepted', () async {
      build(namespaces: [themeView(fontSize: 99)]);
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      expect(form.snapshot.status, ConfigFormStatus.loading);
      expect(form.snapshot.value, isNull);
      // The revision and layers still follow the Host.
      expect(form.snapshot.revision, 0);
    });

    test('a later invalid section keeps the last accepted value', () async {
      build();
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      host.handlers['settings/describe'] = (_) =>
          describeValue([themeView(fontSize: 99, revision: 1)]);
      await forms.mirror.load();
      expect(form.snapshot.value?['fontSize'], 14);
      expect(form.snapshot.revision, 1);
    });

    test('a read-only provider reports writable false', () async {
      host.handlers['settings/describe'] = (_) =>
          describeValue([themeView()], writable: false);
      forms = ConfigForms(host.remotes);
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      expect(form.snapshot.writable, isFalse);
    });

    test(
      'set writes one path op fenced with the revision and folds the answer',
      () async {
        build();
        host.handlers['settings/mutate'] = (args) =>
            themeView(fontSize: 18, revision: 1, user: {'fontSize': 18});
        final form = forms.get('ui-theme');
        await forms.mirror.ensure();
        expect(await form.set('fontSize', 18), isTrue);
        final call = host.callsTo('settings/mutate').single;
        expect(call.args, {
          'ns': 'ui-theme',
          'ops': [
            {
              'op': 'set',
              'path': ['fontSize'],
              'value': 18,
            },
          ],
          'expectedRevision': 0,
        });
        expect(form.snapshot.value?['fontSize'], 18);
        expect(form.snapshot.revision, 1);
        expect((form.snapshot.user as Map)['fontSize'], 18);
        // The answer was folded in: no extra describe read.
        expect(host.callsTo('settings/describe'), hasLength(1));
      },
    );

    test('unset sends an unset op', () async {
      build();
      host.handlers['settings/mutate'] = (_) => themeView(revision: 1);
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      await form.unset('fontSize');
      expect(host.callsTo('settings/mutate').single.args['ops'], [
        {
          'op': 'unset',
          'path': ['fontSize'],
        },
      ]);
    });

    test(
      'rapid writes keep their order and chain the answered revision',
      () async {
        build();
        final gate = Completer<void>();
        var n = 0;
        host.handlers['settings/mutate'] = (args) async {
          n += 1;
          if (n == 1) await gate.future;
          final op = (args['ops']! as List).single as Map;
          return themeView(
            fontSize: op['value']! as int,
            revision: n,
            user: {'fontSize': op['value']},
          );
        };
        final form = forms.get('ui-theme');
        await forms.mirror.ensure();
        final first = form.set('fontSize', 15);
        final second = form.set('fontSize', 16);
        final third = form.set('fontSize', 17);
        await settle();
        expect(host.callsTo('settings/mutate'), hasLength(1));
        gate.complete();
        expect(await Future.wait([first, second, third]), [true, true, true]);
        final calls = host.callsTo('settings/mutate');
        expect(
          [for (final c in calls) (c.args['ops']! as List).single['value']],
          [15, 16, 17],
        );
        // Superseded answers pass their revision on; the latest folds in.
        expect([for (final c in calls) c.args['expectedRevision']], [0, 1, 2]);
        expect(form.snapshot.value?['fontSize'], 17);
        expect(form.snapshot.revision, 3);
      },
    );

    test('a refused write reloads the Host state and reports false', () async {
      build();
      host.handlers['settings/mutate'] = (_) => throw RemoteException(
        'settings/conflict',
        'stale',
        {'ns': 'ui-theme', 'expected': 0, 'actual': 5},
      );
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      host.handlers['settings/describe'] = (_) =>
          describeValue([themeView(fontSize: 12, revision: 5)]);
      expect(await form.set('fontSize', 18), isFalse);
      expect(form.snapshot.value?['fontSize'], 12);
      expect(form.snapshot.revision, 5);
    });

    test('a transport failure rejects and leaves the queue usable', () async {
      build();
      var fail = true;
      host.handlers['settings/mutate'] = (_) {
        if (fail) throw RemoteException('transport/http-502', 'bad gateway');
        return themeView(fontSize: 18, revision: 1);
      };
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      await expectLater(
        form.set('fontSize', 18),
        throwsA(isA<RemoteException>()),
      );
      fail = false;
      expect(await form.set('fontSize', 18), isTrue);
    });

    test('an explicit expectedRevision is the fence', () async {
      build();
      host.handlers['settings/mutate'] = (_) => themeView(revision: 4);
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      await form.mutate([
        const SetOp(['fontSize'], 12),
      ], expectedRevision: 3);
      expect(
        host.callsTo('settings/mutate').single.args['expectedRevision'],
        3,
      );
    });

    test('after dispose writes are skipped', () async {
      build();
      final form = forms.get('ui-theme');
      await forms.mirror.ensure();
      await form.dispose();
      expect(await form.set('fontSize', 18), isFalse);
      expect(host.callsTo('settings/mutate'), isEmpty);
    });
  });

  group('whileServed', () {
    test('registers while a namespace is served and withdraws after', () async {
      build(namespaces: [themeView()]);
      var live = 0;
      final off = forms.whileServed(['ui-theme', 'other'], (served) {
        expect(served, contains('ui-theme'));
        live += 1;
        return () => live -= 1;
      });
      await forms.mirror.ensure();
      expect(live, 1);
      host.handlers['settings/describe'] = (_) => describeValue([]);
      await forms.mirror.load();
      expect(live, 0);
      host.handlers['settings/describe'] = (_) => describeValue([themeView()]);
      await forms.mirror.load();
      expect(live, 1);
      off();
      expect(live, 0);
    });
  });

  group('settings schema', () {
    final schema = SettingsSchema.rehydrate(themeSchema);

    test('accepts a section within bounds and rejects outside it', () {
      expect(schema.validate({'fontSize': 14}), isNull);
      expect(schema.validate({'fontSize': 9}), contains('>= 10'));
      expect(schema.validate({'fontSize': 23}), contains('<= 22'));
      expect(schema.validate({'fontSize': 14.5}), contains('multiple of 1'));
      expect(schema.validate({'fontSize': 'big'}), contains('expected number'));
      expect(schema.validate({}), isNull);
      expect(schema.validate([]), contains('expected object'));
    });

    test('a malformed envelope rejects everything', () {
      expect(
        SettingsSchema.rehydrate({}).validate({}),
        contains('unsupported'),
      );
      expect(SettingsSchema.rehydrate(5).validate(1), contains('unsupported'));
    });

    test('nodeAtPath, getPath and hasPath', () {
      expect(schema.nodeAtPath(['fontSize'])?.max, 22);
      expect(schema.nodeAtPath(['nope']), isNull);
      expect(
        SettingsSchema.getPath(
          {
            'a': [1, 2],
          },
          ['a', '1'],
        ),
        2,
      );
      expect(SettingsSchema.hasPath({'a': null}, ['a']), isTrue);
      expect(SettingsSchema.hasPath({'a': null}, ['b']), isFalse);
    });
  });
}
