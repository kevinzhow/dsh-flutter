// Serialized preference persistence (dsh `persistence.client.spec.ts` and the
// persistence cases of `desktop-chords.client.spec.ts`).
import 'dart:async';
import 'dart:convert';

import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:test/test.dart';

import 'support.dart';

const one = 'test.one';
const two = 'test.two';
const binding = ShortcutBinding('KeyJ', [ShortcutModifier.primary]);
const pair = ShortcutBinding('KeyA', [], 'KeyB');

ShortcutDefinition def(String id, String code) => ShortcutDefinition(
  id: id,
  defaults: {
    for (final p in ['desktop:macos', 'desktop:windows', 'desktop:linux'])
      p: ShortcutBinding(code, const [ShortcutModifier.primary]),
  },
);

final definitions = [def(one, 'KeyB'), def(two, 'Comma')];

const edit = SetShortcut(one, binding);

class Fixture {
  Fixture({
    bool reread = false,
    ShortcutPlatform platform = ShortcutPlatform.windows,
    ShortcutRuntime runtime = ShortcutRuntime.desktop,
    List<ShortcutDefinition>? defs,
    String? raw,
  }) : storage = MemoryStorage(raw) {
    store = ShortcutPersistence(storage, runtime, platform, reread, (s) {
      published++;
      state = s;
    });
    store.setDefinitions(defs ?? definitions);
    published = 0;
  }

  final MemoryStorage storage;
  late final ShortcutPersistence store;
  late ShortcutConfigSnapshot state;
  int published = 0;
}

void main() {
  test(
    'rejects an unsupported Web binding without writing preferences',
    () async {
      final storage = MemoryStorage();
      final store = ShortcutPersistence(
        storage,
        ShortcutRuntime.web,
        ShortcutPlatform.linux,
        false,
        (_) {},
      );
      store.setDefinitions([const ShortcutDefinition(id: one)]);
      final snapshot = await store.readCurrent();
      final result = await store.edit(
        const SetShortcut(
          one,
          ShortcutBinding('KeyB', [ShortcutModifier.control]),
        ),
        snapshot.revision,
      );
      expect(result.status, ShortcutSaveStatus.conflict);
      expect(result.issue, BindingIssue.unsupportedBrowser);
      expect(result.conflicts, isEmpty);
      expect(storage.writes, 0);
    },
  );

  group('serialized preference persistence', () {
    test('publishes a save once and only after durable completion; rejects the competing old revision', () async {
      final f = Fixture();
      final initial = await f.store.readCurrent();
      final started = Completer<void>();
      final barrier = Completer<void>();
      f.storage.onWrite = () async {
        started.complete();
        await barrier.future;
      };
      final first = f.store.edit(edit, initial.revision);
      final second = f.store.edit(const ResetAllShortcuts(), initial.revision);
      await started.future;
      f.published = 0;
      expect(identical(f.state, initial), isTrue);
      barrier.complete();
      expect((await first).status, ShortcutSaveStatus.saved);
      expect((await second).status, ShortcutSaveStatus.stale);
      expect(f.published, 1);
      expect(f.state.document.profiles['desktop:windows']?[one], binding);
    });

    test('keeps the previous configuration and revision on write failure, allowing the same draft to retry', () async {
      final f = Fixture();
      final initial = await f.store.readCurrent();
      f.storage.failNextWrite = StateError('disk full');
      expect(
        (await f.store.edit(edit, initial.revision)).status,
        ShortcutSaveStatus.writeFailed,
      );
      expect(identical(f.state, initial), isTrue);
      expect(f.storage.raw, isNull);
      expect(
        (await f.store.edit(edit, initial.revision)).status,
        ShortcutSaveStatus.saved,
      );
      final stored = jsonDecode(f.storage.raw!) as Map<String, Object?>;
      expect(
        ((stored['profiles']! as Map)['desktop:windows']! as Map)[one],
        binding.toJson(),
      );
      final restarted = Fixture(raw: f.storage.raw);
      expect(
        (await restarted.store.readCurrent()).document,
        equals(f.state.document),
      );
    });

    for (final raw in ['{broken', '{"schemaVersion":3,"profiles":{}}']) {
      test(
        'retains accepted bindings and original bytes after reading $raw',
        () async {
          final f = Fixture();
          await f.store.readCurrent();
          await f.store.edit(edit, f.state.revision);
          final accepted = f.state.document;
          f.storage.raw = raw;
          final bad = await f.store.readCurrent();
          expect(bad.status, ShortcutConfigStatus.unreadable);
          expect(identical(bad.document, accepted), isTrue);
          for (final operation in [
            edit,
            const ResetAllShortcuts(),
            const ResetShortcut(one),
          ]) {
            expect(
              (await f.store.edit(operation, bad.revision)).status,
              ShortcutSaveStatus.unreadable,
            );
          }
          expect(f.storage.raw, raw);
        },
      );
    }

    test('uses defaults on the first bad read and prevents writes until the source becomes readable', () async {
      final f = Fixture();
      f.storage.failNextRead = StateError('denied');
      expect((await f.store.readCurrent()).usingDefaults, isTrue);
      f.storage.failNextRead = StateError('still denied');
      expect((await f.store.readCurrent()).error, ShortcutReadError.read);
      expect(
        (await f.store.edit(
          const ResetAllShortcuts(),
          f.state.revision,
        )).status,
        ShortcutSaveStatus.unreadable,
      );
      expect(f.storage.writes, 0);
      f.storage.raw = '{';
      expect((await f.store.readCurrent()).error, ShortcutReadError.invalid);
      f.storage.raw = '{"schemaVersion":1,"profiles":{}}';
      expect((await f.store.readCurrent()).status, ShortcutConfigStatus.ready);
    });

    test('rereads before a browser write and requires an explicit review of external updates', () async {
      final f = Fixture(reread: true);
      final initial = await f.store.readCurrent();
      f.storage.raw = '{"schemaVersion":1,"profiles":{"web:macos":{"sleeping.command":null}}}';
      expect(
        (await f.store.edit(edit, initial.revision)).status,
        ShortcutSaveStatus.stale,
      );
      expect(f.storage.writes, 0);
      expect(
        (await f.store.edit(edit, f.state.revision)).status,
        ShortcutSaveStatus.saved,
      );
      expect(f.state.document.profiles['web:macos'], {
        'sleeping.command': null,
      });
    });

    test('accepts Windows single keys and editing combinations but rejects explicit/default conflicts', () async {
      final f = Fixture();
      await f.store.readCurrent();
      Future<ShortcutSaveResult> set(String id, ShortcutBinding b) =>
          f.store.edit(SetShortcut(id, b), f.state.revision);
      expect(
        (await set(
          one,
          const ShortcutBinding('KeyC', [ShortcutModifier.control]),
        )).status,
        ShortcutSaveStatus.saved,
      );
      expect(
        (await set(one, const ShortcutBinding('KeyC'))).status,
        ShortcutSaveStatus.saved,
      );
      expect(
        (await set(
          one,
          const ShortcutBinding('Comma', [ShortcutModifier.primary]),
        )).status,
        ShortcutSaveStatus.conflict,
      );
      await f.store.edit(edit, f.state.revision);
      expect((await set(two, binding)).conflicts, [one]);
      expect(
        (await set(
          two,
          const ShortcutBinding('KeyB', [ShortcutModifier.primary]),
        )).status,
        ShortcutSaveStatus.saved,
      );
      expect(
        (await f.store.edit(const ResetShortcut(one), f.state.revision)).status,
        ShortcutSaveStatus.conflict,
      );
      expect(
        (await f.store.edit(
          const ResetAllShortcuts(),
          f.state.revision,
        )).status,
        ShortcutSaveStatus.saved,
      );
    });

    test('rejects early/unknown/stale-owner edits and does not publish a late read after disposal', () async {
      final f = Fixture();
      expect(
        (await f.store.edit(edit, f.store.snapshot.revision)).status,
        ShortcutSaveStatus.notReady,
      );
      await f.store.readCurrent();
      expect(
        (await f.store.edit(
          const SetShortcut('missing.command', binding),
          f.state.revision,
        )).status,
        ShortcutSaveStatus.notReady,
      );
      f.store.setDefinitions(null);
      expect(
        (await f.store.edit(edit, f.state.revision)).status,
        ShortcutSaveStatus.notReady,
      );
      f.store.dispose();
      f.published = 0;
      f.storage.raw = '{';
      await f.store.readCurrent();
      expect(f.published, 0);
    });
  });

  test('continues transactions after a rejected unsupported code and contains subscriber failures', () async {
    var fail = false;
    var calls = 0;
    final storage = MemoryStorage();
    late ShortcutConfigSnapshot state;
    final reported = <Object>[];
    final store = ShortcutPersistence(
      storage,
      ShortcutRuntime.desktop,
      ShortcutPlatform.windows,
      false,
      (s) {
        calls++;
        state = s;
        if (fail) {
          fail = false;
          throw StateError('subscriber failed');
        }
      },
      onSubscriberError: reported.add,
    );
    store.setDefinitions(definitions);
    await store.readCurrent();
    await expectLater(
      store.edit(
        const SetShortcut(
          one,
          ShortcutBinding('Unidentified', [ShortcutModifier.primary]),
        ),
        state.revision,
      ),
      throwsA(
        isA<ShortcutBindingError>().having(
          (e) => e.message,
          'message',
          contains('Unsupported'),
        ),
      ),
    );
    fail = true;
    final result = await store.edit(edit, state.revision);
    expect(result.status, ShortcutSaveStatus.saved);
    expect(calls, greaterThan(1));
    expect(reported.single, isA<StateError>());
    expect(
      (await store.readCurrent()).document,
      equals(result.snapshot.document),
    );
  });

  group('two-key chords', () {
    for (final platform in [ShortcutPlatform.macos, ShortcutPlatform.windows]) {
      test(
        'migrates ${platform.name} preferences on write and rejects both directions of single/chord conflicts',
        () async {
          final original = jsonEncode({
            'schemaVersion': 1,
            'profiles': {
              'web:macos': {'dormant.web': null},
            },
          });
          final storage = MemoryStorage(original);
          late ShortcutConfigSnapshot published;
          final store = ShortcutPersistence(
            storage,
            ShortcutRuntime.desktop,
            platform,
            false,
            (s) => published = s,
          );
          store.setDefinitions([
            const ShortcutDefinition(id: 'test.action'),
            const ShortcutDefinition(id: 'test.other'),
          ]);
          var state = await store.readCurrent();
          expect(storage.raw, original);
          final saved = await store.edit(
            const SetShortcut('test.action', pair),
            state.revision,
          );
          expect(saved.status, ShortcutSaveStatus.saved);
          expect(jsonDecode(storage.raw!), {
            'schemaVersion': 2,
            'profiles': {
              'web:macos': {'dormant.web': null},
              'desktop:${platform.name}': {'test.action': pair.toJson()},
            },
          });
          expect(
            parseShortcutDocument(storage.raw).document,
            equals(saved.snapshot.document),
          );
          expect(
            parseShortcutDocument(
              storage.raw!.replaceFirst(
                '"schemaVersion": 2',
                '"schemaVersion": 1',
              ),
            ).error,
            ShortcutDocumentError.invalid,
          );
          state = saved.snapshot;
          for (final code in ['KeyA', 'KeyB']) {
            final rejected = await store.edit(
              SetShortcut('test.other', ShortcutBinding(code)),
              state.revision,
            );
            expect(rejected.status, ShortcutSaveStatus.conflict);
            expect(rejected.conflicts, ['test.action']);
          }
          final cleared = await store.edit(
            const ResetAllShortcuts(),
            state.revision,
          );
          final single = await store.edit(
            const SetShortcut('test.action', ShortcutBinding('KeyB')),
            cleared.snapshot.revision,
          );
          expect(
            (await store.edit(
              const SetShortcut('test.other', pair),
              single.snapshot.revision,
            )).status,
            ShortcutSaveStatus.conflict,
          );
          final overlapping = ShortcutDocument(
            schemaVersion: 2,
            profiles: {
              'desktop:${platform.name}': {
                'test.action': pair,
                'test.other': const ShortcutBinding('KeyA'),
              },
            },
          );
          expect(
            effectiveShortcuts(
              [
                const ShortcutDefinition(id: 'test.action'),
                const ShortcutDefinition(id: 'test.other'),
              ],
              overlapping,
              ShortcutRuntime.desktop,
              platform,
            ).map((r) => r.conflicts).toList(),
            [
              ['test.other'],
              ['test.action'],
            ],
          );
          expect(published, isNotNull);
          store.dispose();
        },
      );

      test(
        'rejects direct ${platform.name} writes that overlap fixed actions and disables previously saved conflicts',
        () async {
          const fixedId = 'menu.dismiss';
          final catalog = parseShortcutDefinitions([
            {'id': 'test.action', 'defaults': <String, Object?>{}},
            {'id': 'test.other', 'defaults': <String, Object?>{}},
            {
              'id': fixedId,
              'defaults': <String, Object?>{},
              'fixed': [
                {'code': 'Escape', 'modifiers': <String>[]},
              ],
            },
          ]);
          final storage = MemoryStorage();
          final store = ShortcutPersistence(
            storage,
            ShortcutRuntime.desktop,
            platform,
            false,
            (_) {},
          );
          store.setDefinitions(catalog);
          final state = await store.readCurrent();
          for (final b in const [
            ShortcutBinding('Escape'),
            ShortcutBinding('KeyA', [], 'Escape'),
          ]) {
            final r = await store.edit(
              SetShortcut('test.action', b),
              state.revision,
            );
            expect(r.status, ShortcutSaveStatus.conflict);
            expect(r.conflicts, [fixedId]);
            expect(
              effectiveShortcuts(
                catalog,
                ShortcutDocument(
                  schemaVersion: 2,
                  profiles: {
                    'desktop:${platform.name}': {'test.action': b},
                  },
                ),
                ShortcutRuntime.desktop,
                platform,
              ).firstWhere((row) => row.id == 'test.action').conflicts,
              [fixedId],
            );
          }
          expect(storage.writes, 0);
          expect(
            (await store.edit(
              const SetShortcut(fixedId, null),
              state.revision,
            )).status,
            ShortcutSaveStatus.notReady,
          );
          expect(
            (await store.edit(
              const SetShortcut(
                'test.action',
                ShortcutBinding('Escape', [
                  ShortcutModifier.control,
                  ShortcutModifier.alt,
                ]),
              ),
              state.revision,
            )).status,
            ShortcutSaveStatus.saved,
          );
          store.setDefinitions([
            const ShortcutDefinition(id: 'test.action'),
            const ShortcutDefinition(id: 'test.other'),
          ]);
          expect(
            (await store.edit(
              const SetShortcut('test.action', ShortcutBinding('Escape')),
              (await store.readCurrent()).revision,
            )).status,
            ShortcutSaveStatus.saved,
          );
          store.dispose();
        },
      );
    }

    test('rejects malformed fixed reservations at catalog ingress', () {
      for (final fixed in <Object?>[
        <Object?>[],
        null,
        [null],
        [
          {'code': 'MetaLeft', 'modifiers': <String>[]},
        ],
        [
          {'code': 'Escape', 'modifiers': <String>[], 'extra': true},
        ],
      ]) {
        expect(
          () => parseShortcutDefinitions([
            {
              'id': 'test.action',
              'defaults': <String, Object?>{},
              'fixed': fixed,
            },
          ]),
          throwsA(anything),
          reason: '$fixed',
        );
      }
      expect(
        () => parseShortcutDefinitions([
          {
            'id': 'test.action',
            'defaults': {
              'desktop:macos': pair.toJson(),
              'desktop:windows': pair.toJson(),
              'desktop:linux': pair.toJson(),
            },
            'fixed': [
              {'code': 'Escape', 'modifiers': <String>[]},
            ],
          },
        ]),
        throwsA(anything),
      );
    });

    for (final (runtime, platform) in [
      (ShortcutRuntime.web, ShortcutPlatform.macos),
      (ShortcutRuntime.web, ShortcutPlatform.windows),
      (ShortcutRuntime.web, ShortcutPlatform.linux),
      (ShortcutRuntime.desktop, ShortcutPlatform.linux),
    ]) {
      test(
        'rejects bare keys and chords in ${runtime.name} on ${platform.name}',
        () {
          for (final b in const [
            pair,
            ShortcutBinding('KeyA'),
            ShortcutBinding('KeyA', [
              ShortcutModifier.control,
              ShortcutModifier.alt,
              ShortcutModifier.shift,
              ShortcutModifier.meta,
            ], 'KeyB'),
          ]) {
            expect(
              bindingIssue(normalizeBinding(b, platform), runtime, platform),
              isNotNull,
            );
          }
        },
      );
    }

    test('canonicalizes unordered pairs, rejects invalid main keys, and omits unsupported ARIA accelerators', () {
      final reversed = normalizeBinding(
        const ShortcutBinding('KeyB', [], 'KeyA'),
        ShortcutPlatform.macos,
      );
      expect(reversed, const NormalizedBinding('KeyA', [], 'KeyB'));
      expect(bindingKey(reversed), 'KeyA+KeyB');
      expect(
        presentBinding(reversed, ShortcutPlatform.macos),
        const PresentedBinding(['A', 'B'], null),
      );
      expect(
        presentBinding(reversed, ShortcutPlatform.windows),
        const PresentedBinding(['A', 'B'], null),
      );
      expect(
        presentBinding(
          NormalizedBinding('KeyA', const [
            ShortcutModifier.control,
            ShortcutModifier.shift,
          ], 'KeyB'),
          ShortcutPlatform.windows,
        ).keys,
        ['Ctrl', '+', 'Shift', '+', 'A', 'B'],
      );
      for (final input in <Object?>[
        {'code': 'KeyA', 'secondCode': 'KeyA', 'modifiers': <String>[]},
        {'code': 'KeyA', 'secondCode': 'ShiftLeft', 'modifiers': <String>[]},
        {
          'code': 'KeyA',
          'secondCode': 'KeyB',
          'thirdCode': 'KeyC',
          'modifiers': <String>[],
        },
        {
          'code': 'KeyA',
          'secondCode': ['KeyB', 'KeyC'],
          'modifiers': <String>[],
        },
        {
          'code': 'MetaLeft',
          'modifiers': ['control'],
        },
        {
          'modifiers': ['meta'],
        },
      ]) {
        expect(() => parseBinding(input), throwsA(anything), reason: '$input');
      }
    });
  });
}
